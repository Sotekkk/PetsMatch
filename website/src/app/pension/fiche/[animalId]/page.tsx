'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { usePensionAccess } from '@/hooks/usePensionAccess';
import { supabase } from '@/lib/supabase';
import { useActiveProfile } from '@/hooks/useActiveProfile';

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
}

interface PensionEntry {
  id: string;
  notes?: string | null;
  date_entree?: string;
  date_sortie_prevue?: string;
  statut?: string;
}

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
  const { user, userData, isPension } = usePensionAccess();
  const router = useRouter();
  const params = useParams();
  const animalId = params?.animalId as string;
  const activeProfileId = useActiveProfile();

  const [tab, setTab] = useState<'identite' | 'sante' | 'alimentation' | 'journal'>('identite');
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
  const [loading, setLoading]             = useState(true);


  useEffect(() => {
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isPension) { router.push('/'); return; }
  }, [user, userData, isPension, router]);

  const load = useCallback(async () => {
    if (!user || !animalId) return;
    setLoading(true);

    // Vérifier l'accès — préférer pro_profile_id si disponible
    let accQuery = supabase.from('pension_acces')
      .select('statut')
      .eq('animal_id', animalId)
      .eq('statut', 'approved');
    if (activeProfileId) {
      accQuery = accQuery.eq('pro_profile_id', activeProfileId) as typeof accQuery;
    } else {
      accQuery = accQuery.eq('pro_uid', user.uid) as typeof accQuery;
    }
    const { data: acc } = await accQuery.maybeSingle();

    if (!acc) { setHasAccess(false); setLoading(false); return; }
    setHasAccess(true);

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

    // Entrée pension active pour ce pro
    let entQuery = supabase.from('pension_entrees')
      .select('id, notes, date_entree, date_sortie_prevue, statut')
      .eq('statut', 'en_pension')
      .order('date_entree', { ascending: false })
      .limit(1);
    if (activeProfileId) {
      entQuery = entQuery.eq('pro_profile_id', activeProfileId) as typeof entQuery;
    } else {
      entQuery = entQuery.eq('pro_uid', user.uid) as typeof entQuery;
    }
    const { data: entList } = await entQuery;
    const entry = (entList ?? []).find((e: PensionEntry) => true) ?? null;

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
              ['identite', 'Identité'],
              ['sante', 'Santé'],
              ['alimentation', 'Alimentation'],
              ['journal', 'Journal'],
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
        {tab === 'identite' && <IdentiteTab animal={animal} />}
        {tab === 'sante' && (
          <SanteTab
            animalId={animalId}
            allergies={allergies}
            vaccinations={vaccinations}
            vermifuges={vermifuges}
            antipara={antipara}
            traitements={traitements}
            poids={poids}
            onPoidsAdded={() => load()}
          />
        )}
        {tab === 'alimentation' && <AlimentationTab alimentation={alimentation} />}
        {tab === 'journal' && (
          <JournalTab
            animalId={animalId}
            pensionEntry={pensionEntry}
            onSaved={() => load()}
          />
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

function SanteTab({ animalId, allergies, vaccinations, vermifuges, antipara, traitements, poids, onPoidsAdded }: {
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
      <HealthSection title="Vermifugations" color={GREEN} icon="💊" items={vermifuges}
        renderRow={v => <MedRow label={String(v.produit ?? '')} date={fmtDate(v.date as string)}
          extra={v.date_rappel ? `Rappel : ${fmtDate(v.date_rappel as string)}` : undefined} />} />
      <HealthSection title="Antiparasitaires" color="#f57c00" icon="🐛" items={antipara}
        renderRow={a => <MedRow label={String(a.produit ?? '')} sub={String(a.type ?? '')} date={fmtDate(a.date as string)}
          extra={a.date_rappel ? `Rappel : ${fmtDate(a.date_rappel as string)}` : undefined} />} />
      {traitements.length > 0 && (
        <HealthSection title="Traitements" color={PURPLE} icon="🏥" items={traitements}
          renderRow={t => <MedRow label={String(t.nom ?? '')} sub={String(t.posologie ?? '')} date={fmtDate(t.date as string)} />} />
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

function AlimentationTab({ alimentation }: { alimentation: Alimentation | null }) {
  if (!alimentation) return (
    <div style={{ textAlign: 'center', padding: 60, color: '#aaa' }}>
      <div style={{ fontSize: 40, marginBottom: 12 }}>🍽️</div>
      <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 15 }}>Aucune information sur l&apos;alimentation</p>
    </div>
  );
  const a = alimentation;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      <Section title="Régime alimentaire">
        <Row label="Type de ration" value={RATION_LABEL[a.type_ration ?? ''] ?? a.type_ration} />
        <Row label="Niveau d'activité" value={ACTIVITE_LABEL[a.niveau_activite ?? ''] ?? a.niveau_activite} />
        <Row label="Marque / produit" value={a.marque} />
        <Row label="Référence" value={a.reference_produit} />
        <Row label="Ration quotidienne" value={a.ration_grammes ? `${a.ration_grammes} g/jour` : undefined} />
        <Row label="Apport énergétique" value={a.ration_kcal ? `${a.ration_kcal} kcal/jour` : undefined} />
        <Row label="Nombre de repas" value={a.nb_repas ? `${a.nb_repas} repas/jour` : undefined} last />
      </Section>
      {a.complements && (
        <Section title="Compléments alimentaires">
          <div style={{ padding: '12px 16px', fontFamily: 'Galey, sans-serif', fontSize: 14, color: '#374151' }}>
            {a.complements}
          </div>
        </Section>
      )}
      {a.notes && (
        <Section title="Instructions spéciales">
          <div style={{ margin: 16, padding: 14, background: '#fff7ed', borderRadius: 10,
            border: '1px solid #fed7aa', display: 'flex', gap: 10, alignItems: 'flex-start' }}>
            <span style={{ fontSize: 18 }}>⚠️</span>
            <p style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontSize: 14,
              color: '#92400e', lineHeight: 1.5 }}>{a.notes}</p>
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

function HealthSection({ title, color, icon, items, renderRow }: {
  title: string; color: string; icon: string;
  items: MedRecord[];
  renderRow: (item: MedRecord) => React.ReactNode;
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

function MedRow({ label, sub, date, extra }: {
  label: string; sub?: string; date: string; extra?: string;
}) {
  return (
    <div style={{ padding: '10px 16px' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 12 }}>
        <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 14, fontWeight: 600, color: '#1f2a2e' }}>
          {label}
        </span>
        <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#9ca3af', whiteSpace: 'nowrap' }}>
          {date}
        </span>
      </div>
      {sub && <div style={{ fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#6b7280', marginTop: 2 }}>{sub}</div>}
      {extra && <div style={{ fontFamily: 'Galey, sans-serif', fontSize: 11, color: GREEN, fontWeight: 600, marginTop: 2 }}>{extra}</div>}
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
