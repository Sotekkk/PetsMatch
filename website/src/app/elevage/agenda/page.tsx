'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { usePlan } from '@/lib/use-plan';

// ── Types ──────────────────────────────────────────────────────────────────────

interface Routine {
  id: string;
  label: string;
  date_prevue: string;
  statut: string;
  type_acte?: string | null;
  animal_nom?: string | null;
  etape_id?: string | null;
}

interface TacheManuelle {
  id: string;
  titre: string;
  date: string;
  statut: string;
}

interface RoutineGroupe {
  etapeId: string;
  routines: Routine[];
  label: string;
  typeActe: string;
}

// ── Constantes ────────────────────────────────────────────────────────────────

const ACTE_EMOJIS: Record<string, string> = {
  vermifuge: '💊', vaccination: '💉', antiparasitaire: '🛡️',
  traitement: '🩺', visite: '🏥', nettoyage: '🧹',
  promenade: '🦮', socialisation: '🐾', toilettage: '✂️', autre: '📋',
};

const ACTE_COLOR: Record<string, string> = {
  vaccination:     '#2196F3',
  vermifuge:       '#FF9800',
  antiparasitaire: '#4CAF50',
  traitement:      '#E91E63',
  visite:          '#9C27B0',
  nettoyage:       '#00BCD4',
  promenade:       '#8BC34A',
  socialisation:   '#FF5722',
  toilettage:      '#795548',
  autre:           '#9E9E9E',
};

// ── Helpers ───────────────────────────────────────────────────────────────────

function toISODate(d: Date) { return d.toISOString().split('T')[0]; }
function addDays(d: Date, n: number) { const r = new Date(d); r.setDate(r.getDate() + n); return r; }
function daysInMonthFn(year: number, month: number) { return new Date(year, month + 1, 0).getDate(); }
function firstWeekdayFn(year: number, month: number) { return (new Date(year, month, 1).getDay() + 6) % 7; }

function groupRoutines(routines: Routine[]): RoutineGroupe[] {
  const byKey = new Map<string, Routine[]>();
  for (const r of routines) {
    const key = r.etape_id ?? `solo_${r.id}`;
    if (!byKey.has(key)) byKey.set(key, []);
    byKey.get(key)!.push(r);
  }
  return [...byKey.entries()].map(([etapeId, rs]) => ({
    etapeId,
    routines: rs,
    label: (rs[0]?.label ?? '').split(' — ')[0],
    typeActe: rs[0]?.type_acte ?? '',
  }));
}

// ════════════════════════════════════════════════════════════════════════════════

export default function AgendaElevagePage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const { config: planConfig, loading: planLoading } = usePlan();
  const [selectedDate, setSelectedDate] = useState(toISODate(new Date()));
  const [focusedYear, setFocusedYear]   = useState(new Date().getFullYear());
  const [focusedMois, setFocusedMois]   = useState(new Date().getMonth());
  const [routines, setRoutines] = useState<Routine[]>([]);
  const [tachesM, setTachesM] = useState<TacheManuelle[]>([]);
  const [loadingData, setLoadingData] = useState(true);
  const [validateGroupe, setValidateGroupe] = useState<RoutineGroupe | null>(null);
  const [confirmDelete, setConfirmDelete] = useState<{ label: string; onConfirm: () => void } | null>(null);
  const [monthDates, setMonthDates] = useState<Map<string, string[]>>(new Map());

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [user, loading, router]);

  if (!loading && !planLoading && !planConfig.hasPlanning) {
    return (
      <div className="min-h-screen bg-[#F8F8F6] flex items-center justify-center p-6">
        <div className="bg-white rounded-2xl shadow-sm border border-[#E5E7EB] max-w-md w-full p-8 text-center">
          <div className="text-5xl mb-4">👑</div>
          <h2 className="text-xl font-bold text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
            Fonctionnalité Premium
          </h2>
          <p className="text-[#6B7280] text-sm mb-6" style={{ fontFamily: 'Galey, sans-serif' }}>
            L&apos;agenda des protocoles est réservé aux abonnements <strong>Premium</strong>.
            Gérez vos protocoles quotidiens et suivez l&apos;avancement par animal.
          </p>
          <button
            onClick={() => router.push('/abonnement')}
            className="w-full py-3 rounded-xl text-white font-semibold text-sm"
            style={{ backgroundColor: '#D97706', fontFamily: 'Galey, sans-serif' }}
          >
            Passer en Premium
          </button>
        </div>
      </div>
    );
  }

  const load = useCallback(async () => {
    if (!user) return;
    setLoadingData(true);
    const [r1, r2, tm] = await Promise.all([
      supabase.from('plan_taches')
        .select('id,label,date_prevue,statut,type_acte,animal_nom,etape_id')
        .eq('uid_eleveur', user.uid).eq('date_prevue', selectedDate),
      supabase.from('plan_taches')
        .select('id,label,date_prevue,statut,type_acte,animal_nom,etape_id')
        .eq('assigned_to', user.uid).eq('date_prevue', selectedDate),
      supabase.from('taches_elevage')
        .select('id,titre,date,statut')
        .eq('uid_eleveur', user.uid).eq('date', selectedDate),
    ]);
    const seen = new Set<string>();
    const allR = [...(r1.data ?? []), ...(r2.data ?? [])] as Routine[];
    setRoutines(allR.filter(r => { if (seen.has(r.id)) return false; seen.add(r.id); return true; }));
    setTachesM((tm.data ?? []) as TacheManuelle[]);
    setLoadingData(false);
  }, [user, selectedDate]);

  useEffect(() => { if (user) load(); }, [user, load]);

  const deleteGroupe = useCallback(async (g: RoutineGroupe) => {
    const ids = g.routines.map(r => r.id);
    await supabase.from('plan_taches').delete()
      .in('id', ids)
      .gte('date_prevue', `${selectedDate}T00:00:00`)
      .lte('date_prevue', `${selectedDate}T23:59:59`);
    load();
  }, [selectedDate, load]);

  const deleteManuelTask = useCallback(async (t: TacheManuelle) => {
    await supabase.from('taches_elevage').delete().eq('id', t.id);
    load();
  }, [load]);

  const loadMonth = useCallback(async () => {
    if (!user) return;
    const mm   = String(focusedMois + 1).padStart(2, '0');
    const from = `${focusedYear}-${mm}-01`;
    const to   = `${focusedYear}-${mm}-${String(daysInMonthFn(focusedYear, focusedMois)).padStart(2, '0')}`;
    const [r1, r2, tm] = await Promise.all([
      supabase.from('plan_taches').select('date_prevue,type_acte').eq('uid_eleveur', user.uid)
        .gte('date_prevue', `${from}T00:00:00`).lte('date_prevue', `${to}T23:59:59`),
      supabase.from('plan_taches').select('date_prevue,type_acte').eq('assigned_to', user.uid)
        .gte('date_prevue', `${from}T00:00:00`).lte('date_prevue', `${to}T23:59:59`),
      supabase.from('taches_elevage').select('date').eq('uid_eleveur', user.uid)
        .gte('date', from).lte('date', to),
    ]);
    const map = new Map<string, Set<string>>();
    const addColor = (date: string, color: string) => {
      if (!map.has(date)) map.set(date, new Set());
      map.get(date)!.add(color);
    };
    [...(r1.data ?? []), ...(r2.data ?? [])].forEach((r: { date_prevue: string; type_acte?: string }) => {
      const date = r.date_prevue.split('T')[0];
      addColor(date, ACTE_COLOR[r.type_acte ?? ''] ?? '#9E9E9E');
    });
    ((tm.data ?? []) as { date: string }[]).forEach(t => addColor(t.date, '#6E9E57'));
    setMonthDates(new Map([...map.entries()].map(([d, s]) => [d, [...s]])));
  }, [user, focusedYear, focusedMois]);

  useEffect(() => { if (user) loadMonth(); }, [user, loadMonth]);

  if (loading || !user) return (
    <div className="flex justify-center items-center h-64">
      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-teal-600" />
    </div>
  );

  const groupes           = groupRoutines(routines);
  const groupesEnCours    = groupes.filter(g => !g.routines.every(r => r.statut === 'fait'));
  const groupesEffectuees = groupes.filter(g => g.routines.every(r => r.statut === 'fait'));
  const tachesMEnCours    = tachesM.filter(t => t.statut !== 'fait');
  const tachesMEffectuees = tachesM.filter(t => t.statut === 'fait');

  const today      = new Date();
  const totalItems = groupes.length + tachesM.length;
  const totalDaysInMonth = daysInMonthFn(focusedYear, focusedMois);
  const calOffset        = firstWeekdayFn(focusedYear, focusedMois);
  const calCells: (number | null)[] = [...Array(calOffset).fill(null), ...Array.from({ length: totalDaysInMonth }, (_, i) => i + 1)];
  while (calCells.length % 7 !== 0) calCells.push(null);
  const doneItems  = groupesEffectuees.length + tachesMEffectuees.length;

  const dateLabel = selectedDate === toISODate(new Date())
    ? "Aujourd'hui"
    : new Date(selectedDate + 'T12:00:00').toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });

  const confirmDeleteAction = (label: string, onConfirm: () => void) =>
    setConfirmDelete({ label, onConfirm });

  const GroupeCard = ({ g, effectuee = false }: { g: RoutineGroupe; effectuee?: boolean }) => {
    const done    = g.routines.filter(r => r.statut === 'fait').length;
    const total   = g.routines.length;
    const pct     = total > 0 ? done / total : 0;
    const allDone = done === total;
    const emoji   = ACTE_EMOJIS[g.typeActe] ?? '📋';

    return (
      <div className={`bg-white rounded-2xl shadow-sm border p-4 ${
        effectuee ? 'border-gray-100 opacity-70' : allDone ? 'border-gray-100 opacity-60' : 'border-teal-100'
      }`}>
        <div className="flex items-center gap-3">
          <div
            className={`w-10 h-10 rounded-xl flex items-center justify-center text-xl flex-shrink-0 cursor-pointer hover:shadow-md transition-all ${
              effectuee || allDone ? 'bg-gray-50' : 'bg-teal-50'
            }`}
            onClick={() => !effectuee && setValidateGroupe(g)}
          >
            {emoji}
          </div>
          <div
            className="flex-1 min-w-0 cursor-pointer"
            onClick={() => !effectuee && setValidateGroupe(g)}
          >
            <p className={`font-semibold text-sm ${effectuee || allDone ? 'text-gray-400 line-through' : 'text-gray-800'}`}>
              {g.label}
            </p>
            <p className="text-xs text-gray-400 mt-0.5">
              Protocole · {total} animal{total > 1 ? 'x' : ''}
            </p>
          </div>
          <div className="flex items-center gap-2 flex-shrink-0">
            {!effectuee && (
              <span className={`text-sm font-bold ${allDone ? 'text-gray-400' : 'text-teal-600'}`}>
                {done}/{total}
              </span>
            )}
            <button
              onClick={() => confirmDeleteAction(
                `Supprimer le protocole "${g.label}" de ce jour ?`,
                () => deleteGroupe(g)
              )}
              className="p-1 rounded-lg hover:bg-red-50 text-gray-300 hover:text-red-400 transition-colors"
              title="Supprimer ce protocole du jour"
            >
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                  d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
              </svg>
            </button>
            {!effectuee && <span className="text-gray-300 text-base">›</span>}
          </div>
        </div>
        {total > 1 && !effectuee && (
          <div className="mt-3">
            <div className="w-full bg-gray-100 rounded-full h-1.5">
              <div
                className={`h-1.5 rounded-full transition-all ${allDone ? 'bg-gray-300' : 'bg-teal-500'}`}
                style={{ width: `${pct * 100}%` }}
              />
            </div>
          </div>
        )}
      </div>
    );
  };

  const ManuelRow = ({ t }: { t: TacheManuelle }) => {
    const isDone = t.statut === 'fait';
    return (
      <div className={`bg-white rounded-2xl shadow-sm border p-4 flex items-center gap-3 ${
        isDone ? 'border-gray-100 opacity-70' : 'border-gray-100'
      }`}>
        <button
          onClick={async () => {
            const newStatut = isDone ? 'a_faire' : 'fait';
            await supabase.from('taches_elevage').update({ statut: newStatut }).eq('id', t.id);
            load();
          }}
          className={`w-6 h-6 rounded-full border-2 flex items-center justify-center flex-shrink-0 transition-colors ${
            isDone ? 'bg-green-500 border-green-500' : 'border-gray-300 hover:border-teal-400'
          }`}
        >
          {isDone && <span className="text-white text-xs font-bold leading-none">✓</span>}
        </button>
        <span className={`text-sm font-medium flex-1 ${isDone ? 'line-through text-gray-400' : 'text-gray-800'}`}>
          {t.titre}
        </span>
        <button
          onClick={() => confirmDeleteAction(
            `Supprimer la tâche "${t.titre}" ?`,
            () => deleteManuelTask(t)
          )}
          className="p-1 rounded-lg hover:bg-red-50 text-gray-300 hover:text-red-400 transition-colors flex-shrink-0"
          title="Supprimer cette tâche"
        >
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
              d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
          </svg>
        </button>
      </div>
    );
  };

  return (
    <div className="max-w-2xl mx-auto px-4 py-6">

      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-800">Agenda</h1>
      </div>

      {/* Calendrier mois */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 mb-4">
        <div className="flex items-center justify-between mb-3">
          <button
            onClick={() => { if (focusedMois === 0) { setFocusedYear(y => y - 1); setFocusedMois(11); } else setFocusedMois(m => m - 1); }}
            className="p-2 rounded-lg hover:bg-gray-100 transition-colors text-teal-600 text-xl font-light">‹</button>
          <span className="font-bold text-sm capitalize text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>
            {new Date(focusedYear, focusedMois, 1).toLocaleDateString('fr-FR', { month: 'long', year: 'numeric' })}
          </span>
          <button
            onClick={() => { if (focusedMois === 11) { setFocusedYear(y => y + 1); setFocusedMois(0); } else setFocusedMois(m => m + 1); }}
            className="p-2 rounded-lg hover:bg-gray-100 transition-colors text-teal-600 text-xl font-light">›</button>
        </div>
        <div className="grid grid-cols-7 mb-1">
          {['L','M','M','J','V','S','D'].map((d, i) => (
            <div key={i} className="text-center text-xs font-semibold text-gray-400 py-1">{d}</div>
          ))}
        </div>
        <div className="grid grid-cols-7 gap-1">
          {calCells.map((day, i) => {
            if (!day) return <div key={i} />;
            const ds     = `${focusedYear}-${String(focusedMois + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
            const isT    = day === today.getDate() && focusedMois === today.getMonth() && focusedYear === today.getFullYear();
            const isSel  = ds === selectedDate;
            const colors = monthDates.get(ds) ?? [];
            return (
              <button key={i} onClick={() => setSelectedDate(ds)}
                className="aspect-square rounded-xl flex flex-col items-center justify-center gap-0.5 transition-colors"
                style={{
                  background: isSel ? '#0d9488' : isT ? '#ccfbf1' : 'white',
                  border: isT && !isSel ? '1.5px solid #0d9488' : '1.5px solid transparent',
                }}>
                <span className="text-sm font-bold" style={{ color: isSel ? 'white' : '#374151' }}>{day}</span>
                {colors.length > 0 && (
                  <div className="flex gap-0.5">
                    {colors.slice(0, 3).map((c, ci) => (
                      <div key={ci} className="w-1.5 h-1.5 rounded-full"
                        style={{ background: isSel ? 'rgba(255,255,255,0.75)' : c }} />
                    ))}
                  </div>
                )}
              </button>
            );
          })}
        </div>
      </div>

      {/* Vue jour — navigation + date */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 px-4 py-3 mb-4">
        <div className="flex items-center justify-between">
          <button onClick={() => {
            const d = new Date(selectedDate + 'T12:00:00'); d.setDate(d.getDate() - 1);
            setSelectedDate(toISODate(d)); setFocusedYear(d.getFullYear()); setFocusedMois(d.getMonth());
          }} className="p-2 rounded-lg hover:bg-gray-100 transition-colors text-teal-600 text-xl font-light">‹</button>
          <div className="text-center">
            <span className="font-bold text-sm capitalize text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>
              {dateLabel}
            </span>
            {totalItems > 0 && (
              <span className="ml-2 text-xs font-semibold text-teal-700 bg-teal-50 border border-teal-200 px-2 py-0.5 rounded-full">
                {doneItems}/{totalItems}
              </span>
            )}
          </div>
          <button onClick={() => {
            const d = new Date(selectedDate + 'T12:00:00'); d.setDate(d.getDate() + 1);
            setSelectedDate(toISODate(d)); setFocusedYear(d.getFullYear()); setFocusedMois(d.getMonth());
          }} className="p-2 rounded-lg hover:bg-gray-100 transition-colors text-teal-600 text-xl font-light">›</button>
        </div>
      </div>

      {loadingData ? (
        <div className="flex justify-center py-12">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-teal-600" />
        </div>
      ) : totalItems === 0 ? (
        <div className="text-center py-16">
          <div className="text-5xl mb-4">✅</div>
          <p className="text-gray-500 mb-2">Rien de prévu ce jour</p>
          <p className="text-gray-400 text-sm">
            Créez des protocoles depuis{' '}
            <a href="/elevage/planning" className="text-teal-600 underline font-medium">Planning</a>
          </p>
        </div>
      ) : (
        <div className="space-y-3">

          {/* ── À faire : routines ───────────────────────────────────────────── */}
          {groupesEnCours.map(g => <GroupeCard key={g.etapeId} g={g} />)}

          {/* ── À faire : tâches manuelles ───────────────────────────────────── */}
          {tachesMEnCours.length > 0 && groupesEnCours.length > 0 && (
            <div className="flex items-center gap-2 py-1">
              <div className="flex-1 h-px bg-gray-200" />
              <span className="text-xs text-gray-400 font-semibold px-1">Tâches manuelles</span>
              <div className="flex-1 h-px bg-gray-200" />
            </div>
          )}
          {tachesMEnCours.map(t => <ManuelRow key={t.id} t={t} />)}

          {/* ── Effectuées ───────────────────────────────────────────────────── */}
          {doneItems > 0 && (
            <>
              <div className="flex items-center gap-2 py-1">
                <div className="flex-1 h-px bg-gray-200" />
                <span className="text-xs text-gray-400 font-semibold px-2">
                  Effectuées ({doneItems})
                </span>
                <div className="flex-1 h-px bg-gray-200" />
              </div>
              {groupesEffectuees.map(g => <GroupeCard key={g.etapeId} g={g} effectuee />)}
              {tachesMEffectuees.map(t => <ManuelRow key={t.id} t={t} />)}
            </>
          )}
        </div>
      )}

      {/* Modal validation par animal */}
      {validateGroupe && (
        <RoutineModal
          groupe={validateGroupe}
          selectedDate={selectedDate}
          onClose={() => setValidateGroupe(null)}
          onUpdated={() => { setValidateGroupe(null); load(); }}
          onDeleteGroupe={(g) => {
            setValidateGroupe(null);
            confirmDeleteAction(
              `Supprimer le protocole "${g.label}" de ce jour ?`,
              () => deleteGroupe(g)
            );
          }}
        />
      )}

      {/* Dialog confirmation suppression */}
      {confirmDelete && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl p-6 max-w-sm w-full shadow-xl">
            <p className="text-sm font-semibold text-gray-800 mb-5 text-center">
              {confirmDelete.label}
            </p>
            <div className="flex gap-3">
              <button
                onClick={() => setConfirmDelete(null)}
                className="flex-1 py-2.5 border border-gray-200 rounded-xl text-sm text-gray-600 hover:bg-gray-50 font-medium"
              >
                Annuler
              </button>
              <button
                onClick={() => { confirmDelete.onConfirm(); setConfirmDelete(null); }}
                className="flex-1 py-2.5 bg-red-500 text-white rounded-xl text-sm font-semibold hover:bg-red-600"
              >
                Supprimer
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// ── Modal routines — checkboxes par animal ─────────────────────────────────────

function RoutineModal({ groupe, selectedDate, onClose, onUpdated, onDeleteGroupe }: {
  groupe: RoutineGroupe;
  selectedDate: string;
  onClose: () => void;
  onUpdated: () => void;
  onDeleteGroupe: (g: RoutineGroupe) => void;
}) {
  const [items, setItems] = useState<Routine[]>([...groupe.routines]);

  const toggle = async (idx: number) => {
    const r         = items[idx];
    const newStatut = r.statut === 'fait' ? 'en_attente' : 'fait';
    await supabase.from('plan_taches').update({ statut: newStatut }).eq('id', r.id);
    setItems(prev => prev.map((it, i) => i === idx ? { ...it, statut: newStatut } : it));
  };

  const deleteItem = async (r: Routine, idx: number) => {
    if (!confirm(`Supprimer "${r.animal_nom || `Animal #${idx + 1}`}" de ce protocole ?`)) return;
    await supabase.from('plan_taches').delete()
      .eq('id', r.id)
      .gte('date_prevue', `${selectedDate}T00:00:00`)
      .lte('date_prevue', `${selectedDate}T23:59:59`);
    setItems(prev => prev.filter((_, i) => i !== idx));
    onUpdated();
  };

  const total = items.length;
  const done  = items.filter(r => r.statut === 'fait').length;
  const pct   = total > 0 ? Math.round((done / total) * 100) : 0;
  const emoji = ACTE_EMOJIS[groupe.typeActe] ?? '📋';

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-end justify-center sm:items-center p-4"
         onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="bg-white rounded-2xl w-full max-w-md max-h-[80vh] flex flex-col">

        {/* Header */}
        <div className="p-5 border-b">
          <div className="flex items-start gap-3">
            <span className="text-2xl flex-shrink-0">{emoji}</span>
            <div className="flex-1 min-w-0">
              <h3 className="font-bold text-gray-800 text-base">{groupe.label}</h3>
              <p className="text-xs text-gray-400 mt-0.5">
                Protocole · {done}/{total} fait{done > 1 ? 's' : ''}
              </p>
            </div>
            <button
              onClick={() => onDeleteGroupe(groupe)}
              className="p-1.5 rounded-lg hover:bg-red-50 text-gray-300 hover:text-red-400 transition-colors"
              title="Supprimer ce protocole du jour"
            >
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                  d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
              </svg>
            </button>
            <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-2xl leading-none flex-shrink-0">×</button>
          </div>
          <div className="mt-3">
            <div className="w-full bg-gray-100 rounded-full h-2">
              <div
                className={`h-2 rounded-full transition-all duration-300 ${done === total ? 'bg-green-500' : 'bg-teal-500'}`}
                style={{ width: `${pct}%` }}
              />
            </div>
            <p className="text-right text-xs text-gray-400 mt-1">{pct} %</p>
          </div>
        </div>

        {/* Liste animaux */}
        <div className="overflow-y-auto flex-1">
          {items.map((r, idx) => {
            const isDone = r.statut === 'fait';
            const nom    = r.animal_nom?.trim() || `Animal #${idx + 1}`;
            return (
              <div key={r.id}
                className="flex items-center gap-3 px-5 py-3.5 border-b border-gray-50 last:border-0 hover:bg-gray-50 transition-colors">
                <button onClick={() => toggle(idx)}
                  className={`w-5 h-5 rounded border-2 flex items-center justify-center flex-shrink-0 transition-colors ${
                    isDone ? 'bg-teal-600 border-teal-600' : 'border-gray-300 hover:border-teal-400'
                  }`}>
                  {isDone && <span className="text-white text-xs font-bold leading-none">✓</span>}
                </button>
                <span className="text-sm mr-0.5">🐾</span>
                <span
                  className={`text-sm font-medium flex-1 cursor-pointer ${isDone ? 'line-through text-gray-400' : 'text-gray-800'}`}
                  onClick={() => toggle(idx)}
                >
                  {nom}
                </span>
                <button
                  onClick={() => deleteItem(r, idx)}
                  className="p-1 rounded hover:bg-red-50 text-gray-300 hover:text-red-400 transition-colors flex-shrink-0"
                  title="Supprimer"
                >
                  <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                      d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                  </svg>
                </button>
              </div>
            );
          })}
        </div>

        {/* Footer */}
        <div className="p-4 border-t">
          <button onClick={onUpdated}
            className="w-full py-2.5 bg-teal-600 text-white rounded-xl text-sm font-semibold hover:bg-teal-700 transition-colors">
            Fermer
          </button>
        </div>
      </div>
    </div>
  );
}
