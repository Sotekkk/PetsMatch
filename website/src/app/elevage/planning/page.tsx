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
  is_recurrent: boolean;
  lieu: string;
  description: string;
  ordre: number;
  tranche_horaire?: string | null;
}

interface Template {
  id: string;
  nom: string;
  type: string;
  espece?: string;
  description?: string;
  lieu?: string;
  cible_type: string;
  reference_event: string;
  declencheur_auto?: string | null;
  plan_template_etapes?: Etape[];
}

interface Tache {
  id: string;
  label: string;
  animal_nom?: string | null;
  animaux?: { nom?: string } | null;
  date_prevue: string;
  statut: string;
  jour_traitement: number;
  total_jours: number;
  type_acte?: string;
  lieu?: string | null;
  etape_id?: string | null;
  tranche_horaire?: string | null;
  plans_actifs?: { reference_label?: string } | null;
}

interface TacheGroupe {
  etapeId: string | null;
  taches: Tache[];
  tranche: string | null;
  label: string;
  typeActe: string;
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
  { value: 'individuel', emoji: '🐾', label: 'Animal individuel',  desc: "Sélection manuelle à l'application" },
  { value: 'cheptel',   emoji: '🏡', label: 'Tout le cheptel',    desc: "Tous les animaux de l'espèce" },
  { value: 'males',     emoji: '♂',  label: 'Mâles',             desc: 'Tous les mâles de l\'espèce' },
  { value: 'femelles',  emoji: '♀',  label: 'Femelles',           desc: 'Toutes les femelles de l\'espèce' },
  { value: 'gestantes', emoji: '🤰', label: 'Femelles gestantes', desc: 'Relativement à la date de mise bas' },
  { value: 'bebes',     emoji: '🍼', label: 'Bébés / Jeunes',     desc: "Selon l'âge en semaines" },
];

const REF_EVENT_OPTIONS = [
  { value: 'manuel',       emoji: '📅', label: 'Date choisie',    desc: 'Vous choisissez la date J0' },
  { value: 'saillie',      emoji: '💑', label: 'Saillie',         desc: 'J0 = date de la saillie' },
  { value: 'mise_bas',     emoji: '🍼', label: 'Mise bas',        desc: 'J0 = date de mise bas' },
  { value: 'naissance',    emoji: '🐣', label: 'Naissance',       desc: 'J0 = date de naissance' },
  { value: 'age_semaines', emoji: '📆', label: 'Âge en semaines', desc: 'Déclenche à un âge précis' },
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
  { value: 'ponctuel',     label: 'Ponctuel',     desc: '1 fois (ou N jours consécutifs)' },
  { value: 'quotidien',    label: 'Quotidien',    desc: 'Chaque jour pendant N semaines' },
  { value: 'hebdomadaire', label: '1-3x/semaine', desc: 'Répété N fois/sem. × N semaines' },
  { value: 'mensuel',      label: 'Mensuel',      desc: 'Une fois par mois × N mois' },
];

const ESPECES = ['', 'chien', 'chat', 'cheval', 'lapin', 'oiseau', 'nac', 'ovin', 'caprin', 'porcin'];

const LIEUX_NETTOYAGE = [
  'Chatterie n°1', 'Chatterie n°2', 'Chenil', 'Chenil n°1', 'Chenil n°2',
  'Cuisine', 'Salle de soins', 'Salle de quarantaine', 'Box', 'Jardin', 'Couloir',
];

const ACTE_EMOJIS: Record<string, string> = {
  vermifuge: '💊', vaccination: '💉', antiparasitaire: '🛡️',
  traitement: '🩺', visite: '🏥', nettoyage: '🧹',
  promenade: '🦮', socialisation: '🐾', autre: '📋',
};

const TRANCHES = [
  { value: null,        emoji: '—',  label: 'Non défini' },
  { value: 'matin',    emoji: '🌅', label: 'Matin' },
  { value: 'midi',     emoji: '☀️', label: 'Midi' },
  { value: 'apres_midi', emoji: '🌤️', label: 'Après-midi' },
  { value: 'soir',     emoji: '🌙', label: 'Soir' },
];

const TRANCHE_ORDER: Record<string, number> = { matin: 0, midi: 1, apres_midi: 2, soir: 3 };
const TRANCHE_LABELS: Record<string, string> = {
  matin: '🌅 Matin', midi: '☀️ Midi', apres_midi: '🌤️ Après-midi', soir: '🌙 Soir',
};

// ── Utils ─────────────────────────────────────────────────────────────────────

function toISODate(d: Date) { return d.toISOString().split('T')[0]; }
function addDays(d: Date, n: number) { const r = new Date(d); r.setDate(r.getDate() + n); return r; }

function cibleDescription(cibleType: string, espece?: string) {
  const e = espece ? ` (${espece})` : '';
  const map: Record<string, string> = {
    individuel: 'Sélection manuelle', cheptel: `Tout le cheptel${e}`,
    males: `Mâles${e}`, femelles: `Femelles${e}`,
    gestantes: 'Femelles gestantes — calculé par rapport à la mise bas prévue',
    bebes: "Bébés/jeunes — calculé selon l'âge de chaque animal",
  };
  return map[cibleType] ?? cibleType;
}

function baseLabelFromTaches(taches: Tache[]): string {
  const label = taches[0]?.label ?? '';
  return label.split(' — ')[0] ?? label;
}

function animauxNomFromTaches(taches: Tache[]): string[] {
  return taches.map(t => t.animal_nom ?? '').filter(Boolean);
}

function groupeTaches(taches: Tache[]): TacheGroupe[] {
  const byKey = new Map<string, Tache[]>();
  for (const t of taches) {
    const key = t.etape_id ?? `solo_${t.id}`;
    if (!byKey.has(key)) byKey.set(key, []);
    byKey.get(key)!.push(t);
  }
  const groupes: TacheGroupe[] = [];
  for (const ts of byKey.values()) {
    groupes.push({
      etapeId: ts[0]?.etape_id ?? null,
      taches: ts,
      tranche: ts[0]?.tranche_horaire ?? null,
      label: baseLabelFromTaches(ts),
      typeActe: ts[0]?.type_acte ?? '',
    });
  }
  return groupes.sort((a, b) => {
    const ta = a.tranche ? (TRANCHE_ORDER[a.tranche] ?? 99) : 99;
    const tb = b.tranche ? (TRANCHE_ORDER[b.tranche] ?? 99) : 99;
    return ta !== tb ? ta - tb : a.label.localeCompare(b.label);
  });
}

function printProtocole(template: Template) {
  const etapes = template.plan_template_etapes ?? [];
  const rows = etapes.map((e, i) => {
    const trancheLabel = e.tranche_horaire ? (TRANCHE_LABELS[e.tranche_horaire] ?? e.tranche_horaire) : '—';
    const timing = (e.age_min_semaines != null)
      ? `À ${e.age_min_semaines} semaines`
      : `${e.offset_direction === 'avant' ? 'Avant' : 'Après'} J0 + ${e.jour_offset}j`;
    const freqLabel = e.frequence === 'ponctuel' ? `Ponctuel (${e.duree_jours}j)`
      : e.frequence === 'quotidien' ? `Quotidien (${e.duree_semaines}sem)`
      : e.frequence === 'hebdomadaire' ? `${e.nb_fois_semaine}x/sem × ${e.duree_semaines}sem`
      : `Mensuel × ${e.duree_semaines}mois`;
    return `<tr><td>${i + 1}</td><td>${ACTE_EMOJIS[e.type_acte] ?? '📋'} ${e.type_acte}</td><td>${e.produit || '—'}${e.dosage ? ` (${e.dosage})` : ''}</td><td>${timing}</td><td>${freqLabel}</td><td>${trancheLabel}</td><td>${e.description || ''}</td></tr>`;
  }).join('');
  const html = `<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8"><title>${template.nom}</title>
<style>body{font-family:Arial,sans-serif;font-size:12px;margin:20px;color:#222}h1{font-size:18px;margin-bottom:4px}.meta{color:#666;font-size:11px;margin-bottom:16px}table{width:100%;border-collapse:collapse}th{background:#f0f0f0;font-weight:bold;text-align:left;padding:6px 8px;border:1px solid #ccc}td{padding:6px 8px;border:1px solid #ddd;vertical-align:top}tr:nth-child(even) td{background:#fafafa}.foot{margin-top:24px;font-size:10px;color:#999}@media print{body{margin:10px}}</style>
</head><body>
<h1>📋 ${template.nom}</h1>
<p class="meta">${cibleDescription(template.cible_type, template.espece)} • ${etapes.length} étape${etapes.length > 1 ? 's' : ''}${template.description ? ` • ${template.description}` : ''}</p>
<table><thead><tr><th>#</th><th>Acte</th><th>Produit / Dosage</th><th>Quand</th><th>Fréquence</th><th>Tranche</th><th>Notes</th></tr></thead><tbody>${rows}</tbody></table>
<p class="foot">Imprimé le ${new Date().toLocaleDateString('fr-FR')} • PetsMatch</p>
</body></html>`;
  const win = window.open('', '_blank');
  if (!win) { alert('Autorisez les popups pour imprimer'); return; }
  win.document.write(html);
  win.document.close();
  setTimeout(() => win.print(), 300);
}

function printJour(groupes: TacheGroupe[], date: string) {
  const dateLabel = new Date(date).toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
  const sections: Record<string, TacheGroupe[]> = {};
  for (const g of groupes) {
    const key = g.tranche ?? 'non_defini';
    if (!sections[key]) sections[key] = [];
    sections[key].push(g);
  }
  const sectionOrder = ['matin', 'midi', 'apres_midi', 'soir', 'non_defini'];
  const sectionsHtml = sectionOrder.filter(k => sections[k]?.length).map(k => {
    const sLabel = k === 'non_defini' ? 'Tâches sans tranche' : (TRANCHE_LABELS[k] ?? k);
    const tasksHtml = sections[k].map(g => {
      const animaux = animauxNomFromTaches(g.taches);
      return `<div class="task"><div class="check"></div><div><div class="label">${ACTE_EMOJIS[g.typeActe] ?? '📋'} ${g.label}${g.taches[0]?.lieu ? ` — ${g.taches[0].lieu}` : ''}</div>${animaux.length ? `<div class="sub">🐾 ${animaux.join(', ')}</div>` : ''}</div></div>`;
    }).join('');
    return `<h2>${sLabel}</h2>${tasksHtml}`;
  }).join('');
  const html = `<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8"><title>Planning ${dateLabel}</title>
<style>body{font-family:Arial,sans-serif;font-size:12px;margin:20px;color:#222}h1{font-size:18px;margin-bottom:4px}h2{font-size:13px;color:#555;margin-top:16px;margin-bottom:6px;border-bottom:1px solid #ddd;padding-bottom:2px}.task{display:flex;align-items:flex-start;gap:8px;margin-bottom:8px;padding:8px;border:1px solid #eee;border-radius:6px}.check{width:16px;height:16px;border:1.5px solid #666;border-radius:3px;flex-shrink:0;margin-top:2px}.label{font-weight:bold;font-size:12px}.sub{font-size:11px;color:#555}.sign{margin-top:32px;border-top:1px solid #ccc;padding-top:12px;display:flex;gap:40px}.sign-field{flex:1}.sign-line{border-bottom:1px solid #aaa;margin-top:24px}.foot{margin-top:24px;font-size:10px;color:#999}@media print{body{margin:10px}}</style>
</head><body>
<h1>Planning — ${dateLabel}</h1>
${sectionsHtml}
<div class="sign"><div class="sign-field"><p>Effectué par :</p><div class="sign-line"></div></div><div class="sign-field"><p>Signature :</p><div class="sign-line"></div></div></div>
<p class="foot">Imprimé le ${new Date().toLocaleDateString('fr-FR')} • PetsMatch</p>
</body></html>`;
  const win = window.open('', '_blank');
  if (!win) { alert('Autorisez les popups pour imprimer'); return; }
  win.document.write(html);
  win.document.close();
  setTimeout(() => win.print(), 300);
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
  const [validateGroup, setValidateGroup] = useState<TacheGroupe | null>(null);
  const [deleteGroupe, setDeleteGroupe] = useState<TacheGroupe | null>(null);

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [user, loading, router]);

  const loadTaches = useCallback(async () => {
    if (!user) return;
    setLoadingData(true);
    const { data, error } = await supabase
      .from('plan_taches')
      .select('*, plans_actifs(reference_label)')
      .eq('uid_eleveur', user.uid).eq('date_prevue', selectedDate)
      .not('statut', 'eq', 'fait').order('date_prevue');
    if (error) console.error('[plan_taches]', error.message, error.details);
    setTaches((data ?? []) as Tache[]);
    setLoadingData(false);
  }, [user, selectedDate]);

  const loadTemplates = useCallback(async () => {
    if (!user) return;
    const { data } = await supabase.from('plan_templates').select('*, plan_template_etapes(*)')
      .eq('uid_eleveur', user.uid).order('created_at', { ascending: false });
    setTemplates((data ?? []) as Template[]);
  }, [user]);

  useEffect(() => { if (user) { loadTaches(); loadTemplates(); } }, [user, loadTaches, loadTemplates]);

  if (loading || !user) return (
    <div className="flex justify-center items-center h-64">
      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-green-600" />
    </div>
  );

  const groupes = groupeTaches(taches);

  return (
    <div className="max-w-4xl mx-auto px-4 py-8">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-800">Planning</h1>
        <div className="flex gap-2">
          <button onClick={() => setView('jour')}
            className={`px-4 py-2 rounded-lg text-sm font-semibold transition-colors ${view === 'jour' ? 'bg-green-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>
            Aujourd&apos;hui
          </button>
          <button onClick={() => setView('protocoles')}
            className={`px-4 py-2 rounded-lg text-sm font-semibold transition-colors ${view === 'protocoles' ? 'bg-green-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>
            Protocoles
          </button>
        </div>
      </div>

      {view === 'jour' && (
        <JourView
          groupes={groupes} selectedDate={selectedDate} loading={loadingData}
          onDateChange={setSelectedDate}
          onValider={setValidateGroup}
          onReporter={async (t) => {
            const newDate = toISODate(addDays(new Date(t.date_prevue), 1));
            await supabase.from('plan_taches').update({ statut: 'reporte' }).eq('id', t.id);
            const { data: row } = await supabase.from('plan_taches').select().eq('id', t.id).single();
            if (row) await supabase.from('plan_taches').insert({ ...row, id: undefined, date_prevue: newDate, statut: 'en_attente', valide_par: null, valide_at: null, notes_validation: null, created_at: undefined });
            loadTaches();
          }}
          onDelete={setDeleteGroupe}
          onPrint={() => printJour(groupes, selectedDate)}
          onNewProtocol={() => setView('protocoles')}
        />
      )}

      {view === 'protocoles' && (
        <ProtocolesView
          templates={templates}
          onNew={() => { setEditingTemplate(null); setShowTemplateForm(true); }}
          onEdit={(t) => { setEditingTemplate(t); setShowTemplateForm(true); }}
          onApply={setApplyingTemplate}
          onPrint={printProtocole}
          onDelete={async (id) => {
            if (!confirm('Supprimer ce protocole ?')) return;
            await supabase.from('plan_templates').delete().eq('id', id);
            loadTemplates();
          }}
        />
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
      {validateGroup && (
        <ValidateModal groupe={validateGroup} uid={user.uid}
          onClose={() => setValidateGroup(null)}
          onValidated={() => { setValidateGroup(null); loadTaches(); }} />
      )}
      {deleteGroupe && (
        <DeleteScopeModal groupe={deleteGroupe} uid={user.uid} dateRef={selectedDate}
          onClose={() => setDeleteGroupe(null)}
          onDeleted={() => { setDeleteGroupe(null); loadTaches(); }} />
      )}
    </div>
  );
}

// ── Vue Jour ──────────────────────────────────────────────────────────────────

function JourView({ groupes, selectedDate, loading, onDateChange, onValider, onReporter, onDelete, onPrint, onNewProtocol }: {
  groupes: TacheGroupe[]; selectedDate: string; loading: boolean;
  onDateChange: (d: string) => void;
  onValider: (g: TacheGroupe) => void;
  onReporter: (t: Tache) => void;
  onDelete: (g: TacheGroupe) => void;
  onPrint: () => void;
  onNewProtocol: () => void;
}) {
  const today = new Date();
  const days = Array.from({ length: 7 }, (_, i) => addDays(today, -2 + i));
  const totalTaches = groupes.reduce((s, g) => s + g.taches.length, 0);

  // Build section list preserving tranche order
  const sections: { tranche: string | null; groupes: TacheGroupe[] }[] = [];
  const seenTranches = new Set<string>();
  for (const g of groupes) {
    const key = g.tranche ?? '__none__';
    if (!seenTranches.has(key)) {
      seenTranches.add(key);
      sections.push({ tranche: g.tranche, groupes: [] });
    }
    sections.find(s => (s.tranche ?? '__none__') === key)!.groupes.push(g);
  }

  return (
    <div>
      <div className="flex gap-2 mb-6 overflow-x-auto pb-1">
        {days.map(d => {
          const ds = toISODate(d);
          const isActive = ds === selectedDate;
          const isToday = ds === toISODate(new Date());
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
        <div className="flex items-center gap-2">
          {totalTaches > 0 && (
            <span className="text-xs font-semibold text-green-700 bg-green-100 px-3 py-1 rounded-full">
              {totalTaches} tâche{totalTaches > 1 ? 's' : ''}
            </span>
          )}
          {groupes.length > 0 && (
            <button onClick={onPrint} className="p-2 text-gray-500 hover:text-gray-700 hover:bg-gray-100 rounded-lg" title="Imprimer le planning du jour">
              🖨️
            </button>
          )}
        </div>
      </div>

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-green-600" /></div>
      ) : groupes.length === 0 ? (
        <div className="text-center py-16">
          <div className="text-5xl mb-4">✅</div>
          <p className="text-gray-500 mb-2">Aucune tâche ce jour</p>
          <p className="text-gray-400 text-sm mb-6">Créez des protocoles pour générer des tâches automatiquement</p>
          <button onClick={onNewProtocol} className="px-5 py-2 border border-green-600 text-green-700 rounded-xl text-sm font-semibold hover:bg-green-50">
            Créer un protocole
          </button>
        </div>
      ) : (
        <div className="space-y-6">
          {sections.map(section => (
            <div key={section.tranche ?? 'none'}>
              {section.tranche && (
                <div className="flex items-center gap-2 mb-3">
                  <span className="text-sm font-bold text-gray-500">{TRANCHE_LABELS[section.tranche]}</span>
                  <div className="flex-1 h-px bg-gray-200" />
                </div>
              )}
              <div className="space-y-3">
                {section.groupes.map(g => (
                  <GroupedTacheCard
                    key={g.etapeId ?? g.taches[0]?.id}
                    groupe={g}
                    onValider={() => onValider(g)}
                    onReporter={() => g.taches[0] && onReporter(g.taches[0])}
                    onDelete={() => onDelete(g)}
                  />
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function GroupedTacheCard({ groupe, onValider, onReporter, onDelete }: {
  groupe: TacheGroupe;
  onValider: () => void;
  onReporter: () => void;
  onDelete: () => void;
}) {
  const [menuOpen, setMenuOpen] = useState(false);
  const { taches, label, typeActe } = groupe;
  const first = taches[0];
  const isMulti = (first?.total_jours ?? 0) > 1;
  const animaux = animauxNomFromTaches(taches);
  const ref = first?.plans_actifs?.reference_label;

  return (
    <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 flex gap-3 relative">
      <div className="w-11 h-11 rounded-xl bg-green-50 flex items-center justify-center text-xl flex-shrink-0">
        {ACTE_EMOJIS[typeActe] ?? '📋'}
      </div>
      <div className="flex-1 min-w-0">
        <p className="font-semibold text-gray-800 text-sm">{label}</p>
        {first?.lieu && <p className="text-xs text-gray-400 mt-0.5">📍 {first.lieu}</p>}
        {ref && <p className="text-xs text-gray-400 mt-1">{ref}</p>}
        {animaux.length > 0 && (
          <div className="flex flex-wrap gap-1 mt-2">
            {animaux.map(n => (
              <span key={n} className="text-xs bg-green-100 text-green-700 px-2 py-0.5 rounded-full">🐾 {n}</span>
            ))}
          </div>
        )}
        {isMulti && first && (
          <div className="flex items-center gap-2 mt-2">
            <div className="flex-1 bg-green-100 rounded-full h-1.5">
              <div className="bg-green-600 h-1.5 rounded-full" style={{ width: `${(first.jour_traitement / first.total_jours) * 100}%` }} />
            </div>
            <span className="text-xs font-semibold text-green-700 whitespace-nowrap">J{first.jour_traitement}/{first.total_jours}</span>
          </div>
        )}
      </div>
      <div className="flex flex-col gap-2 flex-shrink-0">
        <button onClick={onValider} className="p-2 bg-green-50 text-green-600 rounded-lg hover:bg-green-100 text-base" title="Valider">✓</button>
        <button onClick={onReporter} className="p-2 bg-amber-50 text-amber-600 rounded-lg hover:bg-amber-100 text-base" title="Reporter">⏰</button>
        <div className="relative">
          <button onClick={() => setMenuOpen(v => !v)} className="p-2 bg-gray-50 text-gray-500 rounded-lg hover:bg-gray-100 text-base leading-none" title="Options">⋯</button>
          {menuOpen && (
            <>
              <div className="fixed inset-0 z-10" onClick={() => setMenuOpen(false)} />
              <div className="absolute right-0 top-full mt-1 bg-white border border-gray-200 rounded-xl shadow-lg z-20 min-w-[190px] py-1">
                <button onClick={() => { setMenuOpen(false); onDelete(); }}
                  className="w-full text-left px-4 py-2.5 text-sm text-red-600 hover:bg-red-50">
                  🗑️ Supprimer…
                </button>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

// ── Vue Protocoles ────────────────────────────────────────────────────────────

function ProtocolesView({ templates, onNew, onEdit, onApply, onPrint, onDelete }: {
  templates: Template[]; onNew: () => void; onEdit: (t: Template) => void;
  onApply: (t: Template) => void; onPrint: (t: Template) => void; onDelete: (id: string) => void;
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
                  <button onClick={() => onPrint(t)} className="p-1.5 text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded-lg" title="Imprimer ce protocole">🖨️</button>
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
  return {
    type_acte: 'vermifuge', produit: '', dosage: '',
    offset_direction: 'apres', jour_offset: 0, age_min_semaines: null,
    frequence: 'ponctuel', nb_fois_semaine: 1, duree_semaines: 1, duree_jours: 1,
    is_recurrent: false, lieu: '', description: '', ordre: 0, tranche_horaire: null,
  };
}

function TemplateFormModal({ existing, uid, onClose, onSaved }: {
  existing: Template | null; uid: string; onClose: () => void; onSaved: () => void;
}) {
  const [nom, setNom] = useState(existing?.nom ?? '');
  const [type, setType] = useState(existing?.type ?? 'sanitaire');
  const [espece, setEspece] = useState(existing?.espece ?? '');
  const [description, setDescription] = useState(existing?.description ?? '');
  const [lieuNett, setLieuNett] = useState(existing?.lieu ?? '');
  const [cibleType, setCibleType] = useState(existing?.cible_type ?? 'individuel');
  const [refEvent, setRefEvent] = useState(existing?.reference_event ?? 'manuel');
  const [declencheurAuto, setDeclencheurAuto] = useState(existing?.declencheur_auto ?? '');
  const [etapes, setEtapes] = useState<Etape[]>(
    existing?.plan_template_etapes?.map(e => ({
      ...e,
      is_recurrent: (e as Etape & { is_recurrent?: boolean }).is_recurrent ?? false,
      tranche_horaire: e.tranche_horaire ?? null,
    })) ?? [newEtape()]
  );
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const updateEtape = (i: number, patch: Partial<Etape>) =>
    setEtapes(prev => prev.map((e, idx) => idx === i ? { ...e, ...patch } : e));

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
      const isNett = type === 'nettoyage' || existing?.type === 'nettoyage';
      const ep = etapes.map((e, i) => ({
        ...e, ordre: i,
        produit: e.produit || null, dosage: e.dosage || null,
        lieu: e.lieu || null, description: e.description || null,
        age_min_semaines: e.age_min_semaines ?? null,
        tranche_horaire: e.tranche_horaire ?? null,
        duree_semaines: e.is_recurrent ? 52 : e.duree_semaines,
      }));
      const templatePayload = {
        nom, espece: espece || null, description: description || null,
        lieu: isNett ? (lieuNett || null) : null,
        cible_type: isNett ? 'cheptel' : cibleType,
        reference_event: isNett ? 'manuel' : refEvent,
        declencheur_auto: (isNett || !declencheurAuto) ? null : declencheurAuto,
      };
      if (existing) {
        await supabase.from('plan_templates').update(templatePayload).eq('id', existing.id);
        await supabase.from('plan_template_etapes').delete().eq('template_id', existing.id);
        if (ep.length > 0) await supabase.from('plan_template_etapes').insert(ep.map(e => ({ ...e, template_id: existing.id })));
      } else {
        const { data: row } = await supabase.from('plan_templates')
          .insert({ uid_eleveur: uid, type, ...templatePayload }).select('id').single();
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

          <div className="space-y-3">
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">Nom *</label>
              <input value={nom} onChange={e => setNom(e.target.value)} placeholder="ex: Vermifuge portée standard chien"
                className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-green-500" />
            </div>
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">Description</label>
              <textarea value={description} onChange={e => setDescription(e.target.value)} rows={2}
                className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-green-500 resize-none" />
            </div>
          </div>

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

          {type === 'nettoyage' && (
            <div className="bg-gray-50 rounded-xl p-4 space-y-3">
              <label className="block text-sm font-bold text-teal-700">Lieu à nettoyer</label>
              <p className="text-xs text-green-700 bg-green-50 p-2 rounded-lg">Indiquez le lieu concerné par ce protocole de nettoyage.</p>
              <div className="flex flex-wrap gap-2">
                {LIEUX_NETTOYAGE.map(l => (
                  <button key={l} onClick={() => setLieuNett(l)}
                    className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors ${lieuNett === l ? 'bg-green-600 text-white' : 'bg-white border border-gray-300 text-gray-600 hover:bg-gray-100'}`}>
                    {l}
                  </button>
                ))}
              </div>
              <input value={lieuNett} onChange={e => setLieuNett(e.target.value)}
                placeholder="Ou écrivez le lieu (ex: Nurserie, Salle de traite…)"
                className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-green-500 bg-white" />
            </div>
          )}

          {type !== 'nettoyage' && (
            <div className="bg-gray-50 rounded-xl p-4 space-y-3">
              <label className="block text-sm font-bold text-teal-700">Qui est concerné ?</label>
              <p className="text-xs text-green-700 bg-green-50 p-2 rounded-lg">Définissez qui sera automatiquement ciblé quand vous appliquez ce protocole.</p>
              <div>
                <label className="block text-xs font-semibold text-gray-600 mb-1">Espèce</label>
                <select value={espece} onChange={e => setEspece(e.target.value)}
                  className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-green-500">
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
          )}

          {type !== 'nettoyage' && cibleType !== 'bebes' && (
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

          {type !== 'nettoyage' && (
            <div className="bg-gray-50 rounded-xl p-4 space-y-3">
              <label className="block text-sm font-bold text-teal-700">Déclenchement automatique</label>
              <p className="text-xs text-gray-400">Si activé, ce protocole sera appliqué automatiquement à l&apos;animal concerné dès que l&apos;événement est enregistré.</p>
              <div className="flex flex-wrap gap-2">
                {[
                  { value: '',          emoji: '—',   label: 'Manuel uniquement' },
                  { value: 'naissance', emoji: '🐣',  label: 'Naissance' },
                  { value: 'chaleurs',  emoji: '🌡️', label: 'Chaleurs' },
                  { value: 'gestation', emoji: '🤰',  label: 'Gestation confirmée' },
                  { value: 'entree',    emoji: '🏠',  label: 'Entrée animal' },
                ].map(d => (
                  <button key={d.value} onClick={() => setDeclencheurAuto(d.value)}
                    className={`px-3 py-1.5 rounded-xl text-sm font-semibold transition-colors ${declencheurAuto === d.value ? 'bg-teal-600 text-white' : 'bg-white border border-gray-200 text-gray-600 hover:bg-gray-50'}`}>
                    {d.emoji} {d.label}
                  </button>
                ))}
              </div>
            </div>
          )}

          <div>
            <div className="flex items-center justify-between mb-3">
              <label className="text-sm font-bold text-teal-700">Étapes du protocole</label>
              <span className="text-xs text-gray-400">{etapes.length} étape{etapes.length > 1 ? 's' : ''}</span>
            </div>
            <div className="space-y-4">
              {etapes.map((e, i) => (
                <EtapeForm key={i} index={i} etape={e} cibleType={cibleType} refEvent={refEvent}
                  onChange={patch => updateEtape(i, patch)}
                  onRemove={etapes.length > 1 ? () => setEtapes(prev => prev.filter((_, idx) => idx !== i)) : undefined} />
              ))}
            </div>
            <button onClick={() => setEtapes(prev => [...prev, newEtape()])}
              className="mt-3 w-full py-2.5 border border-dashed border-green-400 text-green-700 rounded-xl text-sm font-semibold hover:bg-green-50">
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

      <select value={etape.type_acte} onChange={e => onChange({ type_acte: e.target.value })}
        className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:border-green-500">
        {TYPES_ACTES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
      </select>

      <div className="grid grid-cols-2 gap-2">
        <input value={etape.produit} onChange={e => onChange({ produit: e.target.value })} placeholder="Produit (ex: Milbemax®)"
          className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:border-green-500" />
        <input value={etape.dosage} onChange={e => onChange({ dosage: e.target.value })} placeholder="Dosage (ex: 1 cp/5kg)"
          className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:border-green-500" />
      </div>

      <div className="bg-white rounded-lg p-3 border border-gray-200 space-y-2">
        <p className="text-xs font-bold text-gray-500">Quand ?</p>
        {usesAge ? (
          <div className="flex items-center gap-2 text-sm">
            <span>À partir de</span>
            <input type="number" min={0} value={etape.age_min_semaines ?? 3}
              onChange={e => onChange({ age_min_semaines: parseInt(e.target.value) || 0 })}
              className="w-16 border border-gray-200 rounded-lg px-2 py-1.5 text-center text-sm bg-white focus:outline-none focus:border-green-500" />
            <span>semaines d&apos;âge</span>
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

      <div className="bg-white rounded-lg p-3 border border-gray-200 space-y-3">
        <p className="text-xs font-bold text-gray-500">Fréquence</p>
        <div className="flex flex-wrap gap-2">
          {FREQUENCES.map(f => (
            <button key={f.value} onClick={() => onChange({ frequence: f.value, is_recurrent: false })}
              className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors ${etape.frequence === f.value ? 'bg-green-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>
              {f.label}
            </button>
          ))}
        </div>
        {etape.frequence === 'ponctuel' && (
          <div className="flex items-center gap-2">
            <span className="text-xs text-gray-600">Durée :</span>
            <input type="number" min={1} value={etape.duree_jours} onChange={e => onChange({ duree_jours: parseInt(e.target.value) || 1 })}
              className="w-14 border border-gray-200 rounded-lg px-2 py-1.5 text-center text-sm bg-white focus:outline-none focus:border-green-500" />
            <span className="text-xs text-gray-500">jours consécutifs</span>
          </div>
        )}
        {etape.frequence === 'hebdomadaire' && (
          <div className="space-y-1">
            <p className="text-xs font-semibold text-gray-600">Nb fois / semaine :</p>
            <div className="flex gap-2">
              {[1, 2, 3].map(n => (
                <button key={n} onClick={() => onChange({ nb_fois_semaine: n })}
                  className={`w-10 h-9 rounded-lg text-sm font-bold transition-colors ${etape.nb_fois_semaine === n ? 'bg-green-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>
                  {n}x
                </button>
              ))}
            </div>
          </div>
        )}
        {etape.frequence !== 'ponctuel' && (
          <div className="space-y-2">
            <button onClick={() => onChange({ is_recurrent: !etape.is_recurrent })}
              className="flex items-center gap-2 text-xs font-semibold text-gray-700">
              <div className={`w-9 h-5 rounded-full transition-colors relative ${etape.is_recurrent ? 'bg-green-600' : 'bg-gray-300'}`}>
                <div className={`absolute top-0.5 w-4 h-4 bg-white rounded-full shadow transition-transform ${etape.is_recurrent ? 'translate-x-4' : 'translate-x-0.5'}`} />
              </div>
              Protocole récurrent (sans fin)
            </button>
            {!etape.is_recurrent ? (
              <div className="flex items-center gap-2">
                <span className="text-xs text-gray-600">Pendant :</span>
                <input type="number" min={1} value={etape.duree_semaines} onChange={e => onChange({ duree_semaines: parseInt(e.target.value) || 1 })}
                  className="w-14 border border-gray-200 rounded-lg px-2 py-1.5 text-center text-sm bg-white focus:outline-none focus:border-green-500" />
                <span className="text-xs text-gray-500">{etape.frequence === 'mensuel' ? 'mois' : 'semaines'}</span>
              </div>
            ) : (
              <p className="text-xs text-gray-400 italic">Génère 1 an de tâches à l&apos;application</p>
            )}
          </div>
        )}
      </div>

      <div className="bg-white rounded-lg p-3 border border-gray-200">
        <p className="text-xs font-bold text-gray-500 mb-2">Tranche horaire</p>
        <div className="flex flex-wrap gap-2">
          {TRANCHES.map(t => (
            <button key={String(t.value)} onClick={() => onChange({ tranche_horaire: t.value })}
              className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors ${etape.tranche_horaire === t.value ? 'bg-green-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>
              {t.emoji} {t.label}
            </button>
          ))}
        </div>
      </div>

      {showLieu && (
        <input value={etape.lieu} onChange={e => onChange({ lieu: e.target.value })} placeholder="Lieu (ex: parc, jardin, forêt…)"
          className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:border-green-500" />
      )}

      <input value={etape.description} onChange={e => onChange({ description: e.target.value })} placeholder="Notes / instructions"
        className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:border-green-500" />
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
  const isBebes = cibleType === 'bebes';
  const needsAnimal = cibleType === 'individuel';
  const showDate = cibleType !== 'bebes' && cibleType !== 'gestantes';

  useEffect(() => {
    if (!needsAnimal) return;
    supabase.from('animaux').select('id, nom, espece').eq('uid_eleveur', uid).order('nom')
      .then(({ data }) => setAnimaux((data ?? []) as { id: string; nom: string; espece?: string }[]));
  }, [uid, needsAnimal]);

  const apply = async () => {
    if (needsAnimal && !animalId) { alert('Sélectionnez un animal'); return; }
    setSaving(true);
    try {
      const etapes = template.plan_template_etapes ?? [];
      const targets: { animal_id?: string; date_base: string; animal_nom?: string }[] = [];

      if (cibleType === 'individuel') {
        const animal = animaux.find(a => a.id === animalId);
        targets.push({ animal_id: animalId, date_base: dateRef, animal_nom: animal?.nom });
      } else if (cibleType === 'gestantes') {
        const { data: gestations } = await supabase.from('gestations')
          .select('animal_id, date_prevue, animaux(nom)').eq('uid_eleveur', uid).is('date_mise_bas', null);
        for (const g of (gestations ?? []) as unknown as { animal_id: string; date_prevue: string | null; animaux: { nom: string }[] | null }[]) {
          const animalNom = Array.isArray(g.animaux) ? g.animaux[0]?.nom : undefined;
          targets.push({ animal_id: g.animal_id, date_base: g.date_prevue ?? dateRef, animal_nom: animalNom });
        }
      } else if (cibleType === 'bebes') {
        const sixMoisAgo = toISODate(addDays(new Date(), -183));
        let q = supabase.from('animaux').select('id, nom, date_naissance').eq('uid_eleveur', uid).gte('date_naissance', sixMoisAgo);
        if (template.espece) q = q.eq('espece', template.espece);
        const { data: babies } = await q;
        for (const b of (babies ?? []) as { id: string; nom: string; date_naissance: string | null }[]) {
          targets.push({ animal_id: b.id, date_base: b.date_naissance ?? dateRef, animal_nom: b.nom });
        }
      } else {
        let q = supabase.from('animaux').select('id, nom').eq('uid_eleveur', uid);
        if (template.espece) q = q.eq('espece', template.espece);
        if (cibleType === 'males') q = q.eq('sexe', 'male');
        if (cibleType === 'femelles') q = q.eq('sexe', 'femelle');
        const { data: all } = await q;
        for (const a of (all ?? []) as { id: string; nom: string }[]) {
          targets.push({ animal_id: a.id, date_base: dateRef, animal_nom: a.nom });
        }
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
          const direction = etape.offset_direction === 'avant' ? -1 : 1;
          const ageSem = etape.age_min_semaines;
          const baseDate = new Date(target.date_base);
          // Fix: age_min_semaines appliqué uniquement pour les protocoles bébés
          const startDate = (isBebes && ageSem != null)
            ? addDays(baseDate, ageSem * 7)
            : addDays(baseDate, direction * etape.jour_offset);
          const labelBase = [etape.type_acte, etape.produit, etape.dosage ? `(${etape.dosage})` : ''].filter(Boolean).join(' ');
          const common = {
            plan_id: planRow.id, etape_id: etape.id, uid_eleveur: uid,
            animal_id: target.animal_id ?? null,
            animal_nom: target.animal_nom ?? null,
            type_acte: etape.type_acte || null,
            lieu: etape.lieu || null,
            tranche_horaire: etape.tranche_horaire ?? null,
          };

          if (etape.frequence === 'ponctuel') {
            const d = etape.duree_jours;
            for (let j = 1; j <= d; j++) {
              taches.push({ ...common, label: d > 1 ? `${labelBase} — Jour ${j}/${d}` : (labelBase || etape.description || ''),
                date_prevue: toISODate(addDays(startDate, j - 1)), jour_traitement: j, total_jours: d });
            }
          } else if (etape.frequence === 'quotidien') {
            const total = (etape.duree_semaines ?? 1) * 7;
            for (let j = 1; j <= total; j++) {
              taches.push({ ...common, label: `${labelBase} — Jour ${j}/${total}`,
                date_prevue: toISODate(addDays(startDate, j - 1)), jour_traitement: j, total_jours: total });
            }
          } else if (etape.frequence === 'hebdomadaire') {
            const nbFois = etape.nb_fois_semaine ?? 1;
            const dureeS = etape.duree_semaines ?? 1;
            const offsets = nbFois === 1 ? [0] : nbFois === 2 ? [0, 3] : [0, 2, 4];
            const total = nbFois * dureeS;
            let occ = 1;
            for (let s = 0; s < dureeS; s++) {
              for (const off of offsets) {
                taches.push({ ...common, label: `${labelBase} (${occ}e/${total}e)`,
                  date_prevue: toISODate(addDays(startDate, s * 7 + off)), jour_traitement: occ++, total_jours: total });
              }
            }
          } else if (etape.frequence === 'mensuel') {
            const dureeM = etape.duree_semaines ?? 1;
            for (let m = 0; m < dureeM; m++) {
              const d = new Date(startDate);
              d.setMonth(d.getMonth() + m);
              taches.push({ ...common, label: `${labelBase} (mois ${m + 1}/${dureeM})`,
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
              <select value={animalId} onChange={e => setAnimalId(e.target.value)}
                className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-green-500">
                <option value="">— Choisir —</option>
                {animaux.map(a => <option key={a.id} value={a.id}>{a.nom} ({a.espece})</option>)}
              </select>
            </div>
          )}
          {showDate && (
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">
                {template.reference_event === 'mise_bas' ? 'Date de mise bas prévue (J0)'
                  : template.reference_event === 'saillie' ? 'Date de saillie (J0)'
                  : 'Date de référence (J0)'}
              </label>
              <input type="date" value={dateRef} onChange={e => setDateRef(e.target.value)}
                className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-green-500" />
            </div>
          )}
          <button onClick={apply} disabled={saving}
            className="w-full py-3 bg-green-600 text-white rounded-xl font-semibold hover:bg-green-700 disabled:opacity-50">
            {saving ? 'Génération...' : 'Générer les tâches'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Modale validation avec cases à cocher par animal ─────────────────────────

function ValidateModal({ groupe, uid, onClose, onValidated }: {
  groupe: TacheGroupe; uid: string; onClose: () => void; onValidated: () => void;
}) {
  const { taches } = groupe;
  const [selected, setSelected] = useState<Record<string, boolean>>(
    Object.fromEntries(taches.map(t => [t.id, true]))
  );
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);

  const allChecked = Object.values(selected).every(Boolean);
  const someChecked = Object.values(selected).some(Boolean);
  const isMulti = taches.length > 1;
  const animaux = animauxNomFromTaches(taches);

  const validate = async () => {
    setSaving(true);
    const toValidate = taches.filter(t => selected[t.id]);
    for (const t of toValidate) {
      await supabase.from('plan_taches').update({
        statut: 'fait', valide_par: uid,
        valide_at: new Date().toISOString(),
        notes_validation: notes.trim() || null,
      }).eq('id', t.id);
    }
    onValidated();
  };

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl w-full max-w-md p-6 space-y-4">
        <h2 className="text-lg font-bold text-gray-800">Valider : {groupe.label}</h2>

        {isMulti ? (
          <div className="space-y-1">
            <div className="flex items-center justify-between mb-1">
              <p className="text-xs font-semibold text-gray-500">Sélectionnez les animaux à valider :</p>
              <button onClick={() => setSelected(Object.fromEntries(taches.map(t => [t.id, !allChecked])))}
                className="text-xs text-green-600 font-semibold hover:underline">
                {allChecked ? 'Tout désélectionner' : 'Tout sélectionner'}
              </button>
            </div>
            {taches.map((t, i) => {
              const nom = t.animal_nom ?? t.animaux?.nom ?? animaux[i] ?? t.label;
              return (
                <label key={t.id} className="flex items-center gap-3 p-2 rounded-xl hover:bg-gray-50 cursor-pointer">
                  <input type="checkbox" checked={selected[t.id] ?? false}
                    onChange={e => setSelected(prev => ({ ...prev, [t.id]: e.target.checked }))}
                    className="w-4 h-4 accent-green-600" />
                  <span className="text-sm text-gray-700">🐾 {nom}</span>
                </label>
              );
            })}
          </div>
        ) : (
          <p className="text-sm text-gray-600">{animaux[0] ? `🐾 ${animaux[0]}` : groupe.label}</p>
        )}

        <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={3}
          className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-green-500 resize-none"
          placeholder="Notes (optionnel)" />
        <div className="flex gap-3">
          <button onClick={onClose} className="flex-1 py-2.5 border border-gray-200 rounded-xl text-sm font-semibold text-gray-600 hover:bg-gray-50">
            Annuler
          </button>
          <button onClick={validate} disabled={saving || !someChecked}
            className="flex-1 py-2.5 bg-green-600 text-white rounded-xl text-sm font-semibold hover:bg-green-700 disabled:opacity-50">
            {saving ? '...' : `Valider (${Object.values(selected).filter(Boolean).length})`}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Modale suppression Outlook-style ──────────────────────────────────────────

function DeleteScopeModal({ groupe, uid, dateRef, onClose, onDeleted }: {
  groupe: TacheGroupe; uid: string; dateRef: string; onClose: () => void; onDeleted: () => void;
}) {
  const [scope, setScope] = useState<'cette' | 'suivantes' | 'toutes'>('cette');
  const [deleting, setDeleting] = useState(false);

  const dateFmt = new Date(dateRef).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long' });
  const scopes = [
    { value: 'cette',    label: 'Cette occurrence uniquement',     desc: `Supprime uniquement les tâches du ${dateFmt}` },
    { value: 'suivantes', label: "Aujourd'hui et les suivantes",   desc: 'Supprime cette occurrence et toutes les futures (non validées)' },
    { value: 'toutes',   label: 'Toutes les occurrences',          desc: 'Supprime toutes les tâches de cette étape (non validées)' },
  ] as const;

  const doDelete = async () => {
    setDeleting(true);
    const ids = groupe.taches.map(t => t.id);
    const { etapeId } = groupe;

    if (scope === 'cette' || !etapeId) {
      await supabase.from('plan_taches').delete().in('id', ids);
    } else if (scope === 'suivantes') {
      await supabase.from('plan_taches').delete()
        .eq('etape_id', etapeId).eq('uid_eleveur', uid)
        .gte('date_prevue', dateRef).neq('statut', 'fait');
    } else {
      await supabase.from('plan_taches').delete()
        .eq('etape_id', etapeId).eq('uid_eleveur', uid).neq('statut', 'fait');
    }
    onDeleted();
  };

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl w-full max-w-md p-6 space-y-4">
        <h2 className="text-lg font-bold text-gray-800">Supprimer : {groupe.label}</h2>
        <p className="text-xs text-gray-500">Quelle étendue souhaitez-vous supprimer ?</p>
        <div className="space-y-2">
          {scopes.map(s => (
            <button key={s.value} onClick={() => setScope(s.value)}
              className={`w-full flex items-start gap-3 p-3 rounded-xl text-left border transition-colors ${scope === s.value ? 'border-red-400 bg-red-50' : 'border-gray-200 hover:bg-gray-50'}`}>
              <div className={`w-4 h-4 rounded-full border-2 mt-0.5 flex-shrink-0 ${scope === s.value ? 'border-red-500 bg-red-500' : 'border-gray-300'}`} />
              <div>
                <p className={`text-sm font-semibold ${scope === s.value ? 'text-red-700' : 'text-gray-700'}`}>{s.label}</p>
                <p className="text-xs text-gray-400">{s.desc}</p>
              </div>
            </button>
          ))}
        </div>
        <div className="flex gap-3">
          <button onClick={onClose} className="flex-1 py-2.5 border border-gray-200 rounded-xl text-sm font-semibold text-gray-600 hover:bg-gray-50">
            Annuler
          </button>
          <button onClick={doDelete} disabled={deleting}
            className="flex-1 py-2.5 bg-red-600 text-white rounded-xl text-sm font-semibold hover:bg-red-700 disabled:opacity-50">
            {deleting ? '...' : 'Supprimer'}
          </button>
        </div>
      </div>
    </div>
  );
}
