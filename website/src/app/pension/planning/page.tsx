'use client';

import { Fragment, useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { usePensionAccess } from '@/hooks/usePensionAccess';
import { supabase } from '@/lib/supabase';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { PensionEntreeModal, type PensionEntreePrefill } from '@/components/PensionEntreeModal';
import { lookupAnimalByChip } from '@/lib/pension-chip-lookup';

interface Logement {
  id: string;
  nom: string;
  type: string;
  capacite: number;
  especes?: string[] | null;
  dernier_nettoyage?: string | null;
}

interface Entree {
  id: string;
  pro_uid: string;
  animal_nom: string;
  proprietaire_nom?: string | null;
  logement_id?: string | null;
  animal_id?: string | null;
  seul_dans_logement?: boolean;
  statut: 'en_pension' | 'sorti';
  date_entree: string;
  date_sortie_prevue?: string | null;
  date_sortie_effective?: string | null;
  created_at: string;
}

function rangesOverlap(a: Entree, b: Entree): boolean {
  const aStart = new Date(a.date_entree);
  const bStart = new Date(b.date_entree);
  const aEnd = a.date_sortie_effective ? new Date(a.date_sortie_effective) : (a.date_sortie_prevue ? new Date(a.date_sortie_prevue) : new Date(2100, 0, 1));
  const bEnd = b.date_sortie_effective ? new Date(b.date_sortie_effective) : (b.date_sortie_prevue ? new Date(b.date_sortie_prevue) : new Date(2100, 0, 1));
  return aStart <= bEnd && bStart <= aEnd;
}

/** Range dans capacite lignes les séjours d'un logement sans chevauchement
 * (façon Tetris) — les séjours "seul" sont traités à part par l'appelant. */
function packEntries(entries: Entree[], capacite: number): Entree[][] {
  const rows: Entree[][] = Array.from({ length: Math.max(1, capacite) }, () => []);
  const normales = entries.filter(e => !e.seul_dans_logement)
    .sort((a, b) => a.date_entree.localeCompare(b.date_entree));
  for (const e of normales) {
    let placed = false;
    for (const row of rows) {
      if (!row.some(other => rangesOverlap(other, e))) { row.push(e); placed = true; break; }
    }
    if (!placed) rows[rows.length - 1].push(e);
  }
  return rows;
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
const ESPECES = ['Chien', 'Chat', 'Lapin', 'Oiseau', 'Reptile', 'Rongeur', 'Cheval', 'Autre'];

export default function PensionPlanningPage() {
  const { user, userData, isPension, loading: authLoading } = usePensionAccess();
  const router = useRouter();
  const activeProfileId = useActiveProfile();
  const [logements, setLogements] = useState<Logement[]>([]);
  const [entrees, setEntrees] = useState<Entree[]>([]);
  const [loading, setLoading] = useState(true);
  const [windowStart, setWindowStart] = useState(() => { const d = new Date(); d.setHours(0, 0, 0, 0); return d; });
  const [editingEntree, setEditingEntree] = useState<Entree | null>(null);
  const [filterEspece, setFilterEspece] = useState<string | null>(null);
  const [creatingFor, setCreatingFor] = useState<{ logementId: string; date: string } | null>(null);
  const [chipStepFor, setChipStepFor] = useState<{ logementId: string; date: string } | null>(null);
  const [chipInput, setChipInput] = useState('');
  const [chipSearching, setChipSearching] = useState(false);
  const [prefill, setPrefill] = useState<PensionEntreePrefill | undefined>(undefined);

  async function searchByChip(chip: string) {
    setChipSearching(true);
    setPrefill(await lookupAnimalByChip(chip));
    setChipSearching(false);
    if (chipStepFor) { setCreatingFor(chipStepFor); setChipStepFor(null); }
    setChipInput('');
  }


  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isPension) { router.push('/'); return; }
  }, [user, userData, isPension, authLoading, router]);

  const load = useCallback(async () => {
    if (!user) return;
    const windowEnd = new Date(windowStart); windowEnd.setDate(windowEnd.getDate() + DAYS);
    const [{ data: log }, { data: ent }] = await Promise.all([
      supabase.from('enclos_chenil').select('id, nom, type, capacite, especes, dernier_nettoyage').eq('uid_eleveur', user.uid).order('nom'),
      supabase.from('pension_entrees').select('id, pro_uid, animal_nom, proprietaire_nom, logement_id, animal_id, seul_dans_logement, statut, date_entree, date_sortie_prevue, date_sortie_effective, created_at')
        .eq('pro_uid', user.uid).lte('date_entree', windowEnd.toISOString().slice(0, 10)).order('date_entree'),
    ]);
    setLogements(log ?? []);
    setEntrees((ent ?? []).filter(e => !e.date_sortie_effective || new Date(e.date_sortie_effective) >= windowStart));
    setLoading(false);
  }, [user, windowStart]);

  useEffect(() => { load(); }, [load]);

  async function marquerNettoye(logementId: string) {
    await supabase.from('enclos_chenil').update({ dernier_nettoyage: new Date().toISOString().slice(0, 10) }).eq('id', logementId);
    load();
  }

  const days = Array.from({ length: DAYS }, (_, i) => { const d = new Date(windowStart); d.setDate(d.getDate() + i); return d; });
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const visibleLogements = filterEspece ? logements.filter(l => (l.especes ?? []).includes(filterEspece)) : logements;
  const grouped = visibleLogements.reduce<Record<string, Logement[]>>((acc, l) => {
    (acc[l.type] ??= []).push(l);
    return acc;
  }, {});

  const entryForDay = (list: Entree[], day: Date): Entree | null => {
    const dayOnly = new Date(day.getFullYear(), day.getMonth(), day.getDate());
    for (const e of list) {
      const start = new Date(e.date_entree);
      const startOnly = new Date(start.getFullYear(), start.getMonth(), start.getDate());
      if (dayOnly < startOnly) continue;
      const end = e.date_sortie_effective ? new Date(e.date_sortie_effective) : (e.date_sortie_prevue ? new Date(e.date_sortie_prevue) : null);
      if (end) {
        const endOnly = new Date(end.getFullYear(), end.getMonth(), end.getDate());
        if (dayOnly > endOnly) continue;
      }
      return e;
    }
    return null;
  };

  const estNettoyeAujourdhui = (l: Logement) => {
    if (!l.dernier_nettoyage) return false;
    const d = new Date(l.dernier_nettoyage);
    return sameDay(d, today);
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

      {logements.length > 0 && (
        <div className="flex gap-2 flex-wrap">
          <button onClick={() => setFilterEspece(null)}
            className={`px-3 py-1.5 rounded-full text-xs font-galey font-semibold border transition-colors ${
              filterEspece === null ? 'bg-teal-700 text-white border-teal-700' : 'bg-white text-gray-600 border-gray-200'
            }`}>
            Toutes espèces
          </button>
          {ESPECES.map(esp => (
            <button key={esp} onClick={() => setFilterEspece(esp)}
              className={`px-3 py-1.5 rounded-full text-xs font-galey font-semibold border transition-colors ${
                filterEspece === esp ? 'bg-teal-700 text-white border-teal-700' : 'bg-white text-gray-600 border-gray-200'
              }`}>
              {esp}
            </button>
          ))}
        </div>
      )}

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
        </div>
      ) : visibleLogements.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <p className="text-4xl mb-3">🏘️</p>
          <p className="font-galey">{logements.length === 0 ? 'Aucun logement enregistré' : 'Aucun logement pour cette espèce'}</p>
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
                  {ls.map(l => {
                    const logEntrees = entrees.filter(e => e.logement_id === l.id);
                    const soloEntrees = logEntrees.filter(e => e.seul_dans_logement);
                    const capacite = l.capacite || 1;
                    const rows = packEntries(logEntrees, capacite);
                    return rows.map((rowEntrees, slot) => (
                      <tr key={`${l.id}-${slot}`}>
                        <td className="sticky left-0 bg-white z-10 px-3 py-2 text-sm font-galey font-semibold text-gray-800 border-b border-gray-50 truncate max-w-32">
                          {slot === 0 && (
                            <div className="flex items-center justify-between gap-2">
                              <span className="truncate">{l.nom}</span>
                              <button onClick={() => marquerNettoye(l.id)}
                                title={estNettoyeAujourdhui(l) ? 'Nettoyé aujourd\'hui' : 'Marquer comme nettoyé'}
                                className="shrink-0">
                                {estNettoyeAujourdhui(l)
                                  ? <span className="text-green-600 text-xs">✓</span>
                                  : <span className="text-orange-500 text-xs">🧹</span>}
                              </button>
                            </div>
                          )}
                        </td>
                        {days.map(d => {
                          const solo = entryForDay(soloEntrees, d);
                          const e = solo ?? entryForDay(rowEntrees, d);
                          const st = e ? computeStatut(e, today) : null;
                          return (
                            <td key={d.toISOString()} className="border-b border-gray-50 p-1">
                              {e && st ? (
                                <button
                                  onClick={() => setEditingEntree(e)}
                                  title={e.animal_nom}
                                  className="w-full h-6 rounded relative"
                                  style={{ backgroundColor: STATUT_COLOR[st], border: solo ? '1.5px solid #ef4444' : undefined }}
                                >
                                  {solo && <span className="absolute inset-0 flex items-center justify-center text-[9px] text-white">🔒</span>}
                                </button>
                              ) : (
                                <button
                                  onClick={() => { setPrefill(undefined); setChipStepFor({ logementId: l.id, date: d.toISOString().slice(0, 10) }); }}
                                  title="Ajouter un séjour"
                                  className="w-full h-6 rounded hover:bg-gray-100 flex items-center justify-center text-gray-300 hover:text-gray-400 transition-colors">
                                  +
                                </button>
                              )}
                            </td>
                          );
                        })}
                      </tr>
                    ));
                  })}
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

      {editingEntree && user && (
        <PensionEntreeModal
          proUid={user.uid}
          proProfileId={activeProfileId || null}
          entree={editingEntree}
          onClose={() => setEditingEntree(null)}
          onSaved={() => { setEditingEntree(null); load(); }}
        />
      )}

      {chipStepFor && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4"
          onClick={() => setChipStepFor(null)}>
          <div className="bg-white rounded-2xl w-full max-w-sm p-5" onClick={e => e.stopPropagation()}>
            <h3 className="font-bold font-galey text-lg text-gray-900 mb-3">Identifier l&apos;animal</h3>
            <input value={chipInput} onChange={e => setChipInput(e.target.value)}
              placeholder="Numéro de puce (optionnel)"
              className="w-full px-3 py-2 border border-gray-200 rounded-xl text-sm font-galey mb-3 focus:outline-none focus:ring-2 focus:ring-teal-300" />
            <div className="flex gap-3">
              <button onClick={() => searchByChip(chipInput)} disabled={!chipInput.trim() || chipSearching}
                className="flex-1 bg-[#0C5C6C] text-white text-sm font-galey font-semibold py-2.5 rounded-xl disabled:opacity-40 hover:bg-[#094F5D] transition-colors">
                {chipSearching ? 'Recherche…' : 'Rechercher'}
              </button>
              <button onClick={() => { setPrefill(undefined); setCreatingFor(chipStepFor); setChipStepFor(null); }}
                className="flex-1 border border-gray-200 text-gray-600 text-sm font-galey font-semibold py-2.5 rounded-xl hover:bg-gray-50 transition-colors">
                Sans puce
              </button>
            </div>
          </div>
        </div>
      )}

      {creatingFor && user && (
        <PensionEntreeModal
          proUid={user.uid}
          proProfileId={activeProfileId || null}
          initialLogementId={creatingFor.logementId}
          initialDateEntree={creatingFor.date}
          prefill={prefill}
          onClose={() => setCreatingFor(null)}
          onSaved={() => { setCreatingFor(null); load(); }}
        />
      )}
    </div>
  );
}
