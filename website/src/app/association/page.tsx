'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { Kpi, Icone, EnteteAccueil, BoutonPilule, Puce } from '@/components/dashboard/kit';
import { Bloc, Liste, LigneSimple, Raccourci } from '@/components/EleveurDashboard';
import { chargerTableauBord, HORIZON_JOURS, type LigneTB } from '@/lib/tableau-bord-eleveur';

interface Stats {
  presents: number;
  enSoin: number;
  disponible: number;
  enFa: number;
  adopte: number;
  benevoles: number;
}

interface AnimalAsso {
  id: string; nom: string; espece?: string | null; photo_url?: string | null; statut?: string | null;
  fa_id?: string | null; date_entree?: string | null; date_sortie?: string | null;
  created_at?: string | null; updated_at?: string | null;
}

interface Mouvement { cle: string; animalId: string; nom: string; libelle: string; date: string; sortie: boolean }

// Couleurs de statut existantes, en accents discrets (texte / fond clair).
const STATUT_CONFIG: Record<string, { label: string; fg: string; bg: string }> = {
  en_soin:    { label: 'En soin',    fg: '#C2410C', bg: '#FFEDD5' },
  disponible: { label: 'Disponible', fg: '#15803D', bg: '#DCFCE7' },
  en_fa:      { label: 'En FA',      fg: '#7E22CE', bg: '#F3E8FF' },
  adopte:     { label: 'Adopté',     fg: '#0F766E', bg: '#CCFBF1' },
  transfere:  { label: 'Transféré',  fg: '#1D4ED8', bg: '#DBEAFE' },
  sorti:      { label: 'Sorti',      fg: '#1D4ED8', bg: '#DBEAFE' },
  decede:     { label: 'Décédé',     fg: '#B91C1C', bg: '#FEE2E2' },
};

// Animaux qui ne sont plus à l'association (onglet « Anciens » de la liste).
const ANCIENS = new Set(['adopte', 'transfere', 'sorti', 'decede']);
const LIBELLE_SORTIE: Record<string, string> = { adopte: 'Adoption', transfere: 'Transfert', decede: 'Décès' };
const MAX_RECENTS = 5;

interface Identite { nom: string; avatar: string | null; ville: string }

const jourCourt = (iso: string) => new Date(`${iso.slice(0, 10)}T12:00:00`).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short', year: 'numeric' });

export default function AssociationDashboard() {
  const { user, activeProfileId } = useAuth();
  const [stats, setStats] = useState<Stats>({ presents: 0, enSoin: 0, disponible: 0, enFa: 0, adopte: 0, benevoles: 0 });
  const [recentAnimaux, setRecentAnimaux] = useState<AnimalAsso[]>([]);
  const [mouvements, setMouvements] = useState<Mouvement[] | null>(null);
  const [alertes, setAlertes] = useState<LigneTB[] | undefined>(undefined);
  const [rdv, setRdv] = useState<LigneTB[] | undefined>(undefined);
  const [loading, setLoading] = useState(true);
  const [identite, setIdentite] = useState<Identite>({ nom: '', avatar: null, ville: '' });

  // Identité de l'association (profil actif, sinon compte principal).
  useEffect(() => {
    if (!user) return;
    if (activeProfileId) {
      supabase.from('user_profiles_complet').select('nom, avatar_url, ville, ville_pro').eq('id', activeProfileId).maybeSingle()
        .then(({ data }) => setIdentite({
          nom: (data?.nom as string) || '',
          avatar: (data?.avatar_url as string) || null,
          ville: ((data?.ville_pro ?? data?.ville) as string) || '',
        }));
    } else {
      supabase.from('users_complet').select('name_elevage, firstname, lastname, profile_picture_url_elevage, profile_picture_url, ville_elevage, ville').eq('uid', user.uid).maybeSingle()
        .then(({ data }) => setIdentite({
          nom: (data?.name_elevage as string) || `${data?.firstname ?? ''} ${data?.lastname ?? ''}`.trim(),
          avatar: ((data?.profile_picture_url_elevage || data?.profile_picture_url) as string) || null,
          ville: ((data?.ville_elevage || data?.ville) as string) || '',
        }));
    }
  }, [user, activeProfileId]);

  const charger = useCallback(async () => {
    if (!user) return;
    const [{ data: animaux }, { data: benvl }] = await Promise.all([
      supabase.from('animaux').select('id, nom, espece, photo_url, statut, fa_id, date_entree, date_sortie, created_at, updated_at')
        .eq('uid_eleveur', user.uid).eq('is_association', true).eq('profile_id', activeProfileId),
      // Équipe (miroir appli) : employés + bénévoles actifs du profil association.
      (activeProfileId
        ? supabase.from('employes').select('id').eq('eleveur_profile_id', activeProfileId)
        : supabase.from('employes').select('id').eq('uid_eleveur', user.uid))
        .eq('actif', true).eq('profil_source', 'association'),
    ]);
    const list = (animaux ?? []) as AnimalAsso[];
    // Compteurs = mêmes règles que la liste des animaux : les présents seulement
    // (un adopté reste dans l'historique, compté à part) ; un animal en FA reste
    // aussi « disponible » ou « en soin » (fa_id est un état indépendant).
    const presents = list.filter(a => !ANCIENS.has(a.statut ?? ''));
    setStats({
      presents: presents.length,
      enSoin: presents.filter(a => a.statut === 'en_soin').length,
      disponible: presents.filter(a => a.statut === 'disponible').length,
      enFa: presents.filter(a => !!a.fa_id).length,
      adopte: list.filter(a => a.statut === 'adopte').length,
      benevoles: (benvl ?? []).length,
    });
    const maj = (a: AnimalAsso) => a.updated_at || a.created_at || '';
    setRecentAnimaux([...list].sort((a, b) => maj(b).localeCompare(maj(a))).slice(0, MAX_RECENTS));
    setLoading(false);

    // Entrées et sorties : dates d'entrée des fiches + sorties du registre.
    const ids = list.map(a => a.id);
    const parId = new Map(list.map(a => [a.id, a]));
    const mvts: Mouvement[] = [];
    for (const a of list) {
      if (a.date_entree) {
        mvts.push({
          cle: `e_${a.id}`, animalId: a.id, nom: a.nom, date: a.date_entree.slice(0, 10), sortie: false,
          libelle: a.fa_id && !ANCIENS.has(a.statut ?? '') ? 'Placé en famille d\'accueil' : 'Entrée',
        });
      }
    }
    const sortis = new Set<string>();
    if (ids.length) {
      const { data: reg } = await supabase.from('registre_mouvements').select('id, animal_id, type, date_mouvement, eleveur_profile_id')
        .eq('uid_eleveur', user.uid).eq('type', 'sortie').in('animal_id', ids.slice(0, 500)).order('date_mouvement', { ascending: false }).limit(50);
      for (const m of (reg ?? []) as { id: string; animal_id: string; date_mouvement: string; eleveur_profile_id?: string | null }[]) {
        if (m.eleveur_profile_id && activeProfileId && m.eleveur_profile_id !== activeProfileId) continue;
        const a = parId.get(String(m.animal_id));
        if (!a || !m.date_mouvement || sortis.has(a.id)) continue;
        sortis.add(a.id);
        mvts.push({ cle: `s_${m.id}`, animalId: a.id, nom: a.nom, date: m.date_mouvement.slice(0, 10), sortie: true, libelle: LIBELLE_SORTIE[a.statut ?? ''] ?? 'Sortie' });
      }
    }
    for (const a of list) {
      if (sortis.has(a.id) || !ANCIENS.has(a.statut ?? '') || !a.date_sortie) continue;
      mvts.push({ cle: `d_${a.id}`, animalId: a.id, nom: a.nom, date: a.date_sortie.slice(0, 10), sortie: true, libelle: LIBELLE_SORTIE[a.statut ?? ''] ?? 'Sortie' });
    }
    setMouvements(mvts.sort((x, y) => y.date.localeCompare(x.date)).slice(0, MAX_RECENTS));

    // Alertes et rendez-vous : même moteur que l'accueil éleveur, limité à l'association.
    try {
      const tb = await chargerTableauBord({
        userUid: user.uid, ownerUid: user.uid, activeProfileId: activeProfileId ?? '',
        association: { animalIds: presents.map(a => a.id) },
      });
      setAlertes([...tb.soins, ...tb.aFaire].filter(l => !l.fait)
        .sort((a, b) => Number(b.retard) - Number(a.retard) || a.date.localeCompare(b.date) || (a.heure ?? '99').localeCompare(b.heure ?? '99')));
      setRdv(tb.agenda.filter(l => !l.fait));
    } catch {
      setAlertes([]); setRdv([]);
    }
  }, [user, activeProfileId]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void charger().catch(() => setLoading(false)); }, [charger]);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-24">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  const enRetard = (alertes ?? []).filter(l => l.retard).length;
  const fichePublique = `/associations/${activeProfileId || user?.uid}`;

  return (
    <div className="bg-[#F6F7F5] min-h-screen" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-6xl mx-auto px-4 py-4 sm:py-6 space-y-5">
        <EnteteAccueil
          nom={identite.nom || 'Mon association'}
          avatar={identite.avatar}
          avatarHref="/profil"
          sousTitre="Association / Refuge"
          lieu={identite.ville || undefined}
          actions={<>
            <BoutonPilule href={fichePublique} icone="oeil" contour>Fiche publique</BoutonPilule>
            <BoutonPilule href="/profil" icone="reglages">Modifier mon profil</BoutonPilule>
          </>}
        />

        {/* Accès rapides : formulaires existants */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5">
          <Raccourci label="Ajouter un animal" icone="plus" href="/association/animaux/nouveau" />
          <Raccourci label="Planifier un rendez-vous" icone="calendrier" href="/association/agenda?nouveau=rdv" />
          <Raccourci label="Ajouter une famille d'accueil" icone="maison" href="/association/familles-accueil?ajouter=1" />
          <Raccourci label="Publier une annonce" icone="document" href="/association/annonces/creer" />
        </div>

        {/* Mobile : actions, compteurs, RDV, animaux, mouvements.
            Ordinateur : compteurs en tête, puis deux colonnes. */}
        <div className="flex flex-col gap-5 lg:grid lg:grid-cols-2 lg:items-start">
          <div className="order-2 lg:order-first lg:col-span-2 grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
            <Kpi label="Pris en charge" valeur={stats.presents} icone="patte" teinte="#0C5C6C" href="/association/animaux" />
            <Kpi label="Disponibles" valeur={stats.disponible} icone="coeur" teinte="#15803D" href="/association/animaux?statut=disponible" />
            <Kpi label="En soin" valeur={stats.enSoin} icone="soin" teinte="#C2410C" href="/association/animaux?statut=en_soin" />
            <Kpi label="En famille d'accueil" valeur={stats.enFa} icone="maison" teinte="#7E22CE" href="/association/animaux?statut=en_fa" />
            <Kpi label="Adoptés" valeur={stats.adopte} icone="valide" teinte="#0F766E" href="/association/animaux?statut=adopte" />
            <Kpi label="Équipe" valeur={stats.benevoles} icone="equipe" teinte="#0C5C6C" href="/association/equipe" />
          </div>

          {/* Colonne gauche : animaux et mouvements */}
          <div className="contents lg:flex lg:flex-col lg:gap-5">
            <div className="order-4 lg:order-none">
              <Bloc id="animaux-recents" titre="Animaux récents" icone="patte" lien="/association/animaux" libelleLien="Voir tous">
                {recentAnimaux.length === 0 ? (
                  <p className="text-sm text-gray-500 py-3">Aucun animal enregistré.</p>
                ) : (
                  <ul className="divide-y divide-[#EEF0EE]">
                    {recentAnimaux.map((a) => {
                      const sc = STATUT_CONFIG[a.statut ?? ''] ?? { label: a.statut ?? '', fg: '#6B7280', bg: '#F3F4F6' };
                      return (
                        <li key={a.id}>
                          <Link href={`/association/animaux/${a.id}`} className="flex items-center gap-3 py-2.5 group">
                            <div className="w-11 h-11 rounded-xl overflow-hidden bg-[#E8F4F6] text-[#0C5C6C] flex-shrink-0 flex items-center justify-center">
                              {a.photo_url
                                // eslint-disable-next-line @next/next/no-img-element
                                ? <img src={a.photo_url} alt="" className="w-full h-full object-cover" />
                                : <Icone nom="patte" taille={20} />}
                            </div>
                            <div className="flex-1 min-w-0">
                              <p className="font-semibold text-[#1E2025] text-sm truncate group-hover:underline">{a.nom}</p>
                              <div className="flex items-center gap-2 mt-1 min-w-0">
                                {sc.label && <Puce texte={sc.label} fg={sc.fg} bg={sc.bg} point />}
                                {a.fa_id && !ANCIENS.has(a.statut ?? '') && <Puce texte="En FA" fg="#7E22CE" bg="#F3E8FF" point />}
                                {a.espece && <span className="text-xs text-gray-500 capitalize truncate">{a.espece}</span>}
                              </div>
                            </div>
                            <Icone nom="fleche" taille={16} className="text-gray-400 flex-shrink-0" />
                          </Link>
                        </li>
                      );
                    })}
                  </ul>
                )}
              </Bloc>
            </div>

            <div className="order-5 lg:order-none">
              <Bloc id="mouvements" titre="Entrées et sorties récentes" icone="renouveler" lien="/association/registre-entree-sortie" libelleLien="Registre">
                {mouvements === null ? (
                  <div className="py-6 flex justify-center"><div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>
                ) : mouvements.length === 0 ? (
                  <p className="text-sm text-gray-500 py-3">Aucun mouvement enregistré.</p>
                ) : (
                  <ul className="divide-y divide-[#EEF0EE]">
                    {mouvements.map(m => (
                      <li key={m.cle}>
                        <Link href={`/association/animaux/${m.animalId}`} className="flex items-center gap-3 py-2.5 group">
                          <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ background: m.sortie ? '#0F766E' : '#0C5C6C' }} aria-hidden />
                          <span className="min-w-0 flex-1">
                            <span className="block text-sm font-semibold text-[#1E2025] truncate group-hover:underline">{m.nom}</span>
                            <span className="block text-xs text-gray-500">{m.libelle}</span>
                          </span>
                          <span className="text-xs font-semibold text-gray-500 tabular-nums whitespace-nowrap">{jourCourt(m.date)}</span>
                        </Link>
                      </li>
                    ))}
                  </ul>
                )}
              </Bloc>
            </div>
          </div>

          {/* Colonne droite : actions et planning */}
          <div className="contents lg:flex lg:flex-col lg:gap-5">
            <div className="order-1 lg:order-none">
              <Bloc id="alertes" titre="Alertes et actions" icone="cloche" lien="/association/registre-sanitaire" libelleLien="Suivi sanitaire"
                compteur={enRetard || null} compteurAlerte>
                <Liste lignes={alertes} vide={`Aucun soin ni tâche en retard ou prévu dans les ${HORIZON_JOURS} jours.`}
                  rendu={l => <LigneSimple l={l} />} />
              </Bloc>
            </div>
            <div className="order-3 lg:order-none">
              <Bloc id="rdv" titre="Prochains rendez-vous" icone="calendrier" lien="/association/agenda" libelleLien="Agenda">
                <Liste lignes={rdv} vide={`Aucun rendez-vous dans les ${HORIZON_JOURS} jours.`}
                  rendu={l => <LigneSimple l={l} />} />
              </Bloc>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
