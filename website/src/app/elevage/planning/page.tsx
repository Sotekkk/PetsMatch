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
  jour_offset: number;
  duree_jours: number;
  description: string;
  ordre: number;
}

interface Template {
  id: string;
  nom: string;
  type: string;
  espece?: string;
  description?: string;
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
  plans_actifs?: { reference_label?: string; type_declencheur?: string };
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

const ACTE_EMOJIS: Record<string, string> = {
  vermifuge: '💊', vaccination: '💉', antiparasitaire: '🛡️',
  traitement: '🩺', visite: '🏥', nettoyage: '🧹',
  promenade: '🦮', socialisation: '🐾', autre: '📋',
};

const TYPES_ACTES = [
  { value: 'vermifuge', label: '💊 Vermifuge' },
  { value: 'vaccination', label: '💉 Vaccination' },
  { value: 'antiparasitaire', label: '🛡️ Antiparasitaire' },
  { value: 'traitement', label: '🩺 Traitement' },
  { value: 'visite', label: '🏥 Visite vétérinaire' },
  { value: 'nettoyage', label: '🧹 Nettoyage' },
  { value: 'promenade', label: '🦮 Promenade' },
  { value: 'socialisation', label: '🐾 Socialisation' },
  { value: 'autre', label: '📋 Autre' },
];

const ESPECES = ['', 'chien', 'chat', 'cheval', 'lapin', 'oiseau', 'nac', 'ovin', 'caprin', 'porcin'];

function fmtDate(d: string) {
  return new Date(d).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' });
}

function addDays(date: Date, days: number) {
  const d = new Date(date);
  d.setDate(d.getDate() + days);
  return d;
}

function toISODate(d: Date) {
  return d.toISOString().split('T')[0];
}

// ════════════════════════════════════════════════════════════════════════════════
// PAGE PRINCIPALE
// ════════════════════════════════════════════════════════════════════════════════

export default function PlanningPage() {
  const { user, loading } = useAuth();
  const router = useRouter();

  const [view, setView] = useState<'jour' | 'protocoles'>('jour');
  const [taches, setTaches] = useState<Tache[]>([]);
  const [templates, setTemplates] = useState<Template[]>([]);
  const [selectedDate, setSelectedDate] = useState<string>(toISODate(new Date()));
  const [loadingData, setLoadingData] = useState(true);

  // Modal states
  const [showTemplateForm, setShowTemplateForm] = useState(false);
  const [editingTemplate, setEditingTemplate] = useState<Template | null>(null);
  const [applyingTemplate, setApplyingTemplate] = useState<Template | null>(null);
  const [validateTache, setValidateTache] = useState<Tache | null>(null);

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [user, loading, router]);

  const loadTaches = useCallback(async () => {
    if (!user) return;
    setLoadingData(true);
    const { data } = await supabase
      .from('plan_taches')
      .select('*, plans_actifs(reference_label, type_declencheur)')
      .eq('uid_eleveur', user.uid)
      .eq('date_prevue', selectedDate)
      .neq('statut', 'fait')
      .order('date_prevue');
    setTaches(data ?? []);
    setLoadingData(false);
  }, [user, selectedDate]);

  const loadTemplates = useCallback(async () => {
    if (!user) return;
    const { data } = await supabase
      .from('plan_templates')
      .select('*, plan_template_etapes(*)')
      .eq('uid_eleveur', user.uid)
      .order('created_at', { ascending: false });
    setTemplates(data ?? []);
  }, [user]);

  useEffect(() => { if (user) { loadTaches(); loadTemplates(); } }, [user, loadTaches, loadTemplates]);

  if (loading || !user) return <div className="flex justify-center items-center h-64"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-green-600" /></div>;

  return (
    <div className="max-w-4xl mx-auto px-4 py-8">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-800" style={{ fontFamily: 'Galey' }}>Planning</h1>
        <div className="flex gap-2">
          <button
            onClick={() => setView('jour')}
            className={`px-4 py-2 rounded-lg text-sm font-semibold transition-colors ${view === 'jour' ? 'bg-green-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}
          >
            Aujourd'hui
          </button>
          <button
            onClick={() => setView('protocoles')}
            className={`px-4 py-2 rounded-lg text-sm font-semibold transition-colors ${view === 'protocoles' ? 'bg-green-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}
          >
            Protocoles
          </button>
        </div>
      </div>

      {view === 'jour' && (
        <JourView
          taches={taches}
          selectedDate={selectedDate}
          loading={loadingData}
          onDateChange={setSelectedDate}
          onValider={setValidateTache}
          onReporter={async (t) => {
            const d = new Date(t.date_prevue);
            const newDate = toISODate(addDays(d, 1));
            await supabase.from('plan_taches').update({ statut: 'reporte' }).eq('id', t.id);
            const { data: row } = await supabase.from('plan_taches').select().eq('id', t.id).single();
            if (row) await supabase.from('plan_taches').insert({ ...row, id: undefined, date_prevue: newDate, statut: 'en_attente', valide_par: null, valide_at: null, notes_validation: null, created_at: undefined });
            loadTaches();
          }}
          onNewProtocol={() => setView('protocoles')}
        />
      )}

      {view === 'protocoles' && (
        <ProtocolesView
          templates={templates}
          onNew={() => { setEditingTemplate(null); setShowTemplateForm(true); }}
          onEdit={(t) => { setEditingTemplate(t); setShowTemplateForm(true); }}
          onApply={setApplyingTemplate}
          onDelete={async (id) => {
            if (!confirm('Supprimer ce protocole ?')) return;
            await supabase.from('plan_templates').delete().eq('id', id);
            loadTemplates();
          }}
        />
      )}

      {/* Modale formulaire template */}
      {showTemplateForm && (
        <TemplateFormModal
          existing={editingTemplate}
          uid={user.uid}
          onClose={() => { setShowTemplateForm(false); setEditingTemplate(null); }}
          onSaved={() => { setShowTemplateForm(false); setEditingTemplate(null); loadTemplates(); }}
        />
      )}

      {/* Modale appliquer template */}
      {applyingTemplate && (
        <ApplyModal
          template={applyingTemplate}
          uid={user.uid}
          onClose={() => setApplyingTemplate(null)}
          onApplied={() => { setApplyingTemplate(null); loadTaches(); setView('jour'); }}
        />
      )}

      {/* Modale valider tâche */}
      {validateTache && (
        <ValidateModal
          tache={validateTache}
          uid={user.uid}
          onClose={() => setValidateTache(null)}
          onValidated={() => { setValidateTache(null); loadTaches(); }}
        />
      )}
    </div>
  );
}

// ── Vue Jour ──────────────────────────────────────────────────────────────────

function JourView({ taches, selectedDate, loading, onDateChange, onValider, onReporter, onNewProtocol }: {
  taches: Tache[];
  selectedDate: string;
  loading: boolean;
  onDateChange: (d: string) => void;
  onValider: (t: Tache) => void;
  onReporter: (t: Tache) => void;
  onNewProtocol: () => void;
}) {
  const today = new Date();
  const days = Array.from({ length: 7 }, (_, i) => {
    const d = new Date(today);
    d.setDate(today.getDate() - 2 + i);
    return d;
  });

  return (
    <div>
      {/* Sélecteur 7 jours */}
      <div className="flex gap-2 mb-6 overflow-x-auto pb-1">
        {days.map(d => {
          const ds = toISODate(d);
          const isActive = ds === selectedDate;
          const isToday = toISODate(d) === toISODate(new Date());
          return (
            <button
              key={ds}
              onClick={() => onDateChange(ds)}
              className={`flex flex-col items-center p-3 rounded-xl min-w-[56px] transition-colors ${isActive ? 'bg-green-600 text-white' : isToday ? 'border-2 border-green-500 text-green-700' : 'bg-gray-100 text-gray-600'}`}
            >
              <span className="text-xs font-semibold uppercase">
                {d.toLocaleDateString('fr-FR', { weekday: 'short' }).slice(0, 2)}
              </span>
              <span className="text-lg font-bold">{d.getDate()}</span>
            </button>
          );
        })}
      </div>

      <div className="flex items-center justify-between mb-4">
        <h2 className="text-lg font-bold text-gray-800">
          {selectedDate === toISODate(new Date()) ? "Aujourd'hui" : fmtDate(selectedDate)}
        </h2>
        {taches.length > 0 && (
          <span className="text-xs font-semibold text-green-700 bg-green-100 px-3 py-1 rounded-full">
            {taches.length} tâche{taches.length > 1 ? 's' : ''}
          </span>
        )}
      </div>

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-green-600" /></div>
      ) : taches.length === 0 ? (
        <div className="text-center py-16">
          <div className="text-5xl mb-4">✅</div>
          <p className="text-gray-500 text-base mb-2">Aucune tâche ce jour</p>
          <p className="text-gray-400 text-sm mb-6">Créez des protocoles pour générer des tâches automatiquement</p>
          <button onClick={onNewProtocol} className="px-5 py-2 border border-green-600 text-green-700 rounded-xl text-sm font-semibold hover:bg-green-50 transition-colors">
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

// ── Carte tâche ───────────────────────────────────────────────────────────────

function TacheCard({ tache, onValider, onReporter }: { tache: Tache; onValider: () => void; onReporter: () => void }) {
  const ref = tache.plans_actifs?.reference_label;
  const isMultiJours = tache.total_jours > 1;
  const emoji = ACTE_EMOJIS[tache.type_acte ?? ''] ?? '📋';

  return (
    <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 flex gap-3">
      <div className="w-11 h-11 rounded-xl bg-green-50 flex items-center justify-center text-xl flex-shrink-0">
        {emoji}
      </div>
      <div className="flex-1 min-w-0">
        <p className="font-semibold text-gray-800 text-sm leading-tight">{tache.label}</p>
        {ref && <p className="text-xs text-gray-400 mt-1">{ref}</p>}
        {isMultiJours && (
          <div className="flex items-center gap-2 mt-2">
            <div className="flex-1 bg-green-100 rounded-full h-1.5">
              <div
                className="bg-green-600 h-1.5 rounded-full"
                style={{ width: `${(tache.jour_traitement / tache.total_jours) * 100}%` }}
              />
            </div>
            <span className="text-xs font-semibold text-green-700 whitespace-nowrap">J{tache.jour_traitement}/{tache.total_jours}</span>
          </div>
        )}
      </div>
      <div className="flex flex-col gap-2 flex-shrink-0">
        <button
          onClick={onValider}
          className="p-2 bg-green-50 text-green-600 rounded-lg hover:bg-green-100 transition-colors"
          title="Valider"
        >
          ✓
        </button>
        <button
          onClick={onReporter}
          className="p-2 bg-amber-50 text-amber-600 rounded-lg hover:bg-amber-100 transition-colors"
          title="Reporter"
        >
          ⏰
        </button>
      </div>
    </div>
  );
}

// ── Vue Protocoles ────────────────────────────────────────────────────────────

function ProtocolesView({ templates, onNew, onEdit, onApply, onDelete }: {
  templates: Template[];
  onNew: () => void;
  onEdit: (t: Template) => void;
  onApply: (t: Template) => void;
  onDelete: (id: string) => void;
}) {
  return (
    <div>
      <div className="flex justify-between items-center mb-4">
        <h2 className="text-lg font-bold text-gray-800">Mes protocoles</h2>
        <button onClick={onNew} className="flex items-center gap-2 px-4 py-2 bg-green-600 text-white rounded-xl text-sm font-semibold hover:bg-green-700 transition-colors">
          + Nouveau
        </button>
      </div>

      {templates.length === 0 ? (
        <div className="text-center py-16">
          <div className="text-5xl mb-4">📋</div>
          <p className="text-gray-500 mb-4">Aucun protocole créé</p>
          <button onClick={onNew} className="px-5 py-2 bg-green-600 text-white rounded-xl text-sm font-semibold hover:bg-green-700 transition-colors">
            Créer mon premier protocole
          </button>
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
                    <span className={`text-xs px-2 py-0.5 rounded-full font-semibold ${TYPE_COLORS[t.type] ?? 'bg-gray-100 text-gray-600'}`}>
                      {TYPE_LABELS[t.type] ?? t.type}
                    </span>
                    {t.espece && <span className="text-xs px-2 py-0.5 rounded-full bg-gray-100 text-gray-500">{t.espece}</span>}
                    <span className="text-xs text-gray-400">{t.plan_template_etapes?.length ?? 0} étape{(t.plan_template_etapes?.length ?? 0) > 1 ? 's' : ''}</span>
                  </div>
                  {t.description && <p className="text-xs text-gray-400 mt-1">{t.description}</p>}
                </div>
                <div className="flex gap-1">
                  <button onClick={() => onEdit(t)} className="p-1.5 text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded-lg transition-colors" title="Modifier">✏️</button>
                  <button onClick={() => onDelete(t.id)} className="p-1.5 text-red-400 hover:text-red-600 hover:bg-red-50 rounded-lg transition-colors" title="Supprimer">🗑️</button>
                </div>
              </div>
              <button
                onClick={() => onApply(t)}
                className="mt-4 w-full py-2 bg-green-600 text-white rounded-xl text-sm font-semibold hover:bg-green-700 transition-colors"
              >
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

function TemplateFormModal({ existing, uid, onClose, onSaved }: {
  existing: Template | null;
  uid: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [nom, setNom] = useState(existing?.nom ?? '');
  const [type, setType] = useState(existing?.type ?? 'sanitaire');
  const [espece, setEspece] = useState(existing?.espece ?? '');
  const [description, setDescription] = useState(existing?.description ?? '');
  const [etapes, setEtapes] = useState<Etape[]>(
    existing?.plan_template_etapes ?? [{ type_acte: 'vermifuge', produit: '', dosage: '', jour_offset: 0, duree_jours: 1, description: '', ordre: 0 }]
  );
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const addEtape = () => setEtapes(prev => [...prev, { type_acte: 'vermifuge', produit: '', dosage: '', jour_offset: 0, duree_jours: 1, description: '', ordre: prev.length }]);
  const removeEtape = (i: number) => setEtapes(prev => prev.filter((_, idx) => idx !== i));
  const updateEtape = (i: number, field: keyof Etape, value: string | number) => setEtapes(prev => prev.map((e, idx) => idx === i ? { ...e, [field]: value } : e));

  const save = async () => {
    if (!nom.trim()) { setError('Le nom est requis'); return; }
    setSaving(true);
    try {
      const etapesPayload = etapes.map((e, i) => ({ ...e, ordre: i, produit: e.produit || null, dosage: e.dosage || null, description: e.description || null }));
      if (existing) {
        await supabase.from('plan_templates').update({ nom, espece: espece || null, description: description || null }).eq('id', existing.id);
        await supabase.from('plan_template_etapes').delete().eq('template_id', existing.id);
        if (etapesPayload.length > 0) await supabase.from('plan_template_etapes').insert(etapesPayload.map(e => ({ ...e, template_id: existing.id })));
      } else {
        const { data: row } = await supabase.from('plan_templates').insert({ uid_eleveur: uid, nom, type, espece: espece || null, description: description || null }).select('id').single();
        if (row && etapesPayload.length > 0) await supabase.from('plan_template_etapes').insert(etapesPayload.map(e => ({ ...e, template_id: row.id })));
      }
      onSaved();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : 'Erreur');
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl w-full max-w-2xl max-h-[90vh] overflow-y-auto">
        <div className="sticky top-0 bg-white border-b px-6 py-4 flex items-center justify-between">
          <h2 className="text-lg font-bold text-gray-800">{existing ? 'Modifier le protocole' : 'Nouveau protocole'}</h2>
          <div className="flex gap-2">
            <button onClick={onClose} className="px-3 py-1.5 text-gray-500 hover:text-gray-700 text-sm">Annuler</button>
            <button onClick={save} disabled={saving} className="px-4 py-1.5 bg-green-600 text-white rounded-lg text-sm font-semibold hover:bg-green-700 disabled:opacity-50">
              {saving ? 'Enregistrement...' : 'Enregistrer'}
            </button>
          </div>
        </div>

        <div className="p-6 space-y-5">
          {error && <p className="text-red-500 text-sm bg-red-50 p-3 rounded-lg">{error}</p>}

          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">Nom du protocole *</label>
            <input value={nom} onChange={e => setNom(e.target.value)} placeholder="ex: Vermifuge portée standard chien" className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-green-500" />
          </div>

          {!existing && (
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-2">Type de protocole</label>
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

          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">Espèce cible</label>
            <select value={espece} onChange={e => setEspece(e.target.value)} className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-green-500">
              {ESPECES.map(s => <option key={s} value={s}>{s || 'Toutes espèces'}</option>)}
            </select>
          </div>

          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">Description (optionnel)</label>
            <textarea value={description} onChange={e => setDescription(e.target.value)} rows={2} className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-green-500 resize-none" />
          </div>

          <div>
            <div className="flex items-center justify-between mb-3">
              <label className="text-sm font-bold text-teal-700">Étapes du protocole</label>
              <span className="text-xs text-gray-400">{etapes.length} étape{etapes.length > 1 ? 's' : ''}</span>
            </div>
            <div className="space-y-4">
              {etapes.map((e, i) => (
                <div key={i} className="bg-green-50 border border-green-100 rounded-xl p-4 space-y-3">
                  <div className="flex items-center gap-2">
                    <span className="w-6 h-6 bg-green-600 text-white text-xs font-bold rounded-lg flex items-center justify-center">{i + 1}</span>
                    {etapes.length > 1 && (
                      <button onClick={() => removeEtape(i)} className="ml-auto text-red-400 hover:text-red-600 text-xs">✕ Supprimer</button>
                    )}
                  </div>
                  <select value={e.type_acte} onChange={ev => updateEtape(i, 'type_acte', ev.target.value)} className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-green-500 bg-white">
                    {TYPES_ACTES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
                  </select>
                  <div className="grid grid-cols-2 gap-2">
                    <input value={e.produit} onChange={ev => updateEtape(i, 'produit', ev.target.value)} placeholder="Produit (ex: Milbemax®)" className="border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-green-500 bg-white" />
                    <input value={e.dosage} onChange={ev => updateEtape(i, 'dosage', ev.target.value)} placeholder="Dosage (ex: 1 cp/5kg)" className="border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-green-500 bg-white" />
                  </div>
                  <div className="grid grid-cols-2 gap-2">
                    <div>
                      <label className="text-xs text-gray-500 mb-1 block">Jour relatif (J0 = événement)</label>
                      <input type="number" value={e.jour_offset} onChange={ev => updateEtape(i, 'jour_offset', parseInt(ev.target.value) || 0)} placeholder="0" className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-green-500 bg-white" />
                    </div>
                    <div>
                      <label className="text-xs text-gray-500 mb-1 block">Durée (jours)</label>
                      <input type="number" min={1} value={e.duree_jours} onChange={ev => updateEtape(i, 'duree_jours', parseInt(ev.target.value) || 1)} placeholder="1" className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-green-500 bg-white" />
                    </div>
                  </div>
                  <input value={e.description} onChange={ev => updateEtape(i, 'description', ev.target.value)} placeholder="Notes / instructions" className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-green-500 bg-white" />
                </div>
              ))}
            </div>
            <button onClick={addEtape} className="mt-3 w-full py-2.5 border border-dashed border-green-400 text-green-700 rounded-xl text-sm font-semibold hover:bg-green-50 transition-colors">
              + Ajouter une étape
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ── Modale appliquer ──────────────────────────────────────────────────────────

function ApplyModal({ template, uid, onClose, onApplied }: {
  template: Template;
  uid: string;
  onClose: () => void;
  onApplied: () => void;
}) {
  const [declencheur, setDeclencheur] = useState('saillie');
  const [dateRef, setDateRef] = useState(toISODate(new Date()));
  const [referenceId, setReferenceId] = useState('');
  const [referenceLabel, setReferenceLabel] = useState('');
  const [saillies, setSaillies] = useState<{ id: string; label: string }[]>([]);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    supabase.from('saillies').select('id, date_saillie, animaux(nom)').eq('uid_eleveur', uid).order('date_saillie', { ascending: false }).limit(20)
      .then(({ data }) => {
        setSaillies((data ?? []).map((s: Record<string, unknown>) => ({
          id: s.id as string,
          label: `${(s.animaux as Record<string, unknown>)?.nom ?? 'Animal'} — ${s.date_saillie}`,
        })));
      });
  }, [uid]);

  const etapes = template.plan_template_etapes ?? [];
  const totalTaches = etapes.reduce((acc, e) => acc + (e.duree_jours ?? 1), 0);

  const apply = async () => {
    setSaving(true);
    try {
      const { data: planRow } = await supabase.from('plans_actifs').insert({
        template_id: template.id,
        uid_eleveur: uid,
        type_declencheur: declencheur,
        date_reference: dateRef,
        reference_id: referenceId || null,
        reference_label: referenceLabel || null,
      }).select('id').single();

      if (!planRow) throw new Error('Erreur création plan');

      const taches = [];
      for (const etape of etapes) {
        const offset = etape.jour_offset ?? 0;
        const duree = etape.duree_jours ?? 1;
        const baseDate = new Date(dateRef);
        const labelBase = [etape.type_acte, etape.produit, etape.dosage ? `(${etape.dosage})` : ''].filter(Boolean).join(' ');
        for (let jour = 1; jour <= duree; jour++) {
          const date = addDays(addDays(baseDate, offset), jour - 1);
          taches.push({
            plan_id: planRow.id,
            etape_id: etape.id,
            uid_eleveur: uid,
            label: duree > 1 ? `${labelBase} — Jour ${jour}/${duree}` : (labelBase || etape.description || ''),
            date_prevue: toISODate(date),
            jour_traitement: jour,
            total_jours: duree,
          });
        }
      }
      if (taches.length > 0) await supabase.from('plan_taches').insert(taches);
      onApplied();
    } catch (e) {
      console.error(e);
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center p-4">
      <div className="bg-white rounded-2xl w-full max-w-lg max-h-[85vh] overflow-y-auto">
        <div className="p-6 space-y-5">
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-bold text-gray-800">Appliquer : {template.nom}</h2>
            <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl">×</button>
          </div>
          <p className="text-sm text-gray-400">{totalTaches} tâche{totalTaches > 1 ? 's' : ''} seront générées</p>

          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-2">Événement déclencheur</label>
            <div className="flex flex-wrap gap-2">
              {[['saillie', '🐕 Saillie'], ['naissance', '🍼 Naissance'], ['manuel', '📋 Manuel']].map(([k, v]) => (
                <button key={k} onClick={() => setDeclencheur(k)}
                  className={`px-3 py-1.5 rounded-xl text-sm font-semibold transition-colors ${declencheur === k ? 'bg-green-600 text-white' : 'bg-gray-100 text-gray-600'}`}>
                  {v}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">Date de référence (J0)</label>
            <input type="date" value={dateRef} onChange={e => setDateRef(e.target.value)} className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-green-500" />
          </div>

          {declencheur === 'saillie' && saillies.length > 0 && (
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">Lier à une saillie (optionnel)</label>
              <select value={referenceId} onChange={e => {
                setReferenceId(e.target.value);
                setReferenceLabel(saillies.find(s => s.id === e.target.value)?.label ?? '');
              }} className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-green-500">
                <option value="">Aucune</option>
                {saillies.map(s => <option key={s.id} value={s.id}>{s.label}</option>)}
              </select>
            </div>
          )}

          {/* Aperçu */}
          <div className="bg-green-50 border border-green-100 rounded-xl p-4 space-y-2">
            <p className="text-xs font-semibold text-green-700">Aperçu des tâches générées</p>
            {etapes.slice(0, 4).map((e, i) => {
              const date = addDays(addDays(new Date(dateRef), e.jour_offset ?? 0), 0);
              return (
                <div key={i} className="flex gap-2 text-xs">
                  <span className="font-semibold text-green-700 whitespace-nowrap">{date.toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' })}</span>
                  <span className="text-gray-600">{[e.type_acte, e.produit, e.duree_jours > 1 ? `× ${e.duree_jours} j` : ''].filter(Boolean).join(' ')}</span>
                </div>
              );
            })}
            {etapes.length > 4 && <p className="text-xs text-gray-400">... et {etapes.length - 4} autre{etapes.length - 4 > 1 ? 's' : ''}</p>}
          </div>

          <button onClick={apply} disabled={saving} className="w-full py-3 bg-green-600 text-white rounded-xl font-semibold hover:bg-green-700 disabled:opacity-50 transition-colors">
            {saving ? 'Génération...' : 'Générer les tâches'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Modale validation ─────────────────────────────────────────────────────────

function ValidateModal({ tache, uid, onClose, onValidated }: {
  tache: Tache;
  uid: string;
  onClose: () => void;
  onValidated: () => void;
}) {
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);

  const validate = async () => {
    setSaving(true);
    await supabase.from('plan_taches').update({
      statut: 'fait',
      valide_par: uid,
      valide_at: new Date().toISOString(),
      notes_validation: notes.trim() || null,
    }).eq('id', tache.id);
    onValidated();
  };

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl w-full max-w-md p-6 space-y-4">
        <h2 className="text-lg font-bold text-gray-800">Valider la tâche</h2>
        <p className="text-sm text-gray-600">{tache.label}</p>
        <div>
          <label className="block text-sm font-semibold text-gray-700 mb-1">Notes (optionnel)</label>
          <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={3} className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-green-500 resize-none" placeholder="Observations, produit utilisé..." />
        </div>
        <div className="flex gap-3">
          <button onClick={onClose} className="flex-1 py-2.5 border border-gray-200 rounded-xl text-sm font-semibold text-gray-600 hover:bg-gray-50">Annuler</button>
          <button onClick={validate} disabled={saving} className="flex-1 py-2.5 bg-green-600 text-white rounded-xl text-sm font-semibold hover:bg-green-700 disabled:opacity-50">
            {saving ? '...' : 'Valider'}
          </button>
        </div>
      </div>
    </div>
  );
}
