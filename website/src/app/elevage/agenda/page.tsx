'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

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

// ── Helpers ───────────────────────────────────────────────────────────────────

function toISODate(d: Date) { return d.toISOString().split('T')[0]; }
function addDays(d: Date, n: number) { const r = new Date(d); r.setDate(r.getDate() + n); return r; }

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
  const [selectedDate, setSelectedDate] = useState(toISODate(new Date()));
  const [routines, setRoutines] = useState<Routine[]>([]);
  const [tachesM, setTachesM] = useState<TacheManuelle[]>([]);
  const [loadingData, setLoadingData] = useState(true);
  const [validateGroupe, setValidateGroupe] = useState<RoutineGroupe | null>(null);

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [user, loading, router]);

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
    // Dedup plan_taches by id (eleveur peut aussi être assigned_to sur ses propres tâches)
    const seen = new Set<string>();
    const allR = [...(r1.data ?? []), ...(r2.data ?? [])] as Routine[];
    setRoutines(allR.filter(r => { if (seen.has(r.id)) return false; seen.add(r.id); return true; }));
    setTachesM((tm.data ?? []) as TacheManuelle[]);
    setLoadingData(false);
  }, [user, selectedDate]);

  useEffect(() => { if (user) load(); }, [user, load]);

  if (loading || !user) return (
    <div className="flex justify-center items-center h-64">
      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-teal-600" />
    </div>
  );

  const groupes   = groupRoutines(routines);
  const today     = new Date();
  const days      = Array.from({ length: 7 }, (_, i) => addDays(today, -3 + i));
  const doneR     = groupes.filter(g => g.routines.every(r => r.statut === 'fait')).length;
  const doneT     = tachesM.filter(t => t.statut === 'fait').length;
  const totalItems = groupes.length + tachesM.length;
  const doneItems  = doneR + doneT;

  const dateLabel = selectedDate === toISODate(new Date())
    ? "Aujourd'hui"
    : new Date(selectedDate + 'T12:00:00').toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });

  return (
    <div className="max-w-2xl mx-auto px-4 py-6">

      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-800">Agenda</h1>
        {totalItems > 0 && (
          <span className="text-xs font-semibold text-teal-700 bg-teal-50 border border-teal-200 px-3 py-1 rounded-full">
            {doneItems}/{totalItems} fait{doneItems > 1 ? 's' : ''}
          </span>
        )}
      </div>

      {/* Sélecteur semaine */}
      <div className="flex gap-2 mb-6 overflow-x-auto pb-1">
        {days.map(d => {
          const ds      = toISODate(d);
          const isActive = ds === selectedDate;
          const isToday  = ds === toISODate(new Date());
          return (
            <button key={ds} onClick={() => setSelectedDate(ds)}
              className={`flex flex-col items-center p-3 rounded-xl min-w-[48px] transition-colors ${
                isActive  ? 'bg-teal-600 text-white' :
                isToday   ? 'border-2 border-teal-500 text-teal-700' :
                            'bg-gray-100 text-gray-600 hover:bg-gray-200'
              }`}>
              <span className="text-xs font-semibold uppercase">
                {d.toLocaleDateString('fr-FR', { weekday: 'short' }).slice(0, 2)}
              </span>
              <span className="text-lg font-bold">{d.getDate()}</span>
            </button>
          );
        })}
      </div>

      {/* Titre date */}
      <h2 className="text-base font-bold text-gray-700 mb-4 capitalize">{dateLabel}</h2>

      {loadingData ? (
        <div className="flex justify-center py-12">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-teal-600" />
        </div>
      ) : totalItems === 0 ? (
        <div className="text-center py-16">
          <div className="text-5xl mb-4">✅</div>
          <p className="text-gray-500 mb-2">Rien de prévu ce jour</p>
          <p className="text-gray-400 text-sm">
            Créez des routines depuis{' '}
            <a href="/elevage/planning" className="text-teal-600 underline font-medium">Planning</a>
          </p>
        </div>
      ) : (
        <div className="space-y-3">

          {/* ── Routines groupées ────────────────────────────────────────────── */}
          {groupes.map(g => {
            const done    = g.routines.filter(r => r.statut === 'fait').length;
            const total   = g.routines.length;
            const pct     = total > 0 ? done / total : 0;
            const allDone = done === total;
            const emoji   = ACTE_EMOJIS[g.typeActe] ?? '📋';

            return (
              <div key={g.etapeId}
                className={`bg-white rounded-2xl shadow-sm border p-4 cursor-pointer hover:shadow-md transition-all ${
                  allDone ? 'border-gray-100 opacity-60' : 'border-teal-100'
                }`}
                onClick={() => setValidateGroupe(g)}>
                <div className="flex items-center gap-3">
                  <div className={`w-10 h-10 rounded-xl flex items-center justify-center text-xl flex-shrink-0 ${
                    allDone ? 'bg-gray-50' : 'bg-teal-50'
                  }`}>
                    {emoji}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className={`font-semibold text-sm ${allDone ? 'text-gray-400 line-through' : 'text-gray-800'}`}>
                      {g.label}
                    </p>
                    <p className="text-xs text-gray-400 mt-0.5">
                      Routine · {total} animal{total > 1 ? 'x' : ''}
                    </p>
                  </div>
                  <div className="flex items-center gap-1 flex-shrink-0">
                    <span className={`text-sm font-bold ${allDone ? 'text-gray-400' : 'text-teal-600'}`}>
                      {done}/{total}
                    </span>
                    <span className="text-gray-300 text-base">›</span>
                  </div>
                </div>
                {total > 1 && (
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
          })}

          {/* Séparateur tâches manuelles */}
          {groupes.length > 0 && tachesM.length > 0 && (
            <div className="flex items-center gap-2 py-1">
              <div className="flex-1 h-px bg-gray-200" />
              <span className="text-xs text-gray-400 font-semibold px-1">Tâches manuelles</span>
              <div className="flex-1 h-px bg-gray-200" />
            </div>
          )}

          {/* ── Tâches manuelles ─────────────────────────────────────────────── */}
          {tachesM.map(t => {
            const isDone = t.statut === 'fait';
            return (
              <div key={t.id} className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 flex items-center gap-3">
                <button
                  onClick={async () => {
                    const newStatut = isDone ? 'a_faire' : 'fait';
                    await supabase.from('taches_elevage').update({ statut: newStatut }).eq('id', t.id);
                    load();
                  }}
                  className={`w-6 h-6 rounded-full border-2 flex items-center justify-center flex-shrink-0 transition-colors ${
                    isDone ? 'bg-green-500 border-green-500' : 'border-gray-300 hover:border-teal-400'
                  }`}>
                  {isDone && <span className="text-white text-xs font-bold leading-none">✓</span>}
                </button>
                <span className={`text-sm font-medium flex-1 ${isDone ? 'line-through text-gray-400' : 'text-gray-800'}`}>
                  {t.titre}
                </span>
              </div>
            );
          })}
        </div>
      )}

      {/* Modal par-animal */}
      {validateGroupe && (
        <RoutineModal
          groupe={validateGroupe}
          onClose={() => setValidateGroupe(null)}
          onUpdated={() => { setValidateGroupe(null); load(); }}
        />
      )}
    </div>
  );
}

// ── Modal routines — checkboxes par animal ─────────────────────────────────────

function RoutineModal({ groupe, onClose, onUpdated }: {
  groupe: RoutineGroupe;
  onClose: () => void;
  onUpdated: () => void;
}) {
  const [items, setItems] = useState<Routine[]>([...groupe.routines]);

  const toggle = async (idx: number) => {
    const r         = items[idx];
    const newStatut = r.statut === 'fait' ? 'en_attente' : 'fait';
    await supabase.from('plan_taches').update({ statut: newStatut }).eq('id', r.id);
    setItems(prev => prev.map((it, i) => i === idx ? { ...it, statut: newStatut } : it));
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
                Routine · {done}/{total} fait{done > 1 ? 's' : ''}
              </p>
            </div>
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
              <button key={r.id} onClick={() => toggle(idx)}
                className="w-full flex items-center gap-3 px-5 py-3.5 hover:bg-gray-50 transition-colors border-b border-gray-50 last:border-0 text-left">
                <div className={`w-5 h-5 rounded border-2 flex items-center justify-center flex-shrink-0 transition-colors ${
                  isDone ? 'bg-teal-600 border-teal-600' : 'border-gray-300 hover:border-teal-400'
                }`}>
                  {isDone && <span className="text-white text-xs font-bold leading-none">✓</span>}
                </div>
                <span className="text-sm mr-0.5">🐾</span>
                <span className={`text-sm font-medium flex-1 ${isDone ? 'line-through text-gray-400' : 'text-gray-800'}`}>
                  {nom}
                </span>
              </button>
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
