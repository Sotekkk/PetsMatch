'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

// ── Types ──────────────────────────────────────────────────────────────────────

interface TacheManuelle {
  id: string;
  titre: string;
  date: string;
  statut: string;
  assigne_a?: string | null;
  notes?: string | null;
  assigne_nom?: string;
}

interface PlanTache {
  id: string;
  label: string;
  date_prevue: string;
  statut: string;
  type_acte?: string | null;
  animal_nom?: string | null;
  etape_id?: string | null;
  assigned_to?: string | null;
  assigne_nom?: string;
}

interface ProtoGroupe {
  key: string;
  items: PlanTache[];
  label: string;
  typeActe: string;
  date: string;
  assigneNom?: string;
}

interface Employe {
  id: string;
  uid_employe: string;
  nom: string;
  photo?: string | null;
}

// ── Constantes ────────────────────────────────────────────────────────────────

const ACTE_EMOJIS: Record<string, string> = {
  vermifuge: '💊', vaccination: '💉', antiparasitaire: '🛡️',
  traitement: '🩺', visite: '🏥', nettoyage: '🧹',
  promenade: '🦮', socialisation: '🐾', toilettage: '✂️', autre: '📋',
};

function toDateStr(d: Date) { return d.toISOString().split('T')[0]; }

function groupProtos(pts: PlanTache[]): ProtoGroupe[] {
  const map = new Map<string, PlanTache[]>();
  for (const t of pts) {
    const date = (t.date_prevue ?? '').split('T')[0];
    const key  = `${t.etape_id ?? `solo_${t.id}`}_${date}`;
    if (!map.has(key)) map.set(key, []);
    map.get(key)!.push(t);
  }
  return [...map.entries()].map(([key, items]) => ({
    key,
    items,
    label:     (items[0]?.label ?? '').split(' — ')[0],
    typeActe:  items[0]?.type_acte ?? '',
    date:      (items[0]?.date_prevue ?? '').split('T')[0],
    assigneNom: items[0]?.assigne_nom,
  })).sort((a, b) => a.date.localeCompare(b.date));
}

function dateLabel(d: string): string {
  if (!d) return 'Sans date';
  const today = toDateStr(new Date());
  const tmr   = toDateStr(new Date(Date.now() + 86400000));
  if (d === today) return "Aujourd'hui";
  if (d === tmr)   return 'Demain';
  return new Date(d + 'T12:00:00').toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
}

// ════════════════════════════════════════════════════════════════════════════════

export default function EmployesPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const [tab, setTab] = useState<'employes' | 'taches'>('taches');
  const [employes, setEmployes] = useState<Employe[]>([]);
  const [tachesM, setTachesM] = useState<TacheManuelle[]>([]);
  const [planTaches, setPlanTaches] = useState<PlanTache[]>([]);
  const [loadingData, setLoadingData] = useState(true);
  const [showDone, setShowDone] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState<{ label: string; onConfirm: () => void } | null>(null);
  const [protoModal, setProtoModal] = useState<ProtoGroupe | null>(null);

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [user, loading, router]);

  const load = useCallback(async () => {
    if (!user) return;
    setLoadingData(true);
    try {
      // Employés
      const { data: empsRaw } = await supabase.from('employes')
        .select('id,uid_employe').eq('uid_eleveur', user.uid).eq('actif', true);
      const empsData: Employe[] = [];
      const uidToNom: Record<string, string> = {};
      for (const e of empsRaw ?? []) {
        const { data: u } = await supabase.from('users')
          .select('uid,firstname,lastname,name_elevage,is_elevage,profile_picture_url,profile_picture_url_elevage')
          .eq('uid', e.uid_employe).maybeSingle();
        if (u) {
          const nom = u.is_elevage ? (u.name_elevage ?? 'Élevage') : `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim();
          uidToNom[u.uid] = nom;
          empsData.push({
            id: e.id.toString(),
            uid_employe: e.uid_employe,
            nom,
            photo: u.is_elevage ? u.profile_picture_url_elevage : u.profile_picture_url,
          });
        }
      }
      setEmployes(empsData);

      // Tâches manuelles
      const { data: tm } = await supabase.from('taches_elevage')
        .select('id,titre,date,statut,assigne_a,notes').eq('uid_eleveur', user.uid).order('date');
      const tachesResolved = (tm ?? []).map(t => ({
        ...t,
        assigne_nom: t.assigne_a ? (uidToNom[t.assigne_a] ?? 'Employé') : undefined,
      })) as TacheManuelle[];
      setTachesM(tachesResolved);

      // Tâches protocole — à faire (J-7 → J+90) + terminées (30j)
      const pastStr   = toDateStr(new Date(Date.now() - 7 * 86400000));
      const futureStr = toDateStr(new Date(Date.now() + 90 * 86400000));
      const [{ data: pt1 }, { data: pt2 }] = await Promise.all([
        supabase.from('plan_taches')
          .select('id,label,date_prevue,statut,type_acte,animal_nom,etape_id,assigned_to')
          .eq('uid_eleveur', user.uid).not('statut', 'eq', 'fait')
          .gte('date_prevue', pastStr).lte('date_prevue', futureStr).limit(2000),
        supabase.from('plan_taches')
          .select('id,label,date_prevue,statut,type_acte,animal_nom,etape_id,assigned_to')
          .eq('uid_eleveur', user.uid).eq('statut', 'fait')
          .gte('date_prevue', pastStr).limit(500),
      ]);
      const seen = new Set<string>();
      const allPt = [...(pt1 ?? []), ...(pt2 ?? [])].filter(t => { if (seen.has(t.id)) return false; seen.add(t.id); return true; });
      const ptResolved = allPt.map(t => ({
        ...t,
        assigne_nom: t.assigned_to ? (uidToNom[t.assigned_to] ?? 'Employé') : undefined,
      })) as PlanTache[];
      setPlanTaches(ptResolved);
    } catch (_) {}
    setLoadingData(false);
  }, [user]);

  useEffect(() => { if (user) load(); }, [user, load]);

  const deleteManuel = useCallback(async (t: TacheManuelle) => {
    await supabase.from('taches_elevage').delete().eq('id', t.id);
    load();
  }, [load]);

  const deleteProtoGroupe = useCallback(async (g: ProtoGroupe) => {
    const ids = g.items.map(t => t.id);
    await supabase.from('plan_taches').delete()
      .in('id', ids)
      .gte('date_prevue', `${g.date}T00:00:00`)
      .lte('date_prevue', `${g.date}T23:59:59`);
    load();
  }, [load]);

  const deleteProtoItem = useCallback(async (t: PlanTache) => {
    const date = (t.date_prevue ?? '').split('T')[0];
    await supabase.from('plan_taches').delete()
      .eq('id', t.id)
      .gte('date_prevue', `${date}T00:00:00`)
      .lte('date_prevue', `${date}T23:59:59`);
    load();
    setProtoModal(null);
  }, [load]);

  const toggleManuel = useCallback(async (t: TacheManuelle) => {
    const newStatut = t.statut === 'fait' ? 'a_faire' : 'fait';
    await supabase.from('taches_elevage').update({ statut: newStatut }).eq('id', t.id);
    load();
  }, [load]);

  const toggleProtoItem = useCallback(async (t: PlanTache) => {
    const newStatut = t.statut === 'fait' ? 'en_attente' : 'fait';
    await supabase.from('plan_taches').update({ statut: newStatut }).eq('id', t.id);
    load();
    setProtoModal(prev => prev ? {
      ...prev,
      items: prev.items.map(it => it.id === t.id ? { ...it, statut: newStatut } : it),
    } : null);
  }, [load]);

  if (loading || !user) return (
    <div className="flex justify-center items-center h-64">
      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-teal-600" />
    </div>
  );

  // ── Grouper et filtrer ─────────────────────────────────────────────────────
  const groupes = groupProtos(planTaches);
  const groupesAffichees = showDone
    ? groupes.filter(g => g.items.every(t => t.statut === 'fait'))
    : groupes.filter(g => g.items.some(t => t.statut !== 'fait'));
  const tachesMFiltrees = showDone
    ? tachesM.filter(t => t.statut === 'fait')
    : tachesM.filter(t => t.statut !== 'fait');

  // Regrouper par date pour les sections
  const allByDate = new Map<string, { protos: ProtoGroupe[]; manuelles: TacheManuelle[] }>();
  const addDate = (d: string) => { if (!allByDate.has(d)) allByDate.set(d, { protos: [], manuelles: [] }); };
  for (const g of groupesAffichees) { addDate(g.date); allByDate.get(g.date)!.protos.push(g); }
  for (const t of tachesMFiltrees) { addDate(t.date); allByDate.get(t.date)!.manuelles.push(t); }
  const sortedDates = [...allByDate.keys()].sort();

  const TrashIcon = () => (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
        d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
    </svg>
  );

  return (
    <div className="max-w-2xl mx-auto px-4 py-6">

      {/* Header */}
      <h1 className="text-2xl font-bold text-gray-800 mb-6">Mon équipe</h1>

      {/* Tabs */}
      <div className="flex border-b border-gray-200 mb-6">
        {(['employes', 'taches'] as const).map(t => (
          <button key={t} onClick={() => setTab(t)}
            className={`px-5 py-2.5 text-sm font-semibold transition-colors border-b-2 ${
              tab === t ? 'border-teal-600 text-teal-700' : 'border-transparent text-gray-500 hover:text-gray-700'
            }`}>
            {t === 'employes' ? 'Employés' : 'Tâches'}
          </button>
        ))}
      </div>

      {loadingData ? (
        <div className="flex justify-center py-12">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-teal-600" />
        </div>
      ) : tab === 'employes' ? (

        // ── Onglet Employés ─────────────────────────────────────────────────
        <div className="space-y-3">
          {employes.length === 0 ? (
            <div className="text-center py-16 text-gray-400">
              <div className="text-4xl mb-3">👥</div>
              <p>Aucun employé dans votre élevage</p>
            </div>
          ) : employes.map(e => (
            <div key={e.id} className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 flex items-center gap-3">
              <div className="w-10 h-10 rounded-full bg-teal-50 flex items-center justify-center flex-shrink-0 overflow-hidden">
                {e.photo
                  ? <img src={e.photo} alt={e.nom} className="w-full h-full object-cover" />
                  : <span className="text-teal-600 font-bold text-sm">{e.nom[0]?.toUpperCase()}</span>
                }
              </div>
              <span className="flex-1 font-semibold text-gray-800 text-sm">{e.nom}</span>
            </div>
          ))}
        </div>

      ) : (

        // ── Onglet Tâches ───────────────────────────────────────────────────
        <div>
          {/* Filtres */}
          <div className="flex gap-2 mb-5">
            {[{ label: 'À faire', done: false }, { label: 'Terminées', done: true }].map(f => (
              <button key={f.label} onClick={() => setShowDone(f.done)}
                className={`px-4 py-1.5 rounded-full text-xs font-semibold border transition-colors ${
                  showDone === f.done
                    ? 'bg-teal-600 border-teal-600 text-white'
                    : 'bg-white border-gray-200 text-gray-500 hover:border-gray-300'
                }`}>
                {f.label}
              </button>
            ))}
          </div>

          {sortedDates.length === 0 ? (
            <div className="text-center py-16 text-gray-400">
              <div className="text-4xl mb-3">{showDone ? '✅' : '📋'}</div>
              <p>{showDone ? 'Aucune tâche terminée' : 'Aucune tâche à faire'}</p>
            </div>
          ) : sortedDates.map(date => {
            const { protos, manuelles } = allByDate.get(date)!;
            const isPast = date < toDateStr(new Date()) && date !== toDateStr(new Date());
            return (
              <div key={date} className="mb-6">
                {/* Section date */}
                <div className="flex items-center gap-3 mb-3">
                  <span className={`text-xs font-bold px-3 py-1 rounded-full border capitalize ${
                    isPast ? 'bg-red-50 border-red-200 text-red-500'
                           : 'bg-teal-50 border-teal-200 text-teal-700'
                  }`}>
                    {dateLabel(date)}
                  </span>
                  <div className="flex-1 h-px bg-gray-100" />
                </div>

                <div className="space-y-2">
                  {/* Groupes protocole */}
                  {protos.map(g => {
                    const done  = g.items.filter(t => t.statut === 'fait').length;
                    const total = g.items.length;
                    const pct   = total > 0 ? done / total : 0;
                    const emoji = ACTE_EMOJIS[g.typeActe] ?? '📋';
                    const allDone = done === total;
                    return (
                      <div key={g.key} className="bg-white rounded-2xl shadow-sm border border-teal-50 p-4">
                        <div className="flex items-center gap-3">
                          <div className="w-10 h-10 rounded-xl bg-teal-50 flex items-center justify-center text-xl flex-shrink-0 cursor-pointer"
                               onClick={() => setProtoModal(g)}>
                            {emoji}
                          </div>
                          <div className="flex-1 min-w-0 cursor-pointer" onClick={() => setProtoModal(g)}>
                            <p className={`font-semibold text-sm ${allDone ? 'line-through text-gray-400' : 'text-gray-800'}`}>
                              {g.label}
                            </p>
                            <div className="flex items-center gap-2 mt-0.5 flex-wrap">
                              <span className="text-xs text-blue-600 bg-blue-50 px-2 py-0.5 rounded font-semibold">Protocole</span>
                              <span className={`text-xs font-semibold ${allDone ? 'text-gray-400' : 'text-teal-600'}`}>
                                {done}/{total}
                              </span>
                              {g.assigneNom && (
                                <span className="text-xs text-gray-400">👤 {g.assigneNom}</span>
                              )}
                            </div>
                          </div>
                          <div className="flex items-center gap-1 flex-shrink-0">
                            <button
                              onClick={() => setConfirmDelete({
                                label: `Supprimer le protocole "${g.label}" du ${dateLabel(g.date)} ?`,
                                onConfirm: () => deleteProtoGroupe(g),
                              })}
                              className="p-1.5 rounded-lg hover:bg-red-50 text-gray-300 hover:text-red-400 transition-colors"
                            >
                              <TrashIcon />
                            </button>
                            <span className="text-gray-300 text-base cursor-pointer" onClick={() => setProtoModal(g)}>›</span>
                          </div>
                        </div>
                        {total > 1 && (
                          <div className="mt-3">
                            <div className="w-full bg-gray-100 rounded-full h-1.5">
                              <div className={`h-1.5 rounded-full transition-all ${allDone ? 'bg-teal-400' : 'bg-orange-400'}`}
                                   style={{ width: `${pct * 100}%` }} />
                            </div>
                          </div>
                        )}
                      </div>
                    );
                  })}

                  {/* Tâches manuelles */}
                  {manuelles.map(t => {
                    const isDone = t.statut === 'fait';
                    return (
                      <div key={t.id} className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 flex items-center gap-3">
                        <button
                          onClick={() => toggleManuel(t)}
                          className={`w-6 h-6 rounded border-2 flex items-center justify-center flex-shrink-0 transition-colors ${
                            isDone ? 'bg-green-500 border-green-500' : 'border-gray-300 hover:border-teal-400'
                          }`}
                        >
                          {isDone && <span className="text-white text-xs font-bold leading-none">✓</span>}
                        </button>
                        <div className="flex-1 min-w-0">
                          <p className={`text-sm font-medium ${isDone ? 'line-through text-gray-400' : 'text-gray-800'}`}>
                            {t.titre}
                          </p>
                          {t.assigne_nom && (
                            <p className="text-xs text-gray-400 mt-0.5">👤 {t.assigne_nom}</p>
                          )}
                        </div>
                        <button
                          onClick={() => setConfirmDelete({
                            label: `Supprimer la tâche "${t.titre}" ?`,
                            onConfirm: () => deleteManuel(t),
                          })}
                          className="p-1.5 rounded-lg hover:bg-red-50 text-gray-300 hover:text-red-400 transition-colors flex-shrink-0"
                        >
                          <TrashIcon />
                        </button>
                      </div>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Modal détail protocole */}
      {protoModal && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-end justify-center sm:items-center p-4"
             onClick={e => { if (e.target === e.currentTarget) setProtoModal(null); }}>
          <div className="bg-white rounded-2xl w-full max-w-md max-h-[80vh] flex flex-col">
            <div className="p-5 border-b">
              <div className="flex items-start gap-3">
                <span className="text-2xl flex-shrink-0">{ACTE_EMOJIS[protoModal.typeActe] ?? '📋'}</span>
                <div className="flex-1 min-w-0">
                  <h3 className="font-bold text-gray-800 text-base">{protoModal.label}</h3>
                  <p className="text-xs text-gray-400 mt-0.5 capitalize">{dateLabel(protoModal.date)}</p>
                </div>
                <button
                  onClick={() => setConfirmDelete({
                    label: `Supprimer tout le protocole "${protoModal.label}" du jour ?`,
                    onConfirm: () => { deleteProtoGroupe(protoModal); setProtoModal(null); },
                  })}
                  className="p-1.5 rounded-lg hover:bg-red-50 text-gray-300 hover:text-red-400 transition-colors"
                >
                  <TrashIcon />
                </button>
                <button onClick={() => setProtoModal(null)}
                  className="text-gray-400 hover:text-gray-600 text-2xl leading-none flex-shrink-0 ml-1">×</button>
              </div>
              <div className="mt-3">
                {(() => {
                  const done = protoModal.items.filter(t => t.statut === 'fait').length;
                  const pct  = protoModal.items.length > 0 ? done / protoModal.items.length : 0;
                  return (
                    <>
                      <div className="w-full bg-gray-100 rounded-full h-2">
                        <div className={`h-2 rounded-full transition-all ${done === protoModal.items.length ? 'bg-teal-500' : 'bg-orange-400'}`}
                             style={{ width: `${pct * 100}%` }} />
                      </div>
                      <p className="text-right text-xs text-gray-400 mt-1">{done}/{protoModal.items.length}</p>
                    </>
                  );
                })()}
              </div>
            </div>
            <div className="overflow-y-auto flex-1">
              {protoModal.items.map(t => {
                const isDone = t.statut === 'fait';
                const nom = t.animal_nom?.trim() || 'Animal';
                return (
                  <div key={t.id} className="flex items-center gap-3 px-5 py-3.5 border-b border-gray-50 last:border-0 hover:bg-gray-50">
                    <button onClick={() => toggleProtoItem(t)}
                      className={`w-5 h-5 rounded border-2 flex items-center justify-center flex-shrink-0 transition-colors ${
                        isDone ? 'bg-teal-600 border-teal-600' : 'border-gray-300 hover:border-teal-400'
                      }`}>
                      {isDone && <span className="text-white text-xs font-bold leading-none">✓</span>}
                    </button>
                    <span className="text-sm mr-0.5">🐾</span>
                    <span className={`text-sm font-medium flex-1 cursor-pointer ${isDone ? 'line-through text-gray-400' : 'text-gray-800'}`}
                          onClick={() => toggleProtoItem(t)}>
                      {nom}
                    </span>
                    <button
                      onClick={() => setConfirmDelete({
                        label: `Supprimer "${nom}" de ce protocole ?`,
                        onConfirm: () => deleteProtoItem(t),
                      })}
                      className="p-1 rounded hover:bg-red-50 text-gray-300 hover:text-red-400 transition-colors"
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
            <div className="p-4 border-t">
              <button onClick={() => setProtoModal(null)}
                className="w-full py-2.5 bg-teal-600 text-white rounded-xl text-sm font-semibold hover:bg-teal-700">
                Fermer
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Dialog confirmation suppression */}
      {confirmDelete && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl p-6 max-w-sm w-full shadow-xl">
            <p className="text-sm font-semibold text-gray-800 mb-5 text-center">{confirmDelete.label}</p>
            <div className="flex gap-3">
              <button onClick={() => setConfirmDelete(null)}
                className="flex-1 py-2.5 border border-gray-200 rounded-xl text-sm text-gray-600 hover:bg-gray-50 font-medium">
                Annuler
              </button>
              <button onClick={() => { confirmDelete.onConfirm(); setConfirmDelete(null); }}
                className="flex-1 py-2.5 bg-red-500 text-white rounded-xl text-sm font-semibold hover:bg-red-600">
                Supprimer
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
