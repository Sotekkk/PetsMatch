'use client';

// Accueil vétérinaire : tableau de bord de gestion de la clinique.
// Uniquement des données réelles (rdv, comptes_rendus, praticiens) ; chaque
// indicateur / ligne ouvre le module existant (agenda, Mes patients, fiche
// patient) — aucun module médical parallèle. Miroir appli :
// lib/pages/pro/vet_dashboard.dart.

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { retardsEnCascade } from '@/lib/retards-rdv';
import TuilesSanteVet from '@/components/dashboard/TuilesSanteVet';

const TEAL = '#0C5C6C';

/** Motifs de réservation (≠ actes réalisés, qui vivent dans les comptes
 *  rendus). Couleurs : palette catégorielle validée daltonisme, ordre fixe. */
export const VET_MOTIFS = [
  { key: 'consultation', label: 'Consultation', color: '#2a78d6' },
  { key: 'vaccination', label: 'Vaccination', color: '#eb6834' },
  { key: 'bilan', label: 'Bilan annuel', color: '#1baf7a' },
  { key: 'urgence', label: 'Urgence', color: '#eda100' },
  { key: 'chirurgie', label: 'Chirurgie', color: '#e87ba4' },
  { key: 'autre', label: 'Autre', color: '#008300' },
] as const;

/** Classe le motif saisi à la réservation (texte libre ou prestation). */
export function categorieMotif(motif?: string | null): string {
  const m = (motif ?? '').toLowerCase();
  if (m.includes('urgen')) return 'urgence';
  if (m.includes('vaccin') || m.includes('rappel')) return 'vaccination';
  if (m.includes('bilan') || m.includes('annuel') || m.includes('check')) return 'bilan';
  if (['chirurg', 'opérat', 'operat', 'stérilis', 'sterilis', 'castra'].some(k => m.includes(k))) return 'chirurgie';
  if (m.includes('consult') || !m) return 'consultation';
  return 'autre';
}

interface Rdv {
  id: string; date_heure: string; duree_minutes: number | null; statut: string; motif: string | null;
  animal_id: string | null; client_uid: string | null; client_profile_id: string | null;
  client_nom_manuel: string | null; animal_nom_manuel: string | null;
  instructeur_profile_id: string | null; praticien_indifferent: boolean | null; termine_at: string | null;
}
interface Cr { id: string; animal_id: string | null; created_at: string; motif: string | null }
interface Animal { id: string; nom: string | null; espece: string | null; photo_url: string | null }

const debutDe = (r: Rdv) => new Date(r.date_heure);
const finDe = (r: Rdv) => new Date(debutDe(r).getTime() + (r.duree_minutes ?? 30) * 60000);
const praticienDe = (r: Rdv) => r.instructeur_profile_id ?? '';
const memeJour = (a: Date, b: Date) => a.toDateString() === b.toDateString();
const hm = (d: Date) => d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
const jm = (d: Date) => d.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' });

/** Statut affiché (« en cours » / « à clôturer » sont calculés). */
function statutRdv(r: Rdv, now: Date): { label: string; fg: string; bg: string } {
  switch (r.statut) {
    case 'demande': case 'contre_proposition': return { label: 'En attente', fg: '#8A5A00', bg: '#FFF4DC' };
    case 'termine': return { label: 'Terminé', fg: '#4B5563', bg: '#F1F2F4' };
    case 'annule': case 'refuse': return { label: 'Annulé', fg: '#9CA3AF', bg: '#F7F7F8' };
    case 'confirme':
      if (now >= debutDe(r) && now < finDe(r)) return { label: 'En cours', fg: '#1D4ED8', bg: '#E8F0FE' };
      if (now >= finDe(r)) return { label: 'À clôturer', fg: '#B45309', bg: '#FFEDD5' };
      return { label: 'Confirmé', fg: TEAL, bg: '#E6F2F3' };
  }
  return { label: r.statut, fg: '#6B7280', bg: '#F1F2F4' };
}

function ongletDe(r: Rdv) {
  return r.statut === 'demande' || r.statut === 'contre_proposition' ? 'demandes' : r.statut === 'confirme' ? 'a_venir' : 'historique';
}
const lienRdv = (r: Rdv) => `/mes-rdv?onglet=${ongletDe(r)}&rdv=${r.id}`;

export default function VetDashboard({ nom, avatar }: { nom: string; avatar: string | null }) {
  const { user, userData } = useAuth();
  const uid = user?.uid ?? '';
  const actif = useActiveProfile();
  const [pidPrincipal, setPidPrincipal] = useState('');
  const pid = actif || pidPrincipal;
  const [loading, setLoading] = useState(true);
  const [rdvs, setRdvs] = useState<Rdv[]>([]);
  const [crs, setCrs] = useState<Cr[]>([]);
  const [praticiens, setPraticiens] = useState<{ id: string; nom: string }[]>([]);
  const [clients, setClients] = useState<Record<string, string>>({});
  const [animaux, setAnimaux] = useState<Record<string, Animal>>({});
  const [patientsCount, setPatientsCount] = useState(0);
  const [filtrePlanning, setFiltrePlanning] = useState('*'); // '*' = toute la clinique, '' = titulaire
  const [periode, setPeriode] = useState<'semaine' | 'mois' | 'annee'>('mois');
  const [filtreStats, setFiltreStats] = useState('*');
  const [now, setNow] = useState(() => new Date());

  // Profil de la clinique : le profil actif, sinon le profil principal.
  useEffect(() => {
    if (!uid || actif) return;
    supabase.from('user_profiles_complet').select('id').eq('uid', uid).eq('is_main', true).maybeSingle()
      .then(({ data }) => setPidPrincipal((data as { id: string } | null)?.id ?? ''));
  }, [uid, actif]);

  // Statuts calculés (en cours, à clôturer, retards) : rafraîchis chaque minute.
  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 60000);
    return () => clearInterval(t);
  }, []);

  useEffect(() => {
    if (!pid || !uid) return;
    let annule = false;
    (async () => {
      const n = new Date();
      const debutAnnee = new Date(n.getFullYear(), 0, 1);
      const lundi = new Date(n.getFullYear(), n.getMonth(), n.getDate() - ((n.getDay() + 6) % 7));
      const depuis = lundi < debutAnnee ? lundi : debutAnnee;
      const [rdvRes, crRes, pratRes, grantRes, rdvAnimRes] = await Promise.all([
        supabase.from('rdv')
          .select('id, date_heure, duree_minutes, statut, motif, animal_id, client_uid, client_profile_id, client_nom_manuel, animal_nom_manuel, instructeur_profile_id, praticien_indifferent, termine_at')
          .eq('pro_profile_id', pid)
          .or(`date_heure.gte.${depuis.toISOString()},statut.in.(demande,contre_proposition,confirme)`)
          .order('date_heure'),
        supabase.from('comptes_rendus').select('id, animal_id, created_at, motif')
          .eq('pro_profile_id', pid).eq('statut', 'brouillon').order('created_at', { ascending: false }).limit(20),
        supabase.rpc('pm_praticiens_clinique', { p_pro_profile_id: pid }),
        // Patients suivis : même règle que /mes-patients.
        supabase.from('animal_access').select('animal_id').eq('pro_profile_id', pid).neq('statut', 'revoked'),
        supabase.from('rdv').select('animal_id').eq('pro_uid', uid).eq('pro_profile_id', pid)
          .in('statut', ['confirme', 'termine']).not('animal_id', 'is', null),
      ]);
      if (annule) return;
      const liste = (rdvRes.data ?? []) as Rdv[];
      const brouillons = (crRes.data ?? []) as Cr[];
      setRdvs(liste);
      setCrs(brouillons);
      setPraticiens(((pratRes.data ?? []) as { praticien_profile_id: string | null; nom: string | null }[])
        .map(p => ({ id: p.praticien_profile_id ?? '', nom: p.nom?.trim() || 'Vétérinaire' })));
      setPatientsCount(new Set([
        ...((grantRes.data ?? []) as { animal_id: string }[]).map(g => String(g.animal_id)),
        ...((rdvAnimRes.data ?? []) as { animal_id: string }[]).map(r => String(r.animal_id)),
      ].filter(Boolean)).size);

      // Noms utiles : planning du jour + actions (pas toute l'année).
      const utiles = liste.filter(r => memeJour(debutDe(r), n) || ['demande', 'contre_proposition'].includes(r.statut)
        || (r.statut === 'confirme' && finDe(r) <= n));
      const profils = [...new Set(utiles.map(r => r.client_profile_id).filter(Boolean) as string[])];
      const ids = [...new Set([...utiles.map(r => r.animal_id), ...brouillons.map(c => c.animal_id)].filter(Boolean).map(String))];
      const [profRes, animRes] = await Promise.all([
        profils.length ? supabase.from('user_profiles_complet').select('id, firstname, lastname, nom').in('id', profils) : Promise.resolve({ data: [] }),
        ids.length ? supabase.from('animaux').select('id, nom, espece, photo_url').in('id', ids) : Promise.resolve({ data: [] }),
      ]);
      if (annule) return;
      const c: Record<string, string> = {};
      for (const p of (profRes.data ?? []) as { id: string; firstname?: string; lastname?: string; nom?: string }[]) {
        c[p.id] = `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim() || p.nom || '';
      }
      const a: Record<string, Animal> = {};
      for (const x of (animRes.data ?? []) as Animal[]) a[String(x.id)] = x;
      setClients(c);
      setAnimaux(a);
      setLoading(false);
    })();
    return () => { annule = true; };
  }, [pid, uid]);

  const nomClient = (r: Rdv) => (r.client_profile_id && clients[r.client_profile_id]) || r.client_nom_manuel || 'Client';
  const nomAnimal = (r: { animal_id: string | null; animal_nom_manuel?: string | null }) =>
    (r.animal_id && animaux[String(r.animal_id)]?.nom) || r.animal_nom_manuel || 'Animal non précisé';
  const nomPraticien = (id: string) => praticiens.find(p => p.id === id)?.nom ?? 'Vétérinaire';
  const plusieurs = praticiens.length > 1;

  const planningJour = (filtre: string) => rdvs.filter(r => memeJour(debutDe(r), now) && (filtre === '*'
    || praticienDe(r) === filtre || (r.praticien_indifferent === true && r.statut === 'demande')));
  const demandes = rdvs.filter(r => r.statut === 'demande' || r.statut === 'contre_proposition');
  const aCloturer = rdvs.filter(r => r.statut === 'confirme' && finDe(r) <= now)
    .sort((a, b) => b.date_heure.localeCompare(a.date_heure));
  const rdvAujourdhui = planningJour('*').filter(r => ['confirme', 'termine', 'demande', 'contre_proposition'].includes(r.statut)).length;
  const retards = retardsEnCascade(rdvs, now);
  const retardMax = Math.max(0, ...Object.values(retards));
  const planning = planningJour(filtrePlanning).sort((a, b) => a.date_heure.localeCompare(b.date_heure));

  const personne = `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim();
  const dateJour = now.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });

  return (
    <div className="min-h-screen bg-[#F8F8F8]" style={{ fontFamily: 'Galey, sans-serif' }}>
      {/* En-tête */}
      <div className="text-white" style={{ background: `linear-gradient(135deg, ${TEAL}, #5F9EAA)` }}>
        <div className="max-w-6xl mx-auto px-4 py-6 flex items-center gap-4">
          <div className="w-14 h-14 rounded-full overflow-hidden bg-white/20 flex-shrink-0 border-2 border-white/30">
            {avatar
              ? <Image src={avatar} alt="" width={56} height={56} className="object-cover w-full h-full" />
              : <div className="w-full h-full flex items-center justify-center text-xl font-bold">{nom[0]?.toUpperCase() ?? '?'}</div>}
          </div>
          <div className="flex-1 min-w-0">
            <h1 className="text-xl font-bold truncate">{nom}</h1>
            <p className="text-sm font-semibold text-white/90 truncate">{[personne, 'Vétérinaire · Gérant'].filter(Boolean).join(' — ')}</p>
            <p className="text-xs text-white/75 first-letter:uppercase">{dateJour}</p>
          </div>
        </div>
      </div>

      <div className="max-w-6xl mx-auto px-4 py-5 space-y-5">
        {loading ? (
          <div className="flex justify-center py-20"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>
        ) : (
          <>
            {/* Notifications pertinentes */}
            {(retardMax > 0 || demandes.length > 0) && (
              <div className="flex flex-wrap gap-2">
                {retardMax > 0 && (
                  <Link href="/mes-rdv?onglet=a_venir" className="inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-sm font-bold" style={{ background: '#FFEDD5', color: '#B45309' }}>
                    ⏱ Retard estimé : +{retardMax} min
                  </Link>
                )}
                {demandes.length > 0 && (
                  <Link href="/mes-rdv?onglet=demandes" className="inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-sm font-bold" style={{ background: '#FFF4DC', color: '#8A5A00' }}>
                    🔔 {demandes.length} demande{demandes.length > 1 ? 's' : ''} à confirmer
                  </Link>
                )}
              </div>
            )}

            {/* Indicateurs */}
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
              <Kpi valeur={rdvAujourdhui} label="RDV aujourd'hui" icone="📅" href="/mes-rdv?onglet=a_venir" />
              <Kpi valeur={demandes.length} label="Demandes à confirmer" icone="📨" href="/mes-rdv?onglet=demandes" />
              <Kpi valeur={aCloturer.length} label="Consultations à clôturer" icone="📋" href="/mes-rdv?onglet=a_venir" />
              <Kpi valeur={patientsCount} label="Patients suivis" icone="🩺" href="/mes-patients" />
            </div>

            <div className="grid lg:grid-cols-3 gap-5 items-start">
              {/* Planning du jour */}
              <section className={`bg-white rounded-2xl border border-[#E4E7E2] p-4 ${demandes.length || aCloturer.length || crs.length ? 'lg:col-span-2' : 'lg:col-span-3'}`}>
                <div className="flex items-center gap-2 mb-2">
                  <h2 className="flex-1 font-bold text-base text-[#1E2025]">Planning du jour</h2>
                  <Link href="/mes-rdv?onglet=a_venir" className="text-sm font-bold" style={{ color: TEAL }}>Voir l&apos;agenda complet</Link>
                </div>
                {plusieurs && (
                  <div className="flex gap-1.5 overflow-x-auto pb-2">
                    {[{ id: '*', nom: 'Toute la clinique' }, ...praticiens].map(p => (
                      <button key={p.id} onClick={() => setFiltrePlanning(p.id)}
                        className="px-3 py-1 rounded-full text-xs font-semibold whitespace-nowrap"
                        style={filtrePlanning === p.id ? { background: TEAL, color: 'white' } : { background: '#F1F4F3', color: '#1E2025' }}>
                        {p.nom}
                      </button>
                    ))}
                  </div>
                )}
                {planning.length === 0 ? (
                  <p className="text-sm text-gray-400 text-center py-8">Aucun rendez-vous aujourd&apos;hui.</p>
                ) : (
                  <div>
                    {planning.map(r => {
                      const st = statutRdv(r, now);
                      const annuleRdv = st.label === 'Annulé';
                      const retard = retards[r.id];
                      const sous = [nomClient(r), r.motif?.trim(),
                        plusieurs ? (r.praticien_indifferent && r.statut === 'demande' ? 'Peu importe' : nomPraticien(praticienDe(r))) : null,
                      ].filter(Boolean).join(' · ');
                      return (
                        <Link key={r.id} href={lienRdv(r)} className="flex items-center gap-3 py-2.5 px-1 border-b border-[#F0F1EF] last:border-0 hover:bg-gray-50 rounded-lg">
                          <div className="w-12 flex-shrink-0">
                            <p className={`text-sm font-bold ${annuleRdv ? 'text-gray-400 line-through' : 'text-[#1E2025]'}`}>{hm(debutDe(r))}</p>
                            <p className="text-[11px] text-gray-500">{r.duree_minutes ?? 30} min</p>
                          </div>
                          <PhotoAnimal url={r.animal_id ? animaux[String(r.animal_id)]?.photo_url : null} />
                          <div className="flex-1 min-w-0">
                            <p className={`text-sm font-bold truncate ${annuleRdv ? 'text-gray-400' : 'text-[#1E2025]'}`}>{nomAnimal(r)}</p>
                            <p className="text-xs text-gray-500 truncate">{sous}</p>
                          </div>
                          <div className="flex flex-col items-end gap-0.5">
                            <span className="text-[11px] font-bold px-2 py-0.5 rounded-full" style={{ color: st.fg, background: st.bg }}>{st.label}</span>
                            {retard > 0 && <span className="text-[11px] font-bold" style={{ color: '#B45309' }}>+{retard} min</span>}
                          </div>
                        </Link>
                      );
                    })}
                  </div>
                )}
              </section>

              {/* Actions — aucune section vide */}
              {(demandes.length > 0 || aCloturer.length > 0 || crs.length > 0) && (
                <section className="bg-white rounded-2xl border border-[#E4E7E2] p-4 space-y-4">
                  <h2 className="font-bold text-base text-[#1E2025]">Actions</h2>
                  {demandes.length > 0 && (
                    <GroupeActions titre="Demandes en attente" total={demandes.length} voirTout="/mes-rdv?onglet=demandes">
                      {[...demandes].sort((a, b) => a.date_heure.localeCompare(b.date_heure)).slice(0, 4).map(r => (
                        <LigneAction key={r.id} href={lienRdv(r)} titre={nomAnimal(r)}
                          detail={`${jm(debutDe(r))} ${hm(debutDe(r))} · ${nomClient(r)}`}
                          photo={r.animal_id ? animaux[String(r.animal_id)]?.photo_url : null} />
                      ))}
                    </GroupeActions>
                  )}
                  {aCloturer.length > 0 && (
                    <GroupeActions titre="Consultations à clôturer" total={aCloturer.length} voirTout="/mes-rdv?onglet=a_venir">
                      {aCloturer.slice(0, 4).map(r => (
                        <LigneAction key={r.id} href={lienRdv(r)} titre={nomAnimal(r)}
                          detail={`${jm(debutDe(r))} ${hm(debutDe(r))} · ${r.motif || 'Consultation'}`}
                          photo={r.animal_id ? animaux[String(r.animal_id)]?.photo_url : null} />
                      ))}
                    </GroupeActions>
                  )}
                  {crs.length > 0 && (
                    <GroupeActions titre="Comptes rendus à valider" total={crs.length} voirTout="/mes-patients">
                      {crs.slice(0, 4).map(c => (
                        <LigneAction key={c.id} href={c.animal_id ? `/mes-patients/${c.animal_id}` : '/mes-patients'}
                          titre={nomAnimal(c)}
                          detail={`Brouillon du ${jm(new Date(c.created_at))}${c.motif ? ` · ${c.motif}` : ''}`}
                          photo={c.animal_id ? animaux[String(c.animal_id)]?.photo_url : null} />
                      ))}
                    </GroupeActions>
                  )}
                </section>
              )}
            </div>

            <Statistiques rdvs={rdvs} now={now} periode={periode} setPeriode={setPeriode}
              filtre={filtreStats} setFiltre={setFiltreStats} praticiens={praticiens} />

            <TuilesSanteVet catPro="veterinaire" uid={uid} profileId={pid} abonnementHref="/veterinaire/abonnement" />
          </>
        )}
      </div>
    </div>
  );
}

function Kpi({ valeur, label, icone, href }: { valeur: number; label: string; icone: string; href: string }) {
  return (
    <Link href={href} className="bg-white rounded-2xl border border-[#E4E7E2] p-4 hover:shadow-md transition-shadow flex flex-col gap-1">
      <div className="flex items-center"><span className="text-lg" aria-hidden>{icone}</span><span className="ml-auto text-gray-400">›</span></div>
      <p className="text-3xl font-extrabold text-[#1E2025] leading-tight">{valeur}</p>
      <p className="text-xs text-gray-500">{label}</p>
    </Link>
  );
}

function PhotoAnimal({ url, taille = 38 }: { url?: string | null; taille?: number }) {
  return (
    <div className="rounded-full overflow-hidden flex-shrink-0 flex items-center justify-center bg-[#E6F2F3]" style={{ width: taille, height: taille }}>
      {url
        // eslint-disable-next-line @next/next/no-img-element
        ? <img src={url} alt="" className="w-full h-full object-cover" />
        : <span className="text-sm" aria-hidden>🐾</span>}
    </div>
  );
}

function GroupeActions({ titre, total, voirTout, children }: { titre: string; total: number; voirTout: string; children: React.ReactNode }) {
  return (
    <div>
      <div className="flex items-center mb-1">
        <p className="flex-1 text-sm font-bold text-[#1E2025]">{titre} ({total})</p>
        {total > 4 && <Link href={voirTout} className="text-xs font-bold" style={{ color: TEAL }}>Tout voir</Link>}
      </div>
      {children}
    </div>
  );
}

function LigneAction({ href, titre, detail, photo }: { href: string; titre: string; detail: string; photo?: string | null }) {
  return (
    <Link href={href} className="flex items-center gap-2 py-1.5 hover:bg-gray-50 rounded-lg">
      <PhotoAnimal url={photo} taille={30} />
      <div className="flex-1 min-w-0">
        <p className="text-[13px] font-bold text-[#1E2025] truncate">{titre}</p>
        <p className="text-[11.5px] text-gray-500 truncate">{detail}</p>
      </div>
      <span className="text-gray-400">›</span>
    </Link>
  );
}

// ── Statistiques ──────────────────────────────────────────────────────────

function Statistiques({ rdvs, now, periode, setPeriode, filtre, setFiltre, praticiens }: {
  rdvs: Rdv[]; now: Date; periode: 'semaine' | 'mois' | 'annee'; setPeriode: (p: 'semaine' | 'mois' | 'annee') => void;
  filtre: string; setFiltre: (f: string) => void; praticiens: { id: string; nom: string }[];
}) {
  const [actif, setActif] = useState<string | null>(null);
  const [barre, setBarre] = useState<number | null>(null);

  // RDV réels : confirmés ou terminés (ni demandes, ni annulés).
  const compte = (r: Rdv) => (r.statut === 'confirme' || r.statut === 'termine') && (filtre === '*' || praticienDe(r) === filtre);
  const lundi = useMemo(() => new Date(now.getFullYear(), now.getMonth(), now.getDate() - ((now.getDay() + 6) % 7)), [now]);
  const [debut, fin] = periode === 'semaine'
    ? [lundi, new Date(lundi.getFullYear(), lundi.getMonth(), lundi.getDate() + 7)]
    : periode === 'annee'
      ? [new Date(now.getFullYear(), 0, 1), new Date(now.getFullYear() + 1, 0, 1)]
      : [new Date(now.getFullYear(), now.getMonth(), 1), new Date(now.getFullYear(), now.getMonth() + 1, 1)];

  const parMotif: Record<string, number> = Object.fromEntries(VET_MOTIFS.map(m => [m.key, 0]));
  for (const r of rdvs) {
    const d = debutDe(r);
    if (compte(r) && d >= debut && d < fin) parMotif[categorieMotif(r.motif)]++;
  }
  const total = Object.values(parMotif).reduce((a, v) => a + v, 0);
  const segments = VET_MOTIFS.filter(m => parMotif[m.key] > 0).map(m => ({ ...m, n: parMotif[m.key] }));

  const parJour = [0, 0, 0, 0, 0, 0, 0];
  for (const r of rdvs) {
    if (!compte(r)) continue;
    const d = debutDe(r);
    const i = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime() - lundi.getTime()) / 86400000);
    if (i >= 0 && i < 7) parJour[i]++;
  }
  const maxJour = Math.max(0, ...parJour);
  const aujourdhui = (now.getDay() + 6) % 7;

  // Anneau SVG : écart de 2 px (couleur de la surface) entre segments.
  const R = 60, EP = 20, C = 2 * Math.PI * R;
  const ecart = segments.length > 1 ? 2 : 0;
  const decalages = segments.map((_, i) => segments.slice(0, i).reduce((a, x) => a + (x.n / total) * C, 0));
  const seg = segments.find(s => s.key === actif);

  return (
    <section className="bg-white rounded-2xl border border-[#E4E7E2] p-4">
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <div className="flex-1 min-w-[180px]">
          <h2 className="font-bold text-base text-[#1E2025]">Répartition des rendez-vous</h2>
          <p className="text-xs text-gray-500">Par motif de réservation · RDV confirmés et terminés</p>
        </div>
        <div className="flex rounded-xl border border-gray-200 overflow-hidden text-xs font-semibold">
          {([['semaine', 'Semaine'], ['mois', 'Mois'], ['annee', 'Année']] as const).map(([k, l]) => (
            <button key={k} onClick={() => setPeriode(k)} className="px-3 py-1.5"
              style={periode === k ? { background: TEAL, color: 'white' } : { color: '#1E2025' }}>{l}</button>
          ))}
        </div>
        {praticiens.length > 1 && (
          <select value={filtre} onChange={e => setFiltre(e.target.value)} className="border border-gray-200 rounded-xl px-2 py-1.5 text-xs">
            <option value="*">Toute la clinique</option>
            {praticiens.map(p => <option key={p.id} value={p.id}>{p.nom}</option>)}
          </select>
        )}
      </div>

      <div className="grid md:grid-cols-2 gap-6">
        {total === 0 ? (
          <p className="text-sm text-gray-400 text-center py-10">Aucun rendez-vous sur la période.</p>
        ) : (
          <div className="flex flex-col sm:flex-row items-center gap-5">
            <svg viewBox="0 0 160 160" width={160} height={160} role="img" aria-label="Répartition des rendez-vous par motif" className="flex-shrink-0">
              <g transform="rotate(-90 80 80)">
                {segments.map((s, i) => {
                  const long = (s.n / total) * C;
                  return (
                    <circle key={s.key} cx={80} cy={80} r={R} fill="none" stroke={s.color}
                      strokeWidth={actif === s.key ? EP + 6 : EP}
                      strokeDasharray={`${Math.max(0.5, long - ecart)} ${C}`} strokeDashoffset={-decalages[i]}
                      opacity={actif && actif !== s.key ? 0.35 : 1}
                      onMouseEnter={() => setActif(s.key)} onMouseLeave={() => setActif(null)}
                      style={{ cursor: 'pointer', transition: 'opacity .15s' }}>
                      <title>{`${s.label} : ${s.n} (${Math.round(s.n * 100 / total)} %)`}</title>
                    </circle>
                  );
                })}
              </g>
              <text x={80} y={78} textAnchor="middle" fontSize={24} fontWeight={800} fill="#1E2025">{seg?.n ?? total}</text>
              <text x={80} y={96} textAnchor="middle" fontSize={11} fill="#6B7280">{seg?.label ?? 'RDV'}</text>
            </svg>
            <table className="w-full text-sm">
              <tbody>
                {segments.map(s => (
                  <tr key={s.key} onMouseEnter={() => setActif(s.key)} onMouseLeave={() => setActif(null)}
                    className={`cursor-default ${actif === s.key ? 'font-extrabold' : ''}`}>
                    <td className="py-1 pr-2"><span className="inline-block w-2.5 h-2.5 rounded-[3px] align-middle" style={{ background: s.color }} /></td>
                    <td className="py-1 text-[#1E2025]">{s.label}</td>
                    <td className="py-1 text-right font-bold text-[#1E2025]">{s.n}</td>
                    <td className="py-1 pl-3 text-right text-gray-500 w-14">{Math.round(s.n * 100 / total)} %</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <div>
          <p className="text-sm font-bold text-[#1E2025]">Activité de la semaine</p>
          <p className="text-xs text-gray-500 mb-3">RDV par jour</p>
          <div className="flex items-end gap-2 h-40">
            {parJour.map((n, i) => {
              const fort = i === aujourdhui || i === barre;
              return (
                <div key={i} className="flex-1 h-full flex flex-col items-center justify-end"
                  onMouseEnter={() => setBarre(i)} onMouseLeave={() => setBarre(null)}
                  title={`${['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'][i]} : ${n} RDV`}>
                  <span className={`text-xs font-bold text-[#1E2025] mb-1 ${fort ? '' : 'invisible'}`}>{n}</span>
                  <div className="w-full max-w-[28px] rounded-t" style={{
                    height: maxJour === 0 ? 2 : Math.max(2, (n / maxJour) * 110),
                    background: fort ? TEAL : `${TEAL}73`,
                  }} />
                  <span className={`text-[11px] mt-1.5 ${i === aujourdhui ? 'font-extrabold text-[#1E2025]' : 'text-gray-500'}`}>
                    {['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'][i]}
                  </span>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </section>
  );
}
