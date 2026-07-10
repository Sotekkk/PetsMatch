'use client';

import { Fragment, Suspense, useEffect, useState, useCallback } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
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
}

interface Entree {
  id: string;
  pro_uid: string;
  animal_nom: string;
  espece?: string | null;
  race?: string | null;
  puce?: string | null;
  proprietaire_nom?: string | null;
  proprietaire_contact?: string | null;
  proprietaire_email?: string | null;
  proprietaire_adresse?: string | null;
  logement_id?: string | null;
  animal_id?: string | null;
  seul_dans_logement?: boolean;
  statut: 'en_pension' | 'sorti';
  date_entree: string;
  date_sortie_prevue?: string | null;
  date_sortie_effective?: string | null;
  notes?: string | null;
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

function PensionPlanningPageInner() {
  const { user, userData, isPension, loading: authLoading } = usePensionAccess();
  const router = useRouter();
  const searchParams = useSearchParams();
  const employerUid = searchParams.get('employerUid');
  const readOnly = !!employerUid;
  const activeProfileId = useActiveProfile();
  const [employerOk, setEmployerOk] = useState(!employerUid);
  const [employerNom, setEmployerNom] = useState('');
  const [logements, setLogements] = useState<Logement[]>([]);
  const [entrees, setEntrees] = useState<Entree[]>([]);
  const [nettoyages, setNettoyages] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);
  const [windowStart, setWindowStart] = useState(() => { const d = new Date(); d.setHours(0, 0, 0, 0); return d; });
  const [editingEntree, setEditingEntree] = useState<Entree | null>(null);
  const [readOnlyEntree, setReadOnlyEntree] = useState<Entree | null>(null);
  const [filterEspece, setFilterEspece] = useState<string | null>(null);
  const [creatingFor, setCreatingFor] = useState<{ logementId: string; date: string } | null>(null);
  const [chipStepFor, setChipStepFor] = useState<{ logementId: string; date: string } | null>(null);
  const [chipInput, setChipInput] = useState('');
  const [chipSearching, setChipSearching] = useState(false);
  const [prefill, setPrefill] = useState<PensionEntreePrefill | undefined>(undefined);

  const effectiveUid = employerUid || user?.uid;

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
    if (!employerUid && userData && !isPension) { router.push('/'); return; }
  }, [user, userData, isPension, authLoading, router, employerUid]);

  // Vue employé : vérifie la permission read_planning_pension pour cet employeur
  useEffect(() => {
    if (!employerUid || !user) return;
    (async () => {
      const { data: emp } = await supabase.from('employes')
        .select('eleveur_profile_id').eq('uid_employe', user.uid).eq('uid_eleveur', employerUid).eq('actif', true).maybeSingle();
      if (!emp?.eleveur_profile_id) { router.push('/mes-employeurs'); return; }
      const { data: perm } = await supabase.from('employe_permissions')
        .select('permission').eq('eleveur_profile_id', emp.eleveur_profile_id)
        .eq('employe_profile_id', activeProfileId).eq('permission', 'read_planning_pension').maybeSingle();
      if (!perm) { router.push('/mes-employeurs'); return; }
      const { data: u } = await supabase.from('user_profiles').select('firstname, lastname, nom, profile_type').eq('uid', employerUid).eq('is_main', true).maybeSingle();
      setEmployerNom(u?.profile_type === 'eleveur' ? (u?.nom ?? 'Employeur') : `${u?.firstname ?? ''} ${u?.lastname ?? ''}`.trim());
      setEmployerOk(true);
    })();
  }, [employerUid, user, activeProfileId, router]);

  const load = useCallback(async () => {
    if (!effectiveUid || !employerOk) return;
    const windowEnd = new Date(windowStart); windowEnd.setDate(windowEnd.getDate() + DAYS);
    const windowStartStr = windowStart.toISOString().slice(0, 10);
    const windowEndStr = windowEnd.toISOString().slice(0, 10);
    const [{ data: log }, { data: ent }, { data: net }] = await Promise.all([
      supabase.from('enclos_chenil').select('id, nom, type, capacite, especes').eq('uid_eleveur', effectiveUid).order('nom'),
      supabase.from('pension_entrees').select('id, pro_uid, animal_nom, espece, race, puce, proprietaire_nom, proprietaire_contact, proprietaire_email, proprietaire_adresse, logement_id, animal_id, seul_dans_logement, statut, date_entree, date_sortie_prevue, date_sortie_effective, notes, created_at')
        .eq('pro_uid', effectiveUid).lte('date_entree', windowEndStr).order('date_entree'),
      supabase.from('pension_nettoyages').select('logement_id, date').eq('uid_eleveur', effectiveUid)
        .gte('date', windowStartStr).lte('date', windowEndStr),
    ]);
    setLogements(log ?? []);
    setEntrees((ent ?? []).filter(e => !e.date_sortie_effective || new Date(e.date_sortie_effective) >= windowStart));
    setNettoyages(new Set((net ?? []).map(n => `${n.logement_id}|${n.date}`)));
    setLoading(false);
  }, [effectiveUid, employerOk, windowStart]);

  useEffect(() => { load(); }, [load]);

  async function toggleNettoyage(logementId: string, day: Date) {
    if (!effectiveUid || readOnly) return;
    const dateStr = day.toISOString().slice(0, 10);
    const key = `${logementId}|${dateStr}`;
    const wasClean = nettoyages.has(key);
    setNettoyages(prev => { const next = new Set(prev); if (wasClean) next.delete(key); else next.add(key); return next; });
    if (wasClean) {
      await supabase.from('pension_nettoyages').delete().eq('logement_id', logementId).eq('date', dateStr);
    } else {
      await supabase.from('pension_nettoyages').insert({ logement_id: logementId, uid_eleveur: effectiveUid, date: dateStr });
    }
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

  const estNettoye = (logementId: string, day: Date) => nettoyages.has(`${logementId}|${day.toISOString().slice(0, 10)}`);

  if (!user || !userData) return null;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <h1 className="text-2xl font-bold font-galey text-teal-800">
          {readOnly ? `Planning — ${employerNom || 'employeur'}` : 'Planning occupation'}
        </h1>
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
                    return [
                      ...rows.map((rowEntrees, slot) => (
                        <tr key={`${l.id}-${slot}`}>
                          <td className="sticky left-0 bg-white z-10 px-3 py-2 text-sm font-galey font-semibold text-gray-800 border-b border-gray-50 truncate max-w-32">
                            {slot === 0 && <span className="truncate">{l.nom}</span>}
                          </td>
                          {days.map(d => {
                            const solo = entryForDay(soloEntrees, d);
                            const e = solo ?? entryForDay(rowEntrees, d);
                            const st = e ? computeStatut(e, today) : null;
                            return (
                              <td key={d.toISOString()} className="border-b border-gray-50 p-1">
                                {e && st ? (
                                  <button
                                    onClick={() => readOnly ? setReadOnlyEntree(e) : setEditingEntree(e)}
                                    title={e.animal_nom}
                                    className="w-full h-6 rounded relative"
                                    style={{ backgroundColor: STATUT_COLOR[st], border: solo ? '1.5px solid #ef4444' : undefined }}
                                  >
                                    {solo && <span className="absolute inset-0 flex items-center justify-center text-[9px] text-white">🔒</span>}
                                  </button>
                                ) : readOnly ? (
                                  <div className="w-full h-6" />
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
                      )),
                      ...(readOnly ? [] : [<tr key={`${l.id}-nettoyage`}>
                        <td className="sticky left-0 bg-white z-10 px-3 py-1 text-[10px] font-galey text-gray-400 border-b border-gray-50">
                          Nettoyage
                        </td>
                        {days.map(d => (
                          <td key={d.toISOString()} className="border-b border-gray-50 p-1 text-center">
                            <button onClick={() => toggleNettoyage(l.id, d)}
                              title={estNettoye(l.id, d) ? 'Nettoyé' : 'Marquer comme nettoyé'}
                              className="w-full h-5 flex items-center justify-center">
                              {estNettoye(l.id, d)
                                ? <span className="text-green-600 text-xs">✓</span>
                                : <span className="text-gray-300 text-xs">🧹</span>}
                            </button>
                          </td>
                        ))}
                      </tr>]),
                    ];
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

      {readOnlyEntree && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4" onClick={() => setReadOnlyEntree(null)}>
          <div className="bg-white rounded-2xl w-full max-w-sm p-5" onClick={e => e.stopPropagation()}>
            <h3 className="font-bold font-galey text-lg text-gray-900 mb-3">{readOnlyEntree.animal_nom}</h3>
            <p className="text-sm font-galey text-gray-600">Propriétaire : {readOnlyEntree.proprietaire_nom ?? '—'}</p>
            <p className="text-sm font-galey text-gray-600">Entrée : {readOnlyEntree.date_entree}</p>
            <p className="text-sm font-galey text-gray-600">Sortie prévue : {readOnlyEntree.date_sortie_prevue ?? '—'}</p>
            <div className="mt-4 flex gap-2">
              {readOnlyEntree.animal_id && (
                <a href={`/pension/fiche/${readOnlyEntree.animal_id}`}
                  className="flex-1 text-center text-sm font-galey font-semibold bg-[#0C5C6C] text-white rounded-xl py-2 hover:bg-[#094F5D]">
                  Voir la fiche
                </a>
              )}
              <button onClick={() => setReadOnlyEntree(null)}
                className="flex-1 text-sm font-galey font-semibold border border-gray-200 rounded-xl py-2 hover:bg-gray-50">
                Fermer
              </button>
            </div>
          </div>
        </div>
      )}

      {chipStepFor && !readOnly && (
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

      {creatingFor && user && !readOnly && (
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

export default function PensionPlanningPage() {
  return (
    <Suspense>
      <PensionPlanningPageInner />
    </Suspense>
  );
}
