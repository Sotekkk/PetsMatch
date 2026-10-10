'use client';

import { useEffect, useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { usePlan } from '@/lib/use-plan';
import AnnonceStatsModal from '@/components/AnnonceStatsModal';
import { apiFetch } from '@/lib/api-fetch';
import { useTypeProfilActif } from '@/hooks/useTypeProfilActif';
import { droitsAnnonces, lireFiltreType, type TypeAnnonceFiltre } from '@/lib/annonces-droits';
import MesAnnoncesMateriel from '@/components/annonces/MesAnnoncesMateriel';
import FiltresAnnonces from '@/components/annonces/FiltresAnnonces';
import { Icone, BORDURE, OMBRE } from '@/components/dashboard/kit';

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
const STATUT_COLOR: Record<string, string> = {
  disponible: 'bg-green-100 text-green-700',
  reserve:    'bg-amber-100 text-amber-700',
  vendu:      'bg-blue-100 text-blue-600',
  archivee:   'bg-gray-100 text-gray-500',
  pause:      'bg-gray-100 text-gray-500',
  expiree:    'bg-red-100 text-red-500',
  brouillon:  'bg-amber-100 text-amber-700',
  brouillon_eleveur: 'bg-gray-100 text-gray-600',
  quota_depasse: 'bg-red-100 text-red-600',
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

  async function handleRenew(a: Annonce) {
    const newExpires = new Date();
    newExpires.setDate(newExpires.getDate() + 30);
    const newExpiresIso = newExpires.toISOString();
    await supabase.from('annonces').update({ statut: 'disponible', expires_at: newExpiresIso }).eq('id', a.id);
    setAnnonces(prev => prev.map(x => x.id === a.id ? { ...x, statut: 'disponible', expires_at: newExpiresIso } : x));
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
    return null;
  });
  useEffect(() => {
    const s = window.location.search;
    if (s.includes('paye=') || s.includes('paiement=') || s.includes('brouillon=')) {
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

  const filtered = filter === 'toutes' ? annonces : annonces.filter(a => (a.statut ?? 'disponible') === filter);
  const voirAnimaux = typeFiltre === 'animaux' || (typeFiltre === 'toutes' && animauxAutorises);
  const voirMateriel = typeFiltre !== 'animaux';
  const total = (animauxAutorises ? annonces.length : 0) + nbMateriel;
  const btnIcone = 'inline-flex items-center justify-center w-9 h-9 border rounded-xl transition-colors';

  return (
    <div className="max-w-4xl mx-auto px-4 py-8" style={{ fontFamily: 'Galey, sans-serif' }}>
      {notice && (
        <div className="mb-4 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800">
          {notice}
        </div>
      )}
      {/* En-tête */}
      <div className="flex flex-wrap items-center justify-between gap-3 mb-4">
        <div>
          <h1 className="text-2xl font-bold text-[#1E2025]">Mes annonces</h1>
          <p className="text-gray-500 text-sm">{total} annonce{total !== 1 ? 's' : ''}</p>
        </div>
        <div className="flex items-center gap-2">
          <Link href="/mes-achats"
            className="border border-[#E5E8E6] bg-white hover:border-[#0C5C6C] text-gray-700 hover:text-[#0C5C6C] font-semibold px-4 py-2.5 rounded-full transition-colors text-sm">
            Mes achats
          </Link>
          <Link href="/annonces/publier"
            className="bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-semibold px-5 py-2.5 rounded-full transition-colors text-sm inline-flex items-center gap-2">
            <Icone nom="plus" taille={16} /> Publier une annonce
          </Link>
        </div>
      </div>

      {/* Quota plan (annonces d'animaux d'éleveur) */}
      {animauxAutorises && !isParticulier && voirAnimaux && <div className={`bg-white rounded-2xl p-4 mb-5 flex items-center gap-4 ${OMBRE}`} style={{ border: `1px solid ${BORDURE}` }}>
        <div className="flex-1">
          <div className="flex items-center justify-between mb-1.5">
            <span className="text-xs font-semibold text-gray-600">
              Plan {planConfig.label} — {planConfig.maxAnnonces === -1 ? 'Annonces illimitées' : `${activeCount} / ${planConfig.maxAnnonces} annonces actives`}
            </span>
            {planConfig.maxAnnonces !== -1 && activeCount >= planConfig.maxAnnonces && (
              <span className="text-xs font-bold text-red-600">Limite atteinte</span>
            )}
          </div>
          {planConfig.maxAnnonces !== -1 && (
            <div className="w-full bg-gray-100 rounded-full h-1.5">
              <div
                className={`h-1.5 rounded-full ${activeCount >= planConfig.maxAnnonces ? 'bg-red-400' : 'bg-[#6E9E57]'}`}
                style={{ width: `${Math.min(100, (activeCount / planConfig.maxAnnonces) * 100)}%` }}
              />
            </div>
          )}
        </div>
        {plan === 'free' && (
          <Link href="/abonnement"
            className="flex-shrink-0 text-xs font-semibold border border-[#0C5C6C] text-[#0C5C6C] px-3 py-1.5 rounded-full hover:bg-[#E8F4F6] transition-colors">
            Changer de formule
          </Link>
        )}
        {plan !== 'free' && (
          <Link href="/abonnement"
            className="flex-shrink-0 text-xs text-gray-500 hover:text-[#0C5C6C]">
            Gérer →
          </Link>
        )}
      </div>}

      <FiltresAnnonces
        type={typeFiltre} onType={choisirType}
        statut={filter} onStatut={s => setFilter(s as FilterKey)}
        statuts={(['toutes', 'disponible', 'archivee', 'pause'] as FilterKey[]).map(f => ({ k: f, label: f === 'toutes' ? 'Tous les statuts' : STATUT_LABEL[f] }))}
      />

      {voirAnimaux && (
        <section className="mb-8">
          {typeFiltre === 'toutes' && <h2 className="text-lg font-bold text-[#1E2025] mb-3">Animaux</h2>}
          {!animauxAutorises ? (
            <div className={`bg-white rounded-2xl p-8 text-center text-sm text-gray-500 ${OMBRE}`} style={{ border: `1px solid ${BORDURE}` }}>
              Les annonces d’animaux ne sont pas proposées pour ce profil. Vous pouvez publier du matériel et des équipements.
            </div>
          ) : fetching ? (
            <div className="flex justify-center py-16">
              <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
            </div>
          ) : filtered.length === 0 ? (
            <div className={`text-center py-12 bg-white rounded-2xl ${OMBRE}`} style={{ border: `1px solid ${BORDURE}` }}>
              <span className="w-11 h-11 mx-auto mb-3 rounded-full bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center"><Icone nom="patte" /></span>
              <p className="text-gray-500 text-sm mb-2">
                {filter === 'toutes' ? 'Aucune annonce d’animal pour le moment.' : `Aucune annonce d’animal ${STATUT_LABEL[filter]?.toLowerCase()}.`}
              </p>
              {filter === 'toutes' && droits.animaux && (
                <Link href={droits.animaux.creer}
                  className="inline-block bg-[#0C5C6C] hover:bg-[#094F5D] text-white text-sm font-semibold px-5 py-2.5 rounded-full transition-colors mt-1">
                  Publier une annonce d’animal
                </Link>
              )}
            </div>
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
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

                return (
                  <div key={a.id} className={`bg-white rounded-2xl overflow-hidden flex flex-col ${OMBRE}`} style={{ border: `1px solid ${BORDURE}` }}>
                    <div className="aspect-[4/3] bg-[#E8F4F6] relative">
                      {photos[0] ? (
                        <Image src={photos[0]} alt={a.titre ?? ''} fill className="object-cover" />
                      ) : (
                        <div className="w-full h-full flex items-center justify-center text-[#0C5C6C]"><Icone nom="patte" taille={40} /></div>
                      )}
                      <div className="absolute top-2 left-2">
                        <span className="bg-white/95 text-[#1E2025] text-xs font-semibold px-2 py-0.5 rounded-full border border-[#E5E8E6]">
                          {isSaillie ? 'Saillie' : equideFl ? equideFl : isPortee ? 'Portée' : 'Compagnon'}
                        </span>
                      </div>
                      <div className="absolute top-2 right-2">
                        <span className={`text-xs font-semibold px-2 py-0.5 rounded-full ${STATUT_COLOR[statut] ?? 'bg-gray-100 text-gray-500'}`}>
                          {STATUT_LABEL[statut] ?? statut}
                        </span>
                      </div>
                    </div>

                    <div className="p-4 flex-1 flex flex-col">
                      <h3 className="font-bold text-[#1E2025] text-[15px] truncate capitalize">
                        {a.titre ?? `${a.espece ?? ''} ${a.race ?? ''}`.trim()}
                      </h3>
                      <p className="text-gray-500 text-xs capitalize">{a.espece}{a.race ? ` · ${a.race}` : ''}</p>
                      {a.ville_eleveur && <p className="text-gray-500 text-xs inline-flex items-center gap-1 mt-0.5"><Icone nom="pin" taille={13} />{a.ville_eleveur}</p>}
                      {prix && <p className="text-[#0C5C6C] font-bold text-sm mt-1">{prix}</p>}

                      <div className="flex items-center gap-3 mt-1.5 text-xs text-gray-500 tabular-nums">
                        {a.vues != null && <span className="inline-flex items-center gap-1"><Icone nom="oeil" taille={14} />{a.vues}</span>}
                        {a.contacts != null && <span className="inline-flex items-center gap-1"><Icone nom="enveloppe" taille={14} />{a.contacts}</span>}
                        {a.created_at && <span className="ml-auto">{new Date(a.created_at).toLocaleDateString('fr-FR')}</span>}
                      </div>

                      {statut === 'quota_depasse' ? (
                        <div className="flex gap-1.5 mt-3 pt-3 border-t border-[#EEF0EE]">
                          <Link href="/abonnement"
                            className="flex-1 text-center text-xs bg-[#B45309] hover:bg-[#92400E] text-white font-semibold py-2 rounded-xl transition-colors">
                            Passer à un plan payant pour republier
                          </Link>
                          <button onClick={() => handleDelete(a.id)} disabled={deleting === a.id} aria-label="Supprimer" title="Supprimer"
                            className={`${btnIcone} border-red-100 hover:bg-red-50 text-red-500 disabled:opacity-50`}>
                            <Icone nom="corbeille" taille={15} />
                          </button>
                        </div>
                      ) : statut === 'brouillon_eleveur' ? (
                        <div className="flex gap-1.5 mt-3 pt-3 border-t border-[#EEF0EE]">
                          <Link href={`/annonces/creer?brouillon=${a.id}`}
                            className="flex-1 text-center text-xs bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-semibold py-2 rounded-xl transition-colors">
                            Reprendre
                          </Link>
                          <button onClick={() => handleDelete(a.id)} disabled={deleting === a.id}
                            className="px-3 py-2 text-xs border border-red-100 hover:bg-red-50 text-red-600 rounded-xl transition-colors disabled:opacity-50">
                            {deleting === a.id ? '…' : 'Supprimer'}
                          </button>
                        </div>
                      ) : statut === 'brouillon' ? (
                        <div className="flex gap-1.5 mt-3 pt-3 border-t border-[#EEF0EE]">
                          <button onClick={() => handlePayerPublier(a)} disabled={payingId === a.id}
                            className="flex-1 text-center text-xs bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 text-white font-semibold py-2 rounded-xl transition-colors">
                            {payingId === a.id ? 'Redirection…' : 'Payer et publier — 4,99 €'}
                          </button>
                          <Link href={`/annonces/creer-cheval?edit=${a.id}`}
                            className="text-center text-xs border border-[#0C5C6C]/30 text-[#0C5C6C] hover:bg-[#E8F4F6] font-semibold py-2 px-3 rounded-xl transition-colors">
                            Modifier
                          </Link>
                          <button onClick={() => handleDelete(a.id)} disabled={deleting === a.id} aria-label="Supprimer" title="Supprimer"
                            className={`${btnIcone} border-red-100 hover:bg-red-50 text-red-500 disabled:opacity-50`}>
                            <Icone nom="corbeille" taille={15} />
                          </button>
                        </div>
                      ) : (
                      <div className="flex gap-1.5 mt-3 pt-3 border-t border-[#EEF0EE]">
                        <Link href={`/annonces/${a.id}`}
                          className="flex-1 text-center text-xs bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-semibold py-2 rounded-xl transition-colors">
                          Voir
                        </Link>
                        <Link href={isParticulier ? `/annonces/creer-cheval?edit=${a.id}` : `/annonces/${a.id}/modifier`}
                          className="flex-1 text-center text-xs border border-[#0C5C6C]/30 text-[#0C5C6C] hover:bg-[#E8F4F6] font-semibold py-2 rounded-xl transition-colors">
                          Modifier
                        </Link>
                        <Link href={`/annonces/${a.id}`}
                          title={booste ? 'Annonce boostée' : 'Booster cette annonce'} aria-label={booste ? 'Annonce boostée' : 'Booster cette annonce'}
                          className={`${btnIcone} ${booste ? 'border-[#B45309] bg-[#FEF3C7] text-[#B45309]' : 'border-gray-200 text-gray-500 hover:border-[#B45309] hover:text-[#B45309]'}`}>
                          <Icone nom="eclair" taille={15} />
                        </Link>
                        {!isParticulier && (
                          <button onClick={() => { setStatsAnnonceId(a.id); setStatsAnnonceTitle(a.titre); }}
                            title="Statistiques" aria-label="Statistiques"
                            className={`${btnIcone} border-gray-200 text-[#0C5C6C] hover:bg-[#E8F4F6]`}>
                            <Icone nom="barres" taille={15} />
                          </button>
                        )}
                        <button onClick={() => handlePause(a)}
                          title={statut === 'pause' ? 'Réactiver' : 'Mettre en pause'} aria-label={statut === 'pause' ? 'Réactiver' : 'Mettre en pause'}
                          className={`${btnIcone} ${statut === 'pause' ? 'border-[#2F7D3A] text-[#2F7D3A] hover:bg-[#EAF5EC]' : 'border-gray-200 text-gray-500 hover:border-[#0C5C6C]/40 hover:text-[#0C5C6C]'}`}>
                          <Icone nom={statut === 'pause' ? 'lecture' : 'pause'} taille={15} />
                        </button>
                        {(statut === 'expiree' || expiresWithinDays(a, 7)) && (
                          <button onClick={() => handleRenew(a)} title="Renouveler pour 30 jours" aria-label="Renouveler pour 30 jours"
                            className={`${btnIcone} border-orange-200 text-orange-700 hover:bg-orange-50`}>
                            <Icone nom="renouveler" taille={15} />
                          </button>
                        )}
                        <button onClick={() => handleDelete(a.id)} disabled={deleting === a.id} aria-label="Supprimer" title="Supprimer"
                          className={`${btnIcone} border-red-100 hover:bg-red-50 text-red-500 disabled:opacity-50`}>
                          <Icone nom="corbeille" taille={15} />
                        </button>
                      </div>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </section>
      )}

      {voirMateriel && (
        <section>
          {typeFiltre === 'toutes' && voirAnimaux && <h2 className="text-lg font-bold text-[#1E2025] mb-3">Matériel & équipements</h2>}
          <MesAnnoncesMateriel statut={filter} onCompte={setNbMateriel} />
        </section>
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
  );
}
