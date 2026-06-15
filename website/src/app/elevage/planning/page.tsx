'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

// ── Types ──────────────────────────────────────────────────────────────────────

interface Etape {
  id?: string;
  type_acte: string;
  produit: string;
  dosage: string;
  offset_direction: 'avant' | 'apres';
  jour_offset: number;
  age_min_semaines?: number | null;
  frequence: string;
  nb_fois_semaine: number;
  duree_semaines: number;
  duree_jours: number;
  lieu: string;
  description: string;
  ordre: number;
}

interface Template {
  id: string;
  nom: string;
  type: string;
  espece?: string;
  description?: string;
  cible_type: string;
  reference_event: string;
  plan_template_etapes?: Etape[];
}

interface Tache {
  id: string;
  label: string;
  date_prevue: string;
  statut: string;
  jour_traitement: number;
  total_jours: number;
  type_acte?: string;
  lieu?: string;
  plans_actifs?: { reference_label?: string };
  animaux?: { nom?: string; espece?: string };
}

// ── Constantes ────────────────────────────────────────────────────────────────

const TYPE_LABELS: Record<string, string> = {
  sanitaire: 'Sanitaire', nettoyage: 'Nettoyage',
  promenade: 'Promenade', socialisation: 'Socialisation',
};

const TYPE_COLORS: Record<string, string> = {
  sanitaire: 'bg-green-100 text-green-700',
  nettoyage: 'bg-teal-100 text-teal-700',
  promenade: 'bg-purple-100 text-purple-700',
  socialisation: 'bg-orange-100 text-orange-700',
};

const CIBLE_OPTIONS = [
  { value: 'individuel',  emoji: '🐾', label: 'Animal individuel',   desc: 'Sélection manuelle à l\'application' },
  { value: 'cheptel',    emoji: '🏡', label: 'Tout le cheptel',      desc: 'Tous les animaux de l\'espèce' },
  { value: 'males',      emoji: '♂',  label: 'Mâles',               desc: 'Tous les mâles de l\'espèce' },
  { value: 'femelles',   emoji: '♀',  label: 'Femelles',             desc: 'Toutes les femelles de l\'espèce' },
  { value: 'gestantes',  emoji: '🤰', label: 'Femelles gestantes',   desc: 'Relativement à la date de mise bas' },
  { value: 'bebes',      emoji: '🍼', label: 'Bébés / Jeunes',       desc: 'Selon l\'âge en semaines' },
];

const REF_EVENT_OPTIONS = [
  { value: 'manuel',       emoji: '📅', label: 'Date choisie',      desc: 'Vous choisissez la date J0' },
  { value: 'saillie',      emoji: '💑', label: 'Saillie',           desc: 'J0 = date de la saillie' },
  { value: 'mise_bas',     emoji: '🍼', label: 'Mise bas',          desc: 'J0 = date de mise bas' },
  { value: 'naissance',    emoji: '🐣', label: 'Naissance',         desc: 'J0 = date de naissance' },
  { value: 'age_semaines', emoji: '📆', label: 'Âge en semaines',   desc: 'Déclenche à un âge précis' },
];

const TYPES_ACTES = [
  { value: 'vermifuge',       label: '💊 Vermifuge' },
  { value: 'vaccination',     label: '💉 Vaccination' },
  { value: 'antiparasitaire', label: '🛡️ Antiparasitaire' },
  { value: 'traitement',      label: '🩺 Traitement' },
  { value: 'visite',          label: '🏥 Visite vétérinaire' },
  { value: 'nettoyage',       label: '🧹 Nettoyage' },
  { value: 'promenade',       label: '🦮 Promenade' },
  { value: 'socialisation',   label: '🐾 Socialisation' },
  { value: 'autre',           label: '📋 Autre' },
];

const FREQUENCES = [
  { value: 'ponctuel',     label: 'Ponctuel',       desc: '1 fois (ou N jours consécutifs)' },
  { value: 'quotidien',    label: 'Quotidien',      desc: 'Chaque jour pendant N semaines' },
  { value: 'hebdomadaire', label: '1-3x/semaine',   desc: 'Répété N fois/sem. × N semaines' },
  { value: 'mensuel',      label: 'Mensuel',        desc: 'Une fois par mois × N mois' },
];

const ESPECES = ['', 'chien', 'chat', 'cheval', 'lapin', 'oiseau', 'nac', 'ovin', 'caprin', 'porcin'];

const ACTE_EMOJIS: Record<string, string> = {
  vermifuge: '💊', vaccination: '💉', antiparasitaire: '🛡️',
  traitement: '🩺', visite: '🏥', nettoyage: '🧹',
  promenade: '🦮', socialisation: '🐾', autre: '📋',
};

function toISODate(d: Date) { return d.toISOString().split('T')[0]; }
function addDays(d: Date, n: number) { const r = new Date(d); r.setDate(r.getDate() + n); return r; }

function cibleDescription(cibleType: string, espece?: string) {
  const e = espece ? ` (${espece})` : '';
  const map: Record<string, string> = {
    individuel: 'Sélection manuelle', cheptel: `Tout le cheptel${e}`,
    males: `Mâles${e}`, femelles: `Femelles${e}`,
    gestantes: `Femelles gestantes — calculé par rapport à la mise bas prévue`,
    bebes: `Bébés/jeunes — calculé selon l'âge de chaque animal`,
  };
  return map[cibleType] ?? cibleType;
}

// ════════════════════════════════════════════════════════════════════════════════

export default function PlanningPage() {
  const { user, loading } = useAuth();
  const router = useRouter();

  const [view, setView] = useState<'jour' | 'protocoles'>('jour');
  const [taches, setTaches] = useState<Tache[]>([]);
  const [templates, setTemplates] = useState<Template[]>([]);
  const [selectedDate, setSelectedDate] = useState<string>(toISODate(new Date()));
  const [loadingData, setLoadingData] = useState(true);

  const [showTemplateForm, setShowTemplateForm] = useState(false);
  const [editingTemplate, setEditingTemplate] = useState<Template | null>(null);
  const [applyingTemplate, setApplyingTemplate] = useState<Template | null>(null);
  const [validateTache, setValidateTache] = useState<Tache | null>(null);

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [user, loading, router]);

  const loadTaches = useCallback(async () => {
    if (!user) return;
    setLoadingData(true);
    const { data } = await supabase
      .from('plan_taches')
      .select('*, plans_actifs(reference_label), animaux(nom, espece)')
      .eq('uid_eleveur', user.uid).eq('date_prevue', selectedDate)
      .neq('statut', 'fait').order('date_prevue');
    setTaches(data ?? []);
    setLoadingData(false);
  }, [user, selectedDate]);

  const loadTemplates = useCallback(async () => {
    if (!user) return;
    const { data } = await supabase.from('plan_templates').select('*, plan_template_etapes(*)')
      .eq('uid_eleveur', user.uid).order('created_at', { ascending: false });
    setTemplates(data ?? []);
  }, [user]);

  useEffect(() => { if (user) { loadTaches(); loadTemplates(); } }, [user, loadTaches, loadTemplates]);

  if (loading || !user) return <div className="flex justify-center items-center h-64"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-green-600" /></div>;

  return (
    <div className="max-w-4xl mx-auto px-4 py-8">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-800">Planning</h1>
        <div className="flex gap-2">
          <button onClick={() => setView('jour')}
            className={`px-4 py-2 rounded-lg text-sm font-semibold transition-colors ${view === 'jour' ? 'bg-green-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>
            Aujourd'hui
          </button>
          <button onClick={() => setView('protocoles')}
            className={`px-4 py-2 rounded-lg text-sm font-semibold transition-colors ${view === 'protocoles' ? 'bg-green-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>
            Protocoles
          </button>
        </div>
      </div>

      {view === 'jour' && (
        <JourView taches={taches} selectedDate={selectedDate} loading={loadingData}
          onDateChange={setSelectedDate} onValider={setValidateTache}
          onReporter={async (t) => {
            const newDate = toISODate(addDays(new Date(t.date_prevue), 1));
            await supabase.from('plan_taches').update({ statut: 'reporte' }).eq('id', t.id);
            const { data: row } = await supabase.from('plan_taches').select().eq('id', t.id).single();
            if (row) await supabase.from('plan_taches').insert({ ...row, id: undefined, date_prevue: newDate, statut: 'en_attente', valide_par: null, valide_at: null, notes_validation: null, created_at: undefined });
            loadTaches();
          }}
          onNewProtocol={() => setView('protocoles')} />
      )}

      {view === 'protocoles' && (
        <ProtocolesView templates={templates}
          onNew={() => { setEditingTemplate(null); setShowTemplateForm(true); }}
          onEdit={(t) => { setEditingTemplate(t); setShowTemplateForm(true); }}
          onApply={setApplyingTemplate}
          onDelete={async (id) => {
            if (!confirm('Supprimer ce protocole ?')) return;
            await supabase.from('plan_templates').delete().eq('id', id);
            loadTemplates();
          }} />
      )}

      {showTemplateForm && (
        <TemplateFormModal existing={editingTemplate} uid={user.uid}
          onClose={() => { setShowTemplateForm(false); setEditingTemplate(null); }}
          onSaved={() => { setShowTemplateForm(false); setEditingTemplate(null); loadTemplates(); }} />
      )}
      {applyingTemplate && (
        <ApplyModal template={applyingTemplate} uid={user.uid}
          onClose={() => setApplyingTemplate(null)}
          onApplied={() => { setApplyingTemplate(null); loadTaches(); setView('jour'); }} />
      )}
      {validateTache && (
        <ValidateModal tache={validateTache} uid={user.uid}
          onClose={() => setValidateTache(null)}
          onValidated={() => { setValidateTache(null); loadTaches(); }} />
      )}
    </div>
  );
}

// ── Vue Jour ──────────────────────────────────────────────────────────────────

function JourView({ taches, selectedDate, loading, onDateChange, onValider, onReporter, onNewProtocol }: {
  taches: Tache[]; selectedDate: string; loading: boolean;
  onDateChange: (d: string) => void; onValider: (t: Tache) => void;
  onReporter: (t: Tache) => void; onNewProtocol: () => void;
}) {
  const today = new Date();
  const days = Array.from({ length: 7 }, (_, i) => addDays(today, -2 + i));

  return (
    <div>
      <div className="flex gap-2 mb-6 overflow-x-auto pb-1">
        {days.map(d => {
          const ds = toISODate(d);
          const isActive = ds === selectedDate;
          const isToday = toISODate(d) === toISODate(new Date());
          return (
            <button key={ds} onClick={() => onDateChange(ds)}
              className={`flex flex-col items-center p-3 rounded-xl min-w-[56px] transition-colors ${isActive ? 'bg-green-600 text-white' : isToday ? 'border-2 border-green-500 text-green-700' : 'bg-gray-100 text-gray-600'}`}>
              <span className="text-xs font-semibold uppercase">{d.toLocaleDateString('fr-FR', { weekday: 'short' }).slice(0, 2)}</span>
              <span className="text-lg font-bold">{d.getDate()}</span>
            </button>
          );
        })}
      </div>

      <div className="flex items-center justify-between mb-4">
        <h2 className="text-lg font-bold text-gray-800">
          {selectedDate === toISODate(new Date()) ? "Aujourd'hui" : new Date(selectedDate).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long' })}
        </h2>
        {taches.length > 0 && <span className="text-xs font-semibold text-green-700 bg-green-100 px-3 py-1 rounded-full">{taches.length} tâche{taches.length > 1 ? 's' : ''}</span>}
      </div>

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-green-600" /></div>
      ) : taches.length === 0 ? (
        <div className="text-center py-16">
          <div className="text-5xl mb-4">✅</div>
          <p className="text-gray-500 mb-2">Aucune tâche ce jour</p>
          <p className="text-gray-400 text-sm mb-6">Créez des protocoles pour générer des tâches automatiquement</p>
          <button onClick={onNewProtocol} className="px-5 py-2 border border-green-600 text-green-700 rounded-xl text-sm font-semibold hover:bg-green-50">
            Créer un protocole
          </button>
        </div>
      ) : (
        <div className="space-y-3">
          {taches.map(t => <TacheCard key={t.id} tache={t} onValider={() => onValider(t)} onReporter={() => onReporter(t)} />)}
        </div>
      )}
    </div>
  );
}

function TacheCard({ tache, onValider, onReporter }: { tache: Tache; onValider: () => void; onReporter: () => void }) {
  const isMulti = tache.total_jours > 1;
  const animalNom = tache.animaux?.nom;
  const ref = tache.plans_actifs?.reference_label;

  return (
    <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 flex gap-3">
      <div className="w-11 h-11 rounded-xl bg-green-50 flex items-center justify-center text-xl flex-shrink-0">
        {ACTE_EMOJIS[tache.type_acte ?? ''] ?? '📋'}
      </div>
      <div className="flex-1 min-w-0">
        <p className="font-semibold text-gray-800 text-sm">{tache.label}</p>
        {animalNom && <p className="text-xs text-green-700 mt-0.5">🐾 {animalNom}</p>}
        {tache.lieu && <p className="text-xs text-gray-400">📍 {tache.lieu}</p>}
        {ref && <p className="text-xs text-gray-400 mt-1">{ref}</p>}
        {isMulti && (
          <div className="flex items-center gap-2 mt-2">
            <div className="flex-1 bg-green-100 rounded-full h-1.5">
              <div className="bg-green-600 h-1.5 rounded-full" style={{ width: `${(tache.jour_traitement / tache.total_jours) * 100}%` }} />
            </div>
            <span className="text-xs font-semibold text-green-700 whitespace-nowrap">J{tache.jour_traitement}/{tache.total_jours}</span>
          </div>
        )}
      </div>
      <div className="flex flex-col gap-2 flex-shrink-0">
        <button onClick={onValider} className="p-2 bg-green-50 text-green-600 rounded-lg hover:bg-green-100 text-base" title="Valider">✓</button>
        <button onClick={onReporter} className="p-2 bg-amber-50 text-amber-600 rounded-lg hover:bg-amber-100 text-base" title="Reporter">⏰</button>
      </div>
    </div>
  );
}

// ── Vue Protocoles ────────────────────────────────────────────────────────────

function ProtocolesView({ templates, onNew, onEdit, onApply, onDelete }: {
  templates: Template[]; onNew: () => void; onEdit: (t: Template) => void;
  onApply: (t: Template) => void; onDelete: (id: string) => void;
}) {
  return (
    <div>
      <div className="flex justify-between items-center mb-4">
        <h2 className="text-lg font-bold text-gray-800">Mes protocoles</h2>
        <button onClick={onNew} className="px-4 py-2 bg-green-600 text-white rounded-xl text-sm font-semibold hover:bg-green-700">+ Nouveau</button>
      </div>
      {templates.length === 0 ? (
        <div className="text-center py-16">
          <div className="text-5xl mb-4">📋</div>
          <p className="text-gray-500 mb-4">Aucun protocole créé</p>
          <button onClick={onNew} className="px-5 py-2 bg-green-600 text-white rounded-xl text-sm font-semibold hover:bg-green-700">Créer mon premier protocole</button>
        </div>
      ) : (
        <div className="space-y-4">
          {templates.map(t => (
            <div key={t.id} className="bg-white rounded-2xl shadow-sm border border-gray-100 p-5">
              <div className="flex items-start gap-3">
                <div className="text-2xl">{ACTE_EMOJIS[t.type] ?? '📋'}</div>
                <div className="flex-1">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-bold text-gray-800">{t.nom}</span>
                    <span className={`text-xs px-2 py-0.5 rounded-full font-semibold ${TYPE_COLORS[t.type] ?? 'bg-gray-100 text-gray-600'}`}>{TYPE_LABELS[t.type] ?? t.type}</span>
                    {t.espece && <span className="text-xs px-2 py-0.5 rounded-full bg-gray-100 text-gray-500">{t.espece}</span>}
                    <span className="text-xs text-gray-400">{CIBLE_OPTIONS.find(c => c.value === t.cible_type)?.label ?? t.cible_type}</span>
                    <span className="text-xs text-gray-400">{t.plan_template_etapes?.length ?? 0} étape{(t.plan_template_etapes?.length ?? 0) > 1 ? 's' : ''}</span>
                  </div>
                  {t.description && <p className="text-xs text-gray-400 mt-1">{t.description}</p>}
                  <p className="text-xs text-gray-400 mt-1">{cibleDescription(t.cible_type, t.espece)}</p>
                </div>
                <div className="flex gap-1">
                  <button onClick={() => onEdit(t)} className="p-1.5 text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded-lg">✏️</button>
                  <button onClick={() => onDelete(t.id)} className="p-1.5 text-red-400 hover:text-red-600 hover:bg-red-50 rounded-lg">🗑️</button>
                </div>
              </div>
              <button onClick={() => onApply(t)} className="mt-4 w-full py-2 bg-green-600 text-white rounded-xl text-sm font-semibold hover:bg-green-700">
                ▶ Appliquer ce protocole
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ── Modale formulaire template ────────────────────────────────────────────────

function newEtape(): Etape {
  return { type_acte: 'vermifuge', produit: '', dosage: '', offset_direction: 'apres', jour_offset: 0, age_min_semaines: null, frequence: 'ponctuel', nb_fois_semaine: 1, duree_semaines: 1, duree_jours: 1, lieu: '', description: '', ordre: 0 };
}

function TemplateFormModal({ existing, uid, onClose, onSaved }: {
  existing: Template | null; uid: string; onClose: () => void; onSaved: () => void;
}) {
  const [nom, setNom] = useState(existing?.nom ?? '');
  const [type, setType] = useState(existing?.type ?? 'sanitaire');
  const [espece, setEspece] = useState(existing?.espece ?? '');
  const [description, setDescription] = useState(existing?.description ?? '');
  const [cibleType, setCibleType] = useState(existing?.cible_type ?? 'individuel');
  const [refEvent, setRefEvent] = useState(existing?.reference_event ?? 'manuel');
  const [etapes, setEtapes] = useState<Etape[]>(existing?.plan_template_etapes ?? [newEtape()]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const updateEtape = (i: number, patch: Partial<Etape>) =>
    setEtapes(prev => prev.map((e, idx) => idx === i ? { ...e, ...patch } : e));
  const addEtape = () => setEtapes(prev => [...prev, newEtape()]);
  const removeEtape = (i: number) => setEtapes(prev => prev.filter((_, idx) => idx !== i));

  // Auto-sélectionner ref_event cohérent avec la cible
  const handleCible = (c: string) => {
    setCibleType(c);
    if (c === 'gestantes') setRefEvent('mise_bas');
    else if (c === 'bebes') setRefEvent('age_semaines');
    else if (c === 'individuel') setRefEvent('manuel');
  };

  const refEventsForCible = REF_EVENT_OPTIONS.filter(r =>
    cibleType === 'gestantes' ? ['mise_bas', 'saillie', 'manuel'].includes(r.value)
    : cibleType === 'bebes'   ? ['naissance', 'age_semaines'].includes(r.value)
    : r.value !== 'age_semaines'
  );

  const save = async () => {
    if (!nom.trim()) { setError('Le nom est requis'); return; }
    setSaving(true);
    try {
      const ep = etapes.map((e, i) => ({
        ...e, ordre: i,
        produit: e.produit || null, dosage: e.dosage || null,
        lieu: e.lieu || null, description: e.description || null,
        age_min_semaines: e.age_min_semaines ?? null,
      }));
      if (existing) {
        await supabase.from('plan_templates').update({ nom, espece: espece || null, description: description || null, cible_type: cibleType, reference_event: refEvent }).eq('id', existing.id);
        await supabase.from('plan_template_etapes').delete().eq('template_id', existing.id);
        if (ep.length > 0) await supabase.from('plan_template_etapes').insert(ep.map(e => ({ ...e, template_id: existing.id })));
      } else {
        const { data: row } = await supabase.from('plan_templates').insert({ uid_eleveur: uid, nom, type, espece: espece || null, description: description || null, cible_type: cibleType, reference_event: refEvent }).select('id').single();
        if (row && ep.length > 0) await supabase.from('plan_template_etapes').insert(ep.map(e => ({ ...e, template_id: row.id })));
      }
      onSaved();
    } catch (e: unknown) { setError(e instanceof Error ? e.message : 'Erreur'); setSaving(false); }
  };

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl w-full max-w-2xl max-h-[90vh] overflow-y-auto">
        <div className="sticky top-0 bg-white border-b px-6 py-4 flex items-center justify-between z-10">
          <h2 className="text-lg font-bold text-gray-800">{existing ? 'Modifier' : 'Nouveau protocole'}</h2>
          <div className="flex gap-2">
            <button onClick={onClose} className="px-3 py-1.5 text-gray-500 text-sm">Annuler</button>
            <button onClick={save} disabled={saving} className="px-4 py-1.5 bg-green-600 text-white rounded-lg text-sm font-semibold disabled:opacity-50">
              {saving ? '...' : 'Enregistrer'}
            </button>
          </div>
        </div>

        <div className="p-6 space-y-6">
          {error && <p className="text-red-500 text-sm bg-red-50 p-3 rounded-lg">{error}</p>}

          {/* Nom + desc */}
          <div className="space-y-3">
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">Nom *</label>
              <input value={nom} onChange={e => setNom(e.target.value)} placeholder="ex: Vermifuge portée standard chien" className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-green-500" />
            </div>
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">Description</label>
              <textarea value={description} onChange={e => setDescription(e.target.value)} rows={2} className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-green-500 resize-none" />
            </div>
          </div>

          {/* Type (seulement création) */}
          {!existing && (
            <div>
              <label className="block text-sm font-semibold text-teal-700 mb-2">Type de protocole</label>
              <div className="flex flex-wrap gap-2">
                {Object.entries(TYPE_LABELS).map(([k, v]) => (
                  <button key={k} onClick={() => setType(k)}
                    className={`px-3 py-1.5 rounded-xl text-sm font-semibold transition-colors ${type === k ? 'bg-green-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>
                    {v}
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Espèce + cible */}
          <div className="bg-gray-50 rounded-xl p-4 space-y-3">
            <label className="block text-sm font-bold text-teal-700">Qui est concerné ?</label>
            <p className="text-xs text-green-700 bg-green-50 p-2 rounded-lg">Définissez qui sera automatiquement ciblé quand vous appliquez ce protocole.</p>
            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Espèce</label>
              <select value={espece} onChange={e => setEspece(e.target.value)} className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-green-500">
                {ESPECES.map(s => <option key={s} value={s}>{s || 'Toutes espèces'}</option>)}
              </select>
            </div>
            <div className="space-y-2">
              {CIBLE_OPTIONS.map(c => (
                <button key={c.value} onClick={() => handleCible(c.value)}
                  className={`w-full flex items-center gap-3 p-3 rounded-xl text-left transition-colors ${cibleType === c.value ? 'bg-green-50 border border-green-400' : 'bg-white border border-gray-200 hover:bg-gray-50'}`}>
                  <span className="text-lg">{c.emoji}</span>
                  <div className="flex-1">
                    <span className={`text-sm font-semibold ${cibleType === c.value ? 'text-green-800' : 'text-gray-700'}`}>{c.label}</span>
                    <p className="text-xs text-gray-400">{c.desc}</p>
                  </div>
                  {cibleType === c.value && <span className="text-green-600 text-base">✓</span>}
                </button>
              ))}
            </div>
          </div>

          {/* Référence temporelle */}
          {cibleType !== 'bebes' && (
            <div className="bg-gray-50 rounded-xl p-4 space-y-3">
              <label className="block text-sm font-bold text-teal-700">Événement de référence (J0)</label>
              <p className="text-xs text-gray-400">Tous les offsets de vos étapes sont calculés depuis cet événement.</p>
              <div className="space-y-2">
                {refEventsForCible.map(r => (
                  <button key={r.value} onClick={() => setRefEvent(r.value)}
                    className={`w-full flex items-center gap-3 p-3 rounded-xl text-left transition-colors ${refEvent === r.value ? 'bg-green-50 border border-green-400' : 'bg-white border border-gray-200 hover:bg-gray-50'}`}>
                    <span className="text-lg">{r.emoji}</span>
                    <div className="flex-1">
                      <span className={`text-sm font-semibold ${refEvent === r.value ? 'text-green-800' : 'text-gray-700'}`}>{r.label}</span>
                      <p className="text-xs text-gray-400">{r.desc}</p>
                    </div>
                    {refEvent === r.value && <span className="text-green-600">✓</span>}
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Étapes */}
          <div>
            <div className="flex items-center justify-between mb-3">
              <label className="text-sm font-bold text-teal-700">Étapes du protocole</label>
              <span className="text-xs text-gray-400">{etapes.length} étape{etapes.length > 1 ? 's' : ''}</span>
            </div>
            <div className="space-y-4">
              {etapes.map((e, i) => (
                <EtapeForm key={i} index={i} etape={e} cibleType={cibleType} refEvent={refEvent}
                  onChange={patch => updateEtape(i, patch)}
                  onRemove={etapes.length > 1 ? () => removeEtape(i) : undefined} />
              ))}
            </div>
            <button onClick={addEtape} className="mt-3 w-full py-2.5 border border-dashed border-green-400 text-green-700 rounded-xl text-sm font-semibold hover:bg-green-50">
              + Ajouter une étape
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ── Formulaire d'étape ────────────────────────────────────────────────────────

function EtapeForm({ index, etape, cibleType, refEvent, onChange, onRemove }: {
  index: number; etape: Etape; cibleType: string; refEvent: string;
  onChange: (patch: Partial<Etape>) => void; onRemove?: () => void;
}) {
  const usesAge = cibleType === 'bebes';
  const refLabel = { saillie: 'la saillie', mise_bas: 'la mise bas', naissance: 'la naissance' }[refEvent] ?? 'la date J0';
  const showLieu = etape.type_acte === 'promenade' || etape.type_acte === 'socialisation';

  return (
    <div className="bg-green-50 border border-green-100 rounded-xl p-4 space-y-3">
      <div className="flex items-center gap-2">
        <span className="w-6 h-6 bg-green-600 text-white text-xs font-bold rounded-lg flex items-center justify-center">{index + 1}</span>
        {onRemove && <button onClick={onRemove} className="ml-auto text-red-400 hover:text-red-600 text-xs">✕ Supprimer</button>}
      </div>

      {/* Type d'acte */}
      <select value={etape.type_acte} onChange={e => onChange({ type_acte: e.target.value })} className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:border-green-500">
        {TYPES_ACTES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
      </select>

      {/* Produit + dosage */}
      <div className="grid grid-cols-2 gap-2">
        <input value={etape.produit} onChange={e => onChange({ produit: e.target.value })} placeholder="Produit (ex: Milbemax®)" className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:border-green-500" />
        <input value={etape.dosage} onChange={e => onChange({ dosage: e.target.value })} placeholder="Dosage (ex: 1 cp/5kg)" className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:border-green-500" />
      </div>

      {/* Timing */}
      <div className="bg-white rounded-lg p-3 border border-gray-200 space-y-2">
        <p className="text-xs font-bold text-gray-500">Quand ?</p>
        {usesAge ? (
          <div className="flex items-center gap-2 text-sm">
            <span>À partir de</span>
            <input type="number" min={0} value={etape.age_min_semaines ?? 3}
              onChange={e => onChange({ age_min_semaines: parseInt(e.target.value) || 0 })}
              className="w-16 border border-gray-200 rounded-lg px-2 py-1.5 text-center text-sm bg-white focus:outline-none focus:border-green-500" />
            <span>semaines d'âge</span>
          </div>
        ) : (
          <div className="flex items-center gap-2 flex-wrap text-sm">
            <select value={etape.offset_direction} onChange={e => onChange({ offset_direction: e.target.value as 'avant' | 'apres' })}
              className="border border-gray-200 rounded-lg px-2 py-1.5 text-sm bg-white focus:outline-none focus:border-green-500">
              <option value="apres">Après</option>
              <option value="avant">Avant</option>
            </select>
            <input type="number" min={0} value={etape.jour_offset}
              onChange={e => onChange({ jour_offset: parseInt(e.target.value) || 0 })}
              className="w-16 border border-gray-200 rounded-lg px-2 py-1.5 text-center text-sm bg-white focus:outline-none focus:border-green-500" />
            <span className="text-green-700 font-semibold text-xs">jours {refLabel}</span>
          </div>
        )}
      </div>

      {/* Fréquence */}
      <div className="bg-white rounded-lg p-3 border border-gray-200 space-y-2">
        <p className="text-xs font-bold text-gray-500">Fréquence</p>
        <div className="flex flex-wrap gap-2">
          {FREQUENCES.map(f => (
            <button key={f.value} onClick={() => onChange({ frequence: f.value })}
              className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors ${etape.frequence === f.value ? 'bg-green-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>
              {f.label}
            </button>
          ))}
        </div>
        {etape.frequence === 'ponctuel' && (
          <div className="flex items-center gap-2 text-sm">
            <span className="text-xs">Durée :</span>
            <input type="number" min={1} value={etape.duree_jours} onChange={e => onChange({ duree_jours: parseInt(e.target.value) || 1 })}
              className="w-14 border border-gray-200 rounded-lg px-2 py-1.5 text-center text-sm bg-white focus:outline-none focus:border-green-500" />
            <span className="text-xs text-gray-500">jours consécutifs</span>
          </div>
        )}
        {etape.frequence !== 'ponctuel' && (
          <div className="flex items-center gap-2 text-sm flex-wrap">
            {etape.frequence === 'hebdomadaire' && (
              <>
                <span className="text-xs">Nb fois/sem. :</span>
                {[1, 2, 3].map(n => (
                  <button key={n} onClick={() => onChange({ nb_fois_semaine: n })}
                    className={`w-8 h-8 rounded-lg text-sm font-bold transition-colors ${etape.nb_fois_semaine === n ? 'bg-green-600 text-white' : 'bg-gray-100 text-gray-600'}`}>
                    {n}
                  </button>
                ))}
              </>
            )}
            <span className="text-xs">Pendant :</span>
            <input type="number" min={1} value={etape.duree_semaines} onChange={e => onChange({ duree_semaines: parseInt(e.target.value) || 1 })}
              className="w-14 border border-gray-200 rounded-lg px-2 py-1.5 text-center text-sm bg-white focus:outline-none focus:border-green-500" />
            <span className="text-xs text-gray-500">{etape.frequence === 'mensuel' ? 'mois' : 'semaines'}</span>
          </div>
        )}
      </div>

      {/* Lieu (promenade / socialisation) */}
      {showLieu && (
        <input value={etape.lieu} onChange={e => onChange({ lieu: e.target.value })} placeholder="Lieu (ex: parc, jardin, forêt…)" className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:border-green-500" />
      )}

      {/* Notes */}
      <input value={etape.description} onChange={e => onChange({ description: e.target.value })} placeholder="Notes / instructions" className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:border-green-500" />
    </div>
  );
}

// ── Modale appliquer ──────────────────────────────────────────────────────────

function ApplyModal({ template, uid, onClose, onApplied }: {
  template: Template; uid: string; onClose: () => void; onApplied: () => void;
}) {
  const [dateRef, setDateRef] = useState(toISODate(new Date()));
  const [animalId, setAnimalId] = useState('');
  const [animaux, setAnimaux] = useState<{ id: string; nom: string; espece?: string }[]>([]);
  const [saving, setSaving] = useState(false);

  const cibleType = template.cible_type;
  const needsAnimal = cibleType === 'individuel';
  const showDate = ['manuel', 'saillie', 'individuel'].includes(cibleType) || cibleType === 'individuel';

  useEffect(() => {
    if (!needsAnimal) return;
    supabase.from('animaux').select('id, nom, espece').eq('uid_eleveur', uid).order('nom')
      .then(({ data }) => setAnimaux(data ?? []));
  }, [uid, needsAnimal]);

  const apply = async () => {
    if (needsAnimal && !animalId) { alert('Sélectionnez un animal'); return; }
    setSaving(true);
    try {
      const etapes = template.plan_template_etapes ?? [];

      // Résoudre les cibles côté web (simplifié — pour gestantes/bébés, le service Flutter est plus complet)
      const targets: { animal_id?: string; date_base: string }[] = [];

      if (cibleType === 'individuel') {
        targets.push({ animal_id: animalId, date_base: dateRef });
      } else if (cibleType === 'gestantes') {
        const { data: gestations } = await supabase.from('gestations')
          .select('animal_id, date_prevue').eq('uid_eleveur', uid).is('date_mise_bas', null);
        for (const g of gestations ?? []) targets.push({ animal_id: g.animal_id, date_base: g.date_prevue ?? dateRef });
      } else if (cibleType === 'bebes') {
        const sixMoisAgo = toISODate(addDays(new Date(), -183));
        let q = supabase.from('animaux').select('id, date_naissance').eq('uid_eleveur', uid).gte('date_naissance', sixMoisAgo);
        if (template.espece) q = q.eq('espece', template.espece);
        const { data: babies } = await q;
        for (const b of babies ?? []) targets.push({ animal_id: b.id, date_base: b.date_naissance ?? dateRef });
      } else {
        // cheptel / males / femelles
        let q = supabase.from('animaux').select('id').eq('uid_eleveur', uid);
        if (template.espece) q = q.eq('espece', template.espece);
        if (cibleType === 'males') q = q.eq('sexe', 'male');
        if (cibleType === 'femelles') q = q.eq('sexe', 'femelle');
        const { data: all } = await q;
        for (const a of all ?? []) targets.push({ animal_id: a.id, date_base: dateRef });
      }

      let totalTaches = 0;
      for (const target of targets) {
        const { data: planRow } = await supabase.from('plans_actifs').insert({
          template_id: template.id, uid_eleveur: uid,
          type_declencheur: template.reference_event ?? 'manuel',
          date_reference: target.date_base,
          reference_id: target.animal_id ?? null,
        }).select('id').single();

        if (!planRow) continue;

        const taches = [];
        for (const etape of etapes) {
          const direction   = etape.offset_direction === 'avant' ? -1 : 1;
          const frequence   = etape.frequence;
          const ageSem      = etape.age_min_semaines;
          const baseDate    = new Date(target.date_base);
          const startDate   = ageSem != null
            ? addDays(baseDate, ageSem * 7)
            : addDays(baseDate, direction * etape.jour_offset);
          const labelBase   = [etape.type_acte, etape.produit, etape.dosage ? `(${etape.dosage})` : ''].filter(Boolean).join(' ');

          if (frequence === 'ponctuel') {
            const d = etape.duree_jours;
            for (let j = 1; j <= d; j++) {
              taches.push({ plan_id: planRow.id, etape_id: etape.id, uid_eleveur: uid, animal_id: target.animal_id ?? null,
                label: d > 1 ? `${labelBase} — Jour ${j}/${d}` : (labelBase || etape.description || ''),
                type_acte: etape.type_acte || null, lieu: etape.lieu || null,
                date_prevue: toISODate(addDays(startDate, j - 1)), jour_traitement: j, total_jours: d });
            }
          } else if (frequence === 'quotidien') {
            const total = (etape.duree_semaines ?? 1) * 7;
            for (let j = 1; j <= total; j++) {
              taches.push({ plan_id: planRow.id, etape_id: etape.id, uid_eleveur: uid, animal_id: target.animal_id ?? null,
                label: `${labelBase} — Jour ${j}/${total}`, type_acte: etape.type_acte || null, lieu: etape.lieu || null,
                date_prevue: toISODate(addDays(startDate, j - 1)), jour_traitement: j, total_jours: total });
            }
          } else if (frequence === 'hebdomadaire') {
            const nbFois = etape.nb_fois_semaine ?? 1;
            const dureeS = etape.duree_semaines ?? 1;
            const offsets = nbFois === 1 ? [0] : nbFois === 2 ? [0, 3] : [0, 2, 4];
            const total = nbFois * dureeS;
            let occ = 1;
            for (let s = 0; s < dureeS; s++) {
              for (const off of offsets) {
                taches.push({ plan_id: planRow.id, etape_id: etape.id, uid_eleveur: uid, animal_id: target.animal_id ?? null,
                  label: `${labelBase} (${occ}e/${total}e)`, type_acte: etape.type_acte || null, lieu: etape.lieu || null,
                  date_prevue: toISODate(addDays(startDate, s * 7 + off)), jour_traitement: occ, total_jours: total });
                occ++;
              }
            }
          } else if (frequence === 'mensuel') {
            const dureeM = etape.duree_semaines ?? 1;
            for (let m = 0; m < dureeM; m++) {
              const d = new Date(startDate);
              d.setMonth(d.getMonth() + m);
              taches.push({ plan_id: planRow.id, etape_id: etape.id, uid_eleveur: uid, animal_id: target.animal_id ?? null,
                label: `${labelBase} (mois ${m + 1}/${dureeM})`, type_acte: etape.type_acte || null, lieu: etape.lieu || null,
                date_prevue: toISODate(d), jour_traitement: m + 1, total_jours: dureeM });
            }
          }
        }
        if (taches.length > 0) await supabase.from('plan_taches').insert(taches);
        totalTaches += taches.length;
      }
      alert(`${totalTaches} tâche${totalTaches > 1 ? 's' : ''} générée${totalTaches > 1 ? 's' : ''} !`);
      onApplied();
    } catch (e) { console.error(e); setSaving(false); }
  };

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center p-4">
      <div className="bg-white rounded-2xl w-full max-w-md max-h-[85vh] overflow-y-auto">
        <div className="p-6 space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-bold text-gray-800">Appliquer : {template.nom}</h2>
            <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl">×</button>
          </div>
          <div className="bg-green-50 rounded-xl p-3">
            <p className="text-sm text-green-800 font-semibold">{cibleDescription(template.cible_type, template.espece)}</p>
          </div>

          {needsAnimal && (
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">Animal</label>
              <select value={animalId} onChange={e => setAnimalId(e.target.value)} className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-green-500">
                <option value="">— Choisir —</option>
                {animaux.map(a => <option key={a.id} value={a.id}>{a.nom} ({a.espece})</option>)}
              </select>
            </div>
          )}

          {showDate && (
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">
                {template.reference_event === 'mise_bas' ? 'Date de mise bas prévue (J0)' : template.reference_event === 'saillie' ? 'Date de saillie (J0)' : 'Date de référence (J0)'}
              </label>
              <input type="date" value={dateRef} onChange={e => setDateRef(e.target.value)} className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-green-500" />
            </div>
          )}

          <button onClick={apply} disabled={saving} className="w-full py-3 bg-green-600 text-white rounded-xl font-semibold hover:bg-green-700 disabled:opacity-50">
            {saving ? 'Génération...' : 'Générer les tâches'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Modale validation ─────────────────────────────────────────────────────────

function ValidateModal({ tache, uid, onClose, onValidated }: {
  tache: Tache; uid: string; onClose: () => void; onValidated: () => void;
}) {
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);
  const validate = async () => {
    setSaving(true);
    await supabase.from('plan_taches').update({ statut: 'fait', valide_par: uid, valide_at: new Date().toISOString(), notes_validation: notes.trim() || null }).eq('id', tache.id);
    onValidated();
  };
  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl w-full max-w-md p-6 space-y-4">
        <h2 className="text-lg font-bold text-gray-800">Valider la tâche</h2>
        <p className="text-sm text-gray-600">{tache.label}</p>
        <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={3} className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-green-500 resize-none" placeholder="Notes (optionnel)" />
        <div className="flex gap-3">
          <button onClick={onClose} className="flex-1 py-2.5 border border-gray-200 rounded-xl text-sm font-semibold text-gray-600 hover:bg-gray-50">Annuler</button>
          <button onClick={validate} disabled={saving} className="flex-1 py-2.5 bg-green-600 text-white rounded-xl text-sm font-semibold hover:bg-green-700 disabled:opacity-50">{saving ? '...' : 'Valider'}</button>
        </div>
      </div>
    </div>
  );
}
