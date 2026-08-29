'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfileState } from '@/hooks/useActiveProfile';

// ── Types ──────────────────────────────────────────────────────────────────────

interface TacheManuelle {
  id: string;
  titre: string;
  date: string;
  statut: string;
  assigne_a?: string | null;
  notes?: string | null;
  animal_nom?: string | null;
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
  assignedTo?: string | null;
}

interface Employe {
  id: string;
  uid_employe: string;
  nom: string;
  photo?: string | null;
  employeProfileId?: string | null;
  eleveurProfileId?: string | null;
}

const PERMS_LIST = [
  { key: 'write_animaux',    label: 'Modifier les animaux',  desc: 'Éditer fiches, photos, identité' },
  { key: 'write_sante',      label: 'Carnet de santé',       desc: 'Vaccins, traitements, poids' },
  { key: 'write_repro',      label: 'Suivi reproducteur',    desc: 'Saillies, gestations, portées' },
  { key: 'write_planning',   label: 'Planning & tâches',     desc: 'Créer et modifier les tâches' },
  { key: 'write_protocoles', label: 'Créer des protocoles',  desc: 'Créer ses propres protocoles, auto-attribués et visibles par l\'employeur' },
  { key: 'write_inventaire', label: 'Inventaire',            desc: 'Gérer les stocks et alertes' },
  { key: 'write_notes',      label: 'Notes',                 desc: 'Ajouter des notes internes' },
  { key: 'read_planning_pension', label: 'Planning pension', desc: 'Voir le planning d\'occupation et les fiches des animaux en pension' },
] as const;

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
    assignedTo: items[0]?.assigned_to ?? null,
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
  const { id: profileId, loaded: profileLoaded } = useActiveProfileState();
  const router = useRouter();
  const [tab, setTab] = useState<'employes' | 'taches'>('taches');
  const [employes, setEmployes] = useState<Employe[]>([]);
  const [tachesM, setTachesM] = useState<TacheManuelle[]>([]);
  const [planTaches, setPlanTaches] = useState<PlanTache[]>([]);
  const [loadingData, setLoadingData] = useState(true);
  const [showDone, setShowDone] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState<{ label: string; onConfirm: () => void } | null>(null);
  const [protoModal, setProtoModal] = useState<ProtoGroupe | null>(null);
  const [permsModal, setPermsModal] = useState<Employe | null>(null);
  const [permsData, setPermsData] = useState<Set<string>>(new Set());
  const [permsLoading, setPermsLoading] = useState(false);
  const [permsSaving, setPermsSaving] = useState(false);
  const [filterEmployeeUid, setFilterEmployeeUid] = useState<string | null>(null);
  const [filterEmployeeNom, setFilterEmployeeNom] = useState<string>('');
  const [showAdd, setShowAdd] = useState(false);
  const [tacheModal, setTacheModal] = useState<{ mode: 'create' } | { mode: 'edit'; tache: TacheManuelle } | null>(null);
  const [isPension, setIsPension] = useState(false);
  const [assignProtoGroup, setAssignProtoGroup] = useState<ProtoGroupe | null>(null);

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [user, loading, router]);

  // « Planning pension » n'est proposé que si l'employeur est une pension.
  useEffect(() => {
    if (!user || !profileLoaded) return;
    (async () => {
      const q = profileId
        ? supabase.from('user_profiles').select('cat_pro').eq('id', profileId).maybeSingle()
        : supabase.from('user_profiles').select('cat_pro').eq('uid', user.uid).eq('is_main', true).maybeSingle();
      const { data } = await q;
      setIsPension((data as { cat_pro?: string } | null)?.cat_pro === 'pension');
    })();
  }, [user, profileId, profileLoaded]);

  const permsList = PERMS_LIST.filter(p => p.key !== 'read_planning_pension' || isPension);

  const load = useCallback(async () => {
    if (!user || !profileLoaded) return;
    setLoadingData(true);
    try {
      // Employés
      let empQ = supabase.from('employes').select('id,uid_employe,employe_profile_id,eleveur_profile_id').eq('actif', true);
      if (profileId) {
        empQ = empQ.eq('eleveur_profile_id', profileId) as typeof empQ;
      } else {
        empQ = empQ.eq('uid_eleveur', user.uid) as typeof empQ;
      }
      const { data: empsRaw } = await empQ;
      const empsData: Employe[] = [];
      const uidToNom: Record<string, string> = {};
      for (const e of empsRaw ?? []) {
        const { data: u } = await supabase.from('user_profiles')
          .select('uid,firstname,lastname,nom,profile_type,avatar_url,profile_picture_url_pro')
          .eq('uid', e.uid_employe).eq('is_main', true).maybeSingle();
        if (u) {
          const isElevage = u.profile_type === 'eleveur';
          const nom = isElevage ? (u.nom ?? 'Élevage') : `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim();
          uidToNom[u.uid] = nom;
          empsData.push({
            id: e.id.toString(),
            uid_employe: e.uid_employe,
            nom,
            photo: isElevage ? u.profile_picture_url_pro : u.avatar_url,
            employeProfileId: e.employe_profile_id as string | null,
            eleveurProfileId: e.eleveur_profile_id as string | null,
          });
        }
      }
      setEmployes(empsData);

      // Tâches manuelles
      let tmQ = supabase.from('taches_elevage').select('id,titre,date,statut,assigne_a,notes,animal_nom').order('date');
      if (profileId) {
        tmQ = tmQ.eq('eleveur_profile_id', profileId) as typeof tmQ;
      } else {
        tmQ = tmQ.eq('uid_eleveur', user.uid) as typeof tmQ;
      }
      const { data: tm } = await tmQ;
      const tachesResolved = (tm ?? []).map(t => ({
        ...t,
        assigne_nom: t.assigne_a ? (uidToNom[t.assigne_a] ?? 'Employé') : undefined,
      })) as TacheManuelle[];
      setTachesM(tachesResolved);

      // Tâches protocole — à faire (J-7 → J+90) + terminées (30j)
      const pastStr   = toDateStr(new Date(Date.now() - 7 * 86400000));
      const futureStr = toDateStr(new Date(Date.now() + 90 * 86400000));
      const ptFilter = profileId
        ? (q: ReturnType<typeof supabase.from>) => (q as ReturnType<typeof supabase.from>).eq('eleveur_profile_id', profileId)
        : (q: ReturnType<typeof supabase.from>) => (q as ReturnType<typeof supabase.from>).eq('uid_eleveur', user.uid);
      const [{ data: pt1 }, { data: pt2 }] = await Promise.all([
        ptFilter(supabase.from('plan_taches').select('id,label,date_prevue,statut,type_acte,animal_nom,etape_id,assigned_to'))
          .not('statut', 'eq', 'fait').gte('date_prevue', pastStr).lte('date_prevue', futureStr).limit(2000),
        ptFilter(supabase.from('plan_taches').select('id,label,date_prevue,statut,type_acte,animal_nom,etape_id,assigned_to'))
          .eq('statut', 'fait').gte('date_prevue', pastStr).limit(500),
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
  }, [user, profileId, profileLoaded]);

  useEffect(() => { if (user) load(); }, [user, load]);

  const revoquer = useCallback(async (e: Employe) => {
    await supabase.from('employes').update({ actif: false }).eq('id', e.id);
    await supabase.from('notifications').insert({
      uid: e.uid_employe, type: 'employee_revoked',
      title: 'Accès retiré',
      body: 'Vous avez été retiré de l\'équipe',
      ...(e.employeProfileId ? { profile_id: e.employeProfileId } : {}),
      data: { eleveurUid: user?.uid },
      read: false,
    });
    load();
  }, [user, load]);

  const openPerms = useCallback(async (e: Employe) => {
    setPermsModal(e);
    setPermsLoading(true);
    setPermsData(new Set());
    if (e.employeProfileId && e.eleveurProfileId) {
      const { data } = await supabase.from('employe_permissions')
        .select('permission')
        .eq('eleveur_profile_id', e.eleveurProfileId)
        .eq('employe_profile_id', e.employeProfileId);
      setPermsData(new Set((data ?? []).map((r: { permission: string }) => r.permission)));
    }
    setPermsLoading(false);
  }, []);

  const savePerms = useCallback(async () => {
    if (!permsModal?.employeProfileId || !permsModal?.eleveurProfileId) return;
    setPermsSaving(true);
    await supabase.from('employe_permissions')
      .delete()
      .eq('eleveur_profile_id', permsModal.eleveurProfileId)
      .eq('employe_profile_id', permsModal.employeProfileId);
    if (permsData.size > 0) {
      await supabase.from('employe_permissions').insert(
        [...permsData].map(p => ({
          eleveur_profile_id: permsModal.eleveurProfileId,
          employe_profile_id: permsModal.employeProfileId,
          permission: p,
        }))
      );
    }
    setPermsSaving(false);
    setPermsModal(null);
  }, [permsModal, permsData]);

  // Assigne (ou retire) tout un groupe de tâches de protocole à un employé,
  // avec notification — miroir de _assignPlanTache de l'appli.
  const assignProto = useCallback(async (groupe: ProtoGroupe, employeUid: string) => {
    if (!user) return;
    const ids = groupe.items.map(t => t.id);
    const newUid = employeUid || null;

    let newProfileId: string | null = null;
    if (newUid) {
      const { data } = await supabase.from('user_profiles')
        .select('id').eq('uid', newUid).eq('profile_type', 'particulier').maybeSingle();
      newProfileId = (data?.id as string | undefined) ?? null;
    }

    await supabase.from('plan_taches')
      .update({ assigned_to: newUid, assigned_profile_id: newProfileId })
      .in('id', ids);

    if (newUid) {
      const { data: prof } = await supabase.from('user_profiles')
        .select('nom, firstname, lastname').eq('uid', user.uid).eq('is_main', true).maybeSingle();
      const nomElevage = ((prof?.nom as string | undefined)?.trim())
        || `${prof?.firstname ?? ''} ${prof?.lastname ?? ''}`.trim()
        || 'Votre élevage';
      const total = groupe.items.length;
      const titre = total > 1 ? `${groupe.label} (${total} animaux)` : groupe.label;
      await supabase.from('notifications').insert({
        uid: newUid,
        type: 'tache',
        title: 'Nouvelle tâche assignée',
        body: `${nomElevage} vous a assigné : ${titre}`,
        ...(newProfileId ? { profile_id: newProfileId } : {}),
        data: { eleveurUid: user.uid },
        read: false,
      });
    }

    setAssignProtoGroup(null);
    load();
  }, [user, load]);

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
  let groupesAffichees = showDone
    ? groupes.filter(g => g.items.every(t => t.statut === 'fait'))
    : groupes.filter(g => g.items.some(t => t.statut !== 'fait'));
  let tachesMFiltrees = showDone
    ? tachesM.filter(t => t.statut === 'fait')
    : tachesM.filter(t => t.statut !== 'fait');
  // Filtre "agenda d'un employé précis" (clic depuis l'onglet Employés) :
  // les tâches qu'on lui a données (manuelles) + celles qu'il a via ses
  // propres protocoles (auto-attribuées).
  if (filterEmployeeUid) {
    groupesAffichees = groupesAffichees.filter(g => g.items.some(t => t.assigned_to === filterEmployeeUid));
    tachesMFiltrees = tachesMFiltrees.filter(t => t.assigne_a === filterEmployeeUid);
  }

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
            <div key={e.id}
              onClick={() => { setFilterEmployeeUid(e.uid_employe); setFilterEmployeeNom(e.nom); setTab('taches'); }}
              className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 flex items-center gap-3 cursor-pointer hover:border-teal-200 transition-colors">
              <div className="w-10 h-10 rounded-full bg-teal-50 flex items-center justify-center flex-shrink-0 overflow-hidden">
                {e.photo
                  ? <img src={e.photo} alt={e.nom} className="w-full h-full object-cover" />
                  : <span className="text-teal-600 font-bold text-sm">{e.nom[0]?.toUpperCase()}</span>
                }
              </div>
              <span className="flex-1 font-semibold text-gray-800 text-sm">{e.nom}</span>
              <span className="text-xs text-teal-600 font-semibold hidden sm:inline">📅 Voir l&apos;agenda</span>
              <button
                onClick={(ev) => { ev.stopPropagation(); openPerms(e); }}
                title="Gérer les accès"
                className="p-2 rounded-xl hover:bg-teal-50 text-gray-400 hover:text-teal-600 transition-colors"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                    d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                </svg>
              </button>
              <button
                onClick={(ev) => { ev.stopPropagation(); setConfirmDelete({ label: `Retirer ${e.nom} de votre équipe ?`, onConfirm: () => revoquer(e) }); }}
                title="Révoquer"
                className="text-xs text-red-500 hover:text-red-700 font-semibold px-2 py-1.5 rounded-lg hover:bg-red-50 transition-colors"
              >
                Révoquer
              </button>
            </div>
          ))}
          <button onClick={() => setShowAdd(true)}
            className="w-full flex items-center justify-center gap-2 bg-teal-600 text-white font-semibold py-3 rounded-xl hover:bg-teal-700 transition-colors text-sm">
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
            </svg>
            Ajouter un employé
          </button>
        </div>

      ) : (

        // ── Onglet Tâches ───────────────────────────────────────────────────
        <div>
          {filterEmployeeUid && (
            <div className="flex items-center gap-2 mb-4 bg-teal-50 border border-teal-200 rounded-xl px-3 py-2">
              <span className="text-sm text-teal-700 font-semibold">📅 Agenda de {filterEmployeeNom}</span>
              <button
                onClick={() => { setFilterEmployeeUid(null); setFilterEmployeeNom(''); }}
                className="ml-auto text-xs font-semibold text-teal-700 hover:underline"
              >
                ✕ Voir toutes les tâches
              </button>
            </div>
          )}
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
            <button onClick={() => setTacheModal({ mode: 'create' })}
              className="ml-auto px-4 py-1.5 rounded-full text-xs font-semibold bg-teal-600 text-white hover:bg-teal-700 transition-colors">
              + Nouvelle tâche
            </button>
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
                              onClick={() => setAssignProtoGroup(g)}
                              title={g.assigneNom ? `Assigné à ${g.assigneNom} — réassigner` : 'Assigner à un employé'}
                              className={`p-1.5 rounded-lg transition-colors ${
                                g.assigneNom
                                  ? 'text-teal-600 bg-teal-50 hover:bg-teal-100'
                                  : 'text-gray-300 hover:bg-teal-50 hover:text-teal-600'
                              }`}
                            >
                              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                                  d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z" />
                              </svg>
                            </button>
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
                        <button
                          onClick={() => setTacheModal({ mode: 'edit', tache: t })}
                          className="flex-1 min-w-0 text-left"
                        >
                          <p className={`text-sm font-medium ${isDone ? 'line-through text-gray-400' : 'text-gray-800'}`}>
                            {t.titre}
                          </p>
                          <p className="text-xs mt-0.5 flex flex-wrap items-center gap-x-1.5">
                            {t.animal_nom && <span className="text-gray-400">🐾 {t.animal_nom}</span>}
                            {t.assigne_nom
                              ? <span className="text-gray-400">👤 {t.assigne_nom}</span>
                              : <span className="text-teal-600 font-medium">+ Attribuer à un employé</span>}
                          </p>
                        </button>
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

      {/* Modal : assigner un protocole à un employé */}
      {assignProtoGroup && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-end justify-center sm:items-center p-4"
             onClick={e => { if (e.target === e.currentTarget) setAssignProtoGroup(null); }}>
          <div className="bg-white rounded-2xl w-full max-w-sm">
            <div className="p-5 border-b">
              <h3 className="font-bold text-gray-800 text-sm">Assigner « {assignProtoGroup.label} »</h3>
              <p className="text-xs text-gray-400 mt-0.5">
                L&apos;employé choisi reçoit une notification et retrouve la tâche dans son espace.
              </p>
            </div>
            <div className="p-3 max-h-[50vh] overflow-y-auto">
              {employes.length === 0 ? (
                <p className="text-center text-sm text-gray-400 py-6">Aucun employé actif</p>
              ) : (
                <>
                  {employes.map(e => {
                    const active = assignProtoGroup.assignedTo === e.uid_employe;
                    return (
                      <button key={e.uid_employe}
                        onClick={() => assignProto(assignProtoGroup, e.uid_employe)}
                        className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-left transition-colors ${
                          active ? 'bg-teal-50' : 'hover:bg-gray-50'
                        }`}>
                        <div className="w-8 h-8 rounded-full bg-teal-100 flex items-center justify-center text-teal-700 text-xs font-bold flex-shrink-0">
                          {(e.nom[0] ?? '?').toUpperCase()}
                        </div>
                        <span className="text-sm font-medium text-gray-800 flex-1">{e.nom}</span>
                        {active && <span className="text-teal-600 text-sm">✓</span>}
                      </button>
                    );
                  })}
                  {assignProtoGroup.assignedTo && (
                    <button onClick={() => assignProto(assignProtoGroup, '')}
                      className="w-full text-center px-3 py-2.5 mt-1 rounded-xl text-sm font-medium text-red-500 hover:bg-red-50 transition-colors">
                      Retirer l&apos;attribution
                    </button>
                  )}
                </>
              )}
            </div>
            <div className="px-5 pb-5 pt-1">
              <button onClick={() => setAssignProtoGroup(null)}
                className="w-full py-2.5 border border-gray-200 rounded-xl text-sm text-gray-600 hover:bg-gray-50 font-medium">
                Annuler
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Modal permissions employé */}
      {permsModal && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-end justify-center sm:items-center p-4"
             onClick={e => { if (e.target === e.currentTarget) setPermsModal(null); }}>
          <div className="bg-white rounded-2xl w-full max-w-md">
            <div className="p-5 border-b flex items-center gap-3">
              <div className="w-9 h-9 rounded-full bg-teal-50 flex items-center justify-center overflow-hidden flex-shrink-0">
                {permsModal.photo
                  ? <img src={permsModal.photo} alt={permsModal.nom} className="w-full h-full object-cover" />
                  : <span className="text-teal-600 font-bold text-sm">{permsModal.nom[0]?.toUpperCase()}</span>
                }
              </div>
              <div className="flex-1">
                <h3 className="font-bold text-gray-800 text-sm">Accès de {permsModal.nom}</h3>
                <p className="text-xs text-gray-400">Choisissez ce que cet employé peut modifier</p>
              </div>
              <button onClick={() => setPermsModal(null)} className="text-gray-400 hover:text-gray-600 text-2xl leading-none">×</button>
            </div>

            {!permsLoading && permsModal.employeProfileId && permsModal.eleveurProfileId && (
              <div className="px-5 pt-3 -mb-1 flex justify-end">
                <button
                  onClick={() => {
                    const keys = permsList.map(p => p.key);
                    const allOn = keys.every(k => permsData.has(k));
                    setPermsData(allOn ? new Set() : new Set(keys));
                  }}
                  className="text-xs font-semibold text-teal-600 hover:text-teal-700">
                  {permsList.every(p => permsData.has(p.key)) ? '✕ Tout retirer' : '✓ Tout autoriser'}
                </button>
              </div>
            )}

            <div className="p-5">
              {permsLoading ? (
                <div className="flex justify-center py-8">
                  <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-teal-600" />
                </div>
              ) : !permsModal.employeProfileId || !permsModal.eleveurProfileId ? (
                <p className="text-center text-sm text-red-500 py-6">
                  Profils non liés — mettez à jour la fiche employé depuis l&apos;app.
                </p>
              ) : (
                <div className="space-y-0 divide-y divide-gray-50">
                  {permsList.map(({ key, label, desc }) => (
                    <div key={key} className="flex items-center gap-3 py-3.5">
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-semibold text-gray-800">{label}</p>
                        <p className="text-xs text-gray-400">{desc}</p>
                      </div>
                      <button
                        onClick={() => setPermsData(prev => {
                          const next = new Set(prev);
                          next.has(key) ? next.delete(key) : next.add(key);
                          return next;
                        })}
                        className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors flex-shrink-0 ${
                          permsData.has(key) ? 'bg-teal-500' : 'bg-gray-200'
                        }`}
                      >
                        <span className={`inline-block h-4 w-4 rounded-full bg-white shadow-sm transition-transform ${
                          permsData.has(key) ? 'translate-x-6' : 'translate-x-1'
                        }`} />
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {!permsLoading && permsModal.employeProfileId && (
              <div className="px-5 pb-5 flex gap-3">
                <button onClick={() => setPermsModal(null)}
                  className="flex-1 py-2.5 border border-gray-200 rounded-xl text-sm text-gray-600 hover:bg-gray-50 font-medium">
                  Annuler
                </button>
                <button onClick={savePerms} disabled={permsSaving}
                  className="flex-1 py-2.5 bg-teal-600 text-white rounded-xl text-sm font-semibold hover:bg-teal-700 disabled:opacity-50">
                  {permsSaving ? 'Enregistrement…' : 'Enregistrer'}
                </button>
              </div>
            )}
          </div>
        </div>
      )}

      {showAdd && user && (
        <AddEmployeModal uid={user.uid} profileId={profileId || null} onClose={() => { setShowAdd(false); load(); }} />
      )}

      {tacheModal && user && (
        <TacheManuelleModal
          uid={user.uid}
          profileId={profileId || null}
          employes={employes}
          tache={tacheModal.mode === 'edit' ? tacheModal.tache : undefined}
          onClose={() => { setTacheModal(null); load(); }}
        />
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

// ── Modal créer / modifier une tâche manuelle ────────────────────────────────

function TacheManuelleModal({
  uid, profileId, employes, tache, onClose,
}: {
  uid: string;
  profileId: string | null;
  employes: Employe[];
  tache?: TacheManuelle;
  onClose: () => void;
}) {
  const [titre, setTitre] = useState(tache?.titre ?? '');
  const [date, setDate] = useState(tache?.date?.slice(0, 10) ?? new Date().toISOString().slice(0, 10));
  const [assigneA, setAssigneA] = useState(tache?.assigne_a ?? '');
  const [notes, setNotes] = useState(tache?.notes ?? '');
  const [saving, setSaving] = useState(false);

  async function save() {
    if (!titre.trim()) return;
    setSaving(true);
    try {
      if (tache) {
        await supabase.from('taches_elevage').update({
          titre: titre.trim(),
          date,
          assigne_a: assigneA || null,
          notes: notes.trim() || null,
        }).eq('id', tache.id);
      } else {
        await supabase.from('taches_elevage').insert({
          titre: titre.trim(),
          date,
          uid_eleveur: uid,
          ...(profileId ? { eleveur_profile_id: profileId } : {}),
          assigne_a: assigneA || null,
          notes: notes.trim() || null,
          statut: 'a_faire',
        });
      }
      onClose();
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="fixed inset-0 bg-black/60 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4">
      <div className="bg-white w-full max-w-md rounded-t-3xl sm:rounded-2xl shadow-2xl">
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <h3 className="font-bold text-[#1F2A2E]">{tache ? 'Modifier la tâche' : 'Nouvelle tâche'}</h3>
          <button onClick={onClose} className="p-1.5 rounded-xl hover:bg-gray-100 transition-colors">
            <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
        <div className="p-5 space-y-4">
          <div>
            <label className="text-xs font-semibold text-gray-500 block mb-1.5">Titre de la tâche *</label>
            <input value={titre} onChange={e => setTitre(e.target.value)} autoFocus
              placeholder="Ex : Nettoyer les box"
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-teal-600 focus:ring-1 focus:ring-teal-600 bg-white" />
          </div>
          <div>
            <label className="text-xs font-semibold text-gray-500 block mb-1.5">Date</label>
            <input type="date" value={date} onChange={e => setDate(e.target.value)}
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-teal-600 focus:ring-1 focus:ring-teal-600 bg-white" />
          </div>
          <div>
            <label className="text-xs font-semibold text-gray-500 block mb-1.5">Attribuer à</label>
            <select value={assigneA} onChange={e => setAssigneA(e.target.value)}
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-teal-600 focus:ring-1 focus:ring-teal-600 bg-white">
              <option value="">Non attribuée</option>
              {employes.map(e => (
                <option key={e.uid_employe} value={e.uid_employe}>{e.nom}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="text-xs font-semibold text-gray-500 block mb-1.5">Notes</label>
            <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2}
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-teal-600 focus:ring-1 focus:ring-teal-600 bg-white resize-none" />
          </div>
          <button onClick={save} disabled={saving || !titre.trim()}
            className="w-full bg-teal-600 hover:bg-teal-700 disabled:opacity-60 text-white font-semibold py-3 rounded-xl transition-colors text-sm mt-2">
            {saving ? 'Enregistrement…' : 'Enregistrer'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Modal ajouter un employé ─────────────────────────────────────────────────

interface CandidateUser {
  uid: string;
  firstname: string | null;
  lastname: string | null;
  name_elevage: string | null;
  is_elevage: boolean;
  is_pro: boolean;
  cat_pro: string | null;
}

const CAT_SANTE = new Set(['sante', 'veterinaire', 'vétérinaire', 'vet']);

function candidateNom(u: CandidateUser): string {
  if (u.is_elevage) return u.name_elevage?.trim() || 'Élevage';
  return `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim() || u.uid;
}

function AddEmployeModal({ uid, profileId, onClose }: { uid: string; profileId: string | null; onClose: () => void }) {
  const [query, setQuery] = useState('');
  const [allUsers, setAllUsers] = useState<CandidateUser[]>([]);
  const [results, setResults] = useState<CandidateUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [adding, setAdding] = useState<string | null>(null);
  const [nomElevage, setNomElevage] = useState('');

  useEffect(() => {
    async function load() {
      const { data: profile } = profileId
        ? await supabase.from('user_profiles').select('nom, firstname, lastname').eq('id', profileId).maybeSingle()
        : await supabase.from('user_profiles').select('nom, firstname, lastname').eq('uid', uid).eq('is_main', true).maybeSingle();
      setNomElevage(
        (profile?.nom as string)?.trim() ||
        `${profile?.firstname ?? ''} ${profile?.lastname ?? ''}`.trim()
      );
      const { data } = await supabase.from('user_profiles')
        .select('uid, firstname, lastname, nom, profile_type, cat_pro')
        .neq('uid', uid).eq('is_main', true).limit(500);
      const filtered = (data ?? []).map(u => ({
        uid: u.uid as string,
        firstname: u.firstname as string | null,
        lastname: u.lastname as string | null,
        name_elevage: u.nom as string | null,
        is_elevage: u.profile_type === 'eleveur',
        is_pro: !!u.profile_type && u.profile_type !== 'eleveur' && u.profile_type !== 'particulier',
        cat_pro: u.cat_pro as string | null,
      })).filter(u => !(u.is_pro && CAT_SANTE.has((u.cat_pro ?? '').toLowerCase().trim())));
      setAllUsers(filtered);
      setLoading(false);
    }
    load();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [uid, profileId]);

  function search(q: string) {
    setQuery(q);
    if (q.trim().length < 2) { setResults([]); return; }
    const lq = q.toLowerCase();
    setResults(
      allUsers.filter(u =>
        `${u.firstname ?? ''} ${u.lastname ?? ''} ${u.name_elevage ?? ''}`.toLowerCase().includes(lq)
      ).slice(0, 15)
    );
  }

  async function ajouter(u: CandidateUser) {
    setAdding(u.uid);
    try {
      let existingQ = supabase.from('employes').select().eq('uid_eleveur', uid).eq('uid_employe', u.uid);
      if (profileId) existingQ = existingQ.eq('eleveur_profile_id', profileId);
      const { data: existing } = await existingQ.maybeSingle();

      // Limite d'employés par forfait (éducateur/pension) — la page
      // d'abonnement annonce ces limites mais rien ne les appliquait jusqu'ici.
      if (!existing || !existing.actif) {
        const catPro = profileId
          ? (await supabase.from('user_profiles').select('profile_type,cat_pro').eq('id', profileId).maybeSingle()).data
          : (await supabase.from('user_profiles').select('cat_pro').eq('uid', uid).eq('is_main', true).maybeSingle()).data;
        const catProVal = (catPro as { cat_pro?: string } | null)?.cat_pro;
        if (catProVal === 'education' || catProVal === 'pension') {
          const { data: abo } = await supabase.from('abonnements')
            .select('plan_code').eq('uid', uid).eq('profil_type', catProVal).eq('statut', 'actif')
            .order('created_at', { ascending: false }).limit(1).maybeSingle();
          const planCode = abo?.plan_code ?? 'free';
          const { data: planRow } = await supabase.from('plans_tarifaires')
            .select('features').eq('profil_type', catProVal).eq('plan_code', planCode).maybeSingle();
          const fallbackMax: Record<string, number> = { free: 0, pro: 3, premium: -1 };
          const features = (planRow?.features ?? {}) as Record<string, unknown>;
          const maxEmployes = typeof features.maxEmployes === 'number' ? features.maxEmployes : (fallbackMax[planCode] ?? 0);
          if (maxEmployes !== -1) {
            let countQ = supabase.from('employes').select('id', { count: 'exact', head: true })
              .eq('uid_eleveur', uid).eq('actif', true);
            if (profileId) countQ = countQ.eq('eleveur_profile_id', profileId);
            const { count } = await countQ;
            if ((count ?? 0) >= maxEmployes) {
              alert(maxEmployes === 0
                ? 'Votre formule actuelle ne permet pas d\'ajouter d\'employé. Passez à une formule supérieure.'
                : `Limite de ${maxEmployes} employé(s) atteinte pour votre formule. Passez à une formule supérieure pour en ajouter plus.`);
              return;
            }
          }
        }
      }

      if (existing) {
        if (existing.actif) { alert('Cette personne est déjà dans votre équipe.'); return; }
        await supabase.from('employes').update({ actif: true }).eq('id', existing.id);
      } else {
        await supabase.from('employes').insert({
          uid_employe: u.uid,
          uid_eleveur: uid,
          ...(profileId ? { eleveur_profile_id: profileId } : {}),
          actif: true,
        });
      }
      const { data: targetParticulier } = await supabase.from('user_profiles')
        .select('id').eq('uid', u.uid).eq('profile_type', 'particulier').maybeSingle();
      await supabase.from('notifications').insert({
        uid: u.uid, type: 'employee_invite',
        title: 'Invitation à rejoindre une équipe',
        body: `Vous avez été ajouté à l'équipe de ${nomElevage}`,
        ...(targetParticulier?.id ? { profile_id: targetParticulier.id } : {}),
        data: { eleveurUid: uid, eleveurNom: nomElevage },
        read: false,
      });
      onClose();
    } finally {
      setAdding(null);
    }
  }

  return (
    <div className="fixed inset-0 bg-black/60 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4">
      <div className="bg-white w-full max-w-md rounded-t-3xl sm:rounded-2xl shadow-2xl max-h-[85vh] flex flex-col">
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <h3 className="font-bold text-[#1F2A2E]">Ajouter un employé</h3>
          <button onClick={onClose} className="p-1.5 rounded-xl hover:bg-gray-100 transition-colors">
            <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
        <div className="p-4">
          <input value={query} onChange={e => search(e.target.value)} autoFocus
            placeholder="Rechercher par prénom ou nom…"
            className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-teal-600 focus:ring-1 focus:ring-teal-600 bg-white" />
        </div>
        <div className="flex-1 overflow-y-auto px-4 pb-4">
          {loading && <div className="flex justify-center py-8"><div className="w-5 h-5 border-2 border-teal-600 border-t-transparent rounded-full animate-spin" /></div>}
          {!loading && query.length < 2 && (
            <p className="text-xs text-gray-400 text-center py-6">Tapez au moins 2 lettres pour rechercher.</p>
          )}
          {!loading && query.length >= 2 && results.length === 0 && (
            <p className="text-sm text-gray-400 text-center py-6">Aucun utilisateur trouvé</p>
          )}
          <div className="space-y-2">
            {results.map(u => {
              const nom = candidateNom(u);
              return (
                <div key={u.uid} className="flex items-center gap-3 p-3 rounded-xl hover:bg-gray-50 transition-colors">
                  <div className="w-10 h-10 rounded-full bg-teal-50 flex items-center justify-center flex-shrink-0 font-bold text-teal-600">
                    {nom[0]?.toUpperCase() ?? '?'}
                  </div>
                  <span className="flex-1 text-sm font-medium text-[#1F2A2E]">{nom}</span>
                  <button onClick={() => ajouter(u)} disabled={adding === u.uid}
                    className="text-sm font-semibold text-teal-700 border border-teal-700 hover:bg-teal-50 px-3 py-1.5 rounded-xl transition-colors disabled:opacity-50">
                    {adding === u.uid ? '…' : 'Ajouter'}
                  </button>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}
