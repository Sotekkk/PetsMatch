'use client';

import { renouvelerAnnonce } from '@/lib/annonce-paiement';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { usePlan } from '@/lib/use-plan';
import AnnonceStatsModal from '@/components/AnnonceStatsModal';
import { apiFetch } from '@/lib/api-fetch';
import { useTypeProfilActif } from '@/hooks/useTypeProfilActif';
import { droitsAnnonces, lireFiltreType, FILTRES_TYPE, type TypeAnnonceFiltre } from '@/lib/annonces-droits';
import MesAnnoncesMateriel from '@/components/annonces/MesAnnoncesMateriel';
import BoostAnnonceModal from '@/components/annonces/BoostAnnonceModal';
import ConfirmationBoost from '@/components/annonces/ConfirmationBoost';
import { Puce } from '@/components/dashboard/kit';
import {
  EnteteGestion, BandeauQuota, BarreFiltres, CarteAnnonce, RubriqueAnnonces, EtatVide, Chargement,
  correspondRecherche, TEINTES_STATUT, type ActionAnnonce,
} from '@/components/annonces/GestionAnnonces';

interface Annonce {
  id: string;
  titre?: string;
  espece?: string;
  race?: string;
  type?: string;
  type_vente?: string;
  prix_unite?: string;
  photos?: string[];
  prix?: number;
  saillie_prix?: number;
  prix_min_portee?: number;
  prix_max_portee?: number;
  ville_eleveur?: string;
  created_at?: string;
  statut?: string;
  vues?: number;
  contacts?: number;
  expires_at?: string;
  paiement_statut?: string;
  boost_until?: string;
}

const STATUT_LABEL: Record<string, string> = {
  disponible: 'Disponible', reserve: 'Réservé', vendu: 'Vendu',
  archivee: 'Archivée', pause: 'En pause', expiree: 'Expirée',
  brouillon: 'Brouillon · non payée',
  brouillon_eleveur: 'Brouillon',
  quota_depasse: 'Bloquée · quota dépassé',
};
// Teinte de la puce de statut (TEINTES_STATUT du kit de gestion).
const STATUT_TEINTE: Record<string, string> = {
  disponible: 'vert', reserve: 'ambre', vendu: 'bleu', archivee: 'gris', pause: 'gris',
  expiree: 'rouge', brouillon: 'ambre', brouillon_eleveur: 'gris', quota_depasse: 'rouge',
};

type FilterKey = 'toutes' | 'disponible' | 'archivee' | 'pause';

export default function MesAnnoncesPage() {
  const { user, loading, activeProfileId } = useAuth();
  const { type: typeProfil, pret: profilPret } = useTypeProfilActif();
  const droits = droitsAnnonces(typeProfil);
  const [typeFiltre, setTypeFiltre] = useState<TypeAnnonceFiltre>('toutes');
  const [nbMateriel, setNbMateriel] = useState(0);
  const { plan, config: planConfig, activeAnnonces: activeCount } = usePlan();
  const router = useRouter();
  const [annonces, setAnnonces] = useState<Annonce[]>([]);
  const [fetching, setFetching] = useState(true);
  const [deleting, setDeleting] = useState<string | null>(null);
  const [filter, setFilter] = useState<FilterKey>('toutes');
  const [recherche, setRecherche] = useState('');
  // Boost : point d'entrée unique (menu « … ») ; ?boost=<id> l'ouvre (lien de l'appli).
  const [boostId, setBoostId] = useState<string | null>(null);
  // Retour du paiement d'un boost choisi à la publication.
  const [publieeId, setPubliee] = useState<string | null>(null);
  // Annonce de matériel (annonces_objets) pour la confirmation et le boost ouvert par lien.
  const [tableLien, setTableLien] = useState<'annonces' | 'annonces_objets'>('annonces');
  useEffect(() => {
    const q = new URLSearchParams(window.location.search);
    if (q.get('table') === 'annonces_objets' || (q.get('publiee') && q.get('type') === 'materiel')) setTableLien('annonces_objets');
    const b = q.get('boost');
    if (b) setBoostId(b);
    const p = q.get('publiee');
    if (p) { setPubliee(p); window.history.replaceState({}, '', q.get('type') === 'materiel' ? '/mes-annonces?type=materiel' : '/mes-annonces'); }
  }, []);
  const [statsAnnonceId, setStatsAnnonceId] = useState<string | null>(null);
  const [statsAnnonceTitle, setStatsAnnonceTitle] = useState<string | undefined>();
  const isPremium = plan === 'premium';
  const isParticulier = typeProfil === 'particulier';
  const animauxAutorises = !!droits.animaux;

  // Filtre de type lu dans l'URL (?type=animaux|materiel), anciens liens compris.
  useEffect(() => {
    setTypeFiltre(lireFiltreType(new URLSearchParams(window.location.search).get('type')));
  }, []);
  function choisirType(t: TypeAnnonceFiltre) {
    setTypeFiltre(t);
    const u = new URL(window.location.href);
    if (t === 'toutes') u.searchParams.delete('type'); else u.searchParams.set('type', t);
    window.history.replaceState({}, '', u.pathname + u.search);
  }

  // Profil association : ses annonces d'animaux vivent sous /association/annonces.
  useEffect(() => {
    if (profilPret && typeProfil === 'association') router.replace('/association/annonces' + window.location.search);
  }, [profilPret, typeProfil, router]);

  useEffect(() => {
    if (loading) return;
    if (!user) { router.push('/connexion'); return; }
  }, [loading, user, router]);

  useEffect(() => {
    if (!user || loading || !profilPret) return;
    if (!animauxAutorises) { setAnnonces([]); setFetching(false); return; }
    const SELECT = 'id, titre, espece, race, type, type_vente, prix_unite, photos, prix, saillie_prix, prix_min_portee, prix_max_portee, ville_eleveur, statut, vues, contacts, created_at, expires_at, paiement_statut, boost_until';

    async function load() {
      // uid Firebase RÉEL du propriétaire de l'élevage actif — jamais
      // forcément user.uid : un cogérant (elevage_cogerants) a un uid
      // différent du gérant, mais la ligne user_profiles du profil emprunté
      // (activeProfileId) reste celle du gérant. Sans ça, "Mes annonces"
      // resterait scopé sur le compte personnel du cogérant. Non pertinent
      // pour un profil particulier (pas de cogérance à ce niveau).
      let ownerUid = user!.uid;
      if (!isParticulier && activeProfileId) {
        const { data: prof } = await supabase.from('user_profiles_complet').select('uid').eq('id', activeProfileId).maybeSingle();
        ownerUid = (prof?.uid as string | undefined) ?? user!.uid;
      }

      let q = supabase.from('annonces').select(SELECT).order('created_at', { ascending: false });
      if (isParticulier) {
        // Particulier : uniquement ses annonces cheval (profil_source='particulier')
        q = q.eq('profil_source', 'particulier');
        const { data: check } = await supabase.from('annonces').select('id')
          .eq('uid_eleveur', ownerUid).eq('profil_source', 'particulier')
          .not('profile_id', 'is', null).limit(1);
        q = (check ?? []).length > 0 && activeProfileId
          ? q.eq('profile_id', activeProfileId)
          : q.eq('uid_eleveur', ownerUid);
      } else {
        // Vérifie si la migration profile_id a été jouée
        const { data: check } = await supabase.from('annonces').select('id')
          .eq('uid_eleveur', ownerUid).not('profile_id', 'is', null).limit(1);
        if ((check ?? []).length > 0 && activeProfileId) {
          q = q.eq('profile_id', activeProfileId);
        } else {
          q = q.eq('uid_eleveur', ownerUid).or('profil_source.is.null,profil_source.neq.association');
        }
      }
      const { data } = await q;
      setAnnonces((data ?? []) as Annonce[]);
      setFetching(false);

      const channel = supabase
        .channel(`mes-annonces-${ownerUid}`)
        .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'annonces', filter: `uid_eleveur=eq.${ownerUid}` },
          (payload) => setAnnonces(prev => [payload.new as Annonce, ...prev])
        )
        .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'annonces', filter: `uid_eleveur=eq.${ownerUid}` },
          (payload) => setAnnonces(prev => prev.map(a => a.id === (payload.new as Annonce).id ? payload.new as Annonce : a))
        )
        .on('postgres_changes', { event: 'DELETE', schema: 'public', table: 'annonces', filter: `uid_eleveur=eq.${ownerUid}` },
          (payload) => setAnnonces(prev => prev.filter(a => a.id !== (payload.old as Annonce).id))
        )
        .subscribe();
      return channel;
    }
    let channelRef: ReturnType<typeof supabase.channel> | undefined;
    load().then(ch => { channelRef = ch; }).catch(() => setFetching(false));

    return () => { if (channelRef) supabase.removeChannel(channelRef); };
  }, [user, loading, activeProfileId, isParticulier, profilPret, animauxAutorises]);

  async function handleDelete(id: string) {
    if (!confirm('Supprimer définitivement cette annonce ?')) return;
    setDeleting(id);
    try {
      await supabase.from('annonces').delete().eq('id', id);
      setAnnonces(prev => prev.filter(a => a.id !== id));
    } finally {
      setDeleting(null);
    }
  }

  async function handlePause(a: Annonce) {
    const newStatut = a.statut === 'pause' ? 'disponible' : 'pause';
    await supabase.from('annonces').update({ statut: newStatut }).eq('id', a.id);
    setAnnonces(prev => prev.map(x => x.id === a.id ? { ...x, statut: newStatut } : x));
  }

  // Renouvellement payant (4,99 €, +30 jours) : paiement sur Stripe, le
  // webhook prolonge l'annonce (lib/annonce-modification.ts).
  async function handleRenew(a: Annonce) {
    try { await renouvelerAnnonce('annonces', a.id); }
    catch (e) { alert(e instanceof Error ? e.message : 'Renouvellement impossible'); }
  }

  const [payingId, setPayingId] = useState<string | null>(null);
  async function handlePayerPublier(a: Annonce) {
    if (!user) return;
    setPayingId(a.id);
    try {
      const res = await apiFetch('/api/stripe/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          uid: user.uid, email: user.email ?? '',
          produit_code: 'annonce_cheval_particulier',
          annonce_id: a.id, returnPath: '/mes-annonces',
        }),
      });
      const json = await res.json();
      if (!res.ok || !json.url) throw new Error(json.error ?? 'Paiement indisponible.');
      window.location.assign(json.url as string);
    } catch (e) {
      alert(e instanceof Error ? e.message : 'Paiement indisponible pour le moment.');
      setPayingId(null);
    }
  }

  // Retour de Stripe Checkout — lu une seule fois au montage.
  const [notice] = useState<string | null>(() => {
    if (typeof window === 'undefined') return null;
    const p = new URLSearchParams(window.location.search);
    if (p.get('paye') === '1') return 'Paiement reçu : votre annonce est en cours de publication.';
    if (p.get('paiement') === 'annule') return 'Paiement annulé — votre annonce reste en brouillon.';
    if (p.get('brouillon') === '1') return 'Brouillon enregistré. Reprenez-le quand vous voulez avec « Reprendre ».';
    if (p.get('boost_success') === '1') return 'Paiement reçu : le boost de votre annonce est activé dès sa confirmation.';
    return null;
  });
  useEffect(() => {
    const s = window.location.search;
    if (s.includes('paye=') || s.includes('paiement=') || s.includes('brouillon=') || s.includes('boost_success=')) {
      const t = new URLSearchParams(s).get('type');
      window.history.replaceState({}, '', t ? `/mes-annonces?type=${t}` : '/mes-annonces');
    }
  }, []);

  // Renouvellement proposé dès J-7, pas seulement une fois l'annonce
  // effectivement expirée — utile pour anticiper avant la coupure.
  function expiresWithinDays(a: Annonce, days: number): boolean {
    if (!a.expires_at) return false;
    const remaining = (new Date(a.expires_at).getTime() - Date.now()) / 86400000;
    return remaining <= days;
  }

  if (loading || !user) {
    return (
      <div className="flex justify-center py-32">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  const parStatut = filter === 'toutes' ? annonces : annonces.filter(a => (a.statut ?? 'disponible') === filter);
  const filtered = parStatut.filter(a => correspondRecherche(recherche, a.titre, a.espece, a.race, a.ville_eleveur));
  const voirAnimaux = typeFiltre === 'animaux' || (typeFiltre === 'toutes' && animauxAutorises);
  const voirMateriel = typeFiltre !== 'animaux';
  const total = (animauxAutorises ? annonces.length : 0) + nbMateriel;

  return (
    <div className="bg-[#F6F7F5] min-h-screen">
    <div className="max-w-5xl mx-auto px-4 py-8" style={{ fontFamily: 'Galey, sans-serif' }}>
      {notice && (
        <div className="mb-4 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800">
          {notice}
        </div>
      )}
      {publieeId && <ConfirmationBoost annonceId={publieeId} table={tableLien} onFermer={() => setPubliee(null)} />}
      <EnteteGestion total={total} publierHref="/annonces/publier" achatsHref="/mes-achats" />

      {/* Quota du plan (annonces d'animaux d'éleveur) */}
      {animauxAutorises && !isParticulier && voirAnimaux && (
        <BandeauQuota actives={activeCount} max={planConfig.maxAnnonces} formule={planConfig.label}
          gererHref="/abonnement" changerFormule={plan === 'free'} />
      )}

      <BarreFiltres recherche={recherche} onRecherche={setRecherche} filtres={[
        { label: 'Type', valeur: typeFiltre, options: FILTRES_TYPE, onChange: v => choisirType(v as TypeAnnonceFiltre) },
        { label: 'Statut', valeur: filter, onChange: v => setFilter(v as FilterKey),
          options: (['toutes', 'disponible', 'archivee', 'pause'] as FilterKey[]).map(f => ({ k: f, label: f === 'toutes' ? 'Tous' : STATUT_LABEL[f] })) },
      ]} />

      {voirAnimaux && (!animauxAutorises ? (
        <EtatVide icone="patte" texte="Les annonces d’animaux ne sont pas proposées pour ce profil. Vous pouvez publier du matériel et des équipements." />
      ) : (
        <RubriqueAnnonces titre="Animaux" icone="patte" nombre={fetching ? null : annonces.length}>
          {fetching ? <Chargement /> : filtered.length === 0 ? (
            <EtatVide icone="patte" texte={recherche.trim() ? 'Aucune annonce d’animal ne correspond à la recherche.'
              : filter === 'toutes' ? 'Aucune annonce d’animal pour le moment.' : `Aucune annonce d’animal ${STATUT_LABEL[filter]?.toLowerCase()}.`} />
          ) : (
            <div className="space-y-3">
              {filtered.map(a => {
                const isSaillie = a.type_vente === 'saillie';
                const isPortee = a.type === 'portee';
                const statutBrut = a.statut ?? 'disponible';
                // Brouillon d'éleveur (enregistré depuis Nouvelle annonce, sans paiement attendu)
                // ≠ brouillon d'annonce cheval en attente de paiement (paiement_statut « attente »).
                const statut = statutBrut === 'brouillon' && a.paiement_statut !== 'attente' ? 'brouillon_eleveur' : statutBrut;
                const photos = (a.photos as unknown as string[]) ?? [];
                const sailliePrixNum = a.saillie_prix != null ? Number(a.saillie_prix) : null;
                const EQUIDE_FL: Record<string, string> = {
                  location: 'Location', demi_pension: 'Demi-pension',
                  pension_complete: 'Pension', valorisation: 'Valorisation',
                };
                const equideFl = EQUIDE_FL[a.type_vente ?? ''];
                const cad = a.prix_unite === 'mois' ? '/mois' : a.prix_unite === 'semaine' ? '/sem.' : '';
                const prix = equideFl
                  ? (a.type_vente === 'valorisation'
                      ? (a.prix != null && a.prix > 0 ? `${a.prix} €` : 'À convenir')
                      : (a.prix != null && a.prix > 0 ? `${equideFl} · ${a.prix} €${cad}` : `${equideFl} · à convenir`))
                  : isSaillie
                  ? (sailliePrixNum != null && !isNaN(sailliePrixNum) ? `Saillie · ${Math.round(sailliePrixNum)} €` : 'Saillie')
                  : isPortee
                  ? (a.prix_min_portee != null || a.prix_max_portee != null
                      ? [a.prix_min_portee, a.prix_max_portee].filter(v => v != null).join(' – ') + ' €'
                      : null)
                  : (a.prix != null ? `${a.prix} €` : null);
                const booste = !!a.boost_until && new Date(a.boost_until) > new Date();
                const teinte = TEINTES_STATUT[STATUT_TEINTE[statut] ?? 'gris'];
                const supprimer: ActionAnnonce = { label: deleting === a.id ? 'Suppression…' : 'Supprimer', icone: 'corbeille', danger: true, disabled: deleting === a.id, onClick: () => handleDelete(a.id) };

                let principales: ActionAnnonce[];
                let menu: ActionAnnonce[];
                let note: string | null = null;
                if (statut === 'quota_depasse') {
                  principales = [{ label: 'Passer à un plan payant', icone: 'couronne', href: '/abonnement' }];
                  menu = [supprimer];
                  note = 'Annonce bloquée : passez à un plan payant pour la republier.';
                } else if (statut === 'brouillon_eleveur') {
                  principales = [{ label: 'Reprendre', icone: 'crayon', href: `/annonces/creer?brouillon=${a.id}` }];
                  menu = [supprimer];
                } else if (statut === 'brouillon') {
                  principales = [
                    { label: payingId === a.id ? 'Redirection…' : 'Payer et publier — 4,99 €', icone: 'euro', disabled: payingId === a.id, onClick: () => handlePayerPublier(a) },
                    { label: 'Modifier', icone: 'crayon', href: `/annonces/creer-cheval?edit=${a.id}` },
                  ];
                  menu = [supprimer];
                } else {
                  principales = [
                    { label: 'Voir', icone: 'oeil', href: `/annonces/${a.id}` },
                    { label: 'Modifier', icone: 'crayon', href: isParticulier ? `/annonces/creer-cheval?edit=${a.id}` : `/annonces/${a.id}/modifier` },
                  ];
                  menu = [
                    { label: booste ? 'Prolonger le boost' : 'Booster l’annonce', icone: 'eclair', onClick: () => setBoostId(a.id), actif: booste },
                    ...(!isParticulier ? [{ label: 'Statistiques', icone: 'barres', onClick: () => { setStatsAnnonceId(a.id); setStatsAnnonceTitle(a.titre); } }] : []),
                    { label: statut === 'pause' ? 'Réactiver' : 'Mettre en pause', icone: statut === 'pause' ? 'lecture' : 'pause', onClick: () => handlePause(a) },
                    ...((statut === 'expiree' || expiresWithinDays(a, 7)) ? [{ label: 'Renouveler pour 30 jours', icone: 'renouveler', onClick: () => handleRenew(a) }] : []),
                    supprimer,
                  ];
                }

                return (
                  <CarteAnnonce key={a.id} href={`/annonces/${a.id}`} photo={photos[0]}
                    titre={a.titre ?? (`${a.espece ?? ''} ${a.race ?? ''}`.trim() || 'Annonce')}
                    sousTitre={[a.espece, a.race, a.ville_eleveur].filter(Boolean).join(' · ')}
                    etiquettes={<>
                      <Puce texte={STATUT_LABEL[statut] ?? statut} fg={teinte.fg} bg={teinte.bg} point />
                      <Puce texte={isSaillie ? 'Saillie' : equideFl ? equideFl : isPortee ? 'Portée' : 'Compagnon'} fg="#41525A" bg="#F3F6F5" />
                      {booste && <Puce texte="Boostée" fg="#B45309" bg="#FEF3C7" icone="eclair" />}
                    </>}
                    prix={prix}
                    indicateurs={[
                      ...(a.vues != null ? [{ icone: 'oeil', texte: `${a.vues} vue${a.vues > 1 ? 's' : ''}` }] : []),
                      ...(a.contacts != null ? [{ icone: 'enveloppe', texte: `${a.contacts} contact${a.contacts > 1 ? 's' : ''}` }] : []),
                      ...(a.created_at ? [{ icone: 'calendrier', texte: new Date(a.created_at).toLocaleDateString('fr-FR') }] : []),
                    ]}
                    principales={principales} menu={menu} note={note} />
                );
              })}
            </div>
          )}
        </RubriqueAnnonces>
      ))}

      {voirMateriel && (
        <RubriqueAnnonces titre="Matériel & équipements" icone="caisse" nombre={nbMateriel}>
          <MesAnnoncesMateriel statut={filter} recherche={recherche} onCompte={setNbMateriel} />
        </RubriqueAnnonces>
      )}

      {boostId && (
        <BoostAnnonceModal annonceId={boostId} returnPath="/mes-annonces" table={tableLien}
          boostUntil={annonces.find(x => x.id === boostId)?.boost_until}
          onClose={() => { setBoostId(null); if (window.location.search.includes('boost=')) window.history.replaceState({}, '', '/mes-annonces'); }} />
      )}

      {statsAnnonceId && (
        <AnnonceStatsModal
          annonceId={statsAnnonceId}
          annonceTitle={statsAnnonceTitle}
          isPremium={isPremium}
          onClose={() => setStatsAnnonceId(null)}
        />
      )}
    </div>
    </div>
  );
}
