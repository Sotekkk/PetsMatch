'use client';

import { useEffect, useState, useCallback } from 'react';
import { useParams, useRouter } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import HealthSection from '@/components/animaux/HealthSection';
import AlimentationTab from '@/app/mes-animaux/[id]/AlimentationTab';

// ─── Types ────────────────────────────────────────────────────────────────────

interface Animal {
  id: string; nom?: string; espece?: string; race?: string; sexe?: string;
  date_naissance?: string; age_estime?: boolean; date_entree?: string; statut?: string;
  photo_url?: string; poids?: string; description?: string;
  vaccins?: boolean; vaccines?: boolean; vermifuge?: boolean;
  identification?: string | boolean; sterilise?: boolean;
  couleur?: string; type_poil?: string;
}
interface HealthRecord { id: string; [key: string]: unknown; }

// ─── Constants ────────────────────────────────────────────────────────────────

const STATUTS: Record<string, { label: string; color: string }> = {
  en_soin:    { label: 'En soin',    color: 'bg-orange-100 text-orange-700' },
  disponible: { label: 'Disponible', color: 'bg-green-100 text-green-700' },
  en_fa:      { label: 'En FA',      color: 'bg-purple-100 text-purple-700' },
  adopte:     { label: 'Adopté',     color: 'bg-teal-100 text-teal-700' },
  transfere:  { label: 'Transféré',  color: 'bg-blue-100 text-blue-700' },
  decede:     { label: 'Décédé',     color: 'bg-red-100 text-red-700' },
};

const TABS = [
  { key: 'identite',      label: 'Identité',      icon: '🐾' },
  { key: 'sante',         label: 'Santé',          icon: '💊' },
  { key: 'alimentation',  label: 'Alimentation',   icon: '🥩' },
  { key: 'consultations', label: 'Consultations',  icon: '🩺' },
] as const;
type Tab = typeof TABS[number]['key'];

// ─── Helpers ──────────────────────────────────────────────────────────────────

function fmtDate(d?: string | null): string {
  if (!d) return '–';
  return new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'long', year: 'numeric' });
}
function age(dn?: string | null, estime?: boolean): string {
  if (!dn) return '';
  const m = Math.floor((Date.now() - new Date(dn).getTime()) / (1000 * 60 * 60 * 24 * 30));
  let txt: string;
  if (m < 1) txt = "< 1 mois";
  else if (m < 12) txt = `${m} mois`;
  else {
    const a = Math.floor(m / 12); const r = m % 12;
    txt = r ? `${a} an${a > 1 ? 's' : ''} ${r} mois` : `${a} an${a > 1 ? 's' : ''}`;
  }
  return estime ? `Environ ${txt} (né(e) vers ${new Date(dn).getFullYear()})` : txt;
}
function fmtDateShort(d?: string | null): string {
  if (!d) return '';
  try { return new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit', year: '2-digit' }); } catch { return ''; }
}

// ─── SantéTab ─────────────────────────────────────────────────────────────────

const HEALTH_SECTIONS = [
  { table: 'vaccinations',     label: 'Vaccinations',       icon: '💉', color: '#6E9E57',
    fields: [{ key: 'vaccin', label: 'Vaccin', required: true }, { key: 'date', label: 'Date', type: 'date' }, { key: 'lot', label: 'N° lot' }, { key: 'notes', label: 'Notes' }] },
  { table: 'vermifuges',       label: 'Vermifugations',     icon: '🪱', color: '#8B7355',
    fields: [{ key: 'produit', label: 'Produit', required: true }, { key: 'date', label: 'Date', type: 'date' }, { key: 'dose', label: 'Dose' }, { key: 'notes', label: 'Notes' }] },
  { table: 'antiparasitaires', label: 'Antiparasitaires',   icon: '🦟', color: '#E06B3F',
    fields: [{ key: 'produit', label: 'Produit', required: true }, { key: 'date', label: 'Date', type: 'date' }, { key: 'notes', label: 'Notes' }] },
  { table: 'traitements',      label: 'Traitements',        icon: '💊', color: '#0C5C6C',
    fields: [{ key: 'traitement', label: 'Traitement', required: true }, { key: 'date_debut', label: 'Début', type: 'date' }, { key: 'date_fin', label: 'Fin', type: 'date' }, { key: 'notes', label: 'Notes' }] },
  { table: 'visites',          label: 'Visites vétérinaires', icon: '🏥', color: '#5C7A9E',
    fields: [{ key: 'motif', label: 'Motif', required: true }, { key: 'date', label: 'Date', type: 'date' }, { key: 'veterinaire', label: 'Vétérinaire' }, { key: 'notes', label: 'Notes' }] },
  { table: 'poids',            label: 'Suivi du poids',     icon: '⚖️', color: '#9E6E57',
    fields: [{ key: 'valeur', label: 'Poids (kg)', required: true }, { key: 'date', label: 'Date', type: 'date' }, { key: 'notes', label: 'Notes' }] },
];

function AddForm({ fields, onSave, onCancel, saving }:
  { fields: { key: string; label: string; type?: string; required?: boolean }[];
    onSave: (d: Record<string, string>) => Promise<void>; onCancel: () => void; saving: boolean }) {
  const [form, setForm] = useState<Record<string, string>>({});
  const cls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30';
  return (
    <div className="space-y-3 p-4">
      {fields.map(f => (
        <div key={f.key}>
          <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">
            {f.label}{f.required && <span className="text-red-400 ml-0.5">*</span>}
          </label>
          <input type={f.type ?? 'text'} value={form[f.key] ?? ''}
            onChange={e => setForm(p => ({ ...p, [f.key]: e.target.value }))} className={cls} />
        </div>
      ))}
      <div className="flex gap-2 pt-1">
        <button onClick={onCancel} className="flex-1 py-2 rounded-xl border border-gray-200 text-sm text-gray-600 hover:bg-gray-50">Annuler</button>
        <button onClick={() => onSave(form)} disabled={saving}
          className="flex-1 py-2 rounded-xl bg-[#0C5C6C] text-white text-sm font-semibold disabled:opacity-50">
          {saving ? '…' : 'Enregistrer'}
        </button>
      </div>
    </div>
  );
}

function RecordRow({ record, mainKey, dateKey, onDelete }:
  { record: HealthRecord; mainKey: string; dateKey?: string; onDelete: () => void }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="px-4 py-3 border-t border-gray-50">
      <div className="flex items-center gap-2 cursor-pointer" onClick={() => setOpen(!open)}>
        <div className="flex-1">
          <p className="text-sm font-medium text-[#1F2A2E]">{String(record[mainKey] ?? '—')}</p>
          {dateKey && !!record[dateKey] && <p className="text-xs text-gray-400">{fmtDateShort(record[dateKey] as string)}</p>}
        </div>
        <svg className={`w-4 h-4 text-gray-400 transition-transform ${open ? 'rotate-180' : ''}`} fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
      </div>
      {open && (
        <div className="mt-2">
          <button onClick={onDelete} className="text-xs text-red-400 hover:text-red-600 font-medium">Supprimer</button>
        </div>
      )}
    </div>
  );
}

function SanteTab({ animalId }: { animalId: string }) {
  const [health, setHealth] = useState<Record<string, HealthRecord[]>>({});
  const [addOpen, setAddOpen] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    const tables = HEALTH_SECTIONS.map(s => s.table);
    Promise.all(tables.map(t => supabase.from(t).select('*').eq('animal_id', animalId).order('date', { ascending: false })))
      .then(results => {
        const h: Record<string, HealthRecord[]> = {};
        tables.forEach((t, i) => { h[t] = (results[i].data ?? []) as HealthRecord[]; });
        setHealth(h);
      });
  }, [animalId]);

  const handleAdd = async (table: string, data: Record<string, string>) => {
    setSaving(true);
    const { data: row } = await supabase.from(table).insert({ ...data, animal_id: animalId }).select().single();
    if (row) setHealth(prev => ({ ...prev, [table]: [row as HealthRecord, ...(prev[table] ?? [])] }));
    setAddOpen(null);
    setSaving(false);
  };
  const handleDelete = async (table: string, id: string) => {
    await supabase.from(table).delete().eq('id', id);
    setHealth(prev => ({ ...prev, [table]: (prev[table] ?? []).filter(r => r.id !== id) }));
  };

  return (
    <div className="space-y-3">
      {HEALTH_SECTIONS.map(s => {
        const records = health[s.table] ?? [];
        const isOpen = addOpen === s.table;
        return (
          <HealthSection key={s.table} title={s.label} icon={s.icon} color={s.color} count={records.length}
            onAdd={() => setAddOpen(isOpen ? null : s.table)}
            addFormOpen={isOpen}
            addForm={isOpen ? (
              <AddForm fields={s.fields} saving={saving}
                onCancel={() => setAddOpen(null)}
                onSave={d => handleAdd(s.table, d)} />
            ) : undefined}>
            {records.map(r => (
              <RecordRow key={r.id} record={r}
                mainKey={s.fields[0].key}
                dateKey={s.fields.find(f => f.type === 'date')?.key}
                onDelete={() => handleDelete(s.table, r.id)} />
            ))}
          </HealthSection>
        );
      })}
    </div>
  );
}

// ─── ConsultationsTab ─────────────────────────────────────────────────────────

function ConsultationsTab({ animalId }: { animalId: string }) {
  const [crs, setCrs] = useState<HealthRecord[]>([]);
  const [ordonnances, setOrdonnances] = useState<HealthRecord[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([
      supabase.from('comptes_rendus').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
      supabase.from('ordonnances').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
    ]).then(([c, o]) => {
      setCrs((c.data ?? []) as HealthRecord[]);
      setOrdonnances((o.data ?? []) as HealthRecord[]);
      setLoading(false);
    });
  }, [animalId]);

  if (loading) return <div className="flex justify-center py-12"><div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;

  if (crs.length === 0 && ordonnances.length === 0) return (
    <div className="flex flex-col items-center py-20 text-center text-gray-400">
      <span className="text-6xl mb-4 opacity-20">🩺</span>
      <p className="font-semibold text-base mb-2" style={{ fontFamily: 'Galey,sans-serif' }}>Aucune consultation enregistrée</p>
      <p className="text-sm">Les comptes rendus et ordonnances de votre vétérinaire apparaîtront ici.</p>
    </div>
  );

  return (
    <div className="space-y-3">
      {crs.length > 0 && (
        <HealthSection title="Comptes rendus" icon="📋" color="#0C5C6C" count={crs.length}>
          {crs.map(r => {
            const date = r.date as string | undefined;
            const notes = (r.notes ?? r.contenu) as string | undefined;
            return (
              <div key={r.id} className="px-4 py-3 border-t border-gray-50">
                {date && <p className="text-sm font-medium text-[#1F2A2E]">{fmtDateShort(date)}</p>}
                {notes && <p className="text-xs text-gray-500 mt-0.5">{notes}</p>}
                {!!r.doc_url && (
                  <a href={String(r.doc_url)} target="_blank" rel="noopener noreferrer"
                    className="text-xs text-[#0C5C6C] font-semibold hover:underline mt-1 inline-flex items-center gap-1">
                    📎 Voir le document
                  </a>
                )}
              </div>
            );
          })}
        </HealthSection>
      )}
      {ordonnances.length > 0 && (
        <HealthSection title="Ordonnances" icon="💊" color="#0C5C6C" count={ordonnances.length}>
          {ordonnances.map(r => {
            const date = r.date as string | undefined;
            const notes = r.notes as string | undefined;
            return (
              <div key={r.id} className="px-4 py-3 border-t border-gray-50">
                {date && <p className="text-sm font-medium text-[#1F2A2E]">{fmtDateShort(date)}</p>}
                {notes && <p className="text-xs text-gray-500 mt-0.5">{notes}</p>}
                {!!r.doc_url && (
                  <a href={String(r.doc_url)} target="_blank" rel="noopener noreferrer"
                    className="text-xs text-[#0C5C6C] font-semibold hover:underline mt-1 inline-flex items-center gap-1">
                    📎 Voir l'ordonnance
                  </a>
                )}
              </div>
            );
          })}
        </HealthSection>
      )}
    </div>
  );
}

// ─── Page principale ──────────────────────────────────────────────────────────

export default function AnimalAssoFichePage() {
  const { id } = useParams<{ id: string }>();
  const { user } = useAuth();
  const router = useRouter();

  const [animal, setAnimal] = useState<Animal | null>(null);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<Tab>('identite');
  const [editStatut, setEditStatut] = useState('');
  const [savingStatut, setSavingStatut] = useState(false);
  const [showDelete, setShowDelete] = useState(false);

  const load = useCallback(async () => {
    if (!user || !id) return;
    const { data } = await supabase.from('animaux').select('*').eq('id', id).eq('uid_eleveur', user.uid).single();
    setAnimal(data as Animal | null);
    setEditStatut(data?.statut ?? '');
    setLoading(false);
  }, [user, id]);

  useEffect(() => { load(); }, [load]);

  const handleStatutChange = async (s: string) => {
    setEditStatut(s);
    setSavingStatut(true);
    await supabase.from('animaux').update({ statut: s }).eq('id', id);
    setAnimal(prev => prev ? { ...prev, statut: s } : prev);
    setSavingStatut(false);
  };

  const handleDelete = async () => {
    await supabase.from('animaux').delete().eq('id', id);
    router.push('/association/animaux');
  };

  if (loading) return (
    <div className="flex justify-center py-20">
      <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
    </div>
  );

  if (!animal) return (
    <div className="text-center py-20 text-gray-500">
      <p className="text-4xl mb-3">🐾</p>
      <p className="font-galey mb-4">Animal introuvable</p>
      <Link href="/association/animaux" className="text-teal-600 underline">Retour</Link>
    </div>
  );

  const sc = STATUTS[animal.statut ?? ''] ?? { label: animal.statut, color: 'bg-gray-100 text-gray-700' };
  const isVaccine = !!(animal.vaccins ?? animal.vaccines);

  return (
    <div className="space-y-4 max-w-2xl">

      {/* Header */}
      <div className="flex items-center gap-3">
        <button onClick={() => router.back()} className="text-gray-400 hover:text-gray-600 text-xl">←</button>
        <h1 className="text-2xl font-bold font-galey text-teal-800 flex-1">{animal.nom}</h1>
        <span className={`text-xs font-galey font-bold px-3 py-1 rounded-full ${sc.color}`}>{sc.label}</span>
      </div>

      {/* Onglets */}
      <div className="flex gap-1 bg-gray-100 rounded-2xl p-1">
        {TABS.map(t => (
          <button key={t.key} onClick={() => setTab(t.key)}
            className={`flex-1 py-2 text-xs font-galey font-semibold rounded-xl transition-all ${
              tab === t.key ? 'bg-white text-teal-800 shadow-sm' : 'text-gray-500 hover:text-gray-700'
            }`}>
            <span className="hidden sm:inline">{t.icon} </span>{t.label}
          </button>
        ))}
      </div>

      {/* ─── Identité ─────────────────────────────────────────────────── */}
      {tab === 'identite' && (
        <div className="space-y-4">
          {/* Photo */}
          <div className="bg-white rounded-2xl shadow-sm overflow-hidden border border-gray-100">
            <div className="aspect-video bg-gray-100 max-h-64 overflow-hidden">
              {animal.photo_url ? (
                <img src={animal.photo_url} alt={animal.nom} className="w-full h-full object-cover" />
              ) : (
                <div className="w-full h-full flex items-center justify-center text-6xl text-gray-300">🐾</div>
              )}
            </div>
            <div className="p-4 grid grid-cols-2 sm:grid-cols-3 gap-3">
              {[
                { label: 'Espèce',   value: animal.espece },
                { label: 'Race',     value: animal.race ?? '–' },
                { label: 'Sexe',     value: animal.sexe === 'male' ? 'Mâle' : animal.sexe === 'femelle' ? 'Femelle' : '–' },
                { label: 'Âge',      value: age(animal.date_naissance, animal.age_estime) || '–' },
                { label: 'Entrée',   value: fmtDate(animal.date_entree) },
                { label: 'Poids',    value: animal.poids ? `${animal.poids} kg` : '–' },
              ].map(({ label, value }) => (
                <div key={label}>
                  <p className="text-xs text-gray-400 font-galey">{label}</p>
                  <p className="text-sm font-galey font-semibold text-gray-800 capitalize">{value}</p>
                </div>
              ))}
            </div>
            {animal.age_estime && (
              <p className="px-4 pb-3 text-xs text-amber-700 italic">
                ⚠ Âge estimé — date de naissance exacte inconnue
              </p>
            )}
          </div>

          {/* Statut */}
          <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
            <p className="text-sm font-galey font-semibold text-gray-700 mb-2">Statut</p>
            <div className="flex flex-wrap gap-2">
              {Object.entries(STATUTS).map(([key, { label, color }]) => (
                <button key={key} onClick={() => handleStatutChange(key)}
                  className={`px-3 py-1.5 rounded-full text-xs font-galey font-semibold border transition-all ${
                    editStatut === key ? color + ' ring-2 ring-offset-1 ring-current' : 'bg-white text-gray-500 border-gray-200 hover:bg-gray-50'
                  }`}>
                  {label}
                </button>
              ))}
            </div>
            {savingStatut && <p className="text-xs text-teal-500 mt-2 font-galey">Enregistrement…</p>}
          </div>

          {/* Suivi santé rapide */}
          <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
            <p className="text-sm font-galey font-semibold text-gray-700 mb-3">Suivi santé</p>
            <div className="grid grid-cols-2 gap-2">
              {[
                { label: 'Vacciné',                value: isVaccine },
                { label: 'Vermifugé',              value: !!animal.vermifuge },
                { label: 'Identifié (puce/tatoo)', value: !!(typeof animal.identification === 'boolean' ? animal.identification : !!animal.identification) },
                { label: 'Stérilisé',              value: !!animal.sterilise },
              ].map(({ label, value }) => (
                <div key={label} className="flex items-center gap-2">
                  <span className={`w-5 h-5 rounded-full flex items-center justify-center text-xs flex-shrink-0 ${value ? 'bg-green-100 text-green-600' : 'bg-gray-100 text-gray-400'}`}>
                    {value ? '✓' : '✗'}
                  </span>
                  <span className="text-sm font-galey text-gray-700">{label}</span>
                </div>
              ))}
            </div>
          </div>

          {/* Notes */}
          {animal.description && (
            <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
              <p className="text-sm font-galey font-semibold text-gray-700 mb-2">Notes</p>
              <p className="text-sm font-galey text-gray-600 whitespace-pre-wrap">{animal.description}</p>
            </div>
          )}

          {/* Actions */}
          <div className="space-y-3">
            {animal.statut === 'disponible' && (
              <Link href={`/association/annonces/creer?animalId=${id}`}
                className="flex items-center justify-center gap-2 w-full bg-teal-700 text-white py-3.5 rounded-xl font-galey font-bold text-base hover:bg-teal-800 transition-colors">
                💚 Mettre en adoption
              </Link>
            )}
            <Link href={`/association/animaux/${id}/modifier`}
              className="flex items-center justify-center gap-2 w-full bg-white border border-teal-200 text-teal-700 py-3 rounded-xl font-galey font-semibold text-sm hover:bg-teal-50 transition-colors">
              ✏️ Modifier la fiche
            </Link>
            {!showDelete ? (
              <button onClick={() => setShowDelete(true)} className="w-full text-red-400 py-2 text-sm font-galey hover:text-red-600">
                Supprimer l'animal
              </button>
            ) : (
              <div className="bg-red-50 border border-red-200 rounded-xl p-4 text-center">
                <p className="text-sm font-galey text-red-700 mb-3">Confirmer la suppression de {animal.nom} ?</p>
                <div className="flex gap-3 justify-center">
                  <button onClick={() => setShowDelete(false)}
                    className="px-4 py-2 rounded-lg border border-gray-200 text-sm font-galey text-gray-600 hover:bg-gray-50">Annuler</button>
                  <button onClick={handleDelete}
                    className="px-4 py-2 rounded-lg bg-red-500 text-white text-sm font-galey hover:bg-red-600">Supprimer</button>
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {/* ─── Santé ────────────────────────────────────────────────────── */}
      {tab === 'sante' && <SanteTab animalId={id} />}

      {/* ─── Alimentation ─────────────────────────────────────────────── */}
      {tab === 'alimentation' && (
        <AlimentationTab animalId={id} espece={animal.espece ?? ''} sexe={animal.sexe ?? ''} sterilise={animal.sterilise ?? false} dateNaissance={animal.date_naissance} nom={animal.nom} userId={''} />
      )}

      {/* ─── Consultations ────────────────────────────────────────────── */}
      {tab === 'consultations' && <ConsultationsTab animalId={id} />}
    </div>
  );
}
