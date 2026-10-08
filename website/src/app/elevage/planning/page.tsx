'use client';

import { Suspense, useEffect, useState, useCallback } from 'react';
import { useRouter, usePathname, useSearchParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import {
  PERIMETRES, CATEGORIES, REF_EVENTS, ACTES_SUGGERES, TRANCHES_LABELS,
  perimetreDe, perimetreLabel, cibleTypePour, acteDepuisSaisie, type Perimetre,
} from '@/lib/protocoles';
import { ouvrirFicheProtocole } from '@/lib/protocole-pdf';
import { useAuth } from '@/lib/auth-context';
import { usePlan, usePensionPlan, usePlanGarde } from '@/lib/use-plan';
import { useActiveProfileState } from '@/hooks/useActiveProfile';

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
  default_animal_ids?: string[] | null;
  plan_template_etapes?: Etape[];
  created_by_uid?: string | null;
  created_by_profile_id?: string | null;
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
  sanitaire:    'Sanitaire',
  nettoyage:    'Désinfection',
  promenade:    'Promenade / Socialisation',
  socialisation:'Promenade / Socialisation',
  alimentaire:  'Alimentaire',
  toilettage:   'Toilettage',
  materiel:     'Matériel',
};
// Type de protocole pour un pet-sitter : pas d'alimentation (déjà son propre
// onglet sur la fiche animal) ni de toilettage (hors périmètre garde).
const TYPE_LABELS_GARDE: Record<string, string> = {
  sanitaire: 'Sanitaire',
  nettoyage: 'Nettoyage',
  materiel:  'Matériel',
  promenade: 'Promenade',
};

const TYPE_COLORS: Record<string, string> = {
  sanitaire:   'bg-green-100 text-green-700',
  nettoyage:   'bg-teal-100 text-teal-700',
  promenade:   'bg-purple-100 text-purple-700',
  socialisation:'bg-purple-100 text-purple-700',
  alimentaire: 'bg-yellow-100 text-yellow-700',
  toilettage:  'bg-pink-100 text-pink-700',
  materiel:    'bg-blue-100 text-blue-700',
};

const ESPECES = ['', 'chien', 'chat', 'cheval', 'lapin', 'oiseau', 'nac', 'ovin', 'caprin', 'porcin'];

const TYPES_LOCAUX_HISTO = ['nettoyage', 'materiel'];

const LIEUX_NETTOYAGE = [
  'Chatterie n°1', 'Chatterie n°2', 'Chenil', 'Chenil n°1', 'Chenil n°2',
  'Cuisine', 'Salle de soins', 'Salle de quarantaine', 'Box', 'Jardin', 'Couloir',
];

const ACTE_EMOJIS: Record<string, string> = {
  vermifuge: '💊', vaccination: '💉', antiparasitaire: '🛡️',
  traitement: '🩺', visite: '🏥', alimentaire: '🍽️',
  toilettage: '✂️', nettoyage: '🧴',
  promenade: '🦮', socialisation: '🦮', autre: '📋',
};

const TRANCHE_ORDER: Record<string, number> = { matin: 0, midi: 1, apres_midi: 2, soir: 3 };
const TRANCHE_LABELS: Record<string, string> = {
  matin: '🌅 Matin', midi: '☀️ Midi', apres_midi: '🌤️ Après-midi', soir: '🌙 Soir',
};

// Libellé propre d'un acte (pas le code brut type_acte) — partagé entre la
// fiche de lecture (ProtocolViewModal) et l'export imprimable (printProtocole).
const ACTE_LABELS: Record<string, string> = {
  vermifuge: 'Vermifuge', vaccination: 'Vaccination', antiparasitaire: 'Antiparasitaire',
  traitement: 'Traitement', visite: 'Visite vétérinaire', alimentaire: 'Alimentaire',
  toilettage: 'Toilettage', nettoyage: 'Désinfection',
  promenade: 'Promenade / Socialisation', socialisation: 'Promenade / Socialisation',
  autre: 'Autre',
};
function acteLabel(v: string) { return ACTE_LABELS[v] ?? v; }

function etapeTimingLabel(e: Etape): string {
  if (e.age_min_semaines != null) return `À ${e.age_min_semaines} semaines`;
  return `${e.offset_direction === 'avant' ? 'Avant' : 'Après'} J0 + ${e.jour_offset}j`;
}
function etapeFreqLabel(e: Etape): string {
  return e.frequence === 'ponctuel' ? `Ponctuel (${e.duree_jours}j)`
    : e.frequence === 'quotidien' ? `Quotidien (${e.duree_semaines}sem)`
    : e.frequence === 'hebdomadaire' ? `${e.nb_fois_semaine}x/sem × ${e.duree_semaines}sem`
    : `Mensuel × ${e.duree_semaines}mois`;
}
function etapeTrancheLabel(e: Etape): string {
  return e.tranche_horaire ? (TRANCHE_LABELS[e.tranche_horaire] ?? e.tranche_horaire) : '—';
}

// ── Utils ─────────────────────────────────────────────────────────────────────

function toISODate(d: Date) { return d.toISOString().split('T')[0]; }
function addDays(d: Date, n: number) { const r = new Date(d); r.setDate(r.getDate() + n); return r; }

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

function PlanningPageInner() {
  const { user, loading } = useAuth();
  const { id: profileId, loaded: profileLoaded } = useActiveProfileState();
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  // Contexte "employé agissant pour un employeur" (venu de /mes-employeurs) :
  // le protocole appartient à l'employeur (employerUid/employerProfileId),
  // pas au profil actif de l'utilisateur connecté.
  const employerUid = searchParams.get('employerUid');
  const employerProfileId = searchParams.get('employerProfileId');
  const employerNom = searchParams.get('employerNom');
  const profilSource = searchParams.get('profilSource')
    ?? (pathname.startsWith('/association') ? 'association' : 'eleveur');
  const targetUid = employerUid || user?.uid || '';
  const targetProfileId = employerProfileId || profileId;
  // Nom de la structure (en-tête / pied de la fiche PDF des protocoles)
  const [nomStructure, setNomStructure] = useState('');
  useEffect(() => {
    if (!targetProfileId) return;
    supabase.from('user_profiles_complet').select('nom, firstname, lastname').eq('id', targetProfileId).maybeSingle()
      .then(({ data }) => setNomStructure((data?.nom as string) || `${data?.firstname ?? ''} ${data?.lastname ?? ''}`.trim()));
  }, [targetProfileId]);
  const { config: planConfig, loading: planLoading } = usePlan();
  const { plan: pensionPlan, loading: pensionPlanLoading } = usePensionPlan();
  const { plan: gardePlan, loading: gardePlanLoading } = usePlanGarde();
  // La pension et la garde ont chacune leur propre abonnement — les
  // protocoles sont inclus dès le plan payant (même logique que le tiroir
  // appli, cf. eleveur_nav.dart _gardePlanCode).
  const isPensionSource = profilSource === 'pension';
  const isGardeSource = profilSource === 'garde';
  const planGateLoading = isPensionSource ? pensionPlanLoading : isGardeSource ? gardePlanLoading : planLoading;
  const hasProtocolesAccess = isPensionSource ? pensionPlan !== 'free' : isGardeSource ? gardePlan !== 'free' : planConfig.hasPlanning;

  const [employePerms, setEmployePerms] = useState<Set<string>>(new Set());
  const canWrite = !employerUid || employePerms.has('write_protocoles');

  useEffect(() => {
    if (!employerUid || !employerProfileId || !profileId) { setEmployePerms(new Set()); return; }
    supabase.from('employe_permissions').select('permission')
      .eq('employe_profile_id', profileId).eq('eleveur_profile_id', employerProfileId)
      .then(({ data }) => setEmployePerms(new Set((data ?? []).map(r => r.permission as string))));
  }, [employerUid, employerProfileId, profileId]);

  // 'protocoles' par défaut : la page est ouverte depuis le lien nav
  // "Protocoles" — le planning (jour/mois) reste accessible via les onglets,
  // mais ne doit pas s'afficher en premier ("en fond") à l'arrivée.
  const [view, setView] = useState<'jour' | 'mois' | 'protocoles'>('protocoles');
  const [taches, setTaches] = useState<Tache[]>([]);
  const [templates, setTemplates] = useState<Template[]>([]);
  const [selectedDate, setSelectedDate] = useState<string>(toISODate(new Date()));
  const [loadingData, setLoadingData] = useState(true);

  // Protocoles de l'élevage que CET employé est spécifiquement autorisé à
  // appliquer (par défaut, un employé ne peut appliquer que ses propres protocoles).
  const [authorizedTemplateIds, setAuthorizedTemplateIds] = useState<Set<string>>(new Set());
  useEffect(() => {
    if (!employerUid || !profileId) { setAuthorizedTemplateIds(new Set()); return; }
    supabase.from('plan_template_autorisations').select('template_id')
      .eq('employe_profile_id', profileId)
      .then(({ data }) => setAuthorizedTemplateIds(new Set((data ?? []).map(r => r.template_id as string))));
  }, [employerUid, profileId, templates]);

  // ── Calendrier mensuel ───────────────────────────────────────────────────────
  const [focusedMonth, setFocusedMonth] = useState<Date>(() => {
    const d = new Date(); d.setDate(1); d.setHours(0, 0, 0, 0); return d;
  });
  const [tasksByDate, setTasksByDate] = useState<Record<string, string[]>>({});
  const [overdueSet, setOverdueSet]   = useState<Set<string>>(new Set());
  const [monthLoading, setMonthLoading] = useState(false);

  const [showTemplateForm, setShowTemplateForm] = useState(false);
  const [editingTemplate, setEditingTemplate] = useState<Template | null>(null);
  const [applyingTemplate, setApplyingTemplate] = useState<Template | null>(null);
  const [validateGroup, setValidateGroup] = useState<TacheGroupe | null>(null);
  const [deleteGroupe, setDeleteGroupe] = useState<TacheGroupe | null>(null);

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [user, loading, router]);

  const loadTaches = useCallback(async () => {
    if (!user || !profileLoaded) return;
    setLoadingData(true);
    let q = supabase.from('plan_taches')
      .select('*, plans_actifs(reference_label)')
      .eq('date_prevue', selectedDate)
      .not('statut', 'eq', 'fait').order('date_prevue');
    if (targetProfileId) {
      q = q.eq('eleveur_profile_id', targetProfileId) as typeof q;
    } else {
      q = q.eq('uid_eleveur', targetUid) as typeof q;
    }
    const { data, error } = await (profilSource === 'pension'
      ? q.eq('profil_source', 'pension')
      : profilSource === 'association'
        ? q.eq('profil_source', 'association')
        : profilSource === 'garde'
          ? q.eq('profil_source', 'garde')
          : q.or('profil_source.is.null,profil_source.eq.eleveur'));
    if (error) console.error('[plan_taches]', error.message, error.details);
    setTaches((data ?? []) as Tache[]);
    setLoadingData(false);
  }, [user, selectedDate, profilSource, targetProfileId, targetUid, profileLoaded]);

  const loadTemplates = useCallback(async () => {
    if (!user || !profileLoaded) return;
    let q = supabase.from('plan_templates').select('*, plan_template_etapes(*)')
      .order('created_at', { ascending: false });
    if (targetProfileId) {
      q = q.eq('eleveur_profile_id', targetProfileId) as typeof q;
    } else {
      q = q.eq('uid_eleveur', targetUid) as typeof q;
    }
    const { data } = await (profilSource === 'pension'
      ? q.eq('profil_source', 'pension')
      : profilSource === 'association'
        ? q.eq('profil_source', 'association')
        : profilSource === 'garde'
          ? q.eq('profil_source', 'garde')
          : q.or('profil_source.is.null,profil_source.eq.eleveur'));
    setTemplates((data ?? []) as Template[]);
  }, [user, profilSource, targetProfileId, targetUid, profileLoaded]);

  const loadMonth = useCallback(async () => {
    if (!user || !profileLoaded) return;
    setMonthLoading(true);
    const first = new Date(focusedMonth); first.setDate(1);
    const last  = new Date(focusedMonth.getFullYear(), focusedMonth.getMonth() + 1, 0);
    const fmt = (d: Date) => d.toISOString().split('T')[0];
    let qMonth = supabase.from('plan_taches')
      .select('date_prevue, type_acte, statut')
      .gte('date_prevue', fmt(first))
      .lte('date_prevue', fmt(last))
      .not('statut', 'eq', 'fait');
    if (targetProfileId) {
      qMonth = qMonth.eq('eleveur_profile_id', targetProfileId) as typeof qMonth;
    } else {
      qMonth = qMonth.eq('uid_eleveur', targetUid) as typeof qMonth;
    }
    const { data } = await (profilSource === 'pension'
      ? qMonth.eq('profil_source', 'pension')
      : profilSource === 'association'
        ? qMonth.eq('profil_source', 'association')
        : profilSource === 'garde'
          ? qMonth.eq('profil_source', 'garde')
          : qMonth.or('profil_source.is.null,profil_source.eq.eleveur'));
    const byDate: Record<string, string[]> = {};
    const overdue = new Set<string>();
    const todayStr = fmt(new Date());
    for (const r of (data ?? []) as { date_prevue: string; type_acte?: string }[]) {
      const ds = (r.date_prevue ?? '').split('T')[0];
      if (!ds) continue;
      if (!byDate[ds]) byDate[ds] = [];
      if (r.type_acte) byDate[ds].push(r.type_acte);
      if (ds < todayStr) overdue.add(ds);
    }
    setTasksByDate(byDate);
    setOverdueSet(overdue);
    setMonthLoading(false);
  }, [user, focusedMonth, profilSource, targetProfileId, targetUid, profileLoaded]);

  useEffect(() => { if (user) { loadTaches(); loadTemplates(); } }, [user, loadTaches, loadTemplates]);
  useEffect(() => { if (user && view === 'mois') loadMonth(); }, [user, view, loadMonth]);

  if (loading || !user) return (
    <div className="flex justify-center items-center h-64">
      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-green-600" />
    </div>
  );

  {/* En mode employé, l'accès Premium a déjà été vérifié côté employeur
      (impossible de créer un protocole sinon) — on ne re-teste pas le plan
      du compte de l'employé, qui n'a pas de rapport. */}
  if (!employerUid && !planGateLoading && !hasProtocolesAccess) {
    return (
      <div className="min-h-screen bg-[#F8F8F6] flex items-center justify-center p-6">
        <div className="bg-white rounded-2xl shadow-sm border border-[#E5E7EB] max-w-md w-full p-8 text-center">
          <div className="text-5xl mb-4">👑</div>
          <h2 className="text-xl font-bold text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
            Fonctionnalité Premium
          </h2>
          <p className="text-[#6B7280] text-sm mb-6" style={{ fontFamily: 'Galey, sans-serif' }}>
            Le planning des protocoles est réservé aux abonnements <strong>Premium</strong>.
            Créez des modèles de protocoles et planifiez-les pour toute votre portée.
          </p>
          <button
            onClick={() => router.push(isPensionSource ? '/pension/abonnement' : '/abonnement')}
            className="w-full py-3 rounded-xl text-white font-semibold text-sm"
            style={{ backgroundColor: '#D97706', fontFamily: 'Galey, sans-serif' }}
          >
            Passer en Premium
          </button>
        </div>
      </div>
    );
  }

  const groupes = groupeTaches(taches);

  return (
    <div className="max-w-4xl mx-auto px-4 py-8">
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <button onClick={() => router.back()} className="p-2 rounded-xl hover:bg-gray-100 transition-colors">
            <svg className="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
            </svg>
          </button>
          <h1 className="text-2xl font-bold text-gray-800">
            {(view === 'protocoles' ? 'Protocoles' : 'Planning') + (employerNom ? ` · ${employerNom}` : '')}
          </h1>
        </div>
        <div className="flex gap-2">
          <button onClick={() => setView('mois')}
            className={`px-4 py-2 rounded-lg text-sm font-semibold transition-colors ${view === 'mois' ? 'bg-[#0C5C6C] text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>
            Mois
          </button>
          <button onClick={() => setView('jour')}
            className={`px-4 py-2 rounded-lg text-sm font-semibold transition-colors ${view === 'jour' ? 'bg-[#0C5C6C] text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>
            Jour
          </button>
          <button onClick={() => setView('protocoles')}
            className={`px-4 py-2 rounded-lg text-sm font-semibold transition-colors ${view === 'protocoles' ? 'bg-[#0C5C6C] text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>
            Protocoles
          </button>
        </div>
      </div>

      {view === 'mois' && (
        <MoisView
          focusedMonth={focusedMonth}
          tasksByDate={tasksByDate}
          overdueSet={overdueSet}
          loading={monthLoading}
          onPrevMonth={() => setFocusedMonth(m => new Date(m.getFullYear(), m.getMonth() - 1, 1))}
          onNextMonth={() => setFocusedMonth(m => new Date(m.getFullYear(), m.getMonth() + 1, 1))}
          onDayClick={(ds) => { setSelectedDate(ds); setView('jour'); }}
        />
      )}

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
          canWrite={canWrite}
          ownerProfileId={targetProfileId}
          myProfileId={profileId}
          isEmployeeMode={!!employerUid}
          authorizedTemplateIds={authorizedTemplateIds}
          onNew={() => { setEditingTemplate(null); setShowTemplateForm(true); }}
          onEdit={(t) => { setEditingTemplate(t); setShowTemplateForm(true); }}
          onApply={setApplyingTemplate}
          onPrint={t => ouvrirFicheProtocole(t, { structure: nomStructure, profilSource })}
          profilSource={profilSource}
          onDelete={async (id) => {
            if (!confirm('Supprimer ce protocole ?')) return;
            // Ne retire que les occurrences FUTURES de l'agenda ; l'historique
            // passé reste visible. On ne supprime donc pas les lignes
            // plans_actifs (ça cascaderait aussi sur l'historique via
            // plan_taches.plan_id ON DELETE CASCADE) : on les détache du
            // template et on les marque annulées à la place.
            const today = new Date().toISOString().slice(0, 10);
            const { data: plans } = await supabase.from('plans_actifs').select('id').eq('template_id', id);
            const planIds = (plans ?? []).map(p => p.id);
            if (planIds.length > 0) {
              await supabase.from('plan_taches').delete().in('plan_id', planIds).gt('date_prevue', today);
              await supabase.from('plans_actifs').update({ template_id: null, statut: 'annule' }).eq('template_id', id);
            }
            await supabase.from('plan_templates').delete().eq('id', id);
            loadTemplates();
          }}
        />
      )}

      {showTemplateForm && (
        <TemplateFormModal existing={editingTemplate} uid={targetUid} profileId={targetProfileId || null} profilSource={profilSource}
          createdByUid={user.uid} createdByProfileId={profileId || null}
          onClose={() => { setShowTemplateForm(false); setEditingTemplate(null); }}
          onSaved={() => { setShowTemplateForm(false); setEditingTemplate(null); loadTemplates(); }} />
      )}
      {applyingTemplate && (
        <ApplyModal template={applyingTemplate} uid={targetUid} profileId={targetProfileId || null} profilSource={profilSource}
          onClose={() => setApplyingTemplate(null)}
          onApplied={() => { setApplyingTemplate(null); loadTaches(); setView('jour'); }} />
      )}
      {validateGroup && (
        <ValidateModal groupe={validateGroup} uid={user.uid} profileId={profileId || null}
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

// ── Couleurs par type d'acte ──────────────────────────────────────────────────

const TYPE_DOT_COLORS: Record<string, string> = {
  vaccination:     '#4CAF50',
  visite:          '#2196F3',
  traitement:      '#0C5C6C',
  vermifuge:       '#FFC107',
  antiparasitaire: '#FF9800',
  osteopathie:     '#9C27B0',
  ferrage:         '#795548',
  radiographie:    '#607D8B',
  chirurgie:       '#F44336',
  alimentaire:     '#FF9800',
  toilettage:      '#E91E63',
  nettoyage:       '#00BCD4',
  promenade:       '#673AB7',
  socialisation:   '#673AB7',
  commande:        '#6E9E57',
};

const DOT_LEGEND = [
  { color: '#EF4444',  label: 'En retard' },
  { color: '#0C5C6C',  label: 'Traitement' },
  { color: '#4CAF50',  label: 'Vaccination' },
  { color: '#2196F3',  label: 'Visite' },
  { color: '#FFC107',  label: 'Vermifuge' },
  { color: '#FF9800',  label: 'Antiparasitaire' },
  { color: '#00BCD4',  label: 'Nettoyage' },
  { color: '#673AB7',  label: 'Promenade' },
  { color: '#FF5722',  label: 'Socialisation' },
];

const MONTH_NAMES_FR = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
  'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'];

// ── Vue Mois ──────────────────────────────────────────────────────────────────

function MoisView({ focusedMonth, tasksByDate, overdueSet, loading, onPrevMonth, onNextMonth, onDayClick }: {
  focusedMonth: Date;
  tasksByDate: Record<string, string[]>;
  overdueSet: Set<string>;
  loading: boolean;
  onPrevMonth: () => void;
  onNextMonth: () => void;
  onDayClick: (ds: string) => void;
}) {
  const today = toISODate(new Date());
  const year  = focusedMonth.getFullYear();
  const month = focusedMonth.getMonth();
  const firstDay = new Date(year, month, 1);
  // offset lundi=0 … dimanche=6
  const startOffset = (firstDay.getDay() + 6) % 7;
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const totalCells  = Math.ceil((startOffset + daysInMonth) / 7) * 7;
  const fmt = (y: number, m: number, d: number) =>
    `${y}-${String(m + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`;

  return (
    <div>
      {/* Navigation mois */}
      <div className="flex items-center justify-between mb-4 px-1">
        <button onClick={onPrevMonth} className="p-2 rounded-xl hover:bg-gray-100 transition-colors text-[#0C5C6C]">
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </button>
        <span className="text-base font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
          {MONTH_NAMES_FR[month]} {year}
        </span>
        <button onClick={onNextMonth} className="p-2 rounded-xl hover:bg-gray-100 transition-colors text-[#0C5C6C]">
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
          </svg>
        </button>
      </div>

      {/* Entête jours */}
      <div className="grid grid-cols-7 mb-1">
        {['Lu', 'Ma', 'Me', 'Je', 'Ve', 'Sa', 'Di'].map(d => (
          <div key={d} className="text-center text-xs font-semibold text-gray-400 py-1">{d}</div>
        ))}
      </div>

      {/* Grille */}
      {loading ? (
        <div className="flex justify-center py-16">
          <div className="w-7 h-7 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
        </div>
      ) : (
        <div className="grid grid-cols-7 gap-1">
          {Array.from({ length: totalCells }, (_, i) => {
            const dayNum = i - startOffset + 1;
            if (dayNum < 1 || dayNum > daysInMonth) {
              return <div key={i} />;
            }
            const ds      = fmt(year, month, dayNum);
            const isToday = ds === today;
            const isOver  = overdueSet.has(ds);
            const types   = tasksByDate[ds] ?? [];
            const unique  = [...new Set(types)].slice(0, 3);

            return (
              <button key={ds} onClick={() => onDayClick(ds)}
                className={`relative flex flex-col items-center justify-center rounded-xl aspect-square transition-colors text-sm font-semibold
                  ${isToday
                    ? 'bg-[#0C5C6C] text-white shadow-md'
                    : isOver && types.length > 0
                      ? 'bg-white border-2 border-red-300 text-[#1F2A2E] hover:bg-red-50'
                      : 'bg-white border border-gray-100 text-[#1F2A2E] hover:bg-gray-50'
                  }`}>
                <span className="text-sm font-bold leading-none">{dayNum}</span>
                {types.length > 0 && (
                  <div className="flex gap-0.5 mt-1 items-center">
                    {isOver && !isToday ? (
                      <span className="w-1.5 h-1.5 rounded-full bg-red-500 inline-block" />
                    ) : (
                      unique.map((t, idx) => (
                        <span key={idx} className="w-1.5 h-1.5 rounded-full inline-block"
                          style={{ backgroundColor: TYPE_DOT_COLORS[t] ?? '#9CA3AF' }} />
                      ))
                    )}
                    {types.length > 3 && !isOver && (
                      <span className={`text-[8px] font-bold leading-none ${isToday ? 'text-white/70' : 'text-gray-400'}`}>
                        +{types.length - 3}
                      </span>
                    )}
                  </div>
                )}
              </button>
            );
          })}
        </div>
      )}

      {/* Légende */}
      <div className="mt-4 flex flex-wrap gap-x-3 gap-y-1.5 px-1">
        {DOT_LEGEND.map(({ color, label }) => (
          <div key={label} className="flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ backgroundColor: color }} />
            <span className="text-xs text-gray-500">{label}</span>
          </div>
        ))}
      </div>
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
    <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 flex gap-3 relative cursor-pointer hover:shadow-md transition-shadow"
         onClick={onValider}>
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
      <div className="flex flex-col gap-2 flex-shrink-0" onClick={e => e.stopPropagation()}>
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

function ProtocolesView({ templates, canWrite = true, ownerProfileId, myProfileId, isEmployeeMode = false, authorizedTemplateIds, profilSource, onNew, onEdit, onApply, onPrint, onDelete }: {
  templates: Template[]; canWrite?: boolean; ownerProfileId?: string | null;
  myProfileId?: string | null; isEmployeeMode?: boolean; authorizedTemplateIds?: Set<string>;
  profilSource?: string;
  onNew: () => void; onEdit: (t: Template) => void;
  onApply: (t: Template) => void; onPrint: (t: Template) => void; onDelete: (id: string) => void;
}) {
  const [creatorNames, setCreatorNames] = useState<Record<string, string>>({});
  const [authModalTemplate, setAuthModalTemplate] = useState<Template | null>(null);
  const [viewModal, setViewModal] = useState<{ template: Template; canEdit: boolean } | null>(null);
  const [menuOuvert, setMenuOuvert] = useState<string | null>(null);
  const [recherche, setRecherche] = useState('');
  const [impression, setImpression] = useState<string | null>(null);

  useEffect(() => {
    const ids = [...new Set(templates
      .map(t => t.created_by_profile_id)
      .filter((id): id is string => !!id && id !== ownerProfileId))];
    if (ids.length === 0) { setCreatorNames({}); return; }
    supabase.from('user_profiles_complet').select('id, nom, prenom').in('id', ids).then(({ data }) => {
      const map: Record<string, string> = {};
      for (const p of data ?? []) {
        map[p.id] = [p.prenom, p.nom].filter(Boolean).join(' ');
      }
      setCreatorNames(map);
    });
  }, [templates, ownerProfileId]);

  // Fermer le menu « ⋯ » au clic ailleurs
  useEffect(() => {
    if (!menuOuvert) return;
    const close = () => setMenuOuvert(null);
    document.addEventListener('click', close);
    return () => document.removeEventListener('click', close);
  }, [menuOuvert]);

  const visibles = recherche.trim()
    ? templates.filter(t => t.nom.toLowerCase().includes(recherche.trim().toLowerCase()))
    : templates;

  const imprimer = async (t: Template) => {
    setImpression(t.id);
    try { await onPrint(t); } finally { setImpression(null); }
  };

  return (
    <div>
      <div className="flex flex-wrap justify-between items-center gap-3 mb-4">
        <h2 className="text-lg font-bold text-gray-800">Mes protocoles</h2>
        <div className="flex gap-2">
          {!isEmployeeMode && (
            <a href="/elevage/protocole-chaleur"
              className="px-4 py-2 border border-[#6E9E57] text-[#6E9E57] rounded-xl text-sm font-semibold hover:bg-[#6E9E57]/10">
              🌸 Protocole chaleur
            </a>
          )}
          {canWrite && (
            <button onClick={onNew} className="px-4 py-2 bg-[#6E9E57] text-white rounded-xl text-sm font-semibold hover:bg-[#5d8a48]">+ Nouveau protocole</button>
          )}
        </div>
      </div>

      {templates.length > 3 && (
        <div className="flex items-center gap-2 px-3 py-2.5 mb-4 rounded-xl border border-gray-200 bg-white focus-within:border-[#0C5C6C]">
          <span className="text-gray-400 text-sm">🔍</span>
          <input value={recherche} onChange={e => setRecherche(e.target.value)} placeholder="Rechercher un protocole…"
            className="flex-1 text-sm outline-none bg-transparent" />
        </div>
      )}

      {templates.length === 0 ? (
        <div className="text-center py-16">
          <div className="text-5xl mb-4">📋</div>
          <p className="text-gray-500 mb-4">Aucun protocole créé</p>
          {canWrite && (
            <button onClick={onNew} className="px-5 py-2 bg-[#6E9E57] text-white rounded-xl text-sm font-semibold hover:bg-[#5d8a48]">Créer mon premier protocole</button>
          )}
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          {visibles.map(t => {
            const isOwnerProtocol = !t.created_by_profile_id || t.created_by_profile_id === ownerProfileId;
            const isMine = isEmployeeMode && !!myProfileId && t.created_by_profile_id === myProfileId;
            const creatorLabel = isOwnerProtocol ? null : (isMine ? 'Vous' : creatorNames[t.created_by_profile_id!]);
            const canEditThis = isEmployeeMode ? (canWrite && isMine) : canWrite;
            const canApplyThis = !isEmployeeMode || isMine || !!authorizedTemplateIds?.has(t.id);
            const nbEtapes = t.plan_template_etapes?.length ?? 0;
            return (
              <div key={t.id} className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 flex flex-col">
                <div className="flex items-start gap-2">
                  <button onClick={() => setViewModal({ template: t, canEdit: canEditThis })} className="flex-1 min-w-0 text-left">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="font-bold text-gray-800 truncate">{t.nom}</span>
                      <span className={`text-[11px] px-2 py-0.5 rounded-full font-semibold ${TYPE_COLORS[t.type] ?? 'bg-gray-100 text-gray-600'}`}>{TYPE_LABELS[t.type] ?? t.type}</span>
                      {isEmployeeMode && isOwnerProtocol && (
                        <span className="text-[11px] px-2 py-0.5 rounded-full font-semibold bg-gray-100 text-gray-500">🏠 Élevage</span>
                      )}
                      {creatorLabel && (
                        <span className="text-[11px] px-2 py-0.5 rounded-full font-semibold bg-amber-100 text-amber-700">👤 {creatorLabel}</span>
                      )}
                    </div>
                    <p className="text-sm text-gray-500 mt-1">
                      {perimetreLabel(t, profilSource)} · {nbEtapes} étape{nbEtapes > 1 ? 's' : ''}
                    </p>
                  </button>
                  <div className="relative">
                    <button aria-label="Autres actions" onClick={e => { e.stopPropagation(); setMenuOuvert(m => m === t.id ? null : t.id); }}
                      className="w-8 h-8 rounded-lg text-gray-400 hover:bg-gray-100 hover:text-gray-600 text-lg leading-none">⋯</button>
                    {menuOuvert === t.id && (
                      <div className="absolute right-0 top-9 z-20 w-56 bg-white border border-gray-200 rounded-xl shadow-lg py-1 text-sm" onClick={e => e.stopPropagation()}>
                        <button onClick={() => { setMenuOuvert(null); setViewModal({ template: t, canEdit: canEditThis }); }}
                          className="w-full text-left px-3 py-2 hover:bg-gray-50">👁️ Voir le détail</button>
                        {canEditThis && (
                          <button onClick={() => { setMenuOuvert(null); onEdit(t); }}
                            className="w-full text-left px-3 py-2 hover:bg-gray-50">✏️ Modifier</button>
                        )}
                        {!isEmployeeMode && (
                          <button onClick={() => { setMenuOuvert(null); setAuthModalTemplate(t); }}
                            className="w-full text-left px-3 py-2 hover:bg-gray-50">🔓 Qui peut l&apos;appliquer</button>
                        )}
                        {canEditThis && (
                          <button onClick={() => { setMenuOuvert(null); onDelete(t.id); }}
                            className="w-full text-left px-3 py-2 hover:bg-red-50 text-red-600">🗑️ Supprimer</button>
                        )}
                        {!canEditThis && isEmployeeMode && (
                          <p className="px-3 py-2 text-xs text-gray-400">🔒 Protocole de l&apos;élevage — non modifiable</p>
                        )}
                      </div>
                    )}
                  </div>
                </div>
                <div className="flex items-center gap-3 mt-3">
                  {canApplyThis ? (
                    <button onClick={() => onApply(t)}
                      className="px-4 py-2 bg-[#0C5C6C] hover:bg-[#0a4d5b] text-white rounded-xl text-sm font-semibold">
                      Appliquer
                    </button>
                  ) : (
                    <span title="Non autorisé par l'élevage à appliquer ce protocole"
                      className="px-3 py-2 bg-gray-100 text-gray-400 rounded-xl text-sm font-semibold">🔒 Non autorisé</span>
                  )}
                  <button onClick={() => imprimer(t)} disabled={impression === t.id}
                    className="text-sm font-semibold text-[#0C5C6C] underline underline-offset-2 hover:text-[#0a4d5b] disabled:opacity-50">
                    {impression === t.id ? 'Préparation…' : '🖨️ Imprimer / PDF'}
                  </button>
                </div>
              </div>
            );
          })}
          {visibles.length === 0 && (
            <p className="text-sm text-gray-400 py-6">Aucun protocole ne correspond à « {recherche} ».</p>
          )}
        </div>
      )}

      {authModalTemplate && ownerProfileId && (
        <ProtocolAuthModal
          templateId={authModalTemplate.id}
          templateNom={authModalTemplate.nom}
          eleveurProfileId={ownerProfileId}
          onClose={() => setAuthModalTemplate(null)}
        />
      )}

      {viewModal && (
        <ProtocolViewModal
          template={viewModal.template}
          canEdit={viewModal.canEdit}
          onEdit={() => { setViewModal(null); onEdit(viewModal.template); }}
          onClose={() => setViewModal(null)}
          onPrint={() => onPrint(viewModal.template)}
        />
      )}
    </div>
  );
}

// ── Modale : fiche de synthèse en lecture (+ impression) ─────────────────────

function ProtocolViewModal({ template, canEdit, onEdit, onClose, onPrint }: {
  template: Template; canEdit: boolean; onEdit: () => void; onClose: () => void;
  onPrint: () => void;
}) {
  const etapes = template.plan_template_etapes ?? [];
  return (
    <div className="fixed inset-0 bg-black/60 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4">
      <div className="bg-white w-full max-w-lg rounded-t-3xl sm:rounded-2xl shadow-2xl max-h-[85vh] flex flex-col">
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <h3 className="font-bold text-[#1F2A2E]">Fiche protocole</h3>
          <div className="flex items-center gap-1">
            <button onClick={onPrint}
              className="p-1.5 rounded-xl hover:bg-gray-100 transition-colors text-gray-500" title="Imprimer">
              🖨️
            </button>
            <button onClick={onClose} className="p-1.5 rounded-xl hover:bg-gray-100 transition-colors">
              <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>
        <div className="p-5 overflow-y-auto space-y-4">
          <div className="bg-[#0C5C6C] rounded-2xl p-4 text-white">
            <p className="font-bold text-lg">{template.nom}</p>
            <div className="flex flex-wrap gap-1.5 mt-2">
              <span className="text-xs px-2 py-0.5 rounded-full bg-white/15 font-semibold">{acteLabel(template.type)}</span>
              {template.espece && <span className="text-xs px-2 py-0.5 rounded-full bg-white/15 font-semibold">{template.espece}</span>}
              <span className="text-xs px-2 py-0.5 rounded-full bg-white/15 font-semibold">{etapes.length} étape{etapes.length > 1 ? 's' : ''}</span>
            </div>
            {template.description && <p className="text-xs text-white/80 mt-2">{template.description}</p>}
          </div>

          {etapes.length === 0 ? (
            <p className="text-sm text-gray-400 text-center py-6">Aucune étape définie.</p>
          ) : (
            <div className="space-y-2">
              {etapes.map((e, i) => {
                const prodDos = [e.produit, e.dosage ? `(${e.dosage})` : ''].filter(Boolean).join(' ');
                return (
                  <div key={e.id ?? i} className="border border-gray-100 rounded-xl p-3 flex gap-3">
                    <div className="w-6 h-6 rounded-full bg-[#0C5C6C]/10 text-[#0C5C6C] text-xs font-bold flex items-center justify-center flex-shrink-0 mt-0.5">
                      {i + 1}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between gap-2">
                        <span className="font-semibold text-sm text-[#1F2A2E]">{ACTE_EMOJIS[e.type_acte] ?? '📋'} {acteLabel(e.type_acte)}</span>
                        <span className="text-xs text-gray-400 whitespace-nowrap">{etapeTimingLabel(e)}</span>
                      </div>
                      {prodDos && <p className="text-xs text-gray-600 mt-0.5">{prodDos}</p>}
                      <div className="flex flex-wrap gap-1.5 mt-1.5">
                        <span className="text-[11px] px-1.5 py-0.5 rounded bg-gray-100 text-gray-600 font-medium">{etapeFreqLabel(e)}</span>
                        <span className="text-[11px] px-1.5 py-0.5 rounded bg-gray-100 text-gray-600 font-medium">{etapeTrancheLabel(e)}</span>
                      </div>
                      {e.description && <p className="text-xs text-gray-400 italic mt-1.5">{e.description}</p>}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
        {canEdit && (
          <div className="px-5 py-4 border-t border-gray-100">
            <button onClick={onEdit} className="w-full py-2.5 bg-[#0C5C6C] text-white rounded-xl text-sm font-semibold hover:bg-[#0a4d5a]">
              ✏️ Modifier
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

// ── Modale : qui peut APPLIQUER ce protocole ────────────────────────────────────

function ProtocolAuthModal({ templateId, templateNom, eleveurProfileId, onClose }: {
  templateId: string; templateNom: string; eleveurProfileId: string; onClose: () => void;
}) {
  const [employes, setEmployes] = useState<{ employe_profile_id: string; nom: string }[]>([]);
  const [authorized, setAuthorized] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      const { data: empRows } = await supabase.from('employes').select('employe_profile_id')
        .eq('eleveur_profile_id', eleveurProfileId).eq('actif', true);
      const ids = (empRows ?? []).map(e => e.employe_profile_id).filter((id): id is string => !!id);
      let result: { employe_profile_id: string; nom: string }[] = [];
      if (ids.length > 0) {
        const { data: profs } = await supabase.from('user_profiles_complet').select('id, firstname, lastname').in('id', ids);
        result = ids.map(id => {
          const p = (profs ?? []).find(pr => pr.id === id);
          const nom = p ? `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim() : '';
          return { employe_profile_id: id, nom: nom || 'Employé' };
        });
      }
      const { data: authRows } = await supabase.from('plan_template_autorisations').select('employe_profile_id')
        .eq('template_id', templateId);
      setEmployes(result);
      setAuthorized(new Set((authRows ?? []).map(r => r.employe_profile_id as string)));
      setLoading(false);
    })();
  }, [templateId, eleveurProfileId]);

  async function toggle(employeProfileId: string, value: boolean) {
    setAuthorized(prev => {
      const next = new Set(prev);
      value ? next.add(employeProfileId) : next.delete(employeProfileId);
      return next;
    });
    if (value) {
      await supabase.from('plan_template_autorisations').insert({ template_id: templateId, employe_profile_id: employeProfileId });
    } else {
      await supabase.from('plan_template_autorisations').delete()
        .eq('template_id', templateId).eq('employe_profile_id', employeProfileId);
    }
  }

  return (
    <div className="fixed inset-0 bg-black/60 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4">
      <div className="bg-white w-full max-w-md rounded-t-3xl sm:rounded-2xl shadow-2xl max-h-[80vh] flex flex-col">
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <h3 className="font-bold text-[#1F2A2E]">Qui peut appliquer &quot;{templateNom}&quot; ?</h3>
          <button onClick={onClose} className="p-1.5 rounded-xl hover:bg-gray-100 transition-colors">
            <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
        <div className="p-5 overflow-y-auto">
          <p className="text-xs text-gray-400 mb-3">Par défaut, un employé ne peut appliquer que ses propres protocoles.</p>
          {loading ? (
            <p className="text-sm text-gray-400 text-center py-6">Chargement…</p>
          ) : employes.length === 0 ? (
            <p className="text-sm text-gray-400 text-center py-6">Aucun employé actif.</p>
          ) : (
            <div className="space-y-1">
              {employes.map(e => {
                const checked = authorized.has(e.employe_profile_id);
                return (
                  <div key={e.employe_profile_id} className="flex items-center justify-between py-2.5 border-b border-gray-50 last:border-0">
                    <span className="text-sm text-gray-800">{e.nom}</span>
                    <button onClick={() => toggle(e.employe_profile_id, !checked)}
                      className={`w-11 h-6 rounded-full transition-colors relative flex-shrink-0 ${checked ? 'bg-[#0C5C6C]' : 'bg-gray-200'}`}>
                      <div className={`w-5 h-5 bg-white rounded-full absolute top-0.5 transition-transform shadow-sm ${checked ? 'translate-x-5' : 'translate-x-0.5'}`} />
                    </button>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

// ── Modale formulaire template ────────────────────────────────────────────────

function newEtape(ordre = 0): Etape {
  return {
    type_acte: '', produit: '', dosage: '',
    offset_direction: 'apres', jour_offset: 0, age_min_semaines: null,
    frequence: 'ponctuel', nb_fois_semaine: 1, duree_semaines: 1, duree_jours: 1,
    is_recurrent: false, lieu: '', description: '', ordre, tranche_horaire: null,
  };
}

const champCls = 'w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm bg-white focus:outline-none focus:border-[#0C5C6C] focus:ring-2 focus:ring-[#0C5C6C]/10';
const libelleCls = 'block text-xs font-semibold text-gray-500 mb-1';

function BlocNumerote({ n, titre, children }: { n: number; titre: string; children: React.ReactNode }) {
  return (
    <section className="flex gap-3">
      <span className="w-8 h-8 rounded-full bg-[#0C5C6C]/10 text-[#0C5C6C] font-bold flex items-center justify-center flex-shrink-0">{n}</span>
      <div className="flex-1 min-w-0 space-y-3">
        <h3 className="font-bold text-[#1F2A2E] pt-1">{titre}</h3>
        {children}
      </div>
    </section>
  );
}

function TemplateFormModal({ existing, uid, profileId, profilSource = 'eleveur', createdByUid, createdByProfileId, onClose, onSaved }: {
  existing: Template | null; uid: string; profileId: string | null; profilSource?: string;
  createdByUid?: string; createdByProfileId?: string | null; onClose: () => void; onSaved: () => void;
}) {
  const typeLabels = profilSource === 'garde' ? TYPE_LABELS_GARDE : TYPE_LABELS;
  const [nom, setNom] = useState(existing?.nom ?? '');
  const [type, setType] = useState(existing?.type ?? 'sanitaire');
  const [espece, setEspece] = useState(existing?.espece ?? '');
  const [description, setDescription] = useState(existing?.description ?? '');
  const [lieu, setLieu] = useState(existing?.lieu ?? '');
  const [perimetre, setPerimetre] = useState<Perimetre>(existing ? perimetreDe(existing, profilSource) : 'animal');
  const [categorie, setCategorie] = useState(
    existing && CATEGORIES.some(c => c.value === existing.cible_type) ? existing.cible_type : 'femelles');
  const [refEvent, setRefEvent] = useState(existing?.reference_event ?? 'manuel');
  const [declencheurAuto, setDeclencheurAuto] = useState(existing?.declencheur_auto ?? '');
  const [animalIds, setAnimalIds] = useState<string[]>(existing?.default_animal_ids ?? []);
  const [showAnimalPicker, setShowAnimalPicker] = useState(false);
  const [animalSearch, setAnimalSearch] = useState('');
  const [animaux, setAnimaux] = useState<{ id: string; nom: string; espece?: string }[]>([]);
  const [etapes, setEtapes] = useState<Etape[]>(
    existing?.plan_template_etapes?.length
      ? [...existing.plan_template_etapes].sort((a, b) => a.ordre - b.ordre).map(e => ({
          ...e,
          produit: e.produit ?? '', dosage: e.dosage ?? '', lieu: e.lieu ?? '', description: e.description ?? '',
          is_recurrent: (e as Etape & { is_recurrent?: boolean }).is_recurrent ?? false,
          tranche_horaire: e.tranche_horaire ?? null,
        }))
      : [newEtape()]
  );
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  // Animaux chargés seulement pour le périmètre « animal » (sélection par défaut)
  useEffect(() => {
    if (perimetre !== 'animal' || profilSource === 'garde') return;
    let q = supabase.from('animaux').select('id, nom, espece').eq('uid_eleveur', uid);
    if (profileId) q = q.eq('profile_id', profileId) as typeof q;
    (profilSource === 'association' ? q.eq('is_association', true) : q.or('is_association.is.null,is_association.eq.false'))
      .order('nom')
      .then(({ data }) => setAnimaux((data ?? []) as { id: string; nom: string; espece?: string }[]));
  }, [uid, profileId, profilSource, perimetre]);

  const selectedAnimaux = animaux.filter(a => animalIds.includes(a.id));
  const filteredAnimaux = animaux.filter(a =>
    (!espece || a.espece === espece) &&
    (!animalSearch.trim() || a.nom.toLowerCase().includes(animalSearch.trim().toLowerCase())));
  const toggleAnimal = (id: string) => setAnimalIds(prev => prev.includes(id) ? prev.filter(x => x !== id) : [...prev, id]);

  // Périmètres et événements de référence selon le profil (pas de
  // reproduction pour une association ni une pension, pas de cheptel pour
  // un pet-sitter).
  const perimetresDispo = PERIMETRES.filter(p =>
    profilSource === 'garde' ? (p.value === 'animal' || p.value === 'locaux')
      : profilSource === 'pension' ? p.value !== 'portee' : true);
  const categoriesDispo = CATEGORIES.filter(c =>
    !((profilSource === 'association' || profilSource === 'pension') && c.value === 'gestantes') &&
    !(profilSource === 'pension' && c.value === 'bebes'));
  const cibleEffective = cibleTypePour(perimetre, categorie);
  const refEventsDispo = REF_EVENTS.filter(r => {
    if ((profilSource === 'association' || profilSource === 'pension' || profilSource === 'garde')
      && (r.value === 'saillie' || r.value === 'mise_bas')) return false;
    if ((profilSource === 'pension' || profilSource === 'garde') && r.value === 'naissance') return false;
    if (cibleEffective === 'gestantes') return ['mise_bas', 'saillie', 'manuel'].includes(r.value);
    if (cibleEffective === 'bebes') return ['naissance', 'age_semaines'].includes(r.value);
    if (perimetre === 'portee') return ['naissance', 'age_semaines', 'manuel'].includes(r.value);
    return r.value !== 'age_semaines';
  });
  useEffect(() => {
    if (perimetre === 'locaux') { setRefEvent('manuel'); return; }
    if (!refEventsDispo.some(r => r.value === refEvent)) setRefEvent(refEventsDispo[0]?.value ?? 'manuel');
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [perimetre, categorie]);

  const updateEtape = (i: number, patch: Partial<Etape>) =>
    setEtapes(prev => prev.map((e, idx) => idx === i ? { ...e, ...patch } : e));
  const deplacerEtape = (i: number, d: -1 | 1) => setEtapes(prev => {
    const j = i + d;
    if (j < 0 || j >= prev.length) return prev;
    const next = [...prev];
    [next[i], next[j]] = [next[j], next[i]];
    return next;
  });

  const save = async () => {
    if (!nom.trim()) { setError('Le nom du protocole est requis'); return; }
    if (etapes.some(e => !e.type_acte.trim())) { setError('Indiquez l’action de chaque étape'); return; }
    setSaving(true); setError('');
    try {
      const locaux = perimetre === 'locaux';
      const ep = etapes.map((e, i) => ({
        ...e, ordre: i,
        type_acte: acteDepuisSaisie(e.type_acte),
        produit: e.produit || null, dosage: e.dosage || null,
        lieu: e.lieu || null, description: e.description || null,
        age_min_semaines: refEvent === 'age_semaines' || cibleEffective === 'bebes' ? (e.age_min_semaines ?? 0) : null,
        tranche_horaire: e.tranche_horaire ?? null,
        duree_semaines: e.is_recurrent ? 52 : e.duree_semaines,
      }));
      const templatePayload = {
        nom: nom.trim(), type, espece: locaux ? null : (espece || null), description: description.trim() || null,
        lieu: locaux ? (lieu.trim() || null) : null,
        cible_type: cibleEffective,
        reference_event: locaux ? 'manuel' : refEvent,
        declencheur_auto: (locaux || !declencheurAuto) ? null : declencheurAuto,
        default_animal_ids: (perimetre === 'animal' && animalIds.length > 0) ? animalIds : null,
      };
      // Base pas encore migrée (portée / locaux absents de la contrainte
      // cible_type) : « locaux » s'enregistre à l'ancienne (cheptel, relu
      // comme locaux pour un nettoyage / matériel) ; « portée » est refusée.
      const enregistrer = async (payload: typeof templatePayload) => existing
        ? supabase.from('plan_templates').update(payload).eq('id', existing.id).select('id').single()
        : supabase.from('plan_templates').insert({
            uid_eleveur: uid, ...(profileId ? { eleveur_profile_id: profileId } : {}),
            profil_source: profilSource,
            ...(createdByUid ? { created_by_uid: createdByUid } : {}),
            ...(createdByProfileId ? { created_by_profile_id: createdByProfileId } : {}),
            ...payload,
          }).select('id').single();
      let res = await enregistrer(templatePayload);
      if (res.error?.code === '23514' && (cibleEffective === 'locaux' || cibleEffective === 'portee')) {
        if (cibleEffective === 'portee') throw new Error('Le périmètre « Portée » sera disponible après la mise à jour de la base (migration_plan_templates_perimetre.sql).');
        if (!TYPES_LOCAUX_HISTO.includes(type)) throw new Error('Pour l’instant, « Locaux / matériel » n’est possible qu’avec un protocole de type Désinfection ou Matériel (mise à jour de la base en attente).');
        res = await enregistrer({ ...templatePayload, cible_type: 'cheptel' });
      }
      if (res.error) throw new Error(res.error.message);
      const templateId = (res.data as { id: string }).id;

      if (existing) {
        // Jamais de suppression / réinsertion en bloc : une étape déjà
        // appliquée est référencée par des plan_taches (clé étrangère). Mise
        // à jour en place, insertion des nouvelles, suppression des seules
        // étapes retirées qui n'ont jamais généré de tâche.
        const existingIds = new Set((existing.plan_template_etapes ?? []).map(e => e.id).filter(Boolean) as string[]);
        const keptIds = new Set(ep.filter(e => e.id).map(e => e.id as string));
        const removedIds = [...existingIds].filter(id => !keptIds.has(id));
        if (removedIds.length > 0) {
          const { data: referenced } = await supabase.from('plan_taches').select('etape_id').in('etape_id', removedIds);
          const referencedIds = new Set((referenced ?? []).map(r => r.etape_id));
          const safeToDelete = removedIds.filter(id => !referencedIds.has(id));
          if (safeToDelete.length > 0) await supabase.from('plan_template_etapes').delete().in('id', safeToDelete);
        }
        for (const e of ep) {
          if (e.id && existingIds.has(e.id)) {
            const { id, ...patch } = e;
            await supabase.from('plan_template_etapes').update(patch).eq('id', id);
          }
        }
        const toInsert = ep.filter(e => !e.id || !existingIds.has(e.id))
          .map(({ id: _id, ...rest }) => ({ ...rest, template_id: templateId }));
        if (toInsert.length > 0) await supabase.from('plan_template_etapes').insert(toInsert);
      } else if (ep.length > 0) {
        await supabase.from('plan_template_etapes').insert(ep.map(({ id: _id, ...e }) => ({ ...e, template_id: templateId })));
      }
      onSaved();
    } catch (e: unknown) { setError(e instanceof Error ? e.message : 'Erreur'); setSaving(false); }
  };

  const declencheurs = [
    { value: '', label: 'Manuel uniquement' },
    ...(profilSource === 'pension' || profilSource === 'garde' ? [] : [{ value: 'naissance', label: 'À la naissance' }]),
    ...(profilSource === 'association' || profilSource === 'pension' || profilSource === 'garde' ? [] : [
      { value: 'chaleurs', label: 'Aux chaleurs' },
      { value: 'gestation', label: 'Gestation confirmée' },
    ]),
    ...(profilSource === 'garde' ? [] : [{ value: 'entree', label: 'À l’entrée d’un animal' }]),
  ];

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center sm:p-4" onClick={onClose}>
      <div className="bg-white rounded-t-2xl sm:rounded-2xl w-full max-w-2xl max-h-[94vh] flex flex-col" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between px-6 pt-5 pb-3 border-b border-gray-100">
          <h2 className="text-lg font-bold text-[#1F2A2E]">{existing ? 'Modifier le protocole' : 'Créer un protocole'}</h2>
          <button onClick={onClose} aria-label="Fermer" className="text-gray-400 hover:text-gray-600 text-2xl leading-none">×</button>
        </div>

        <div className="flex-1 overflow-y-auto px-6 py-5 space-y-7">
          {error && <p className="text-red-600 text-sm bg-red-50 p-3 rounded-xl">{error}</p>}

          <BlocNumerote n={1} titre="Informations générales">
            <div className="grid grid-cols-1 sm:grid-cols-[1.4fr_1fr] gap-3">
              <div>
                <label className={libelleCls}>Nom du protocole *</label>
                <input value={nom} onChange={e => setNom(e.target.value)} className={champCls}
                  placeholder={profilSource === 'garde' ? 'Ex : Nettoyage du parc après le départ' : 'Ex : Entretien des locaux'} />
              </div>
              <div>
                <label className={libelleCls}>Type</label>
                <select value={type} onChange={e => setType(e.target.value)} className={champCls}>
                  {Object.entries(typeLabels).filter(([k]) => k !== 'socialisation').map(([k, v]) =>
                    <option key={k} value={k}>{v}</option>)}
                </select>
              </div>
            </div>
            <div>
              <label className={libelleCls}>Description (facultative)</label>
              <textarea value={description} onChange={e => setDescription(e.target.value)} rows={2}
                placeholder="Ex : objectifs, contexte, précisions…" className={`${champCls} resize-none`} />
            </div>
          </BlocNumerote>

          <BlocNumerote n={2} titre="Périmètre concerné">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <label className={libelleCls}>Concerne</label>
                <select value={perimetre} onChange={e => setPerimetre(e.target.value as Perimetre)} className={champCls}>
                  {perimetresDispo.map(p => <option key={p.value} value={p.value}>{p.label}</option>)}
                </select>
              </div>
              {perimetre === 'locaux' ? (
                <div>
                  <label className={libelleCls}>Zone / lieu</label>
                  <input value={lieu} onChange={e => setLieu(e.target.value)} list="lieux-protocole" className={champCls}
                    placeholder="Ex : Nurserie, chenil n°1…" />
                  <datalist id="lieux-protocole">{LIEUX_NETTOYAGE.map(l => <option key={l} value={l} />)}</datalist>
                </div>
              ) : perimetre === 'categorie' ? (
                <div>
                  <label className={libelleCls}>Catégorie d&apos;animaux</label>
                  <select value={categorie} onChange={e => setCategorie(e.target.value)} className={champCls}>
                    {categoriesDispo.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
                  </select>
                </div>
              ) : profilSource !== 'garde' ? (
                <div>
                  <label className={libelleCls}>Espèce</label>
                  <select value={espece} onChange={e => setEspece(e.target.value)} className={champCls}>
                    {ESPECES.map(s => <option key={s} value={s}>{s ? s.charAt(0).toUpperCase() + s.slice(1) : 'Toutes espèces'}</option>)}
                  </select>
                </div>
              ) : null}
            </div>
            {perimetre === 'categorie' && profilSource !== 'garde' && (
              <div className="sm:w-1/2 sm:pr-1.5">
                <label className={libelleCls}>Espèce</label>
                <select value={espece} onChange={e => setEspece(e.target.value)} className={champCls}>
                  {ESPECES.map(s => <option key={s} value={s}>{s ? s.charAt(0).toUpperCase() + s.slice(1) : 'Toutes espèces'}</option>)}
                </select>
              </div>
            )}
            <p className="text-xs text-gray-400">ⓘ {PERIMETRES.find(p => p.value === perimetre)?.aide}</p>

            {perimetre === 'animal' && profilSource !== 'garde' && (
              <div className="relative">
                <label className={libelleCls}>Animaux par défaut (facultatif)</label>
                <button type="button" onClick={() => setShowAnimalPicker(v => !v)}
                  className={`${champCls} flex items-center justify-between text-left`}>
                  <span className={selectedAnimaux.length ? 'text-[#1F2A2E]' : 'text-gray-400'}>
                    {selectedAnimaux.length ? `${selectedAnimaux.length} animal${selectedAnimaux.length > 1 ? 'x' : ''} sélectionné${selectedAnimaux.length > 1 ? 's' : ''}` : 'Choisir au moment d’appliquer'}
                  </span>
                  <span className="text-gray-400 text-xs">▼</span>
                </button>
                {showAnimalPicker && (
                  <div className="absolute z-20 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg overflow-hidden">
                    <div className="p-2 border-b border-gray-100">
                      <input autoFocus value={animalSearch} onChange={e => setAnimalSearch(e.target.value)}
                        placeholder="Rechercher un animal…" className="w-full px-3 py-1.5 text-sm border border-gray-200 rounded-lg focus:outline-none focus:border-[#0C5C6C]" />
                    </div>
                    <div className="max-h-48 overflow-y-auto overscroll-contain">
                      {filteredAnimaux.length === 0
                        ? <p className="text-sm text-gray-400 text-center py-4">Aucun animal</p>
                        : filteredAnimaux.map(a => (
                          <label key={a.id} className={`flex items-center gap-2.5 px-3 py-2 text-sm cursor-pointer border-b border-gray-50 last:border-0 ${animalIds.includes(a.id) ? 'bg-[#0C5C6C]/5' : 'hover:bg-gray-50'}`}>
                            <input type="checkbox" checked={animalIds.includes(a.id)} onChange={() => toggleAnimal(a.id)} className="w-4 h-4 accent-[#0C5C6C]" />
                            <span className="flex-1 truncate">{a.nom}</span>
                            {a.espece && <span className="text-xs text-gray-400">{a.espece}</span>}
                          </label>
                        ))}
                    </div>
                    <button type="button" onClick={() => { setShowAnimalPicker(false); setAnimalSearch(''); }}
                      className="w-full py-2 text-sm font-semibold text-white bg-[#0C5C6C]">Valider</button>
                  </div>
                )}
                {!showAnimalPicker && selectedAnimaux.length > 0 && selectedAnimaux.length <= 8 && (
                  <div className="flex flex-wrap gap-1.5 mt-2">
                    {selectedAnimaux.map(a => (
                      <span key={a.id} className="inline-flex items-center gap-1 text-xs font-semibold text-[#0C5C6C] bg-[#0C5C6C]/10 rounded-full pl-2.5 pr-1 py-0.5">
                        {a.nom}
                        <button type="button" onClick={() => toggleAnimal(a.id)} className="w-4 h-4 rounded-full hover:bg-[#0C5C6C]/20 leading-none">×</button>
                      </span>
                    ))}
                  </div>
                )}
              </div>
            )}

            {perimetre !== 'locaux' && profilSource !== 'garde' && (
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-1">
                <div>
                  <label className={libelleCls}>Calcul des dates à partir de</label>
                  <select value={refEvent} onChange={e => setRefEvent(e.target.value)} className={champCls}>
                    {refEventsDispo.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}
                  </select>
                  <p className="text-[11px] text-gray-400 mt-1">{REF_EVENTS.find(r => r.value === refEvent)?.aide}</p>
                </div>
                <div>
                  <label className={libelleCls}>Application automatique</label>
                  <select value={declencheurAuto} onChange={e => setDeclencheurAuto(e.target.value)} className={champCls}>
                    {declencheurs.map(d => <option key={d.value} value={d.value}>{d.label}</option>)}
                  </select>
                </div>
              </div>
            )}
          </BlocNumerote>

          <BlocNumerote n={3} titre="Étapes du protocole">
            <datalist id="actes-protocole">{ACTES_SUGGERES.map(a => <option key={a.value} value={a.label} />)}</datalist>
            <div className="space-y-3">
              {etapes.map((e, i) => (
                <EtapeForm key={e.id ?? `n${i}`} index={i} total={etapes.length} etape={e}
                  refEvent={perimetre === 'locaux' ? 'manuel' : refEvent}
                  usesAge={refEvent === 'age_semaines' || cibleEffective === 'bebes'}
                  onChange={patch => updateEtape(i, patch)}
                  onMove={d => deplacerEtape(i, d)}
                  onDuplicate={() => setEtapes(prev => [...prev.slice(0, i + 1), { ...e, id: undefined }, ...prev.slice(i + 1)])}
                  onRemove={etapes.length > 1 ? () => setEtapes(prev => prev.filter((_, idx) => idx !== i)) : undefined} />
              ))}
            </div>
            <button onClick={() => setEtapes(prev => [...prev, newEtape(prev.length)])}
              className="text-sm font-semibold text-[#0C5C6C] hover:underline">+ Ajouter une étape</button>
          </BlocNumerote>
        </div>

        <div className="flex justify-end gap-3 px-6 py-3 border-t border-gray-100">
          <button onClick={onClose} className="px-5 py-2.5 border border-gray-200 rounded-xl text-sm font-semibold text-gray-600 hover:bg-gray-50">Annuler</button>
          <button onClick={save} disabled={saving}
            className="px-6 py-2.5 bg-[#0C5C6C] hover:bg-[#0a4d5b] text-white rounded-xl text-sm font-semibold disabled:opacity-50">
            {saving ? 'Enregistrement…' : 'Enregistrer'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Carte d'une étape ─────────────────────────────────────────────────────────

function EtapeForm({ index, total, etape, refEvent, usesAge, onChange, onMove, onDuplicate, onRemove }: {
  index: number; total: number; etape: Etape; refEvent: string; usesAge: boolean;
  onChange: (patch: Partial<Etape>) => void; onMove: (d: -1 | 1) => void; onDuplicate: () => void; onRemove?: () => void;
}) {
  const [menu, setMenu] = useState(false);
  const refLabel = { saillie: 'la saillie', mise_bas: 'la mise bas', naissance: 'la naissance' }[refEvent] ?? 'la date de début';
  const sanitaire = ['vermifuge', 'vaccination', 'antiparasitaire', 'traitement'].includes(acteDepuisSaisie(etape.type_acte));
  const [details, setDetails] = useState(!!(etape.produit || etape.dosage || etape.lieu));
  const frequenceValeur = etape.is_recurrent ? `${etape.frequence}_an` : etape.frequence;
  const unite = etape.frequence === 'mensuel' ? 'mois' : 'semaines';
  const nbTaches = etape.frequence === 'quotidien' ? (etape.is_recurrent ? 364 : etape.duree_semaines * 7)
    : etape.frequence === 'hebdomadaire' ? (etape.is_recurrent ? 52 : etape.duree_semaines) * (etape.nb_fois_semaine || 1)
    : etape.frequence === 'mensuel' ? (etape.is_recurrent ? 12 : etape.duree_semaines) : etape.duree_jours;

  return (
    <div className="border border-gray-200 rounded-xl p-4 space-y-3 bg-white">
      <div className="flex items-center gap-2">
        <span className="text-sm font-bold text-[#1F2A2E]">Étape {index + 1}</span>
        <div className="ml-auto flex items-center gap-1">
          <button type="button" onClick={() => onMove(-1)} disabled={index === 0} aria-label="Monter"
            className="w-7 h-7 rounded-lg text-gray-400 hover:bg-gray-100 disabled:opacity-30">▲</button>
          <button type="button" onClick={() => onMove(1)} disabled={index === total - 1} aria-label="Descendre"
            className="w-7 h-7 rounded-lg text-gray-400 hover:bg-gray-100 disabled:opacity-30">▼</button>
          <div className="relative">
            <button type="button" onClick={() => setMenu(m => !m)} aria-label="Actions de l'étape"
              className="w-7 h-7 rounded-lg text-gray-400 hover:bg-gray-100 text-lg leading-none">⋯</button>
            {menu && (
              <div className="absolute right-0 top-8 z-20 w-40 bg-white border border-gray-200 rounded-xl shadow-lg py-1 text-sm" onMouseLeave={() => setMenu(false)}>
                <button type="button" onClick={() => { setMenu(false); onDuplicate(); }} className="w-full text-left px-3 py-2 hover:bg-gray-50">Dupliquer</button>
                {onRemove && <button type="button" onClick={() => { setMenu(false); onRemove(); }} className="w-full text-left px-3 py-2 hover:bg-red-50 text-red-600">Supprimer</button>}
              </div>
            )}
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
        <div className="sm:col-span-2 lg:col-span-1">
          <label className={libelleCls}>Action *</label>
          <input value={acteLabel(etape.type_acte)} onChange={e => onChange({ type_acte: e.target.value })} list="actes-protocole"
            placeholder="Ex : Nettoyer les surfaces" className={champCls} />
        </div>
        <div>
          <label className={libelleCls}>Déclenchement</label>
          {usesAge ? (
            <div className="flex items-center gap-1.5">
              <input type="number" min={0} value={etape.age_min_semaines ?? 0}
                onChange={e => onChange({ age_min_semaines: parseInt(e.target.value) || 0 })}
                className={`${champCls} w-16 text-center px-2`} />
              <span className="text-xs text-gray-500">sem. d&apos;âge</span>
            </div>
          ) : (
            <div className="flex items-center gap-1.5">
              <input type="number" min={0} value={etape.jour_offset}
                onChange={e => onChange({ jour_offset: parseInt(e.target.value) || 0 })}
                className={`${champCls} w-14 text-center px-2`} title={`Jours par rapport à ${refLabel}`} />
              <select value={etape.offset_direction} onChange={e => onChange({ offset_direction: e.target.value as 'avant' | 'apres' })}
                className={`${champCls} px-2`} title={`Par rapport à ${refLabel}`}>
                <option value="apres">j. après</option>
                <option value="avant">j. avant</option>
              </select>
            </div>
          )}
        </div>
        <div>
          <label className={libelleCls}>Fréquence</label>
          <select value={frequenceValeur} className={champCls}
            onChange={e => {
              const v = e.target.value;
              const an = v.endsWith('_an');
              onChange({ frequence: an ? v.slice(0, -3) : v, is_recurrent: an });
            }}>
            <option value="ponctuel">Une fois / jours de suite</option>
            <option value="quotidien">Chaque jour</option>
            <option value="hebdomadaire">Chaque semaine</option>
            <option value="mensuel">Chaque mois</option>
            <option value="quotidien_an">Chaque jour (1 an)</option>
            <option value="hebdomadaire_an">Chaque semaine (1 an)</option>
            <option value="mensuel_an">Chaque mois (1 an)</option>
          </select>
        </div>
        <div>
          <label className={libelleCls}>Créneau</label>
          <select value={etape.tranche_horaire ?? ''} onChange={e => onChange({ tranche_horaire: e.target.value || null })} className={champCls}>
            <option value="">Non défini</option>
            {Object.entries(TRANCHES_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-x-4 gap-y-2 text-sm text-gray-600">
        {etape.frequence === 'ponctuel' && (
          <label className="flex items-center gap-1.5">Durée
            <input type="number" min={1} value={etape.duree_jours} onChange={e => onChange({ duree_jours: parseInt(e.target.value) || 1 })}
              className="w-14 border border-gray-200 rounded-lg px-2 py-1 text-center" /> jour(s) de suite
          </label>
        )}
        {etape.frequence === 'hebdomadaire' && (
          <label className="flex items-center gap-1.5">
            <select value={etape.nb_fois_semaine} onChange={e => onChange({ nb_fois_semaine: parseInt(e.target.value) })}
              className="border border-gray-200 rounded-lg px-2 py-1">
              {[1, 2, 3].map(n => <option key={n} value={n}>{n}</option>)}
            </select> fois par semaine
          </label>
        )}
        {etape.frequence !== 'ponctuel' && !etape.is_recurrent && (
          <label className="flex items-center gap-1.5">pendant
            <input type="number" min={1} value={etape.duree_semaines} onChange={e => onChange({ duree_semaines: parseInt(e.target.value) || 1 })}
              className="w-14 border border-gray-200 rounded-lg px-2 py-1 text-center" /> {unite}
          </label>
        )}
        {nbTaches >= 60 && <span className="text-xs text-amber-600 font-semibold">⚠️ {nbTaches} tâches générées par animal / application</span>}
      </div>

      {(details || sanitaire) ? (
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <div>
            <label className={libelleCls}>Produit</label>
            <input value={etape.produit} onChange={e => onChange({ produit: e.target.value })} placeholder="Ex : Milbemax®" className={champCls} />
          </div>
          <div>
            <label className={libelleCls}>Dosage</label>
            <input value={etape.dosage} onChange={e => onChange({ dosage: e.target.value })} placeholder="Ex : 1 cp / 5 kg" className={champCls} />
          </div>
          <div>
            <label className={libelleCls}>Lieu</label>
            <input value={etape.lieu} onChange={e => onChange({ lieu: e.target.value })} placeholder="Ex : parc, salle de soins" className={champCls} />
          </div>
        </div>
      ) : (
        <button type="button" onClick={() => setDetails(true)} className="text-xs font-semibold text-[#0C5C6C] hover:underline">
          + Produit, dosage, lieu
        </button>
      )}

      <div>
        <label className={libelleCls}>Consignes</label>
        <textarea value={etape.description} onChange={e => onChange({ description: e.target.value })} rows={2}
          placeholder="Ex : suivre les consignes du responsable, précautions…" className={`${champCls} resize-y`} />
      </div>
    </div>
  );
}

// ── Modale appliquer ──────────────────────────────────────────────────────────

function ApplyModal({ template, uid, profileId, profilSource = 'eleveur', onClose, onApplied }: {
  template: Template; uid: string; profileId: string | null; profilSource?: string; onClose: () => void; onApplied: () => void;
}) {
  const [dateRef, setDateRef] = useState(toISODate(new Date()));
  const [animalIds, setAnimalIds] = useState<string[]>(template.default_animal_ids ?? []);
  const [showPicker, setShowPicker] = useState(false);
  const [animalSearch, setAnimalSearch] = useState('');
  const [animaux, setAnimaux] = useState<{ id: string; nom: string; espece?: string; photo_url?: string | null }[]>([]);
  const [saving, setSaving] = useState(false);

  const cibleType = template.cible_type;
  const perimetre = perimetreDe(template, profilSource);
  const isBebes = cibleType === 'bebes';
  // Étapes calculées à un âge (bébés, ou protocole « âge des animaux »)
  const usesAge = isBebes || template.reference_event === 'age_semaines';
  const needsAnimal = perimetre === 'animal';
  const isPortee = perimetre === 'portee';
  const datesDeNaissance = isPortee && (template.reference_event === 'naissance' || template.reference_event === 'age_semaines');
  const showDate = cibleType !== 'bebes' && cibleType !== 'gestantes' && !datesDeNaissance;
  const [portees, setPortees] = useState<{ id: string; label: string; membres: { id: string; nom: string; date_naissance: string | null }[] }[]>([]);
  const [porteeIds, setPorteeIds] = useState<string[]>([]);
  useEffect(() => {
    if (!isPortee) return;
    let q = supabase.from('animaux').select('id, nom, date_naissance, portee_id, nom_mere, espece')
      .eq('uid_eleveur', uid).not('portee_id', 'is', null).not('statut', 'in', '(sorti,decede)');
    if (template.espece) q = q.eq('espece', template.espece);
    if (profileId) q = q.eq('profile_id', profileId) as typeof q;
    q.order('date_naissance', { ascending: false }).then(({ data }) => {
      const map = new Map<string, { id: string; label: string; membres: { id: string; nom: string; date_naissance: string | null }[] }>();
      for (const a of (data ?? []) as { id: string; nom: string; date_naissance: string | null; portee_id: string; nom_mere: string | null }[]) {
        if (!map.has(a.portee_id)) {
          const dn = a.date_naissance ? ` — née le ${new Date(a.date_naissance).toLocaleDateString('fr-FR')}` : '';
          map.set(a.portee_id, { id: a.portee_id, label: `${a.nom_mere ? `Portée de ${a.nom_mere}` : 'Portée'}${dn}`, membres: [] });
        }
        map.get(a.portee_id)!.membres.push({ id: a.id, nom: a.nom, date_naissance: a.date_naissance });
      }
      setPortees([...map.values()]);
    });
  }, [isPortee, uid, profileId, template.espece]);
  const selectedAnimaux = animaux.filter(a => animalIds.includes(a.id));
  const filteredAnimaux = animalSearch.trim()
    ? animaux.filter(a => a.nom.toLowerCase().includes(animalSearch.trim().toLowerCase()))
    : animaux;

  function toggleAnimal(id: string) {
    setAnimalIds(prev => prev.includes(id) ? prev.filter(x => x !== id) : [...prev, id]);
  }

  useEffect(() => {
    if (!needsAnimal) return;
    // Un pet-sitter ne possède aucun animal sous son propre uid_eleveur — la
    // cible individuelle porte sur les animaux de ses clients, résolus via
    // animal_access (même pattern que mes-patients/page.tsx).
    if (profilSource === 'garde') {
      (async () => {
        const { data: grants } = await supabase.from('animal_access')
          .select('animal_id').eq('pro_profile_id', profileId ?? '').neq('statut', 'revoked');
        const ids = [...new Set((grants ?? []).map(g => g.animal_id as string))];
        if (!ids.length) { setAnimaux([]); return; }
        const { data } = await supabase.from('animaux').select('id, nom, espece, photo_url').in('id', ids).order('nom');
        setAnimaux((data ?? []) as { id: string; nom: string; espece?: string; photo_url?: string | null }[]);
      })();
      return;
    }
    let q = supabase.from('animaux').select('id, nom, espece, photo_url').eq('uid_eleveur', uid);
    if (profileId) q = q.eq('profile_id', profileId) as typeof q;
    (profilSource === 'association' ? q.eq('is_association', true) : q.or('is_association.is.null,is_association.eq.false'))
      .order('nom')
      .then(({ data }) => setAnimaux((data ?? []) as { id: string; nom: string; espece?: string; photo_url?: string | null }[]));
  }, [uid, needsAnimal, profilSource, profileId]);

  // Un protocole créé par un employé (autorisé) s'auto-attribue à ce
  // dernier sur les tâches générées, visible par l'employeur.
  const autoAssignUid = (template.created_by_uid && template.created_by_profile_id
    && template.created_by_profile_id !== profileId) ? template.created_by_uid : null;
  const autoAssignProfileId = autoAssignUid ? template.created_by_profile_id : null;

  const apply = async () => {
    if (needsAnimal && animalIds.length === 0) { alert('Sélectionnez au moins un animal'); return; }
    if (isPortee && porteeIds.length === 0) { alert('Sélectionnez au moins une portée'); return; }
    setSaving(true);
    try {
      const etapes = template.plan_template_etapes ?? [];
      const targets: { animal_id?: string; date_base: string; animal_nom?: string }[] = [];

      if (perimetre === 'locaux') {
        // Locaux / matériel : aucune tâche par animal, une seule série.
        targets.push({ date_base: dateRef });
      } else if (isPortee) {
        for (const p of portees.filter(x => porteeIds.includes(x.id))) {
          for (const m of p.membres) {
            targets.push({ animal_id: m.id, animal_nom: m.nom,
              date_base: datesDeNaissance ? (m.date_naissance ?? dateRef) : dateRef });
          }
        }
      } else if (cibleType === 'individuel') {
        for (const id of animalIds) {
          const animal = animaux.find(a => a.id === id);
          targets.push({ animal_id: id, date_base: dateRef, animal_nom: animal?.nom });
        }
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
        if (profileId) q = q.eq('profile_id', profileId) as typeof q;
        q = profilSource === 'association' ? q.eq('is_association', true) : q.or('is_association.is.null,is_association.eq.false') as typeof q;
        const { data: babies } = await q;
        for (const b of (babies ?? []) as { id: string; nom: string; date_naissance: string | null }[]) {
          targets.push({ animal_id: b.id, date_base: b.date_naissance ?? dateRef, animal_nom: b.nom });
        }
      } else {
        let q = supabase.from('animaux').select('id, nom').eq('uid_eleveur', uid);
        if (template.espece) q = q.eq('espece', template.espece);
        if (cibleType === 'males') q = q.eq('sexe', 'male');
        if (cibleType === 'femelles') q = q.eq('sexe', 'femelle');
        if (profileId) q = q.eq('profile_id', profileId) as typeof q;
        q = profilSource === 'association' ? q.eq('is_association', true) : q.or('is_association.is.null,is_association.eq.false') as typeof q;
        const { data: all } = await q;
        for (const a of (all ?? []) as { id: string; nom: string }[]) {
          targets.push({ animal_id: a.id, date_base: dateRef, animal_nom: a.nom });
        }
      }

      let totalTaches = 0;
      for (const target of targets) {
        const { data: planRow } = await supabase.from('plans_actifs').insert({
          template_id: template.id,
          uid_eleveur: uid,
          ...(profileId ? { eleveur_profile_id: profileId } : {}),
          type_declencheur: template.reference_event ?? 'manuel',
          date_reference: target.date_base,
          reference_id: target.animal_id ?? null,
          reference_label: perimetre === 'locaux' ? (template.lieu || 'Locaux / matériel') : (target.animal_nom ?? null),
          profil_source: profilSource,
        }).select('id').single();
        if (!planRow) continue;

        const taches = [];
        for (const etape of etapes) {
          const direction = etape.offset_direction === 'avant' ? -1 : 1;
          const ageSem = etape.age_min_semaines;
          const baseDate = new Date(target.date_base);
          // Fix: age_min_semaines appliqué uniquement pour les protocoles bébés
          const startDate = (usesAge && ageSem != null)
            ? addDays(baseDate, ageSem * 7)
            : addDays(baseDate, direction * etape.jour_offset);
          const labelBase = [etape.type_acte, etape.produit, etape.dosage ? `(${etape.dosage})` : ''].filter(Boolean).join(' ');
          const common = {
            plan_id: planRow.id, etape_id: etape.id, uid_eleveur: uid,
            profile_id: profileId || null,
            ...(profileId ? { eleveur_profile_id: profileId } : {}),
            animal_id: target.animal_id ?? null,
            animal_nom: target.animal_nom ?? null,
            type_acte: etape.type_acte || null,
            lieu: etape.lieu || null,
            tranche_horaire: etape.tranche_horaire ?? null,
            profil_source: profilSource,
            ...(autoAssignUid ? { assigned_to: autoAssignUid } : {}),
            ...(autoAssignProfileId ? { assigned_profile_id: autoAssignProfileId } : {}),
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
            <p className="text-sm text-green-800 font-semibold">{perimetreLabel(template, profilSource)}</p>
            {perimetre !== 'locaux' && <p className="text-xs text-green-700 mt-0.5">Dates calculées à partir de : {REF_EVENTS.find(r => r.value === template.reference_event)?.label ?? template.reference_event}</p>}
          </div>
          {isPortee && (
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">
                Portées{porteeIds.length > 0 ? ` — ${porteeIds.length} sélectionnée(s)` : ''}
              </label>
              <div className="border border-gray-200 rounded-xl max-h-56 overflow-y-auto overscroll-contain">
                {portees.length === 0
                  ? <p className="text-sm text-gray-400 text-center py-4">Aucune portée</p>
                  : portees.map(p => (
                    <label key={p.id} className={`flex items-center gap-2.5 px-3 py-2 text-sm cursor-pointer border-b border-gray-50 last:border-0 ${porteeIds.includes(p.id) ? 'bg-green-50' : 'hover:bg-gray-50'}`}>
                      <input type="checkbox" checked={porteeIds.includes(p.id)} className="w-4 h-4 accent-[#0C5C6C]"
                        onChange={() => setPorteeIds(prev => prev.includes(p.id) ? prev.filter(x => x !== p.id) : [...prev, p.id])} />
                      <span className="flex-1">{p.label}</span>
                      <span className="text-xs text-gray-400">{p.membres.length} petit{p.membres.length > 1 ? 's' : ''}</span>
                    </label>
                  ))}
              </div>
              {datesDeNaissance && <p className="text-xs text-gray-400 mt-1">Les dates sont calculées depuis la naissance de chaque petit.</p>}
            </div>
          )}
          {needsAnimal && (
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">
                Animaux{selectedAnimaux.length > 0 ? ` — ${selectedAnimaux.length} sélectionné(s)` : ''}
              </label>
              <div className="relative">
                <button type="button" onClick={() => setShowPicker(v => !v)}
                  className="w-full flex items-center gap-2 px-3 py-2.5 border border-gray-200 rounded-xl text-sm hover:border-green-500 focus:outline-none focus:border-green-500 bg-white">
                  {selectedAnimaux.length > 0 ? (
                    <span className="font-medium text-gray-800 flex-1 text-left truncate">
                      {selectedAnimaux.map(a => a.nom).join(', ')}
                    </span>
                  ) : (
                    <span className="text-gray-400 flex-1 text-left">— Choisir un ou plusieurs animaux —</span>
                  )}
                  <svg className="w-4 h-4 text-gray-400 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                  </svg>
                </button>
                {selectedAnimaux.length > 0 && (
                  <div className="flex flex-wrap gap-1.5 mt-1.5">
                    {selectedAnimaux.map(a => (
                      <button key={a.id} type="button" onClick={() => toggleAnimal(a.id)}
                        className="flex items-center gap-1 text-xs font-semibold text-white bg-green-600 hover:bg-green-700 rounded-full pl-2.5 pr-1.5 py-1">
                        {a.nom}
                        <span className="text-green-100">×</span>
                      </button>
                    ))}
                  </div>
                )}
                {showPicker && (
                  <div className="absolute z-20 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg overflow-hidden">
                    <div className="p-2 border-b border-gray-100">
                      <input
                        autoFocus
                        value={animalSearch}
                        onChange={e => setAnimalSearch(e.target.value)}
                        placeholder="Rechercher un animal…"
                        className="w-full px-3 py-1.5 text-sm border border-gray-200 rounded-lg focus:outline-none focus:border-green-500"
                      />
                    </div>
                    <div className="max-h-48 overflow-y-auto">
                      {filteredAnimaux.length === 0
                        ? <p className="text-sm text-gray-400 text-center py-4">Aucun animal</p>
                        : filteredAnimaux.map(a => {
                          const checked = animalIds.includes(a.id);
                          return (
                            <button key={a.id} type="button"
                              onClick={() => toggleAnimal(a.id)}
                              className={`w-full flex items-center gap-3 px-3 py-2 text-left border-b border-gray-50 last:border-0 transition-colors ${
                                checked ? 'bg-green-100' : 'hover:bg-green-50'
                              }`}>
                              <input type="checkbox" checked={checked} readOnly
                                className="rounded text-green-600 focus:ring-green-400 flex-shrink-0" />
                              <div className="w-8 h-8 rounded-lg overflow-hidden flex-shrink-0 bg-gray-100 flex items-center justify-center">
                                {a.photo_url
                                  ? <img src={a.photo_url} alt="" className="w-full h-full object-cover" />
                                  : <span className="text-sm">🐾</span>}
                              </div>
                              <div className="min-w-0">
                                <p className="text-sm font-semibold text-gray-800 truncate">{a.nom}</p>
                                {a.espece && <p className="text-xs text-gray-400">{a.espece}</p>}
                              </div>
                            </button>
                          );
                        })
                      }
                    </div>
                    <button type="button" onClick={() => { setShowPicker(false); setAnimalSearch(''); }}
                      className="w-full py-2 text-sm font-semibold text-green-700 bg-green-50 hover:bg-green-100 border-t border-gray-100">
                      Terminé
                    </button>
                  </div>
                )}
              </div>
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

function ValidateModal({ groupe, uid, profileId, onClose, onValidated }: {
  groupe: TacheGroupe; uid: string; profileId: string | null; onClose: () => void; onValidated: () => void;
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
        statut: 'fait', valide_par: uid, valide_par_profile_id: profileId,
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

export default function PlanningPage() {
  return (
    <Suspense fallback={null}>
      <PlanningPageInner />
    </Suspense>
  );
}
