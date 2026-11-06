'use client';

// Accueil du profil Éleveur : tableau de bord (présentation seulement).
// Données : lib/tableau-bord-eleveur.ts (lecture des modules existants) ;
// coche d'une tâche simple : lib/valider-tache.ts (même code que l'agenda).
// Les soins et les RDV vétérinaires ne se cochent pas ici : lien vers leur
// module (inscription au carnet, récapitulatif du RDV).
// Miroir appli : lib/pages/eleveur/eleveur_dashboard.dart.
import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { usePlan, resolveOwnerUid } from '@/lib/use-plan';
import { Icone, Puce, BORDURE, OMBRE, TEAL } from '@/components/dashboard/kit';
import { chargerTableauBord, animauxDuProfil, ymd, type DonneesTB, type LigneTB, HORIZON_JOURS } from '@/lib/tableau-bord-eleveur';
import PorteeSoinModal, { type SoinAnimal } from '@/components/animaux/PorteeSoinModal';
import AnnonceStatsModal from '@/components/AnnonceStatsModal';
import { basculerRoutine, basculerTacheManuelle } from '@/lib/valider-tache';

interface Annonce {
  id: string;
  titre?: string;
  espece?: string;
  race?: string;
  photos?: string[];
  statut?: string;
  vues?: number;
  contacts?: number;
  created_at?: string;
}

interface ProfilActif { nom?: string | null; avatar_url?: string | null; ville?: string | null; ville_pro?: string | null; is_main?: boolean | null }

const VERT = '#6E9E57';
const ORANGE = '#B45309';
const ROUGE = '#B42318';
const MAX_LIGNES = 5;

const LIBELLE_CONTRAT: Record<string, { texte: string; fg: string; bg: string }> = {
  brouillon: { texte: 'Brouillon à envoyer', fg: '#6B7280', bg: '#F3F4F6' },
  en_attente: { texte: 'En attente de signature', fg: ORANGE, bg: '#FEF3C7' },
  partiellement_signe: { texte: 'Signature partielle', fg: '#1D4ED8', bg: '#DBEAFE' },
};

function libelleJour(date: string): string {
  const auj = new Date(); auj.setHours(12, 0, 0, 0);
  const j = new Date(`${date}T12:00:00`);
  const ecart = Math.round((j.getTime() - auj.getTime()) / 86400000);
  if (ecart === 0) return "Aujourd'hui";
  if (ecart === 1) return 'Demain';
  if (ecart === -1) return 'Hier';
  return j.toLocaleDateString('fr-FR', { weekday: ecart > 0 && ecart < 7 ? 'short' : undefined, day: 'numeric', month: 'short' });
}

export default function EleveurDashboard() {
  const { user, userData, loading: authLoading, activeProfileId } = useAuth();
  const { plan, config: planConfig, loading: planLoading } = usePlan();
  const [profilLu, setProfilLu] = useState<{ id: string; data: ProfilActif | null } | null>(null);
  const [animalCount, setAnimalCount] = useState(0);
  const [mesAlertes, setMesAlertes] = useState<{ id: string }[]>([]);
  const [postCount, setPostCount] = useState(0);
  const [recentAnnonces, setRecentAnnonces] = useState<Annonce[]>([]);
  // Statistiques des annonces actives (vues et contacts cumulés, favoris).
  const [statsAnnonces, setStatsAnnonces] = useState<{ vues: number; contacts: number; favoris: number; top: (Annonce & { favoris: number })[] } | null>(null);
  const [statsOuverte, setStatsOuverte] = useState<{ id: string; titre: string } | null>(null);
  // Rappel du carnet ouvert dans le formulaire de soin (animaux concernés cochés).
  const [soinOuvert, setSoinOuvert] = useState<{ ligne: LigneTB; animaux: SoinAnimal[]; ownerUid: string; dateRappel?: string } | null>(null);
  const [donnees, setDonnees] = useState<DonneesTB | null>(null);
  const [erreurTB, setErreurTB] = useState(false);
  const [enCours, setEnCours] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  // Nom, photo et ville : ceux du PROFIL actif (jamais ceux du compte s'il en a plusieurs).
  useEffect(() => {
    if (!activeProfileId) return;
    supabase.from('user_profiles_complet').select('nom, avatar_url, ville, ville_pro, is_main')
      .eq('id', activeProfileId).maybeSingle()
      .then(({ data }) => setProfilLu({ id: activeProfileId, data: (data ?? null) as ProfilActif | null }));
  }, [activeProfileId]);
  // Ligne lue pour un autre profil (changement en cours) : ignorée.
  const profil = activeProfileId && profilLu?.id === activeProfileId ? profilLu.data : null;

  const principal = !activeProfileId || profil?.is_main === true;
  const displayName = profil?.nom || (principal ? (userData?.nameElevage ?? userData?.firstname) : null) || 'Mon élevage';
  const city = profil?.ville_pro || profil?.ville || (principal ? (userData?.villeElevage ?? userData?.ville) : null) || '';
  const avatar = profil?.avatar_url || (principal ? (userData?.profilePictureUrlElevage ?? userData?.profilePictureUrl) : null) || null;

  useEffect(() => {
    if (!user || authLoading) return;
    const userUid = user.uid;

    async function loadCount() {
      // Propriétaire réel du profil actif : un cogérant (elevage_cogerants) a
      // un uid différent du gérant — les compteurs sont ceux de l'élevage.
      const uid = await resolveOwnerUid(userUid, activeProfileId ?? '');
      let count = 0;
      if (activeProfileId) {
        const { data: check } = await supabase
          .from('animaux_proprietes').select('animal_id')
          .eq('uid_proprio', uid).not('profile_id_proprio', 'is', null).limit(1);
        if ((check ?? []).length > 0) {
          const { count: c } = await supabase
            .from('animaux_proprietes')
            .select('animal_id', { count: 'exact', head: true })
            .eq('uid_proprio', uid).eq('profile_id_proprio', activeProfileId).is('date_fin', null);
          count = c ?? 0;
        } else {
          const { count: c } = await supabase
            .from('animaux_proprietes')
            .select('animal_id', { count: 'exact', head: true })
            .eq('uid_proprio', uid).is('date_fin', null);
          count = c ?? 0;
        }
      } else {
        const { count: c } = await supabase
          .from('animaux_proprietes')
          .select('animal_id', { count: 'exact', head: true })
          .eq('uid_proprio', uid).is('date_fin', null);
        count = c ?? 0;
      }
      let qa = supabase.from('alertes_perdus').select('id').eq('uid_proprietaire', uid).eq('statut', 'perdu');
      if (activeProfileId) qa = qa.eq('profile_id', activeProfileId);
      const { data: alertes } = await qa;
      setAnimalCount(count);
      setMesAlertes((alertes ?? []) as { id: string }[]);
      setLoading(false);
    }

    loadCount().catch(() => setLoading(false));
  }, [user, authLoading, activeProfileId]);

  useEffect(() => {
    if (!user) return;
    (async () => {
      // Annonces de l'élevage (profil actif), cogérant compris — miroir appli.
      const ownerUid = await resolveOwnerUid(user.uid, activeProfileId ?? '');
      let q = supabase
        .from('annonces')
        .select('id, titre, espece, race, photos, statut, vues, contacts, created_at')
        .eq('uid_eleveur', ownerUid)
        .in('statut', ['disponible', 'reserve', 'pause']);
      q = activeProfileId ? q.eq('profile_id', activeProfileId) : q.neq('profil_source', 'association');
      const { data } = await q.order('created_at', { ascending: false }).limit(50);
      const docs = (data ?? []) as Annonce[];
      setPostCount(docs.filter(d => ['disponible', 'reserve'].includes(d.statut ?? '')).length);
      setRecentAnnonces(docs.slice(0, 3));
      // Favoris par annonce (table likes, comme la fenêtre Statistiques).
      const ids = docs.map(d => d.id);
      const { data: likes } = ids.length ? await supabase.from('likes').select('annonce_id').in('annonce_id', ids) : { data: [] };
      const fav = new Map<string, number>();
      ((likes ?? []) as { annonce_id: string }[]).forEach(l => fav.set(l.annonce_id, (fav.get(l.annonce_id) ?? 0) + 1));
      const avec = docs.map(d => ({ ...d, favoris: fav.get(d.id) ?? 0 }));
      setStatsAnnonces({
        vues: avec.reduce((t, d) => t + Number(d.vues ?? 0), 0),
        contacts: avec.reduce((t, d) => t + Number(d.contacts ?? 0), 0),
        favoris: avec.reduce((t, d) => t + d.favoris, 0),
        top: [...avec].sort((a, b) => Number(b.vues ?? 0) - Number(a.vues ?? 0)).slice(0, 3),
      });
    })();
  }, [user, activeProfileId]);

  const chargerTB = useCallback(async () => {
    if (!user) return;
    try {
      const ownerUid = await resolveOwnerUid(user.uid, activeProfileId ?? '');
      setDonnees(await chargerTableauBord({ userUid: user.uid, ownerUid, activeProfileId: activeProfileId ?? '' }));
      setErreurTB(false);
    } catch {
      setErreurTB(true);
    }
  }, [user, activeProfileId]);

  useEffect(() => {
    if (!user || authLoading) return;
    // Changement de profil : jamais d'affichage des données du profil précédent.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setDonnees(null);
    chargerTB();
  }, [user, authLoading, chargerTB]);

  // Rappel du carnet : formulaire de soin prérempli (soin, produit, prochain rappel,
  // animaux concernés cochés ; les autres animaux de l'élevage restent proposés).
  async function ouvrirSoin(l: LigneTB) {
    if (!user || !l.soin) return;
    const ownerUid = await resolveOwnerUid(user.uid, activeProfileId ?? '');
    const ids = [...new Set([...l.soin.animalIds, ...await animauxDuProfil(ownerUid, activeProfileId ?? '')])];
    const animaux: SoinAnimal[] = [];
    for (let i = 0; i < ids.length; i += 100) {
      const { data } = await supabase.from('animaux').select('id, nom, espece, sexe, date_naissance, identification, statut').in('id', ids.slice(i, i + 100));
      animaux.push(...((data ?? []) as (SoinAnimal & { statut?: string | null })[])
        .filter(a => l.soin!.animalIds.includes(String(a.id)) || !['sorti', 'decede', 'adopte', 'transfere'].includes(a.statut ?? ''))
        .map(a => ({ ...a, id: String(a.id) })));
    }
    // Animaux concernés en tête, puis les autres par nom.
    animaux.sort((a, b) => Number(l.soin!.animalIds.includes(b.id)) - Number(l.soin!.animalIds.includes(a.id)) || (a.nom ?? '').localeCompare(b.nom ?? ''));
    // Même intervalle que la dernière fois, à partir d'aujourd'hui.
    let dateRappel: string | undefined;
    if (l.soin.ecartJours) { const d = new Date(); d.setDate(d.getDate() + l.soin.ecartJours); dateRappel = ymd(d); }
    setSoinOuvert({ ligne: l, animaux, ownerUid, dateRappel });
  }

  async function cocher(l: LigneTB) {
    if (!user || !l.cochable || enCours) return;
    setEnCours(l.cle);
    const qui = { uid: user.uid, profileId: activeProfileId || null };
    try {
      if (l.cochable.table === 'taches_elevage') {
        const statut = await basculerTacheManuelle(l.cochable.ligne, qui);
        const ligne = { ...l.cochable.ligne, statut };
        // La tâche cochée reste visible, cochée.
        setDonnees(d => d && ({ ...d, aFaire: d.aFaire.map(x => x.cle === l.cle ? { ...x, fait: statut === 'fait', cochable: { table: 'taches_elevage', ligne } } : x) }));
      } else {
        const statut = await basculerRoutine(l.cochable.ligne, qui);
        const ligne = { ...l.cochable.ligne, statut };
        setDonnees(d => d && ({ ...d, aFaire: d.aFaire.map(x => x.cle === l.cle ? { ...x, fait: statut === 'fait', cochable: { table: 'plan_taches', ligne } } : x) }));
      }
    } catch {
      alert("La tâche n'a pas pu être mise à jour. Réessayez depuis l'agenda.");
    } finally {
      setEnCours(null);
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-24">
        <div className="w-8 h-8 border-2 border-[#6E9E57] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  const planIcone = plan === 'premium' ? 'couronne' : plan === 'pro' ? 'etoile' : 'valide';
  const carte = `bg-white rounded-2xl ${OMBRE}`;
  const aFaireOuvertes = donnees?.aFaire.filter(l => !l.fait).length ?? null;
  const soinsOuverts = donnees?.soins.filter(l => !l.fait) ?? null;
  const soinsRetard = soinsOuverts?.filter(l => l.retard).length ?? 0;
  const rdvVenir = donnees?.agenda.filter(l => !l.fait).length ?? null;
  const nbActivite = donnees ? donnees.contrats.length + donnees.recuperations.length : 0;

  return (
    <div className="bg-[#F6F7F5] min-h-screen" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-6xl mx-auto px-4 py-4 sm:py-6 space-y-5">

        {/* En-tête compact : profil actif, ville, abonnement, réglages */}
        <section className={`${carte} px-4 py-3 flex items-center gap-3`} style={{ border: `1px solid ${BORDURE}` }}>
          <Link href="/elevage/profil" className="w-12 h-12 rounded-full overflow-hidden flex-shrink-0 flex items-center justify-center bg-white" style={{ border: `1px solid ${BORDURE}` }}>
            {avatar
              // eslint-disable-next-line @next/next/no-img-element
              ? <img src={avatar} alt="" className="w-full h-full object-contain" />
              : <span className="w-full h-full flex items-center justify-center bg-[#E8F4F6] text-lg font-bold text-[#0C5C6C]">{displayName[0]?.toUpperCase() ?? '?'}</span>}
          </Link>
          <div className="min-w-0 flex-1">
            <h1 className="text-lg sm:text-xl font-bold text-[#1E2025] leading-tight truncate">{displayName}</h1>
            <div className="flex flex-wrap items-center gap-x-3 gap-y-1 mt-0.5">
              {city && (
                <span className="flex items-center gap-1 text-sm text-gray-600 min-w-0">
                  <Icone nom="pin" taille={14} className="text-[#0C5C6C] flex-shrink-0" /><span className="truncate">{city}</span>
                </span>
              )}
              {!planLoading && <Puce texte={planConfig.label} fg={planConfig.color} bg={planConfig.bg} icone={planIcone} href="/abonnement" />}
            </div>
          </div>
          {plan === 'free' && (
            <Link href="/abonnement" className="hidden sm:inline-flex rounded-full text-sm font-semibold px-4 py-2 border border-[#0C5C6C]/40 text-[#0C5C6C] hover:bg-[#E8F4F6]">Passer Pro</Link>
          )}
          <Link href="/elevage/profil" aria-label="Paramètres du profil élevage"
            className="inline-flex items-center gap-2 rounded-full text-sm font-semibold px-3 sm:px-4 py-2 bg-[#0C5C6C] text-white hover:bg-[#094F5D] flex-shrink-0">
            <Icone nom="reglages" taille={16} /><span className="hidden sm:inline">Mon profil élevage</span>
          </Link>
        </section>

        {/* Indicateurs */}
        <div className="flex sm:grid sm:grid-cols-5 gap-3 overflow-x-auto -mx-4 px-4 sm:mx-0 sm:px-0 pb-1 sm:pb-0 snap-x">
          <Indicateur valeur={animalCount} label="Animaux" icone="patte" href="/mes-animaux" />
          <Indicateur valeur={aFaireOuvertes} label="Tâches en attente" icone="valide" href="#a-faire" teinte={VERT} />
          <Indicateur valeur={rdvVenir} label={`RDV et événements (${HORIZON_JOURS} j)`} icone="calendrier" href="#agenda" teinte="#2196F3" />
          <Indicateur valeur={postCount} label="Annonces actives" icone="document" href="/mes-annonces" />
          <Indicateur valeur={soinsOuverts?.length ?? null} label={soinsRetard ? `Échéances sanitaires, dont ${soinsRetard} en retard` : 'Échéances sanitaires'}
            icone="seringue" href="#soins" teinte={soinsRetard ? ROUGE : '#FF9800'} />
        </div>

        {mesAlertes.length > 0 && (
          <Link href="/mes-alertes"
            className="flex items-center gap-4 bg-white rounded-2xl p-4 hover:shadow-md transition-shadow"
            style={{ border: '1px solid #F3D9A4' }}>
            <span className="w-10 h-10 rounded-full bg-amber-50 text-amber-700 flex items-center justify-center flex-shrink-0">
              <Icone nom="recherche" />
            </span>
            <div className="flex-1 min-w-0">
              <p className="font-bold text-[#1E2025] text-sm">
                {mesAlertes.length} alerte{mesAlertes.length > 1 ? 's' : ''} active{mesAlertes.length > 1 ? 's' : ''}
              </p>
              <p className="text-gray-600 text-xs">
                {mesAlertes.length === 1 ? 'Gérer votre alerte' : 'Gérer vos alertes'}
              </p>
            </div>
            <Icone nom="fleche" taille={18} className="text-gray-400" />
          </Link>
        )}

        {/* Accès rapides : pages et formulaires existants */}
        <div className="grid grid-cols-3 sm:grid-cols-6 gap-2.5">
          <Raccourci label="Ajouter un animal" icone="plus" href="/mes-animaux/ajouter" />
          <Raccourci label="Ajouter une tâche" icone="valide" href="/mes-taches?add=1" />
          <Raccourci label="Protocoles" icone="calendrier" href="/elevage/planning" />
          <Raccourci label="Créer une annonce" icone="document" href="/annonces/creer" />
          <Raccourci label="Entrée / Sortie" icone="renouveler" href="/elevage/registre-entree-sortie" />
          <Raccourci label="Créer un contrat" icone="crayon" href="/elevage/contrat" />
        </div>

        {erreurTB && (
          <div className="bg-white rounded-2xl p-4 text-sm text-gray-600 flex items-center justify-between gap-3" style={{ border: `1px solid ${BORDURE}` }}>
            <span>Le tableau de bord n&apos;a pas pu être chargé.</span>
            <button type="button" onClick={chargerTB} className="text-[#0C5C6C] font-semibold hover:underline">Réessayer</button>
          </div>
        )}

        <div className="grid lg:grid-cols-2 gap-5 items-start">
          <div className="space-y-5">
            <Bloc id="a-faire" titre="À faire" icone="valide" lien="/elevage/agenda" compteur={aFaireOuvertes}>
              <Liste lignes={donnees?.aFaire} vide="Aucune tâche en attente ni prévue cette semaine."
                rendu={l => <LigneTache l={l} enCours={enCours === l.cle} onCocher={() => cocher(l)} />} />
            </Bloc>
            <Bloc id="soins" titre="Soins et échéances" icone="seringue" lien="/elevage/registre-sanitaire" libelleLien="Suivi sanitaire"
              compteur={soinsRetard || null} compteurAlerte>
              <Liste lignes={donnees?.soins} vide="Aucun soin prévu cette semaine ni en retard."
                rendu={l => <LigneSimple l={l} onClick={l.soin ? () => ouvrirSoin(l) : undefined} />} />
            </Bloc>
          </div>
          <div className="space-y-5">
            <Bloc id="agenda" titre="Agenda" icone="calendrier" lien="/elevage/agenda">
              <Liste lignes={donnees?.agenda} vide={`Aucun événement dans les ${HORIZON_JOURS} prochains jours.`}
                rendu={l => <LigneSimple l={l} />} />
            </Bloc>
            <Bloc id="activite" titre="Activité" icone="document" compteur={nbActivite || null}>
              {!donnees ? <Chargement /> : (
                <div className="space-y-4">
                  {(donnees.contrats.length > 0 || donnees.recuperations.length > 0) && (
                    <div className="divide-y divide-[#EEF0EE]">
                      {donnees.contrats.slice(0, MAX_LIGNES).map(c => {
                        const st = LIBELLE_CONTRAT[c.statut] ?? LIBELLE_CONTRAT.en_attente;
                        return (
                          <Link key={c.id} href="/elevage/contrat" className="flex items-center gap-3 py-2.5 hover:bg-gray-50 -mx-2 px-2 rounded-lg">
                            <span className="w-8 h-8 rounded-full bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center flex-shrink-0"><Icone nom="crayon" taille={16} /></span>
                            <span className="min-w-0 flex-1">
                              <span className="block text-sm font-semibold text-[#1E2025] truncate">{c.titre}</span>
                              {c.animal_nom && <span className="block text-xs text-gray-500 truncate">{c.animal_nom}</span>}
                            </span>
                            <Puce texte={st.texte} fg={st.fg} bg={st.bg} />
                          </Link>
                        );
                      })}
                      {donnees.recuperations.length > 0 && (
                        <Link href="/mes-animaux/recuperations" className="flex items-center gap-3 py-2.5 hover:bg-gray-50 -mx-2 px-2 rounded-lg">
                          <span className="w-8 h-8 rounded-full bg-amber-50 text-amber-700 flex items-center justify-center flex-shrink-0"><Icone nom="renouveler" taille={16} /></span>
                          <span className="min-w-0 flex-1">
                            <span className="block text-sm font-semibold text-[#1E2025]">
                              {donnees.recuperations.length} demande{donnees.recuperations.length > 1 ? 's' : ''} de récupération en attente
                            </span>
                            <span className="block text-xs text-gray-500 truncate">{donnees.recuperations.slice(0, 3).map(r => r.animal_nom).join(', ')}</span>
                          </span>
                          <Icone nom="fleche" taille={16} className="text-gray-400" />
                        </Link>
                      )}
                    </div>
                  )}

                  <div>
                    <div className="flex items-center justify-between mb-1.5">
                      <p className="text-xs font-bold uppercase tracking-wide text-gray-500">Mes annonces en ligne</p>
                      <Link href="/mes-annonces" className="text-xs font-semibold text-[#0C5C6C] hover:underline">Voir tout</Link>
                    </div>
                    {recentAnnonces.length === 0 ? (
                      <p className="text-sm text-gray-500 py-2">
                        Aucune annonce publiée. <Link href="/annonces/creer" className="text-[#0C5C6C] font-semibold hover:underline">Créer une annonce</Link>
                      </p>
                    ) : (
                      <>
                        {statsAnnonces && (
                          <div className="grid grid-cols-3 gap-2 mb-2">
                            {[['Vues', statsAnnonces.vues], ['Contacts', statsAnnonces.contacts], ['Favoris', statsAnnonces.favoris]].map(([t, v]) => (
                              <div key={t as string} className="rounded-xl bg-[#F1F7F8] px-2 py-2 text-center">
                                <p className="text-lg font-bold text-[#1E2025] tabular-nums leading-tight">{v}</p>
                                <p className="text-[11px] text-gray-600">{t}</p>
                              </div>
                            ))}
                          </div>
                        )}
                        <p className="text-[11px] text-gray-400 mb-1">Depuis la mise en ligne. Touchez une annonce pour ses statistiques détaillées.</p>
                        <div className="divide-y divide-[#EEF0EE]">
                          {(statsAnnonces?.top ?? recentAnnonces.map(a => ({ ...a, favoris: 0 }))).map(a => {
                            const title = a.titre || a.race || a.espece || 'Annonce';
                            const photos = (a.photos as unknown as string[]) ?? [];
                            return (
                              <div key={a.id} className="flex items-center gap-2">
                              <button type="button" onClick={() => setStatsOuverte({ id: a.id, titre: title })}
                                className="flex-1 min-w-0 text-left flex items-center gap-3 py-2 hover:bg-gray-50 -mx-2 px-2 rounded-lg">
                                <span className="w-10 h-10 rounded-lg overflow-hidden bg-[#E8F4F6] text-[#0C5C6C] flex-shrink-0 flex items-center justify-center">
                                  {photos[0]
                                    // eslint-disable-next-line @next/next/no-img-element
                                    ? <img src={photos[0]} alt="" className="w-full h-full object-cover" />
                                    : <Icone nom="patte" taille={18} />}
                                </span>
                                <span className="min-w-0 flex-1 text-sm font-semibold text-[#1E2025] truncate capitalize">{title}</span>
                                <span className="text-xs text-gray-500 tabular-nums whitespace-nowrap">
                                  {Number(a.vues ?? 0)} vues · {Number(a.contacts ?? 0)} contacts · {a.favoris} favoris
                                </span>
                              </button>
                              {/* Voir l'annonce telle que la voient les visiteurs. */}
                              <Link href={`/annonces/${a.id}`} aria-label={`Voir l'annonce ${title}`} title="Voir l'annonce"
                                className="w-9 h-9 rounded-full flex items-center justify-center flex-shrink-0 text-[#0C5C6C] hover:bg-[#E8F4F6]">
                                <Icone nom="oeil" taille={18} />
                              </Link>
                              </div>
                            );
                          })}
                        </div>
                      </>
                    )}
                  </div>
                </div>
              )}
            </Bloc>
          </div>
        </div>
      </div>
      {soinOuvert && soinOuvert.ligne.soin && (
        <PorteeSoinModal
          titre={soinOuvert.ligne.titre}
          animals={soinOuvert.animaux}
          uid={soinOuvert.ownerUid}
          activeProfileId={activeProfileId || null}
          initial={{
            typeActe: soinOuvert.ligne.soin.typeActe,
            description: soinOuvert.ligne.soin.produit,
            selection: soinOuvert.ligne.soin.animalIds,
            dateRappel: soinOuvert.dateRappel,
          }}
          onSaved={chargerTB}
          onClose={() => setSoinOuvert(null)} />
      )}
      {statsOuverte && (
        <AnnonceStatsModal annonceId={statsOuverte.id} annonceTitle={statsOuverte.titre} isPremium={plan === 'premium'}
          onClose={() => setStatsOuverte(null)} />
      )}
    </div>
  );
}

function Indicateur({ valeur, label, icone, href, teinte = TEAL }: { valeur: number | null; label: string; icone: string; href: string; teinte?: string }) {
  const contenu = (
    <>
      <span className="w-9 h-9 rounded-full flex items-center justify-center flex-shrink-0" style={{ background: `${teinte}17`, color: teinte }} aria-hidden>
        <Icone nom={icone} taille={18} />
      </span>
      <span className="min-w-0">
        <span className="block text-2xl font-bold text-[#1E2025] leading-tight tabular-nums">{valeur ?? '–'}</span>
        <span className="block text-xs font-medium text-gray-600 leading-snug">{label}</span>
      </span>
    </>
  );
  const cls = `bg-white rounded-2xl p-3 flex items-center gap-3 min-w-[150px] sm:min-w-0 snap-start hover:shadow-md transition-shadow ${OMBRE}`;
  const style = { border: `1px solid ${BORDURE}` };
  return href.startsWith('#')
    ? <a href={href} className={cls} style={style}>{contenu}</a>
    : <Link href={href} className={cls} style={style}>{contenu}</Link>;
}

function Raccourci({ label, icone, href }: { label: string; icone: string; href: string }) {
  return (
    <Link href={href} className={`bg-white rounded-xl min-h-[64px] px-2 py-2.5 flex flex-col sm:flex-row items-center justify-center gap-1.5 sm:gap-2 text-center hover:shadow-md transition-shadow ${OMBRE}`}
      style={{ border: `1px solid ${BORDURE}` }}>
      <span className="w-8 h-8 rounded-full flex items-center justify-center bg-[#0C5C6C]/10 text-[#0C5C6C] flex-shrink-0" aria-hidden><Icone nom={icone} taille={16} /></span>
      <span className="text-xs font-semibold text-[#1E2025] leading-tight">{label}</span>
    </Link>
  );
}

function Bloc({ id, titre, icone, lien, libelleLien = 'Voir tout', compteur, compteurAlerte = false, children }: {
  id: string; titre: string; icone: string; lien?: string; libelleLien?: string; compteur?: number | null; compteurAlerte?: boolean; children: React.ReactNode;
}) {
  return (
    <section id={id} className={`bg-white rounded-2xl p-4 scroll-mt-24 ${OMBRE}`} style={{ border: `1px solid ${BORDURE}` }}>
      <div className="flex items-center gap-2 mb-2">
        <span className="text-[#0C5C6C]" aria-hidden><Icone nom={icone} taille={18} /></span>
        <h2 className="font-bold text-base text-[#1E2025]">{titre}</h2>
        {!!compteur && (
          <span className={`min-w-[20px] h-5 px-1.5 rounded-full text-[11px] font-bold flex items-center justify-center ${compteurAlerte ? 'bg-red-600 text-white' : 'bg-[#E8F4F6] text-[#0C5C6C]'}`}>{compteur}</span>
        )}
        <span className="flex-1" />
        {lien && <Link href={lien} className="text-sm font-semibold text-[#0C5C6C] hover:underline whitespace-nowrap">{libelleLien}</Link>}
      </div>
      {children}
    </section>
  );
}

function Chargement() {
  return <div className="py-6 flex justify-center"><div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
}

function Liste({ lignes, vide, rendu }: { lignes: LigneTB[] | undefined; vide: string; rendu: (l: LigneTB) => React.ReactNode }) {
  const [tout, setTout] = useState(false);
  if (!lignes) return <Chargement />;
  if (lignes.length === 0) return <p className="text-sm text-gray-500 py-3">{vide}</p>;
  const visibles = tout ? lignes : lignes.slice(0, MAX_LIGNES);
  return (
    <>
      <ul className="divide-y divide-[#EEF0EE]">
        {visibles.map(l => <li key={l.cle}>{rendu(l)}</li>)}
      </ul>
      {lignes.length > MAX_LIGNES && (
        <button type="button" onClick={() => setTout(v => !v)} className="mt-1 text-sm font-semibold text-[#0C5C6C] hover:underline">
          {tout ? 'Réduire' : `Afficher les ${lignes.length - MAX_LIGNES} autres`}
        </button>
      )}
    </>
  );
}

function Quand({ l }: { l: LigneTB }) {
  return (
    <span className={`text-xs font-semibold tabular-nums whitespace-nowrap ${l.retard ? 'text-[#B42318]' : 'text-gray-500'}`}>
      {l.retard ? `En retard · ${libelleJour(l.date)}` : libelleJour(l.date)}{l.heure ? ` · ${l.heure.slice(0, 5)}` : ''}
    </span>
  );
}

function Details({ l }: { l: LigneTB }) {
  const infos = [l.animal, l.sousTitre, l.responsable ? `Responsable : ${l.responsable}` : null].filter(Boolean);
  if (!infos.length) return null;
  return <span className="block text-xs text-gray-500 truncate">{infos.join(' · ')}</span>;
}

function LigneTache({ l, enCours, onCocher }: { l: LigneTB; enCours: boolean; onCocher: () => void }) {
  return (
    <div className="flex items-center gap-3 py-2.5">
      <button type="button" onClick={onCocher} disabled={enCours}
        aria-label={l.fait ? `Marquer « ${l.titre} » comme à faire` : `Marquer « ${l.titre} » comme faite`}
        className={`w-6 h-6 rounded-md flex items-center justify-center flex-shrink-0 border-2 transition-colors disabled:opacity-50 ${l.fait ? 'bg-[#6E9E57] border-[#6E9E57] text-white' : 'border-gray-300 hover:border-[#6E9E57]'}`}>
        {l.fait && <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" aria-hidden><path d="M5 12l5 5L20 7" /></svg>}
      </button>
      <Link href={l.lien} className="min-w-0 flex-1 group">
        <span className={`block text-sm font-semibold truncate group-hover:underline ${l.fait ? 'text-gray-400 line-through' : 'text-[#1E2025]'}`}>{l.titre}</span>
        <Details l={l} />
      </Link>
      <Quand l={l} />
    </div>
  );
}

function LigneSimple({ l, onClick }: { l: LigneTB; onClick?: () => void }) {
  const contenu = (
    <>
      <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ background: l.retard ? ROUGE : (l.couleur ?? '#FF9800') }} aria-hidden />
      <span className="min-w-0 flex-1">
        <span className={`block text-sm font-semibold truncate group-hover:underline ${l.fait ? 'text-gray-400 line-through' : 'text-[#1E2025]'}`}>{l.titre}</span>
        <Details l={l} />
      </span>
      <Quand l={l} />
    </>
  );
  // Rappel du carnet : ouvre le formulaire de soin ; sinon lien vers le module.
  return onClick
    ? <button type="button" onClick={onClick} className="w-full text-left flex items-center gap-3 py-2.5 group">{contenu}</button>
    : <Link href={l.lien} className="flex items-center gap-3 py-2.5 group">{contenu}</Link>;
}
