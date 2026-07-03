'use client';

import { Fragment, useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { usePensionAccess } from '@/hooks/usePensionAccess';
import { supabase } from '@/lib/supabase';

interface Logement {
  id: string;
  nom: string;
  type: string;
}

interface Entree {
  id: string;
  animal_nom: string;
  proprietaire_nom?: string | null;
  logement_id?: string | null;
  statut: string;
  date_entree: string;
  date_sortie_prevue?: string | null;
  date_sortie_effective?: string | null;
}

const TYPE_LABEL: Record<string, string> = { box: 'Box', enclos: 'Enclos', parc: 'Parc', chatterie: 'Chatterie', cage: 'Cage' };

type Statut = 'a_venir' | 'entree_aujourdhui' | 'en_cours' | 'sortie_aujourdhui' | 'sortie_retard' | 'sortie_faite_aujourdhui' | 'passe';

const STATUT_COLOR: Record<Statut, string> = {
  a_venir: '#3B82F6',
  entree_aujourdhui: '#06B6D4',
  en_cours: '#6E9E57',
  sortie_aujourdhui: '#EAB308',
  sortie_retard: '#EA580C',
  sortie_faite_aujourdhui: '#4B5563',
  passe: '#D1D5DB',
};

const STATUT_LABEL: Record<Statut, string> = {
  a_venir: 'Séjour à venir',
  entree_aujourdhui: 'Entrée aujourd\'hui',
  en_cours: 'Séjour en cours',
  sortie_aujourdhui: 'Sortie aujourd\'hui',
  sortie_retard: 'Sortie en retard',
  sortie_faite_aujourdhui: 'Sortie faite aujourd\'hui',
  passe: 'Séjour passé',
};

function sameDay(a: Date, b: Date) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

function computeStatut(e: Entree, today: Date): Statut {
  const dateEntree = e.date_entree ? new Date(e.date_entree) : null;
  const dateSortiePrevue = e.date_sortie_prevue ? new Date(e.date_sortie_prevue) : null;
  const dateSortieEff = e.date_sortie_effective ? new Date(e.date_sortie_effective) : null;

  if (e.statut === 'sorti') {
    if (dateSortieEff && sameDay(dateSortieEff, today)) return 'sortie_faite_aujourdhui';
    return 'passe';
  }
  if (dateEntree && dateEntree > today && !sameDay(dateEntree, today)) return 'a_venir';
  if (dateEntree && sameDay(dateEntree, today)) return 'entree_aujourdhui';
  if (dateSortiePrevue && sameDay(dateSortiePrevue, today)) return 'sortie_aujourdhui';
  if (dateSortiePrevue && dateSortiePrevue < today && !sameDay(dateSortiePrevue, today)) return 'sortie_retard';
  return 'en_cours';
}

const DAYS = 14;
const DAY_FMT = new Intl.DateTimeFormat('fr-FR', { weekday: 'short', day: 'numeric', month: 'numeric' });

export default function PensionPlanningPage() {
  const { user, userData, isPension } = usePensionAccess();
  const router = useRouter();
  const [logements, setLogements] = useState<Logement[]>([]);
  const [entrees, setEntrees] = useState<Entree[]>([]);
  const [loading, setLoading] = useState(true);
  const [windowStart, setWindowStart] = useState(() => { const d = new Date(); d.setHours(0, 0, 0, 0); return d; });
  const [selected, setSelected] = useState<{ e: Entree; st: Statut } | null>(null);


  useEffect(() => {
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isPension) { router.push('/'); return; }
  }, [user, userData, isPension, router]);

  const load = useCallback(async () => {
    if (!user) return;
    const windowEnd = new Date(windowStart); windowEnd.setDate(windowEnd.getDate() + DAYS);
    const [{ data: log }, { data: ent }] = await Promise.all([
      supabase.from('enclos_chenil').select('id, nom, type').eq('uid_eleveur', user.uid).order('nom'),
      supabase.from('pension_entrees').select('id, animal_nom, proprietaire_nom, logement_id, statut, date_entree, date_sortie_prevue, date_sortie_effective')
        .eq('pro_uid', user.uid).lte('date_entree', windowEnd.toISOString().slice(0, 10)).order('date_entree'),
    ]);
    setLogements(log ?? []);
    setEntrees((ent ?? []).filter(e => !e.date_sortie_effective || new Date(e.date_sortie_effective) >= windowStart));
    setLoading(false);
  }, [user, windowStart]);

  useEffect(() => { load(); }, [load]);

  const days = Array.from({ length: DAYS }, (_, i) => { const d = new Date(windowStart); d.setDate(d.getDate() + i); return d; });
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const grouped = logements.reduce<Record<string, Logement[]>>((acc, l) => {
    (acc[l.type] ??= []).push(l);
    return acc;
  }, {});

  const entryFor = (logementId: string, day: Date): Entree | null => {
    for (const e of entrees) {
      if (e.logement_id !== logementId) continue;
      const start = new Date(e.date_entree);
      const end = e.date_sortie_effective ? new Date(e.date_sortie_effective) : (e.date_sortie_prevue ? new Date(e.date_sortie_prevue) : null);
      const dayOnly = new Date(day.getFullYear(), day.getMonth(), day.getDate());
      const startOnly = new Date(start.getFullYear(), start.getMonth(), start.getDate());
      if (dayOnly < startOnly) continue;
      if (end) {
        const endOnly = new Date(end.getFullYear(), end.getMonth(), end.getDate());
        if (dayOnly > endOnly) continue;
      }
      return e;
    }
    return null;
  };

  if (!user || !userData) return null;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <h1 className="text-2xl font-bold font-galey text-teal-800">Planning occupation</h1>
        <div className="flex items-center gap-2">
          <button onClick={() => setWindowStart(d => { const n = new Date(d); n.setDate(n.getDate() - 7); return n; })}
            className="w-8 h-8 rounded-full border border-gray-200 hover:bg-gray-50 flex items-center justify-center">‹</button>
          <button onClick={() => { const d = new Date(); d.setHours(0, 0, 0, 0); setWindowStart(d); }}
            className="text-xs font-galey font-semibold px-3 py-1.5 rounded-full border border-gray-200 hover:bg-gray-50">
            Aujourd&apos;hui
          </button>
          <button onClick={() => setWindowStart(d => { const n = new Date(d); n.setDate(n.getDate() + 7); return n; })}
            className="w-8 h-8 rounded-full border border-gray-200 hover:bg-gray-50 flex items-center justify-center">›</button>
        </div>
      </div>

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
        </div>
      ) : logements.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <p className="text-4xl mb-3">🏘️</p>
          <p className="font-galey">Aucun logement enregistré</p>
        </div>
      ) : (
        <div className="bg-white rounded-2xl border border-gray-100 overflow-x-auto">
          <table className="border-collapse w-full">
            <thead>
              <tr>
                <th className="sticky left-0 bg-white z-10 w-32 min-w-32 border-b border-gray-200" />
                {days.map(d => (
                  <th key={d.toISOString()} className={`w-14 min-w-14 text-center py-2 border-b border-gray-200 ${sameDay(d, today) ? 'bg-[#EEF5EA]' : ''}`}>
                    <p className="text-[10px] text-gray-400 font-galey capitalize">{DAY_FMT.format(d).split(' ')[0]}</p>
                    <p className="text-xs font-galey font-semibold text-gray-700">{d.getDate()}/{d.getMonth() + 1}</p>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {Object.entries(grouped).map(([type, ls]) => (
                <Fragment key={type}>
                  <tr>
                    <td colSpan={DAYS + 1} className="bg-[#EEF5EA] text-teal-800 text-xs font-galey font-bold px-3 py-1.5 sticky left-0">
                      {TYPE_LABEL[type] ?? type}
                    </td>
                  </tr>
                  {ls.map(l => (
                    <tr key={l.id}>
                      <td className="sticky left-0 bg-white z-10 px-3 py-2 text-sm font-galey font-semibold text-gray-800 border-b border-gray-50 truncate max-w-32">
                        {l.nom}
                      </td>
                      {days.map(d => {
                        const e = entryFor(l.id, d);
                        const st = e ? computeStatut(e, today) : null;
                        return (
                          <td key={d.toISOString()} className="border-b border-gray-50 p-1">
                            {e && st ? (
                              <button
                                onClick={() => setSelected({ e, st })}
                                title={e.animal_nom}
                                className="w-full h-6 rounded"
                                style={{ backgroundColor: STATUT_COLOR[st] }}
                              />
                            ) : <div className="w-full h-6" />}
                          </td>
                        );
                      })}
                    </tr>
                  ))}
                </Fragment>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <div className="flex flex-wrap gap-3 bg-white rounded-2xl border border-gray-100 p-3">
        {(Object.keys(STATUT_COLOR) as Statut[]).map(st => (
          <div key={st} className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-sm" style={{ backgroundColor: STATUT_COLOR[st] }} />
            <span className="text-xs font-galey text-gray-500">{STATUT_LABEL[st]}</span>
          </div>
        ))}
      </div>

      {selected && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4" onClick={() => setSelected(null)}>
          <div className="bg-white rounded-2xl w-full max-w-sm p-5" onClick={e => e.stopPropagation()}>
            <h3 className="font-bold font-galey text-lg text-gray-900 mb-1">{selected.e.animal_nom}</h3>
            <span className="inline-block text-xs font-galey font-semibold px-2.5 py-1 rounded-full mb-3"
              style={{ backgroundColor: `${STATUT_COLOR[selected.st]}26`, color: STATUT_COLOR[selected.st] }}>
              {STATUT_LABEL[selected.st]}
            </span>
            <p className="text-sm font-galey text-gray-600">Propriétaire : {selected.e.proprietaire_nom ?? '—'}</p>
            <p className="text-sm font-galey text-gray-600">Entrée : {selected.e.date_entree}</p>
            <p className="text-sm font-galey text-gray-600">Sortie prévue : {selected.e.date_sortie_prevue ?? '—'}</p>
            <button onClick={() => setSelected(null)}
              className="mt-4 w-full text-sm font-galey font-semibold border border-gray-200 rounded-xl py-2 hover:bg-gray-50">
              Fermer
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
