'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { usePensionAccess } from '@/hooks/usePensionAccess';
import { supabase } from '@/lib/supabase';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import ProAnimalEntete from '@/components/animaux/ProAnimalEntete';
import ArriveeDepartModal from '@/components/pension/ArriveeDepartModal';
import { PensionJournal } from '@/components/PensionJournal';
import { alimSejourFournisParLabel, type AlimentationSejour } from '@/lib/pension-especes';

// ── Types ─────────────────────────────────────────────────────────────────────

interface Animal {
  id: string;
  nom: string;
  espece?: string;
  race?: string;
  sexe?: string;
  sterilise?: boolean;
  date_naissance?: string;
  couleur?: string;
  couleur_yeux?: string;
  type_poil?: string;
  poids?: number;
  taille?: number;
  identification?: string;
  passeport_europeen?: string;
  description?: string;
  notes?: string;
  photo_url?: string;
  contacts_urgence?: { nom: string; tel: string }[];
}

interface MedRecord {
  id: string;
  date?: string;
  [key: string]: unknown;
}

interface Alimentation {
  type_ration?: string;
  niveau_activite?: string;
  marque?: string;
  reference_produit?: string;
  ration_grammes?: number;
  ration_kcal?: number;
  nb_repas?: number;
  complements?: string;
  notes?: string;
  gamme?: string;
  ration2_grammes?: number;
}

interface PensionEntry {
  id: string;
  notes?: string | null;
  date_entree?: string;
  date_sortie_prevue?: string;
  statut?: string;
  logement_id?: string | null;
  alimentation_sejour?: AlimentationSejour | null;
  // migration_pension_fiche.sql
  date_sortie_effective?: string | null; arrivee_reelle_le?: string | null; depart_reel_le?: string | null;
  depose_par?: string | null; recupere_par?: string | null; effets_personnels?: string | null;
  consignes_sejour?: string | null; observations_depart?: string | null;
  animal_id?: string | null; animal_nom?: string | null; proprietaire_nom?: string | null; pro_profile_id?: string | null;
}
interface TachePension { id: string; titre: string | null; date: string; statut: string | null }
interface ObservationPension { id: string; note: string | null; photo_url: string | null; created_at: string; incident?: boolean | null }
const fmtFr = (s?: string | null) => s ? new Date(s).toLocaleDateString('fr-FR') : '';
const hmFr = (s?: string | null) => s ? new Date(s).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }) : '';

// ── Helpers ───────────────────────────────────────────────────────────────────

const TEAL   = '#0C5C6C';
const PURPLE = '#7B5EA7';
const GREEN  = '#6E9E57';

function fmtDate(iso?: string | null) {
  if (!iso) return '';
  try { return new Date(iso).toLocaleDateString('fr-FR'); } catch { return iso ?? ''; }
}

function age(iso?: string | null) {
  if (!iso) return '';
  try {
    const dob = new Date(iso);
    const now = new Date();
    const m = (now.getFullYear() - dob.getFullYear()) * 12 + now.getMonth() - dob.getMonth();
    if (m < 12) return `${m} mois`;
    const y = Math.floor(m / 12);
    const r = m % 12;
    return r === 0 ? `${y} an${y > 1 ? 's' : ''}` : `${y} an${y > 1 ? 's' : ''} ${r} mois`;
  } catch { return ''; }
}

const ESP_EMOJI: Record<string, string> = {
  chien: '🐕', chat: '🐈', lapin: '🐇', oiseau: '🦜',
  cheval: '🐴', nac: '🐹', ovin: '🐑', caprin: '🐐', porcin: '🐷',
};

const RATION_LABEL: Record<string, string> = {
  croquettes: 'Croquettes', barf: 'BARF (viande crue)', mixte: 'Mixte',
  menagere: 'Ration ménagère', paturage: 'Pâturage', foin: 'Foin',
  complement: 'Complément', granules: 'Granulés',
};

const ACTIVITE_LABEL: Record<string, string> = {
  repos: 'Repos / faible', leger: 'Léger', modere: 'Modéré',
  actif: 'Actif', tres_actif: 'Très actif',
};

// ── Page ──────────────────────────────────────────────────────────────────────

export default function AnimalFichePensionWebPage() {
  const { user, userData, isPension, loading: authLoading } = usePensionAccess();
  const router = useRouter();
  const params = useParams();
  const animalId = params?.animalId as string;
  const activeProfileId = useActiveProfile();

  const [tab, setTab] = useState<'synthese' | 'sejours' | 'consignes' | 'suivi' | 'identite'>('synthese');
  const [consignesVue, setConsignesVue] = useState<'alimentation' | 'sante'>('alimentation');
  const [sejours, setSejours] = useState<PensionEntry[]>([]);
  const [logementsNoms, setLogementsNoms] = useState<Record<string, string>>({});
  const [taches, setTaches] = useState<TachePension[]>([]);
  const [observations, setObservations] = useState<ObservationPension[]>([]);
  const [action, setAction] = useState<'arrivee' | 'depart' | null>(null);
  const [journalOuvert, setJournalOuvert] = useState(false);
  const [pensionUid, setPensionUid] = useState<string | null>(null);
  const [animal, setAnimal]               = useState<Animal | null>(null);
  const [vaccinations, setVaccinations]   = useState<MedRecord[]>([]);
  const [vermifuges, setVermifuges]       = useState<MedRecord[]>([]);
  const [antipara, setAntipara]           = useState<MedRecord[]>([]);
  const [traitements, setTraitements]     = useState<MedRecord[]>([]);
  const [allergies, setAllergies]         = useState<MedRecord[]>([]);
  const [poids, setPoids]                 = useState<MedRecord[]>([]);
  const [alimentation, setAlimentation]   = useState<Alimentation | null>(null);
  const [pensionEntry, setPensionEntry]   = useState<PensionEntry | null>(null);
  const [hasAccess, setHasAccess]         = useState(false);
  // Compléter vermifuges / antiparasitaires : seulement si le propriétaire l'a autorisé.
  const [peutModifierSante, setPeutModifierSante] = useState(false);
  const [loading, setLoading]             = useState(true);


  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isPension) { router.push('/'); return; }
  }, [user, userData, isPension, authLoading, router]);

  const load = useCallback(async () => {
    if (!user || !animalId) return;
    setLoading(true);

    // Vérifier l'accès — animal_access du profil actif ; repli sur le profil
    // pension / pet-sitter du compte, jamais is_main (accès d'un autre profil).
    let proProfileId: string | null = activeProfileId || null;
    if (!proProfileId) {
      const { data: proProfile } = await supabase.from('user_profiles_complet')
        .select('id').eq('uid', user.uid).in('profile_type', ['pension', 'garde']).limit(1).maybeSingle();
      proProfileId = proProfile?.id ?? null;
    }
    let { data: acc } = proProfileId
      ? await supabase.from('animal_access').select('statut, permissions')
          .eq('animal_id', animalId).eq('pro_profile_id', proProfileId).eq('statut', 'active').maybeSingle()
      : { data: null };

    // Pas d'accès direct → vérifier si employé d'une pension ayant elle-même l'accès
    if (!acc) {
      const { data: emplois } = await supabase.from('employes')
        .select('uid_eleveur, eleveur_profile_id').eq('uid_employe', user.uid).eq('actif', true);
      if (emplois && emplois.length > 0 && proProfileId) {
        const eleveurProfileIds = emplois.map(e => e.eleveur_profile_id).filter(Boolean) as string[];
        const { data: perms } = await supabase.from('employe_permissions')
          .select('eleveur_profile_id').eq('employe_profile_id', proProfileId)
          .eq('permission', 'read_planning_pension').in('eleveur_profile_id', eleveurProfileIds);
        const allowedEleveurProfileIds = new Set((perms ?? []).map(p => p.eleveur_profile_id));
        for (const emp of emplois) {
          if (!emp.eleveur_profile_id || !allowedEleveurProfileIds.has(emp.eleveur_profile_id)) continue;
          const { data: employerAcc } = await supabase.from('animal_access').select('statut, permissions')
            .eq('animal_id', animalId).eq('pro_profile_id', emp.eleveur_profile_id).eq('statut', 'active').maybeSingle();
          if (employerAcc) { acc = employerAcc; proProfileId = emp.eleveur_profile_id; break; }
        }
      }
    }

    if (!acc) { setHasAccess(false); setLoading(false); return; }
    setHasAccess(true);
    setPeutModifierSante(((acc as { permissions?: string[] | null }).permissions ?? []).includes('write_health'));

    const [
      { data: a }, { data: vac }, { data: ver }, { data: api },
      { data: trt }, { data: alg }, { data: poi }, { data: alim },
    ] = await Promise.all([
      supabase.from('animaux').select('*').eq('id', animalId).single(),
      supabase.from('vaccinations').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
      supabase.from('vermifuges').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
      supabase.from('antiparasitaires').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
      supabase.from('traitements').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
      supabase.from('allergies').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
      supabase.from('poids').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
      supabase.from('alimentations').select('*').eq('animal_id', animalId).maybeSingle(),
    ]);

    // Entrée pension active pour ce pro (proProfileId peut être celui de l'employeur si vue employé)
    // Séjours de l'animal dans CETTE pension (profil actif, ou celui de l'employeur).
    const sejQuery = proProfileId
      ? supabase.from('pension_entrees').select('*').eq('animal_id', animalId).eq('pro_profile_id', proProfileId)
      : supabase.from('pension_entrees').select('*').eq('animal_id', animalId).eq('pro_uid', user.uid);
    const { data: sejList } = await sejQuery.order('date_entree', { ascending: false });
    const tous = (sejList ?? []) as (PensionEntry & { pro_uid?: string })[];
    const auj = new Date().toISOString().slice(0, 10);
    const enPension = tous.filter(e => e.statut === 'en_pension');
    const entry = enPension.find(e => (e.date_entree ?? '') <= auj) ?? enPension[enPension.length - 1] ?? null;
    const proUidPension = tous[0]?.pro_uid ?? user.uid;
    const [{ data: logs }, { data: tch }, obsRes] = await Promise.all([
      supabase.from('enclos_chenil').select('id, nom').eq('uid_eleveur', proUidPension),
      supabase.from('taches_elevage').select('id, titre, date, statut').eq('animal_id', animalId).eq('profil_source', 'pension')
        .gte('date', new Date(Date.now() - 7 * 86400000).toISOString().slice(0, 10)).order('date', { ascending: false }),
      supabase.from('pension_updates').select('*').eq('animal_id', animalId).eq('pro_uid', proUidPension)
        .order('created_at', { ascending: false }).limit(30),
    ]);
    const ln: Record<string, string> = {};
    for (const l of (logs ?? []) as { id: string; nom: string }[]) ln[l.id] = l.nom;
    setSejours(tous); setLogementsNoms(ln); setTaches((tch ?? []) as TachePension[]);
    setObservations(obsRes.error ? [] : (obsRes.data ?? []) as ObservationPension[]); setPensionUid(proUidPension);

    setAnimal(a as Animal);
    setVaccinations((vac ?? []) as MedRecord[]);
    setVermifuges((ver ?? []) as MedRecord[]);
    setAntipara((api ?? []) as MedRecord[]);
    setTraitements((trt ?? []) as MedRecord[]);
    setAllergies((alg ?? []) as MedRecord[]);
    setPoids((poi ?? []) as MedRecord[]);
    setAlimentation(alim as Alimentation | null);
    setPensionEntry(entry as PensionEntry | null);
    setLoading(false);
  }, [user, animalId, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  if (!user || !userData) return null;

  if (loading) return (
    <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: '#F8F8F6' }}>
      <div style={{ fontFamily: 'Galey, sans-serif', color: '#999' }}>Chargement…</div>
    </div>
  );

  if (!hasAccess) return (
    <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: '#F8F8F6', flexDirection: 'column', gap: 16 }}>
      <div style={{ fontSize: 48 }}>🔒</div>
      <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 16, color: '#374151', textAlign: 'center' }}>
        Accès non autorisé.<br />Le propriétaire n&apos;a pas encore accordé l&apos;accès à cette fiche.
      </p>
      <button onClick={() => router.back()}
        style={{ padding: '10px 24px', background: TEAL, color: 'white', border: 'none', borderRadius: 20,
          fontFamily: 'Galey, sans-serif', fontWeight: 700, cursor: 'pointer' }}>
        Retour
      </button>
    </div>
  );

  const nom    = animal?.nom ?? 'Animal';
  const espece = animal?.espece ?? '';
  const emoji  = ESP_EMOJI[espece] ?? '🐾';

  return (
    <div style={{ minHeight: '100vh', background: '#F8F8F6', paddingBottom: 60 }}>
      {/* Header */}
      <div style={{ background: PURPLE, padding: '20px 24px 0' }}>
        <div style={{ maxWidth: 800, margin: '0 auto' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 12 }}>
            <button onClick={() => router.back()}
              style={{ background: 'none', border: 'none', color: 'white', fontSize: 20, cursor: 'pointer', padding: 0 }}>←</button>
            {animal?.photo_url ? (
              <img src={animal.photo_url} alt={nom}
                style={{ width: 40, height: 40, borderRadius: 8, objectFit: 'cover' }} />
            ) : (
              <div style={{ width: 40, height: 40, borderRadius: 8, background: 'rgba(255,255,255,0.2)',
                display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 22 }}>{emoji}</div>
            )}
            <h1 style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 20, color: 'white', flex: 1 }}>
              {nom}
            </h1>
          </div>

          {/* Bannière accès */}
          <div style={{ background: 'rgba(255,255,255,0.12)', borderRadius: 10, padding: '8px 14px',
            marginBottom: 12, display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ fontSize: 14 }}>🔓</span>
            <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 12, color: 'rgba(255,255,255,0.9)' }}>
              Accès lecture / écriture · Accordé par le propriétaire
            </span>
          </div>

          {/* Onglets */}
          <div style={{ display: 'flex', gap: 0 }}>
            {([
              ['synthese', 'Synthèse'],
              ['sejours', 'Séjours'],
              ['consignes', 'Consignes & soins'],
              ['suivi', 'Suivi quotidien'],
            ] as const).map(([val, label]) => (
              <button key={val} onClick={() => setTab(val)} style={{
                flex: 1, padding: '10px 0', background: 'none', border: 'none',
                borderBottom: tab === val ? '2px solid white' : '2px solid transparent',
                color: tab === val ? 'white' : 'rgba(255,255,255,0.6)',
                fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 13, cursor: 'pointer',
              }}>{label}</button>
            ))}
          </div>
        </div>
      </div>

      {/* Contenu */}
      <div style={{ maxWidth: 800, margin: '24px auto', padding: '0 16px' }}>
        {/* Propriétaire : appeler, message, urgence, personnes autorisées. */}
        {user && (
          <div style={{ marginBottom: 16 }}>
            <ProAnimalEntete animalId={animalId} catPro="pension" myUid={user.uid} myProfileId={activeProfileId || null} />
          </div>
        )}
        {tab === 'synthese' && (() => {
          const auj = new Date().toISOString().slice(0, 10);
          const present = !!pensionEntry && (pensionEntry.date_entree ?? '') <= auj;
          const tachesJour = taches.filter(t => t.date === auj);
          const traitsEnCours = traitements.filter(t => !t.date_fin || new Date(String(t.date_fin)) >= new Date());
          const carte: React.CSSProperties = { background: 'white', borderRadius: 14, border: '1px solid #E6E8E6', padding: 16, marginBottom: 12, fontFamily: 'Galey, sans-serif' };
          const titre: React.CSSProperties = { fontWeight: 700, fontSize: 14, color: '#1F2A2E', margin: '0 0 8px' };
          const ligne: React.CSSProperties = { fontSize: 13.5, color: '#1F2A2E', margin: '0 0 4px' };
          const discret: React.CSSProperties = { fontSize: 13, color: '#6B7280', margin: 0 };
          return (
            <>
              <div style={carte}>
                <p style={titre}>Présence</p>
                {!pensionEntry ? <p style={discret}>Aucun séjour en cours ni à venir dans votre pension.</p> : (
                  <>
                    <p style={{ ...ligne, fontWeight: 700, color: present ? '#2E7D5E' : PURPLE }}>{present ? 'En pension' : `Arrivée prévue le ${fmtFr(pensionEntry.date_entree)}`}</p>
                    <p style={ligne}>Arrivée : {fmtFr(pensionEntry.date_entree)}{pensionEntry.arrivee_reelle_le ? ` à ${hmFr(pensionEntry.arrivee_reelle_le)}` : ''}{pensionEntry.depose_par ? ` · déposé par ${pensionEntry.depose_par}` : ''}</p>
                    <p style={ligne}>Départ prévu : {pensionEntry.date_sortie_prevue ? fmtFr(pensionEntry.date_sortie_prevue) : 'non renseigné'}</p>
                    <p style={ligne}>Hébergement : {(pensionEntry.logement_id && logementsNoms[pensionEntry.logement_id]) || 'non attribué'}</p>
                    <div style={{ display: 'flex', gap: 8, marginTop: 8, flexWrap: 'wrap' }}>
                      {!pensionEntry.arrivee_reelle_le && (
                        <button onClick={() => setAction('arrivee')} style={{ padding: '8px 14px', borderRadius: 10, border: 'none', background: '#E6F2F3', color: TEAL, fontWeight: 700, cursor: 'pointer' }}>Enregistrer l&apos;arrivée</button>
                      )}
                      {present && (
                        <button onClick={() => setAction('depart')} style={{ padding: '8px 14px', borderRadius: 10, border: 'none', background: '#EFE9F7', color: PURPLE, fontWeight: 700, cursor: 'pointer' }}>Enregistrer le départ</button>
                      )}
                    </div>
                  </>
                )}
              </div>
              <div style={carte}>
                <p style={titre}>Consignes prioritaires</p>
                {pensionEntry?.consignes_sejour && <p style={{ ...ligne, whiteSpace: 'pre-line' }}>{pensionEntry.consignes_sejour}</p>}
                {allergies.map(a => <p key={a.id} style={{ ...ligne, color: '#B3261E' }}>Allergie : {String(a.nom ?? a.allergene ?? a.description ?? '')}</p>)}
                {traitsEnCours.map(t => <p key={t.id} style={ligne}>Traitement : {String(t.nom ?? '')}{t.posologie ? ` — ${String(t.posologie)}` : ''}</p>)}
                {!pensionEntry?.consignes_sejour && allergies.length === 0 && traitsEnCours.length === 0 && <p style={discret}>Aucune consigne particulière renseignée.</p>}
              </div>
              <div style={carte}>
                <p style={titre}>Tâches du jour</p>
                {tachesJour.length === 0 ? <p style={discret}>Aucune tâche prévue aujourd&apos;hui.</p>
                  : tachesJour.map(t => <p key={t.id} style={{ ...ligne, textDecoration: t.statut === 'fait' ? 'line-through' : 'none', color: t.statut === 'fait' ? '#9CA3AF' : '#1F2A2E' }}>{t.titre ?? 'Tâche'}</p>)}
              </div>
              <div style={carte}>
                <p style={titre}>Dernières observations</p>
                {observations.length === 0 ? <p style={discret}>Aucune observation partagée.</p>
                  : observations.slice(0, 3).map(o => <p key={o.id} style={ligne}>{fmtFr(o.created_at)} {hmFr(o.created_at)} — {o.note?.trim() || 'Photo / vidéo'}</p>)}
              </div>
              <button onClick={() => setTab('identite')} style={{ padding: '10px 16px', borderRadius: 12, border: `1px solid ${TEAL}`, background: 'white', color: TEAL, fontWeight: 600, cursor: 'pointer', fontFamily: 'Galey, sans-serif' }}>Identité complète</button>
            </>
          );
        })()}
        {tab === 'sejours' && (() => {
          const auj = new Date().toISOString().slice(0, 10);
          const groupes: [string, PensionEntry[]][] = [
            ['En cours', sejours.filter(e => e.statut === 'en_pension' && (e.date_entree ?? '') <= auj)],
            ['À venir', sejours.filter(e => e.statut === 'en_pension' && (e.date_entree ?? '') > auj)],
            ['Terminés', sejours.filter(e => e.statut !== 'en_pension')],
          ];
          return groupes.map(([titre, l]) => (
            <div key={titre} style={{ background: 'white', borderRadius: 14, border: '1px solid #E6E8E6', padding: 16, marginBottom: 12, fontFamily: 'Galey, sans-serif' }}>
              <p style={{ fontWeight: 700, fontSize: 14, margin: '0 0 8px' }}>{titre}</p>
              {l.length === 0 ? <p style={{ fontSize: 13, color: '#6B7280', margin: 0 }}>Aucun.</p> : l.map(e => (
                <div key={e.id} style={{ padding: '6px 0', borderTop: '1px solid #F3F4F6' }}>
                  <p style={{ fontSize: 13.5, fontWeight: 700, margin: 0 }}>Du {fmtFr(e.date_entree)} au {fmtFr(e.date_sortie_effective ?? e.date_sortie_prevue)}</p>
                  <p style={{ fontSize: 12, color: '#4B5563', margin: '2px 0 0' }}>
                    {[(e.logement_id && logementsNoms[e.logement_id]) || 'Sans hébergement attribué', e.arrivee_reelle_le ? `arrivé à ${hmFr(e.arrivee_reelle_le)}` : '',
                      e.depart_reel_le ? `parti à ${hmFr(e.depart_reel_le)}` : '', e.recupere_par ? `récupéré par ${e.recupere_par}` : ''].filter(Boolean).join(' · ')}
                  </p>
                  {e.observations_depart && <p style={{ fontSize: 12, color: '#6B7280', margin: '2px 0 0', whiteSpace: 'pre-line' }}>{e.observations_depart}</p>}
                </div>
              ))}
            </div>
          ));
        })()}
        {tab === 'identite' && <IdentiteTab animal={animal} />}
        {tab === 'consignes' && (pensionEntry?.consignes_sejour || pensionEntry?.effets_personnels) && (
          <div style={{ background: '#FFF8E8', borderRadius: 12, padding: 12, marginBottom: 12, fontFamily: 'Galey, sans-serif' }}>
            <p style={{ fontWeight: 700, fontSize: 13, margin: '0 0 4px' }}>Consignes de ce séjour</p>
            {pensionEntry?.consignes_sejour && <p style={{ fontSize: 13, margin: 0, whiteSpace: 'pre-line' }}>{pensionEntry.consignes_sejour}</p>}
            {pensionEntry?.effets_personnels && <p style={{ fontSize: 12.5, margin: '4px 0 0' }}>Effets personnels : {pensionEntry.effets_personnels}</p>}
          </div>
        )}
        {tab === 'consignes' && (
          <div style={{ display: 'flex', gap: 6, marginBottom: 12 }}>
            {([['alimentation', 'Alimentation (permanente)'], ['sante', 'Santé & soins']] as const).map(([v, l]) => (
              <button key={v} onClick={() => setConsignesVue(v)} style={{
                padding: '6px 12px', borderRadius: 999, border: 'none', cursor: 'pointer', fontFamily: 'Galey, sans-serif', fontWeight: 600, fontSize: 12.5,
                background: consignesVue === v ? TEAL : '#F1F4F3', color: consignesVue === v ? 'white' : '#1F2A2E',
              }}>{l}</button>
            ))}
          </div>
        )}
        {tab === 'consignes' && consignesVue === 'sante' && (
          <SanteTab
            animalId={animalId}
            allergies={allergies}
            vaccinations={vaccinations}
            vermifuges={vermifuges}
            antipara={antipara}
            traitements={traitements}
            poids={poids}
            peutModifier={peutModifierSante}
            onPoidsAdded={() => load()}
          />
        )}
        {tab === 'consignes' && consignesVue === 'alimentation' && <AlimentationTab alimentation={alimentation} pensionEntry={pensionEntry} />}
        {tab === 'suivi' && (
          <>
            <div style={{ background: 'white', borderRadius: 14, border: '1px solid #E6E8E6', padding: 16, marginBottom: 12, fontFamily: 'Galey, sans-serif' }}>
              <p style={{ fontWeight: 700, fontSize: 14, margin: '0 0 8px' }}>Tâches et soins (7 derniers jours)</p>
              {taches.length === 0 ? <p style={{ fontSize: 13, color: '#6B7280', margin: 0 }}>Aucune tâche pour cet animal.</p> : taches.map(t => (
                <label key={t.id} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '4px 0', fontSize: 13.5 }}>
                  <input type="checkbox" checked={t.statut === 'fait'} onChange={async e => {
                    const statut = e.target.checked ? 'fait' : 'a_faire';
                    setTaches(prev => prev.map(x => x.id === t.id ? { ...x, statut } : x));
                    await supabase.from('taches_elevage').update({ statut, ...(statut === 'fait' && activeProfileId ? { fait_par_profile_id: activeProfileId } : {}) }).eq('id', t.id);
                  }} />
                  <span style={{ flex: 1, textDecoration: t.statut === 'fait' ? 'line-through' : 'none', color: t.statut === 'fait' ? '#9CA3AF' : '#1F2A2E' }}>{t.titre ?? 'Tâche'}</span>
                  <span style={{ fontSize: 11.5, color: '#6B7280' }}>{fmtFr(t.date)}</span>
                </label>
              ))}
            </div>
            <div style={{ background: 'white', borderRadius: 14, border: '1px solid #E6E8E6', padding: 16, marginBottom: 12, fontFamily: 'Galey, sans-serif' }}>
              <p style={{ fontWeight: 700, fontSize: 14, margin: '0 0 8px' }}>Observations et photos</p>
              {observations.length === 0 && <p style={{ fontSize: 13, color: '#6B7280', margin: 0 }}>Aucune observation pour le moment.</p>}
              {observations.slice(0, 10).map(o => (
                <div key={o.id} style={{ display: 'flex', gap: 10, padding: '6px 0' }}>
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  {o.photo_url && <img src={o.photo_url} alt="" style={{ width: 48, height: 48, borderRadius: 8, objectFit: 'cover' }} />}
                  <div>
                    <p style={{ fontSize: 11.5, margin: 0, color: o.incident ? '#B3261E' : '#6B7280' }}>{fmtFr(o.created_at)} à {hmFr(o.created_at)}{o.incident ? ' · incident' : ''}</p>
                    {o.note && <p style={{ fontSize: 13, margin: 0 }}>{o.note}</p>}
                  </div>
                </div>
              ))}
              <button onClick={() => setJournalOuvert(true)} style={{ marginTop: 8, width: '100%', padding: '10px 0', borderRadius: 12, border: `1px solid ${TEAL}`, background: 'white', color: TEAL, fontWeight: 600, cursor: 'pointer' }}>
                Ajouter une observation ou une photo
              </button>
            </div>
            <JournalTab
              animalId={animalId}
              pensionEntry={pensionEntry}
              onSaved={() => load()}
            />
          </>
        )}
        {action && pensionEntry && pensionUid && (
          <ArriveeDepartModal sejour={{ ...pensionEntry, animal_id: animalId, animal_nom: animal?.nom ?? pensionEntry.animal_nom }} mode={action} uid={pensionUid}
            onClose={() => setAction(null)} onDone={() => { setAction(null); load(); }} />
        )}
        {journalOuvert && (
          <PensionJournal animalId={animalId} pensionEntreeId={pensionEntry?.id} animalNom={animal?.nom ?? 'Animal'}
            proUid={pensionUid ?? user.uid} onClose={() => { setJournalOuvert(false); load(); }} />
        )}
      </div>
    </div>
  );
}

// ── Onglet Identité ───────────────────────────────────────────────────────────

function IdentiteTab({ animal }: { animal: Animal | null }) {
  if (!animal) return <Empty text="Données non disponibles" />;
  const a = animal;
  const ageStr = age(a.date_naissance);
  const urgList = a.contacts_urgence ?? [];

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      <Section title="Informations générales">
        <Row label="Espèce" value={a.espece} capitalize />
        <Row label="Race" value={a.race} />
        <Row label="Sexe" value={a.sexe === 'male' ? 'Mâle' : a.sexe === 'femelle' ? 'Femelle' : a.sexe} />
        <Row label="Stérilisé(e)" value={a.sterilise ? 'Oui' : 'Non'} />
        <Row label="Naissance" value={a.date_naissance ? `${fmtDate(a.date_naissance)}${ageStr ? `  ·  ${ageStr}` : ''}` : undefined} />
        <Row label="Couleur / robe" value={a.couleur} />
        <Row label="Couleur des yeux" value={a.couleur_yeux} />
        <Row label="Type de poil" value={a.type_poil} />
        <Row label="Poids" value={a.poids ? `${a.poids} kg` : undefined} />
        <Row label="Taille" value={a.taille ? `${a.taille} cm` : undefined} last />
      </Section>

      <Section title="Identification">
        <Row label="Puce électronique" value={a.identification} />
        <Row label="Passeport européen" value={a.passeport_europeen} last />
      </Section>

      {a.notes && (
        <Section title="Notes du propriétaire">
          <div style={{ padding: '12px 16px', fontFamily: 'Galey, sans-serif', fontSize: 14,
            color: '#374151', lineHeight: 1.6 }}>{a.notes}</div>
        </Section>
      )}

      {urgList.length > 0 && (
        <Section title="Contacts d'urgence">
          {urgList.map((c, i) => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 10,
              padding: '10px 16px', borderBottom: i < urgList.length - 1 ? '1px solid #f3f4f6' : 'none' }}>
              <span style={{ fontSize: 16 }}>📞</span>
              <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 14 }}>
                {[c.nom, c.tel].filter(Boolean).join(' — ')}
              </span>
            </div>
          ))}
        </Section>
      )}
    </div>
  );
}

// ── Onglet Santé (lecture + ajout poids) ─────────────────────────────────────

function SanteTab({ animalId, allergies, vaccinations, vermifuges, antipara, traitements, poids, peutModifier, onPoidsAdded }: {
  /** false = lecture seule (pas d'autorisation « modifier la santé » du propriétaire). */
  peutModifier: boolean;
  animalId: string;
  allergies: MedRecord[];
  vaccinations: MedRecord[];
  vermifuges: MedRecord[];
  antipara: MedRecord[];
  traitements: MedRecord[];
  poids: MedRecord[];
  onPoidsAdded: () => void;
}) {
  const [showPoidsForm, setShowPoidsForm] = useState(false);
  const [newPoids, setNewPoids]           = useState('');
  const [newDate, setNewDate]             = useState(new Date().toISOString().split('T')[0]);
  const [saving, setSaving]               = useState(false);
  const [err, setErr]                     = useState('');

  // Vermifuges/antiparasitaires — ajout + renouvellement (même logique que
  // "poids" ci-dessous : formulaire inline, rechargé via onPoidsAdded).
  const [openTraitementForm, setOpenTraitementForm] = useState<'vermifuges' | 'antiparasitaires' | null>(null);
  const [renouvellementDe, setRenouvellementDe] = useState<Record<string, unknown> | undefined>(undefined);

  async function saveTraitement(table: 'vermifuges' | 'antiparasitaires', data: Record<string, string | null>) {
    const { error } = await supabase.from(table).insert({ ...data, animal_id: animalId });
    if (!error) {
      setOpenTraitementForm(null);
      setRenouvellementDe(undefined);
      onPoidsAdded();
    }
  }

  async function addPoids() {
    const val = parseFloat(newPoids.replace(',', '.'));
    if (isNaN(val) || val <= 0) { setErr('Valeur invalide'); return; }
    setSaving(true);
    setErr('');
    const { error } = await supabase.from('poids').insert({
      animal_id: animalId,
      poids: val,
      date: newDate,
    });
    setSaving(false);
    if (error) { setErr(error.message); return; }
    setNewPoids('');
    setShowPoidsForm(false);
    onPoidsAdded();
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {allergies.length > 0 && (
        <HealthSection title="Allergies / intolérances" color="#dc2626" icon="⚠️" items={allergies}
          renderRow={a => <MedRow label={String(a.allergene ?? '')} sub={String(a.reaction ?? '')} date={fmtDate(a.date as string)} />} />
      )}
      <HealthSection title="Vaccinations" color={TEAL} icon="💉" items={vaccinations}
        renderRow={v => <MedRow label={String(v.nom_vaccin ?? '')} date={fmtDate(v.date as string)}
          extra={v.date_rappel ? `Rappel : ${fmtDate(v.date_rappel as string)}` : undefined} />} />
      <div style={{ background: 'white', borderRadius: 14, border: '1px solid #e5e7eb',
        boxShadow: '0 2px 8px rgba(0,0,0,0.04)', overflow: 'hidden' }}>
        <HealthSectionHeader title="Vermifugations" color={GREEN} icon="💊" count={vermifuges.length}
          onAdd={peutModifier ? () => { setRenouvellementDe(undefined); setOpenTraitementForm(openTraitementForm === 'vermifuges' ? null : 'vermifuges'); } : undefined} />
        {openTraitementForm === 'vermifuges' && (
          <TraitementAddForm type="vermifuges" initial={renouvellementDe}
            onCancel={() => { setOpenTraitementForm(null); setRenouvellementDe(undefined); }}
            onSave={d => saveTraitement('vermifuges', d)} />
        )}
        {vermifuges.length === 0 ? (
          <div style={{ padding: '12px 16px', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#d1d5db' }}>Aucun enregistrement</div>
        ) : vermifuges.map((v, i) => (
          <div key={v.id ?? i} style={{ borderBottom: i < vermifuges.length - 1 ? '1px solid #f3f4f6' : 'none' }}>
            <MedRow label={String(v.produit ?? '')} date={fmtDate(v.date as string)}
              extra={v.date_rappel ? `Rappel : ${fmtDate(v.date_rappel as string)}` : undefined}
              onRappel={peutModifier ? () => { setRenouvellementDe(v); setOpenTraitementForm('vermifuges'); } : undefined} />
          </div>
        ))}
      </div>

      <div style={{ background: 'white', borderRadius: 14, border: '1px solid #e5e7eb',
        boxShadow: '0 2px 8px rgba(0,0,0,0.04)', overflow: 'hidden' }}>
        <HealthSectionHeader title="Antiparasitaires" color="#f57c00" icon="🐛" count={antipara.length}
          onAdd={peutModifier ? () => { setRenouvellementDe(undefined); setOpenTraitementForm(openTraitementForm === 'antiparasitaires' ? null : 'antiparasitaires'); } : undefined} />
        {openTraitementForm === 'antiparasitaires' && (
          <TraitementAddForm type="antiparasitaires" initial={renouvellementDe}
            onCancel={() => { setOpenTraitementForm(null); setRenouvellementDe(undefined); }}
            onSave={d => saveTraitement('antiparasitaires', d)} />
        )}
        {antipara.length === 0 ? (
          <div style={{ padding: '12px 16px', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#d1d5db' }}>Aucun enregistrement</div>
        ) : antipara.map((a, i) => (
          <div key={a.id ?? i} style={{ borderBottom: i < antipara.length - 1 ? '1px solid #f3f4f6' : 'none' }}>
            <MedRow label={String(a.produit ?? '')} sub={String(a.type ?? '')} date={fmtDate(a.date as string)}
              extra={a.date_rappel ? `Rappel : ${fmtDate(a.date_rappel as string)}` : undefined}
              onRappel={peutModifier ? () => { setRenouvellementDe(a); setOpenTraitementForm('antiparasitaires'); } : undefined} />
          </div>
        ))}
      </div>
      {traitements.length > 0 && (
        <HealthSection title="Traitements" color={PURPLE} icon="🏥" items={traitements}
          renderRow={t => <MedRow label={String(t.nom ?? '')} sub={String(t.posologie ?? '')} date={fmtDate(t.date as string)}
            extra={t.notes ? String(t.notes) : undefined} />} />
      )}

      {/* Poids — avec bouton ajout */}
      <div style={{ background: 'white', borderRadius: 14, border: '1px solid #e5e7eb',
        boxShadow: '0 2px 8px rgba(0,0,0,0.04)', overflow: 'hidden' }}>
        <div style={{ padding: '12px 16px', display: 'flex', alignItems: 'center', gap: 8, borderBottom: '1px solid #f3f4f6' }}>
          <span style={{ fontSize: 16 }}>⚖️</span>
          <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 14, fontWeight: 700, color: TEAL, flex: 1 }}>
            Suivi du poids
          </span>
          <button onClick={() => setShowPoidsForm(v => !v)}
            style={{ padding: '4px 12px', background: TEAL, color: 'white', border: 'none', borderRadius: 20,
              fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 700, cursor: 'pointer' }}>
            + Ajouter
          </button>
        </div>

        {showPoidsForm && (
          <div style={{ padding: '12px 16px', background: '#f8fbfa', borderBottom: '1px solid #f3f4f6', display: 'flex', gap: 10, alignItems: 'flex-end', flexWrap: 'wrap' }}>
            <div>
              <div style={{ fontFamily: 'Galey, sans-serif', fontSize: 11, color: '#9ca3af', marginBottom: 4 }}>Poids (kg)</div>
              <input
                type="number" step="0.1" min="0" value={newPoids}
                onChange={e => setNewPoids(e.target.value)}
                placeholder="ex: 4.5"
                style={{ width: 90, padding: '8px 10px', border: '1px solid #d1d5db', borderRadius: 8,
                  fontFamily: 'Galey, sans-serif', fontSize: 14 }} />
            </div>
            <div>
              <div style={{ fontFamily: 'Galey, sans-serif', fontSize: 11, color: '#9ca3af', marginBottom: 4 }}>Date</div>
              <input
                type="date" value={newDate}
                onChange={e => setNewDate(e.target.value)}
                style={{ padding: '8px 10px', border: '1px solid #d1d5db', borderRadius: 8,
                  fontFamily: 'Galey, sans-serif', fontSize: 14 }} />
            </div>
            <button onClick={addPoids} disabled={saving}
              style={{ padding: '8px 18px', background: GREEN, color: 'white', border: 'none', borderRadius: 8,
                fontFamily: 'Galey, sans-serif', fontSize: 14, fontWeight: 700, cursor: 'pointer' }}>
              {saving ? '…' : 'Enregistrer'}
            </button>
            {err && <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#dc2626' }}>{err}</span>}
          </div>
        )}

        {poids.length === 0 && !showPoidsForm ? (
          <div style={{ padding: '12px 16px', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#d1d5db' }}>
            Aucune mesure enregistrée
          </div>
        ) : poids.slice(0, 10).map((p, i) => (
          <Row key={p.id ?? i} label={fmtDate(p.date as string)} value={`${p.poids} kg`} last={i === Math.min(9, poids.length - 1)} />
        ))}
      </div>
    </div>
  );
}

// ── Onglet Alimentation ───────────────────────────────────────────────────────

function AlimSejourCard({ s }: { s: AlimentationSejour }) {
  const rows: [string, string][] = [];
  if (s.fournis_par) rows.push(['Prise en charge', alimSejourFournisParLabel(s.fournis_par)]);
  if (s.foin) rows.push(['Foin', s.foin]);
  if (s.granules) rows.push(['Granulés / concentrés', s.granules]);
  if (s.complements) rows.push(['Compléments', s.complements]);
  if (s.autres) rows.push(['Autres', s.autres]);
  if (s.consignes) rows.push(['Consignes', s.consignes]);
  return (
    <div style={{ background: '#F0F5EC', border: '1px solid #DDE8D4', borderRadius: 14, padding: 14 }}>
      <p style={{ margin: '0 0 8px', fontFamily: 'Galey, sans-serif', fontSize: 14, fontWeight: 700, color: '#1F2A2E' }}>
        🌾 Alimentation pour ce séjour (pension)
      </p>
      {rows.map(([k, v]) => (
        <div key={k} style={{ display: 'flex', gap: 12, padding: '3px 0', fontFamily: 'Galey, sans-serif', fontSize: 13 }}>
          <span style={{ width: 140, flexShrink: 0, color: '#6b7280' }}>{k}</span>
          <span style={{ fontWeight: 600, color: '#1F2A2E' }}>{v}</span>
        </div>
      ))}
    </div>
  );
}

function AlimentationTab({ alimentation, pensionEntry }: { alimentation: Alimentation | null; pensionEntry: PensionEntry | null }) {
  const sejour = pensionEntry?.alimentation_sejour ?? null;
  const hasSejour = !!sejour && Object.keys(sejour).some(k => k !== 'fournis_par' && (sejour as Record<string, string>)[k]);
  if (!alimentation) return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {hasSejour && <AlimSejourCard s={sejour!} />}
      {hasSejour
        ? <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#9ca3af' }}>Régime habituel non renseigné par le propriétaire.</p>
        : (
          <div style={{ textAlign: 'center', padding: 60, color: '#aaa' }}>
            <div style={{ fontSize: 40, marginBottom: 12 }}>🍽️</div>
            <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 15 }}>Aucune information sur l&apos;alimentation</p>
          </div>
        )}
    </div>
  );
  const a = alimentation;
  // « notes » encode l'état du calculateur du propriétaire (« 50|30|…|nb_repas|… ») :
  // jamais affiché tel quel ; nb de repas / dose manuelle en repli des colonnes dédiées.
  const parts = a.notes?.includes('|') ? a.notes.split('|') : [];
  const nbRepas = a.nb_repas || Number(parts[3]) || 0;
  const ration = a.ration_grammes || Number((parts[5] ?? '').replace(',', '.')) || 0;
  const ration2 = a.ration2_grammes || Number((parts[6] ?? '').replace(',', '.')) || 0;
  const instructions = a.notes && !a.notes.includes('|') ? a.notes : '';
  const parRepas = (g: number) => nbRepas > 1 ? ` (${Math.round(g / nbRepas)} g par repas)` : '';
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {hasSejour && <AlimSejourCard s={sejour!} />}
      {hasSejour && (
        <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 600, color: '#6b7280', margin: 0 }}>
          Régime habituel — renseigné par le propriétaire
        </p>
      )}
      <Section title="Régime alimentaire">
        <Row label="Type de ration" value={RATION_LABEL[a.type_ration ?? ''] ?? a.type_ration} />
        <Row label="Niveau d'activité" value={ACTIVITE_LABEL[a.niveau_activite ?? ''] ?? a.niveau_activite} />
        <Row label="Marque / produit" value={a.marque} />
        <Row label="Gamme" value={a.gamme} />
        <Row label="Référence" value={a.reference_produit} />
        <Row label="Nombre de repas" value={nbRepas ? `${nbRepas} repas/jour` : undefined} />
        <Row label="Quantité par jour" value={ration ? `${Math.round(ration)} g/jour${parRepas(ration)}` : 'Non calculée par le propriétaire'} />
        {ration2 > 0 && <Row label="2e composant (mixte)" value={`${Math.round(ration2)} g/jour${parRepas(ration2)}`} />}
        <Row label="Apport énergétique" value={a.ration_kcal ? `${a.ration_kcal} kcal/jour` : undefined} last />
      </Section>
      {a.complements && (
        <Section title="Compléments alimentaires">
          <div style={{ padding: '12px 16px', fontFamily: 'Galey, sans-serif', fontSize: 14, color: '#374151' }}>
            {a.complements}
          </div>
        </Section>
      )}
      {instructions && (
        <Section title="Instructions spéciales">
          <div style={{ margin: 16, padding: 14, background: '#fff7ed', borderRadius: 10,
            border: '1px solid #fed7aa', display: 'flex', gap: 10, alignItems: 'flex-start' }}>
            <span style={{ fontSize: 18 }}>⚠️</span>
            <p style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontSize: 14,
              color: '#92400e', lineHeight: 1.5 }}>{instructions}</p>
          </div>
        </Section>
      )}
    </div>
  );
}

// ── Onglet Journal de bord ────────────────────────────────────────────────────

function JournalTab({ animalId, pensionEntry, onSaved }: {
  animalId: string;
  pensionEntry: PensionEntry | null;
  onSaved: () => void;
}) {
  const [notes, setNotes]   = useState(pensionEntry?.notes ?? '');
  const [saving, setSaving] = useState(false);
  const [saved, setSaved]   = useState(false);
  const [err, setErr]       = useState('');

  useEffect(() => { setNotes(pensionEntry?.notes ?? ''); }, [pensionEntry]);

  async function saveNotes() {
    if (!pensionEntry?.id) return;
    setSaving(true); setErr(''); setSaved(false);
    const { error } = await supabase.from('pension_entrees')
      .update({ notes })
      .eq('id', pensionEntry.id);
    setSaving(false);
    if (error) { setErr(error.message); return; }
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
    onSaved();
  }

  if (!pensionEntry) return (
    <div style={{ textAlign: 'center', padding: 60, color: '#aaa' }}>
      <div style={{ fontSize: 40, marginBottom: 12 }}>📋</div>
      <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 15 }}>
        Aucun séjour actif trouvé pour cet animal.
      </p>
      <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#bbb' }}>
        Créez une entrée dans le registre pour accéder au journal.
      </p>
    </div>
  );

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {/* Infos séjour */}
      <Section title="Séjour en cours">
        <Row label="Date d'entrée" value={fmtDate(pensionEntry.date_entree)} />
        <Row label="Sortie prévue" value={fmtDate(pensionEntry.date_sortie_prevue)} last />
      </Section>

      {/* Notes */}
      <div style={{ background: 'white', borderRadius: 14, border: '1px solid #e5e7eb',
        boxShadow: '0 2px 8px rgba(0,0,0,0.04)', overflow: 'hidden' }}>
        <div style={{ padding: '12px 16px', display: 'flex', alignItems: 'center', gap: 8, borderBottom: '1px solid #f3f4f6' }}>
          <span style={{ fontSize: 16 }}>📝</span>
          <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 14, fontWeight: 700, color: PURPLE, flex: 1 }}>
            Notes de séjour
          </span>
        </div>
        <div style={{ padding: 16 }}>
          <textarea
            value={notes}
            onChange={e => setNotes(e.target.value)}
            rows={6}
            placeholder="Observations, comportement, incidents, alimentation particulière…"
            style={{
              width: '100%', boxSizing: 'border-box',
              padding: '12px', border: '1px solid #d1d5db', borderRadius: 10,
              fontFamily: 'Galey, sans-serif', fontSize: 14, color: '#374151',
              resize: 'vertical', lineHeight: 1.6,
            }}
          />
          {err && <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#dc2626', margin: '4px 0 0' }}>{err}</p>}
          <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 12, gap: 10, alignItems: 'center' }}>
            {saved && <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 12, color: GREEN }}>✓ Enregistré</span>}
            <button onClick={saveNotes} disabled={saving}
              style={{ padding: '10px 24px', background: PURPLE, color: 'white', border: 'none', borderRadius: 20,
                fontFamily: 'Galey, sans-serif', fontSize: 14, fontWeight: 700, cursor: 'pointer' }}>
              {saving ? 'Enregistrement…' : 'Enregistrer les notes'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ── Composants UI ─────────────────────────────────────────────────────────────

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div style={{ background: 'white', borderRadius: 14, border: '1px solid #e5e7eb',
      boxShadow: '0 2px 8px rgba(0,0,0,0.04)', overflow: 'hidden' }}>
      <div style={{ padding: '12px 16px 8px', fontFamily: 'Galey, sans-serif', fontSize: 12,
        fontWeight: 700, color: '#6b7280', letterSpacing: 0.4, borderBottom: '1px solid #f3f4f6' }}>
        {title}
      </div>
      {children}
    </div>
  );
}

function Row({ label, value, capitalize, last }: {
  label: string; value?: string | null; capitalize?: boolean; last?: boolean;
}) {
  if (!value) return null;
  return (
    <div style={{ display: 'flex', padding: '10px 16px',
      borderBottom: last ? 'none' : '1px solid #f3f4f6', gap: 12 }}>
      <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#9ca3af', minWidth: 140 }}>
        {label}
      </span>
      <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 14, color: '#1f2a2e',
        fontWeight: 600, textTransform: capitalize ? 'capitalize' : 'none' }}>
        {value}
      </span>
    </div>
  );
}

function HealthSectionHeader({ title, color, icon, count, onAdd }: {
  title: string; color: string; icon: string; count: number; onAdd?: () => void;
}) {
  return (
    <div style={{ padding: '12px 16px', display: 'flex', alignItems: 'center', gap: 8,
      borderBottom: '1px solid #f3f4f6' }}>
      <span style={{ fontSize: 16 }}>{icon}</span>
      <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 14, fontWeight: 700, color, flex: 1 }}>
        {title}
      </span>
      <span style={{ padding: '2px 10px', borderRadius: 20, fontSize: 11, fontWeight: 700,
        fontFamily: 'Galey, sans-serif', background: `${color}18`, color }}>
        {count}
      </span>
      {onAdd && (
        <button onClick={onAdd}
          style={{ padding: '4px 12px', background: color, color: 'white', border: 'none', borderRadius: 20,
            fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 700, cursor: 'pointer' }}>
          + Ajouter
        </button>
      )}
    </div>
  );
}

function HealthSection({ title, color, icon, items, renderRow, onAdd }: {
  title: string; color: string; icon: string;
  items: MedRecord[];
  renderRow: (item: MedRecord) => React.ReactNode;
  onAdd?: () => void;
}) {
  return (
    <div style={{ background: 'white', borderRadius: 14, border: '1px solid #e5e7eb',
      boxShadow: '0 2px 8px rgba(0,0,0,0.04)', overflow: 'hidden' }}>
      <div style={{ padding: '12px 16px', display: 'flex', alignItems: 'center', gap: 8,
        borderBottom: '1px solid #f3f4f6' }}>
        <span style={{ fontSize: 16 }}>{icon}</span>
        <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 14, fontWeight: 700, color, flex: 1 }}>
          {title}
        </span>
        <span style={{ padding: '2px 10px', borderRadius: 20, fontSize: 11, fontWeight: 700,
          fontFamily: 'Galey, sans-serif', background: `${color}18`, color }}>
          {items.length}
        </span>
        {onAdd && (
          <button onClick={onAdd}
            style={{ padding: '4px 12px', background: color, color: 'white', border: 'none', borderRadius: 20,
              fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 700, cursor: 'pointer' }}>
            + Ajouter
          </button>
        )}
      </div>
      {items.length === 0 ? (
        <div style={{ padding: '12px 16px', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#d1d5db' }}>
          Aucun enregistrement
        </div>
      ) : items.map((item, i) => (
        <div key={item.id ?? i} style={{ borderBottom: i < items.length - 1 ? '1px solid #f3f4f6' : 'none' }}>
          {renderRow(item)}
        </div>
      ))}
    </div>
  );
}

function MedRow({ label, sub, date, extra, onRappel }: {
  label: string; sub?: string; date: string; extra?: string; onRappel?: () => void;
}) {
  return (
    <div style={{ padding: '10px 16px' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 12 }}>
        <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 14, fontWeight: 600, color: '#1f2a2e' }}>
          {label}
        </span>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#9ca3af', whiteSpace: 'nowrap' }}>
            {date}
          </span>
          {onRappel && (
            <button onClick={onRappel} title="Renouvellement"
              style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 0, fontSize: 14, color: GREEN }}>
              ⏰
            </button>
          )}
        </div>
      </div>
      {sub && <div style={{ fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#6b7280', marginTop: 2 }}>{sub}</div>}
      {extra && <div style={{ fontFamily: 'Galey, sans-serif', fontSize: 11, color: GREEN, fontWeight: 600, marginTop: 2 }}>{extra}</div>}
    </div>
  );
}

// Formulaire vermifuge/antiparasitaire — même logique fréquence + calcul
// auto du rappel que mes-animaux/[id] et l'appli (jour/semaine/mois).
function TraitementAddForm({ type, initial, onCancel, onSave }: {
  type: 'vermifuges' | 'antiparasitaires';
  initial?: Record<string, unknown>;
  onCancel: () => void;
  onSave: (data: Record<string, string | null>) => Promise<void>;
}) {
  const parsedFreq = /^(\d+)\s*(jour|semaine|mois)/i.exec(String(initial?.frequence ?? ''));
  const [produit, setProduit] = useState(String(initial?.produit ?? ''));
  const [subInfo, setSubInfo] = useState(String((type === 'vermifuges' ? initial?.dosage : initial?.type) ?? ''));
  const [date, setDate] = useState(new Date().toISOString().split('T')[0]);
  const [freqValeur, setFreqValeur] = useState(parsedFreq?.[1] ?? '1');
  const [freqUnite, setFreqUnite] = useState<'jour' | 'semaine' | 'mois'>(
    (parsedFreq?.[2]?.toLowerCase() as 'jour' | 'semaine' | 'mois') ?? 'mois');
  const [dateRappel, setDateRappel] = useState('');
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');

  function recomputeRappel(d: string, valeur: string, unite: 'jour' | 'semaine' | 'mois') {
    const n = parseInt(valeur, 10);
    if (!d || !(n > 0)) return;
    const days = unite === 'jour' ? n : unite === 'semaine' ? n * 7 : n * 30;
    const dt = new Date(d);
    dt.setDate(dt.getDate() + days);
    setDateRappel(dt.toISOString().split('T')[0]);
  }

  async function save() {
    if (!produit.trim()) { setErr('Produit requis'); return; }
    setSaving(true); setErr('');
    const n = parseInt(freqValeur, 10);
    const freqLabel = n > 0
      ? `${n} ${freqUnite === 'jour' ? `jour${n > 1 ? 's' : ''}` : freqUnite === 'semaine' ? `semaine${n > 1 ? 's' : ''}` : 'mois'}`
      : null;
    await onSave({
      produit: produit.trim(),
      [type === 'vermifuges' ? 'dosage' : 'type']: subInfo.trim() || null,
      date,
      date_rappel: dateRappel || null,
      frequence: freqLabel,
    });
    setSaving(false);
  }

  const inputStyle = { padding: '8px 10px', border: '1px solid #d1d5db', borderRadius: 8,
    fontFamily: 'Galey, sans-serif', fontSize: 14 };
  const labelStyle = { fontFamily: 'Galey, sans-serif', fontSize: 11, color: '#9ca3af', marginBottom: 4 };

  return (
    <div style={{ padding: '12px 16px', background: '#f8fbfa', borderBottom: '1px solid #f3f4f6',
      display: 'flex', gap: 10, alignItems: 'flex-end', flexWrap: 'wrap' }}>
      <div>
        <div style={labelStyle}>Produit</div>
        <input value={produit} onChange={e => setProduit(e.target.value)} style={{ ...inputStyle, width: 160 }} />
      </div>
      <div>
        <div style={labelStyle}>{type === 'vermifuges' ? 'Dosage' : 'Type'}</div>
        <input value={subInfo} onChange={e => setSubInfo(e.target.value)} style={{ ...inputStyle, width: 130 }} />
      </div>
      <div>
        <div style={labelStyle}>Date</div>
        <input type="date" value={date}
          onChange={e => { setDate(e.target.value); recomputeRappel(e.target.value, freqValeur, freqUnite); }}
          style={inputStyle} />
      </div>
      <div>
        <div style={labelStyle}>Fréquence</div>
        <div style={{ display: 'flex', gap: 6 }}>
          <input type="number" min={1} value={freqValeur}
            onChange={e => { setFreqValeur(e.target.value); recomputeRappel(date, e.target.value, freqUnite); }}
            style={{ ...inputStyle, width: 55 }} />
          <select value={freqUnite}
            onChange={e => { const u = e.target.value as 'jour' | 'semaine' | 'mois'; setFreqUnite(u); recomputeRappel(date, freqValeur, u); }}
            style={inputStyle}>
            <option value="jour">Jour(s)</option>
            <option value="semaine">Semaine(s)</option>
            <option value="mois">Mois</option>
          </select>
        </div>
      </div>
      <div>
        <div style={labelStyle}>Rappel</div>
        <input type="date" value={dateRappel} onChange={e => setDateRappel(e.target.value)} style={inputStyle} />
      </div>
      <button onClick={save} disabled={saving}
        style={{ padding: '8px 18px', background: GREEN, color: 'white', border: 'none', borderRadius: 8,
          fontFamily: 'Galey, sans-serif', fontSize: 14, fontWeight: 700, cursor: 'pointer' }}>
        {saving ? '…' : 'Enregistrer'}
      </button>
      <button onClick={onCancel}
        style={{ padding: '8px 14px', background: 'none', color: '#6b7280', border: '1px solid #d1d5db', borderRadius: 8,
          fontFamily: 'Galey, sans-serif', fontSize: 14, cursor: 'pointer' }}>
        Annuler
      </button>
      {err && <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#dc2626' }}>{err}</span>}
    </div>
  );
}

function Empty({ text }: { text: string }) {
  return (
    <div style={{ textAlign: 'center', padding: 60, color: '#aaa' }}>
      <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 15 }}>{text}</p>
    </div>
  );
}
