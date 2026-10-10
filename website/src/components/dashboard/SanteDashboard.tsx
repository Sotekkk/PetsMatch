'use client';

// Accueil ostéopathe animalier / santé : tableau de bord de l'activité.
// Uniquement des données réelles (rdv, suivis_morpho, animal_access) ; chaque
// élément ouvre le module existant (agenda, Mes patients, Mes suivis,
// messagerie). Briques communes : components/dashboard/kit.tsx.
// Miroir appli : lib/pages/pro/sante_dashboard.dart.
//
// Extérieur (domicile, écurie, élevage…) = RDV avec une adresse d'intervention
// (rdv.lieu, sans salle) ou des coordonnées — même règle que l'agenda.
// L'adresse du propriétaire n'est jamais supposée.

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import ItineraireMenu from '@/components/dashboard/ItineraireMenu';
import { retardsEnCascade } from '@/lib/retards-rdv';
import { Kpi, Section, Badge, PhotoAnimal, Donut, BarresSemaine, EnteteAccueil, PALETTE, TEAL, type Segment } from '@/components/dashboard/kit';

const VERT = '#2E7D5E';
const VIOLET = '#7B5EA7';
const AMBRE = '#D97706';

const TYPES_SUIVI: Record<string, string> = {
  bilan_morphologique: 'Bilan morphologique', bilan_posture: 'Bilan de posture', osteopathie: 'Ostéopathie',
  physiotherapie: 'Physiothérapie', suivi_veterinaire: 'Suivi vétérinaire', suivi_sportif: 'Suivi sportif',
  suivi_post_operatoire: 'Suivi post-opératoire', suivi_reproduction: 'Suivi reproduction', prevention: 'Prévention', autre: 'Autre',
};

interface Rdv {
  id: string; date_heure: string; duree_minutes: number | null; statut: string; motif: string | null;
  animal_id: string | null; client_uid: string | null; client_profile_id: string | null;
  client_nom_manuel: string | null; animal_nom_manuel: string | null;
  lieu: string | null; lieu_lat: number | null; lieu_lng: number | null; salle_id: string | null;
  notes_client: string | null; created_at: string | null;
}
interface Suivi {
  id: string; animal_id: string | null; animal_nom_libre: string | null; type_suivi: string | null;
  date: string | null; prochain_controle: string | null; motif: string | null;
}
interface Animal { id: string; nom: string | null; photo_url: string | null }

export const estExterieur = (r: Rdv) => (!!r.lieu?.trim() && !r.salle_id) || r.lieu_lat != null;
const debutDe = (r: Rdv) => new Date(r.date_heure);
const finDe = (r: Rdv) => new Date(debutDe(r).getTime() + (r.duree_minutes ?? 45) * 60000);
const memeJour = (a: Date, b: Date) => a.toDateString() === b.toDateString();
const hm = (d: Date) => d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
const jm = (d: Date) => d.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' });
const actif = (r: Rdv) => ['confirme', 'termine', 'demande', 'contre_proposition'].includes(r.statut);

function statut(r: Rdv, now: Date): { label: string; fg: string; bg: string } {
  switch (r.statut) {
    case 'demande': case 'contre_proposition': return { label: 'En attente', fg: '#8A5A00', bg: '#FFF4DC' };
    case 'termine': return { label: 'Terminé', fg: '#4B5563', bg: '#F1F2F4' };
    case 'annule': case 'refuse': return { label: 'Annulé', fg: '#9CA3AF', bg: '#F7F7F8' };
    case 'confirme':
      if (now < debutDe(r)) return { label: 'À venir', fg: '#1D4ED8', bg: '#E8F0FE' };
      if (now < finDe(r)) return { label: 'En cours', fg: TEAL, bg: '#E6F2F3' };
      return { label: 'Confirmé', fg: VERT, bg: '#E8F5EE' };
  }
  return { label: r.statut, fg: '#6B7280', bg: '#F1F2F4' };
}

function lienRdv(r: Rdv) {
  const futur = debutDe(r) > new Date();
  const onglet = r.statut === 'demande' || r.statut === 'contre_proposition' ? 'demandes' : r.statut === 'confirme' && futur ? 'a_venir' : 'historique';
  return `/mes-rdv?onglet=${onglet}&rdv=${r.id}`;
}

// Icônes vectorielles sobres (trait, 18 px).
const I = {
  cal: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><rect x="3" y="5" width="18" height="16" rx="2" /><path d="M16 3v4M8 3v4M3 10h18" /></svg>,
  maison: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><path d="M3 11l9-7 9 7v9a1 1 0 01-1 1h-5v-6H9v6H4a1 1 0 01-1-1z" /></svg>,
  suivi: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><rect x="3" y="5" width="18" height="16" rx="2" /><path d="M3 10h18M9 15l2 2 4-4" /></svg>,
  horloge: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></svg>,
  pin: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><path d="M12 21s7-6.2 7-12a7 7 0 10-14 0c0 5.8 7 12 7 12z" /><circle cx="12" cy="9" r="2.5" /></svg>,
  cloche: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><path d="M6 16V11a6 6 0 1112 0v5l2 2H4z" /><path d="M10 21h4" /></svg>,
  anneau: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><circle cx="12" cy="12" r="8" /><circle cx="12" cy="12" r="3.5" /></svg>,
  barres: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><path d="M5 20V12M10 20V6M15 20v-9M20 20V9" /></svg>,
  eclair: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><path d="M13 3L5 13h6l-1 8 8-10h-6z" /></svg>,
  cabinet: <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M4 21V8l8-5 8 5v13M9 21v-6h6v6" /></svg>,
};

export default function SanteDashboard({ nom, avatar }: { nom: string; avatar: string | null }) {
  const { user } = useAuth();
  const router = useRouter();
  const uid = user?.uid ?? '';
  const actifPid = useActiveProfile();
  const [pidPrincipal, setPidPrincipal] = useState('');
  const pid = actifPid || pidPrincipal;
  const [loading, setLoading] = useState(true);
  const [rdvs, setRdvs] = useState<Rdv[]>([]);
  const [suivis, setSuivis] = useState<Suivi[]>([]);
  const [suivisDispo, setSuivisDispo] = useState(true);
  const [clients, setClients] = useState<Record<string, string>>({});
  const [animaux, setAnimaux] = useState<Record<string, Animal>>({});
  const [now, setNow] = useState(() => new Date());
  const [jour, setJour] = useState(() => new Date());
  const [filtreLieu, setFiltreLieu] = useState<'tous' | 'cabinet' | 'domicile'>('tous');
  const [periode, setPeriode] = useState<'semaine' | 'mois' | 'annee'>('mois');
  const [choixCr, setChoixCr] = useState<Animal[] | null>(null);
  const [specialite, setSpecialite] = useState('');
  const [positionCabinet, setPositionCabinet] = useState<{ lat: number; lng: number } | null>(null);
  const planningRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!uid || actifPid) return;
    supabase.from('user_profiles_complet').select('id').eq('uid', uid).eq('is_main', true).maybeSingle()
      .then(({ data }) => setPidPrincipal((data as { id: string } | null)?.id ?? ''));
  }, [uid, actifPid]);

  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 60000);
    return () => clearInterval(t);
  }, []);

  const charger = useCallback(async () => {
    if (!pid) return;
    const n = new Date();
    const debutAnnee = new Date(n.getFullYear(), 0, 1);
    const lundi = new Date(n.getFullYear(), n.getMonth(), n.getDate() - ((n.getDay() + 6) % 7));
    const depuis = lundi < debutAnnee ? lundi : debutAnnee;
    const [rdvRes, suiviRes, profilRes] = await Promise.all([
      supabase.from('rdv')
        .select('id, date_heure, duree_minutes, statut, motif, animal_id, client_uid, client_profile_id, client_nom_manuel, animal_nom_manuel, lieu, lieu_lat, lieu_lng, salle_id, notes_client, created_at')
        .eq('pro_profile_id', pid)
        .or(`date_heure.gte.${depuis.toISOString()},statut.in.(demande,contre_proposition,confirme)`)
        .order('date_heure'),
      supabase.from('suivis_morpho')
        .select('id, animal_id, animal_nom_libre, type_suivi, date, prochain_controle, motif')
        .eq('pro_profile_id', pid).order('date', { ascending: false }),
      supabase.from('user_profiles_complet').select('profession_pro, latitude, longitude, lat, lng').eq('id', pid).maybeSingle(),
    ]);
    const prof = profilRes.data as { profession_pro?: string | null; latitude?: number | null; longitude?: number | null; lat?: number | null; lng?: number | null } | null;
    setSpecialite((prof?.profession_pro ?? '').trim());
    const cLat = prof?.latitude ?? prof?.lat, cLng = prof?.longitude ?? prof?.lng;
    setPositionCabinet(cLat != null && cLng != null ? { lat: Number(cLat), lng: Number(cLng) } : null);
    const liste = (rdvRes.data ?? []) as Rdv[];
    // Suivis à prévoir : dernier suivi de chaque animal avec un contrôle
    // conseillé (saisi par le praticien) dans les 30 jours ou dépassé.
    let aPrevoir: Suivi[] = [];
    if (suiviRes.error) setSuivisDispo(false);
    else {
      setSuivisDispo(true);
      const dernier = new Map<string, Suivi>();
      for (const s of (suiviRes.data ?? []) as Suivi[]) {
        const cle = s.animal_id ?? `libre:${s.id}`;
        if (!dernier.has(cle)) dernier.set(cle, s);
      }
      const limite = new Date(n.getFullYear(), n.getMonth(), n.getDate() + 30).toISOString().slice(0, 10);
      aPrevoir = [...dernier.values()].filter(s => s.prochain_controle && s.prochain_controle <= limite)
        .sort((a, b) => (a.prochain_controle ?? '').localeCompare(b.prochain_controle ?? ''));
    }
    const profils = [...new Set(liste.map(r => r.client_profile_id).filter(Boolean) as string[])];
    const ids = [...new Set([...liste.map(r => r.animal_id), ...aPrevoir.map(s => s.animal_id)].filter(Boolean).map(String))];
    const [profRes, animRes] = await Promise.all([
      profils.length ? supabase.from('user_profiles_complet').select('id, firstname, lastname, nom, profile_type').in('id', profils) : Promise.resolve({ data: [] }),
      ids.length ? supabase.from('animaux').select('id, nom, photo_url').in('id', ids) : Promise.resolve({ data: [] }),
    ]);
    const c: Record<string, string> = {};
    for (const p of (profRes.data ?? []) as { id: string; firstname?: string; lastname?: string; nom?: string; profile_type?: string }[]) {
      const perso = `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim();
      const structure = (p.nom ?? '').trim();
      c[p.id] = p.profile_type !== 'particulier' && structure ? structure : perso || structure;
    }
    const a: Record<string, Animal> = {};
    for (const x of (animRes.data ?? []) as Animal[]) a[String(x.id)] = x;
    setRdvs(liste); setSuivis(aPrevoir); setClients(c); setAnimaux(a); setLoading(false);
  }, [pid]);

  useEffect(() => {
    if (!pid) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    charger();
    // Compteurs à jour quand un RDV change (demande, confirmation…).
    const canal = supabase.channel(`dash-sante-${pid}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'rdv', filter: `pro_profile_id=eq.${pid}` }, () => { charger(); })
      .subscribe();
    return () => { supabase.removeChannel(canal); };
  }, [pid, charger]);

  const nomClient = (r: Rdv) => (r.client_profile_id && clients[r.client_profile_id]) || r.client_nom_manuel || 'Client';
  const nomAnimal = (r: { animal_id: string | null; animal_nom_manuel?: string | null; animal_nom_libre?: string | null }) =>
    (r.animal_id && animaux[String(r.animal_id)]?.nom) || r.animal_nom_manuel || r.animal_nom_libre || 'Animal non précisé';
  const photo = (r: { animal_id: string | null }) => (r.animal_id ? animaux[String(r.animal_id)]?.photo_url : null);
  const lieuCourt = (r: Rdv) => !estExterieur(r) ? 'Cabinet'
    : !r.lieu?.trim() || r.lieu.trim().toLowerCase() === 'à domicile' ? 'Domicile — adresse non renseignée' : `Domicile · ${r.lieu.trim()}`;

  const duJour = (j: Date) => rdvs.filter(r => memeJour(debutDe(r), j)).sort((a, b) => a.date_heure.localeCompare(b.date_heure));
  const aujourdhui = duJour(now).filter(actif);
  const demandes = rdvs.filter(r => r.statut === 'demande' || r.statut === 'contre_proposition')
    .sort((a, b) => (b.created_at ?? '').localeCompare(a.created_at ?? ''));

  // Prochain déplacement : prochain RDV extérieur confirmé + les autres RDV
  // du même jour à la même adresse (chaque animal garde son RDV / dossier).
  const deplacement = useMemo(() => {
    const cand = rdvs.filter(r => r.statut === 'confirme' && estExterieur(r) && finDe(r) > now)
      .sort((a, b) => a.date_heure.localeCompare(b.date_heure));
    if (!cand.length) return [];
    const p = cand[0];
    const memeLieu = (x: Rdv) => (x.lieu_lat != null && p.lieu_lat != null && x.lieu_lng != null && p.lieu_lng != null)
      ? Math.abs(x.lieu_lat - p.lieu_lat) < 0.0015 && Math.abs(x.lieu_lng - p.lieu_lng) < 0.0015
      : !!x.lieu?.trim() && x.lieu.trim().toLowerCase() === (p.lieu ?? '').trim().toLowerCase();
    return cand.filter(x => memeJour(debutDe(x), debutDe(p)) && memeLieu(x));
  }, [rdvs, now]);

  const planning = duJour(jour);
  const cabinet = planning.filter(r => !estExterieur(r));
  const domicile = planning.filter(estExterieur);
  const listePlanning = filtreLieu === 'cabinet' ? cabinet : filtreLieu === 'domicile' ? domicile : planning;
  const estAujourdhui = memeJour(jour, now);
  // Retard estimé en cascade (trajets compris) — aujourd'hui seulement.
  const retards = estAujourdhui ? retardsEnCascade(rdvs, now, { avecTrajets: true, cabinet: positionCabinet }) : {};
  const dateLongue = (d: Date) => d.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });

  async function choisirPatientCr() {
    const ids = new Set(rdvs.filter(r => r.animal_id && (r.statut === 'confirme' || r.statut === 'termine')).map(r => String(r.animal_id)));
    const { data: g } = await supabase.from('animal_access').select('animal_id').eq('pro_profile_id', pid).in('statut', ['active', 'active_write']);
    for (const x of (g ?? []) as { animal_id: string }[]) if (x.animal_id) ids.add(String(x.animal_id));
    if (!ids.size) { setChoixCr([]); return; }
    const { data } = await supabase.from('animaux').select('id, nom, photo_url').in('id', [...ids]).order('nom');
    setChoixCr((data ?? []) as Animal[]);
  }

  const libelleMetier = !specialite || specialite.toLowerCase().includes('osté') ? 'Ostéopathe animalier' : specialite;
  const chip = (actifChip: boolean) => `px-3 py-1.5 rounded-lg text-xs font-semibold border ${actifChip ? 'text-white border-transparent' : 'text-[#1E2025] border-[#E4E7E2] bg-white'}`;

  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-6xl mx-auto px-4 py-5 space-y-5">
        {/* En-tête */}
        <EnteteAccueil
          nom={nom}
          avatar={avatar}
          sousTitre={libelleMetier}
          actions={
            <span className="hidden sm:inline-flex items-center gap-2 text-sm text-[#1E2025] bg-white border border-[#E5E8E6] rounded-full px-3.5 py-2">
              {I.cal}<span className="first-letter:uppercase">{now.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}</span>
            </span>
          }
        />

        {loading ? (
          <div className="flex justify-center py-20"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>
        ) : (
          <>
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
              <Kpi valeur={aujourdhui.length} label="Rendez-vous aujourd'hui" icone={I.cal} href="/mes-rdv?onglet=a_venir" />
              <Kpi valeur={aujourdhui.filter(estExterieur).length} label="Visites à domicile" icone={I.maison} teinte={VERT}
                actif={filtreLieu === 'domicile' && estAujourdhui}
                onClick={() => { setJour(new Date()); setFiltreLieu('domicile'); planningRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' }); }} />
              <Kpi valeur={suivis.length} label="Suivis à prévoir" icone={I.suivi} teinte={VIOLET} href="/sante/suivis" />
              <Kpi valeur={demandes.length} label="Demandes en attente" icone={I.horloge} teinte={AMBRE} href="/mes-rdv?onglet=demandes" />
            </div>

            <div className="grid lg:grid-cols-3 gap-5 items-start">
              {/* Planning du jour */}
              <div ref={planningRef} className="lg:col-span-2">
                <Section titre="Planning du jour" icone={I.cal}
                  action={<Link href="/mes-rdv?onglet=a_venir" className="text-sm font-bold" style={{ color: TEAL }}>Voir l&apos;agenda complet</Link>}>
                  <div className="flex flex-wrap items-center gap-2 mb-3">
                    {([['tous', `Tous (${planning.length})`], ['cabinet', `Cabinet (${cabinet.length})`], ['domicile', `Domicile (${domicile.length})`]] as const).map(([k, l]) => (
                      <button key={k} onClick={() => setFiltreLieu(k)} className={chip(filtreLieu === k)} style={filtreLieu === k ? { background: TEAL } : undefined}>{l}</button>
                    ))}
                    <span className="flex-1" />
                    <div className="flex items-center gap-1 border border-[#E5E8E6] rounded-lg px-1">
                      <button aria-label="Jour précédent" onClick={() => setJour(d => new Date(d.getFullYear(), d.getMonth(), d.getDate() - 1))} className="px-2 py-1 text-[#0C5C6C]">‹</button>
                      <button onClick={() => setJour(new Date())} className="text-xs font-semibold text-[#1E2025] px-1 first-letter:uppercase">
                        {estAujourdhui ? `Aujourd'hui · ${dateLongue(jour)}` : dateLongue(jour)}
                      </button>
                      <button aria-label="Jour suivant" onClick={() => setJour(d => new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1))} className="px-2 py-1 text-[#0C5C6C]">›</button>
                    </div>
                  </div>
                  {listePlanning.length === 0 ? (
                    <p className="text-sm text-gray-400 text-center py-8">{planning.length === 0 ? 'Aucun rendez-vous ce jour.' : 'Aucun rendez-vous pour ce filtre.'}</p>
                  ) : (
                    <div className="space-y-2">
                      {listePlanning.map(r => {
                        const st = statut(r, now);
                        const annuleRdv = st.label === 'Annulé';
                        const ext = estExterieur(r);
                        return (
                          <Link key={r.id} href={lienRdv(r)} className="flex items-center gap-3 border border-[#EEF0EE] rounded-xl px-3 py-2.5 hover:bg-gray-50">
                            <div className="w-12 flex-shrink-0">
                              <p className={`text-sm font-bold ${annuleRdv ? 'text-gray-400 line-through' : 'text-[#1E2025]'}`}>{hm(debutDe(r))}</p>
                              <p className="text-[11px] text-gray-500">{r.duree_minutes ?? 45} min</p>
                            </div>
                            <PhotoAnimal url={photo(r)} />
                            <div className="min-w-0 sm:w-40 flex-shrink-0">
                              <p className={`text-sm font-bold truncate ${annuleRdv ? 'text-gray-400' : 'text-[#1E2025]'}`}>{nomAnimal(r)}</p>
                              <p className="text-xs text-gray-500 truncate">{nomClient(r)}</p>
                            </div>
                            <div className="hidden sm:block flex-1 min-w-0">
                              <p className="text-sm font-semibold text-[#1E2025] truncate">{r.motif?.trim() || 'Rendez-vous'}</p>
                              <p className="text-xs truncate flex items-center gap-1" style={{ color: ext ? VERT : '#6B7280' }}>{ext ? I.maison : I.cabinet}<span className="truncate">{lieuCourt(r)}</span></p>
                            </div>
                            <div className="flex-1 sm:hidden" />
                            <span className="flex flex-col items-end gap-0.5">
                              <Badge texte={st.label} fg={st.fg} bg={st.bg} />
                              {(retards[r.id] ?? 0) >= 5 && <span className="text-[11px] font-bold" style={{ color: '#B45309' }}>+{retards[r.id]} min</span>}
                            </span>
                            <span className="text-gray-400">›</span>
                          </Link>
                        );
                      })}
                    </div>
                  )}
                </Section>
              </div>

              <div className="space-y-5">
                {/* Prochain déplacement */}
                <Section titre="Prochain déplacement" icone={I.pin}
                  action={deplacement[0] && (deplacement[0].lieu?.trim() || deplacement[0].lieu_lat != null)
                    ? <ItineraireMenu lat={deplacement[0].lieu_lat} lng={deplacement[0].lieu_lng} adresse={deplacement[0].lieu}
                        className="text-sm font-bold text-[#0C5C6C]">Voir l&apos;itinéraire ▾</ItineraireMenu> : undefined}>
                  {deplacement.length === 0 ? (
                    <p className="text-sm text-gray-400">Aucun rendez-vous extérieur à venir.</p>
                  ) : (() => {
                    const r = deplacement[0];
                    const sansAdresse = !r.lieu?.trim() && r.lieu_lat == null;
                    return (
                      <div className="flex gap-3">
                        <p className="text-lg font-extrabold text-[#1E2025]">{hm(debutDe(r))}</p>
                        <div className="min-w-0 text-sm">
                          <p className="font-bold text-[#1E2025]">{memeJour(debutDe(r), now) ? '' : `${jm(debutDe(r))} · `}{nomClient(r)}</p>
                          <p className="text-xs" style={{ color: sansAdresse ? AMBRE : '#6B7280' }}>{sansAdresse ? "Adresse d'intervention non renseignée" : r.lieu?.trim() || 'Position enregistrée'}</p>
                          <p className="text-xs text-[#1E2025] mt-1">{deplacement.length > 1 ? `${deplacement.length} animaux : ${deplacement.map(nomAnimal).join(', ')}` : nomAnimal(r)}</p>
                          {r.notes_client?.trim() && <p className="text-xs text-gray-500 mt-1 line-clamp-3">Infos : {r.notes_client.trim()}</p>}
                        </div>
                      </div>
                    );
                  })()}
                </Section>

                {/* Demandes en attente */}
                <Section titre="Demandes en attente" icone={I.cloche} compteur={demandes.length}
                  action={demandes.length ? <Link href="/mes-rdv?onglet=demandes" className="text-sm font-bold" style={{ color: TEAL }}>Voir toutes</Link> : undefined}>
                  {demandes.length === 0 ? <p className="text-sm text-gray-400">Aucune demande à traiter.</p> : demandes.slice(0, 3).map(r => {
                    const c = r.created_at ? new Date(r.created_at) : null;
                    const j = c ? Math.round((new Date(now.toDateString()).getTime() - new Date(c.toDateString()).getTime()) / 86400000) : null;
                    return (
                      <Link key={r.id} href={lienRdv(r)} className="flex items-center gap-2 py-1.5 hover:bg-gray-50 rounded-lg">
                        <PhotoAnimal url={photo(r)} taille={32} />
                        <div className="flex-1 min-w-0">
                          <p className="text-[13px] font-bold text-[#1E2025] truncate">{nomAnimal(r)} · {nomClient(r)}</p>
                          <p className="text-[11.5px] text-gray-500 truncate">{[r.motif?.trim() || 'Rendez-vous', `pour le ${jm(debutDe(r))} ${hm(debutDe(r))}`, estExterieur(r) ? lieuCourt(r) : null].filter(Boolean).join(' · ')}</p>
                        </div>
                        <span className="text-[11.5px] font-semibold text-red-600 whitespace-nowrap">{j === 0 ? "Aujourd'hui" : j === 1 ? 'Hier' : c ? jm(c) : ''}</span>
                        <span className="text-gray-400">›</span>
                      </Link>
                    );
                  })}
                </Section>

                {/* Suivis à prévoir */}
                <Section titre="Suivis à prévoir" icone={I.suivi} compteur={suivis.length}
                  action={<Link href="/sante/suivis" className="text-sm font-bold" style={{ color: TEAL }}>Voir tous</Link>}>
                  {!suivisDispo ? <p className="text-xs text-gray-500">Indiquez un « prochain contrôle conseillé » dans vos suivis pour les retrouver ici.</p>
                    : suivis.length === 0 ? <p className="text-sm text-gray-400">Aucun contrôle conseillé dans les 30 prochains jours.</p>
                    : suivis.slice(0, 3).map(s => {
                      const d = new Date(`${s.prochain_controle}T00:00:00`);
                      const ecart = Math.round((d.getTime() - new Date(now.toDateString()).getTime()) / 86400000);
                      return (
                        <Link key={s.id} href={`/sante/suivis/${s.id}`} className="flex items-center gap-2 py-1.5 hover:bg-gray-50 rounded-lg">
                          <PhotoAnimal url={photo(s)} taille={32} />
                          <div className="flex-1 min-w-0">
                            <p className="text-[13px] font-bold text-[#1E2025] truncate">{nomAnimal(s)}</p>
                            <p className="text-[11.5px] text-gray-500 truncate">{[TYPES_SUIVI[s.type_suivi ?? ''] ?? 'Suivi', s.date ? `dernière séance ${jm(new Date(s.date))}` : null].filter(Boolean).join(' · ')}</p>
                          </div>
                          <span className={`text-[11.5px] font-semibold whitespace-nowrap ${ecart < 0 ? 'text-red-600' : 'text-gray-500'}`}>{ecart < 0 ? 'En retard' : ecart === 0 ? "Aujourd'hui" : `Dans ${ecart} j`}</span>
                          <span className="text-gray-400">›</span>
                        </Link>
                      );
                    })}
                </Section>
              </div>
            </div>

            <Statistiques rdvs={rdvs} now={now} periode={periode} setPeriode={setPeriode} />

            {/* Accès rapides */}
            <Section titre="Accès rapides" icone={I.eclair}>
              <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
                {[
                  { l: 'Nouveau RDV', href: '/mes-rdv?onglet=a_venir&nouveau=1' },
                  { l: 'Rechercher un patient', href: '/mes-patients' },
                  { l: 'Créer un suivi', href: '/sante/suivis/nouveau' },
                  { l: 'Rédiger un compte rendu', onClick: choisirPatientCr },
                  { l: 'Itinéraire du prochain déplacement', itineraire: deplacement[0] && (deplacement[0].lieu?.trim() || deplacement[0].lieu_lat != null) ? deplacement[0] : undefined },
                  { l: 'Envoyer un message', href: '/messages' },
                ].map(t => {
                  const cls = 'border border-[#E5E8E6] rounded-xl px-3 py-2.5 text-sm font-semibold text-left';
                  if (t.onClick) return <button key={t.l} onClick={t.onClick} className={`${cls} text-[#1E2025] hover:bg-gray-50`}>{t.l}</button>;
                  if ('itineraire' in t) {
                    return t.itineraire
                      ? <ItineraireMenu key={t.l} lat={t.itineraire.lieu_lat} lng={t.itineraire.lieu_lng} adresse={t.itineraire.lieu}
                          className={`${cls} w-full text-[#1E2025] hover:bg-gray-50`}>{t.l}</ItineraireMenu>
                      : <span key={t.l} className={`${cls} text-gray-300`} title="Aucun déplacement prévu">{t.l}</span>;
                  }
                  if (!t.href) return <span key={t.l} className={`${cls} text-gray-300`}>{t.l}</span>;
                  return <Link key={t.l} href={t.href} className={`${cls} text-[#1E2025] hover:bg-gray-50`}>{t.l}</Link>;
                })}
              </div>
            </Section>
          </>
        )}
      </div>

      {choixCr && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={() => setChoixCr(null)}>
          <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-md p-5 max-h-[80vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
            <h3 className="font-bold text-[#1E2025] mb-3">Compte rendu — choisir le patient</h3>
            {choixCr.length === 0 ? <p className="text-sm text-gray-500">Aucun patient pour l&apos;instant : un compte rendu se rédige pour un animal suivi.</p>
              : choixCr.map(a => (
                <button key={a.id} onClick={() => router.push(`/mes-patients/${a.id}`)} className="w-full flex items-center gap-3 py-2 hover:bg-gray-50 rounded-lg text-left">
                  <PhotoAnimal url={a.photo_url} taille={34} />
                  <span className="text-sm font-semibold text-[#1E2025]">{a.nom ?? 'Animal'}</span>
                </button>
              ))}
          </div>
        </div>
      )}
    </div>
  );
}

function Statistiques({ rdvs, now, periode, setPeriode }: {
  rdvs: Rdv[]; now: Date; periode: 'semaine' | 'mois' | 'annee'; setPeriode: (p: 'semaine' | 'mois' | 'annee') => void;
}) {
  const lundi = new Date(now.getFullYear(), now.getMonth(), now.getDate() - ((now.getDay() + 6) % 7));
  const [debut, fin] = periode === 'semaine'
    ? [lundi, new Date(lundi.getFullYear(), lundi.getMonth(), lundi.getDate() + 7)]
    : periode === 'annee'
      ? [new Date(now.getFullYear(), 0, 1), new Date(now.getFullYear() + 1, 0, 1)]
      : [new Date(now.getFullYear(), now.getMonth(), 1), new Date(now.getFullYear(), now.getMonth() + 1, 1)];
  const faits = rdvs.filter(r => r.statut === 'confirme' || r.statut === 'termine');
  const cle = (r: Rdv) => { const m = (r.motif ?? '').trim(); return m ? m[0].toUpperCase() + m.slice(1) : 'Sans motif'; };
  // Couleur = motif (ordre de première apparition sur l'année), pas le rang.
  const ordre: string[] = [];
  for (const r of faits) { const k = cle(r); if (!ordre.includes(k)) ordre.push(k); }
  const periodeRdv = faits.filter(r => { const d = debutDe(r); return d >= debut && d < fin; });
  const parMotif: Record<string, number> = {};
  for (const r of periodeRdv) parMotif[cle(r)] = (parMotif[cle(r)] ?? 0) + 1;
  const tries = Object.entries(parMotif).sort((a, b) => b[1] - a[1]);
  const garde = new Set(tries.slice(0, 5).map(([k]) => k));
  const gardesOrdonnes = ordre.filter(k => garde.has(k));
  const segments: Segment[] = [
    ...gardesOrdonnes.map((k, i) => ({ key: k, label: k, color: PALETTE[Math.min(i, 4)], n: parMotif[k] })),
    ...(tries.length > 5 ? [{ key: '_autre', label: 'Autre', color: PALETTE[5], n: tries.slice(5).reduce((a, [, v]) => a + v, 0) }] : []),
  ];
  const cabinet = periodeRdv.filter(r => !estExterieur(r)).length;
  const domicile = periodeRdv.length - cabinet;

  const realises = [0, 0, 0, 0, 0, 0, 0], programmes = [0, 0, 0, 0, 0, 0, 0], annules = [0, 0, 0, 0, 0, 0, 0];
  for (const r of rdvs) {
    const d = debutDe(r);
    const i = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime() - lundi.getTime()) / 86400000);
    if (i < 0 || i > 6) continue;
    if (r.statut === 'termine') realises[i]++;
    else if (r.statut === 'confirme') programmes[i]++;
    else if (r.statut === 'annule' || r.statut === 'refuse') annules[i]++;
  }
  const barreLieu = (label: string, n: number, c: string) => {
    const total = cabinet + domicile;
    return (
      <div className="flex items-center gap-3 text-sm">
        <span className="w-20 text-[#1E2025]">{label}</span>
        <div className="flex-1 h-2 rounded bg-[#F1F4F3] overflow-hidden"><div className="h-full rounded" style={{ width: total ? `${(n / total) * 100}%` : 0, background: c }} /></div>
        <span className="w-20 text-right font-bold text-[#1E2025]">{n}{total ? ` · ${Math.round(n * 100 / total)} %` : ''}</span>
      </div>
    );
  };

  return (
    <div className="grid lg:grid-cols-2 gap-5">
      <Section titre="Répartition des rendez-vous" icone={I.anneau}
        action={
          <select value={periode} onChange={e => setPeriode(e.target.value as 'semaine' | 'mois' | 'annee')} className="border border-gray-200 rounded-lg px-2 py-1 text-xs">
            <option value="semaine">Cette semaine</option><option value="mois">Ce mois</option><option value="annee">Cette année</option>
          </select>
        }>
        <p className="text-xs text-gray-500 mb-3">Par motif de réservation · RDV confirmés et terminés</p>
        {segments.length === 0 ? <p className="text-sm text-gray-400 text-center py-10">Aucun rendez-vous sur la période.</p> : (
          <>
            <Donut segments={segments} />
            <p className="text-sm font-bold text-[#1E2025] mt-4 mb-2">Lieu des consultations</p>
            <div className="space-y-2">{barreLieu('Cabinet', cabinet, TEAL)}{barreLieu('Domicile', domicile, VERT)}</div>
          </>
        )}
      </Section>
      <Section titre="Activité de la semaine" icone={I.barres}>
        <p className="text-xs text-gray-500 mb-3">RDV par jour</p>
        <BarresSemaine series={[realises, programmes, annules]} couleurs={[VERT, TEAL, '#B8BEC6']}
          libelles={['Séances réalisées', 'Programmés', 'Annulés']} aujourdhui={(now.getDay() + 6) % 7} />
      </Section>
    </div>
  );
}
