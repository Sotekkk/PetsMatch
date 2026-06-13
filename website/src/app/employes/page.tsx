'use client';

import { useState, useEffect, useRef, useCallback } from 'react';
import Image from 'next/image';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

// ── Types ─────────────────────────────────────────────────────────────────────

interface Employee {
  id: string;
  uid_employe: string;
  uid_eleveur: string;
  actif: boolean;
  created_at: string;
  permissions: Record<string, boolean>;
  user?: UserProfile;
}

interface UserProfile {
  uid: string;
  firstname: string | null;
  lastname: string | null;
  name_elevage: string | null;
  is_elevage: boolean;
  is_pro: boolean;
  cat_pro: string | null;
  profile_picture_url: string | null;
  profile_picture_url_elevage: string | null;
}

interface Task {
  id: string;
  titre: string;
  animal_id: string | null;
  uid_eleveur: string;
  date: string;
  statut: 'a_faire' | 'fait';
  assigne_a: string | null;
  notes: string | null;
  created_at: string;
  assigne_nom?: string;
  animal_nom?: string;
}

interface Animal {
  id: string;
  nom: string;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const iCls = 'w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] focus:ring-1 focus:ring-[#0C5C6C] bg-white';

function nomUser(u: UserProfile): string {
  if (u.is_elevage) return u.name_elevage?.trim() || 'Élevage';
  return `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim() || u.uid;
}

function photoUser(u: UserProfile): string | null {
  return u.is_elevage ? u.profile_picture_url_elevage : u.profile_picture_url;
}

function Avatar({ src, nom, size = 40 }: { src?: string | null; nom: string; size?: number }) {
  const initiale = nom[0]?.toUpperCase() ?? '?';
  if (src) return (
    <Image src={src} alt={nom} width={size} height={size}
      className="rounded-full object-cover flex-shrink-0"
      style={{ width: size, height: size }} />
  );
  return (
    <div className="rounded-full bg-[#E8F4F6] flex items-center justify-center flex-shrink-0 font-bold text-[#0C5C6C]"
      style={{ width: size, height: size, fontSize: size * 0.4 }}>
      {initiale}
    </div>
  );
}

// ── Page principale ────────────────────────────────────────────────────────────

export default function EmployesPage() {
  const router = useRouter();
  const { user, loading: authLoading } = useAuth();
  const [tab, setTab] = useState<'equipe' | 'taches'>('equipe');

  useEffect(() => {
    if (!authLoading && !user) router.push('/connexion');
  }, [authLoading, user, router]);

  if (authLoading || !user) {
    return <div className="flex justify-center py-32 text-gray-400">Chargement…</div>;
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 pb-20">
      <div className="flex items-center gap-3 mb-5">
        <button onClick={() => router.back()} className="p-2 rounded-xl hover:bg-gray-100 transition-colors">
          <svg className="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </button>
        <h1 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
          Gestion des employés
        </h1>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 bg-gray-100 p-1 rounded-xl mb-5">
        {([['equipe', '👥 Équipe'], ['taches', '✅ Tâches']] as const).map(([v, l]) => (
          <button key={v} onClick={() => setTab(v)}
            className={`flex-1 py-2 text-sm font-semibold rounded-lg transition-colors ${
              tab === v ? 'bg-white text-[#0C5C6C] shadow-sm' : 'text-gray-500 hover:text-gray-700'
            }`}>
            {l}
          </button>
        ))}
      </div>

      {tab === 'equipe' ? <EquipeTab uid={user.uid} /> : <TachesTab uid={user.uid} />}
    </div>
  );
}

// ── Tab Équipe ────────────────────────────────────────────────────────────────

function EquipeTab({ uid }: { uid: string }) {
  const [employes, setEmployes] = useState<Employee[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAdd, setShowAdd] = useState(false);
  const [showPerms, setShowPerms] = useState<Employee | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const { data: rows } = await supabase
        .from('employes').select('*').eq('uid_eleveur', uid).eq('actif', true).order('created_at');

      const result: Employee[] = [];
      for (const e of (rows ?? [])) {
        const { data: u } = await supabase.from('users')
          .select('uid, firstname, lastname, name_elevage, is_elevage, is_pro, cat_pro, profile_picture_url, profile_picture_url_elevage')
          .eq('uid', e.uid_employe).maybeSingle();
        result.push({ ...e, permissions: e.permissions ?? {}, user: u ?? undefined });
      }
      setEmployes(result);
    } finally {
      setLoading(false);
    }
  }, [uid]);

  useEffect(() => { load(); }, [load]);

  async function revoquer(emp: Employee) {
    if (!confirm(`Retirer ${emp.user ? nomUser(emp.user) : 'cet employé'} de votre équipe ?`)) return;
    await supabase.from('employes').update({ actif: false }).eq('id', emp.id);
    load();
  }

  if (loading) return <div className="flex justify-center py-16"><div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;

  return (
    <>
      {employes.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <div className="text-5xl mb-3">👥</div>
          <p className="font-semibold text-base">Aucun employé pour l&apos;instant</p>
          <p className="text-sm mt-1">Ajoutez des membres de votre équipe.</p>
        </div>
      ) : (
        <div className="space-y-3 mb-4">
          {employes.map(emp => {
            const nom = emp.user ? nomUser(emp.user) : 'Utilisateur inconnu';
            const photo = emp.user ? photoUser(emp.user) : null;
            return (
              <div key={emp.id} className="bg-white rounded-2xl border border-gray-100 shadow-sm p-4 flex items-center gap-3">
                <Avatar src={photo} nom={nom} size={44} />
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-[#1F2A2E] text-sm truncate">{nom}</p>
                  <div className="flex gap-2 mt-0.5">
                    {emp.permissions.modifier_animaux && (
                      <span className="text-xs bg-[#E8F4F6] text-[#0C5C6C] px-2 py-0.5 rounded-full">Animaux</span>
                    )}
                    {emp.permissions.gerer_taches && (
                      <span className="text-xs bg-[#EEF5EA] text-[#6E9E57] px-2 py-0.5 rounded-full">Tâches</span>
                    )}
                  </div>
                </div>
                <div className="flex items-center gap-1">
                  <button onClick={() => setShowPerms(emp)}
                    className="p-2 rounded-xl hover:bg-gray-100 transition-colors text-[#0C5C6C]" title="Gérer les accès">
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4" />
                    </svg>
                  </button>
                  <button onClick={() => revoquer(emp)}
                    className="text-xs text-red-500 hover:text-red-700 font-semibold px-2 py-1 rounded-lg hover:bg-red-50 transition-colors">
                    Révoquer
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      <button onClick={() => setShowAdd(true)}
        className="w-full flex items-center justify-center gap-2 bg-[#0C5C6C] text-white font-semibold py-3 rounded-xl hover:bg-[#094F5D] transition-colors text-sm">
        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
        </svg>
        Ajouter un employé
      </button>

      {showAdd && <AddEmployeModal uid={uid} onClose={() => { setShowAdd(false); load(); }} />}
      {showPerms && <PermissionsModal emp={showPerms} onClose={() => { setShowPerms(null); load(); }} />}
    </>
  );
}

// ── Modal ajouter un employé ─────────────────────────────────────────────────

function AddEmployeModal({ uid, onClose }: { uid: string; onClose: () => void }) {
  const [query, setQuery] = useState('');
  const [allUsers, setAllUsers] = useState<UserProfile[]>([]);
  const [results, setResults] = useState<UserProfile[]>([]);
  const [loading, setLoading] = useState(true);
  const [adding, setAdding] = useState<string | null>(null);
  const [nomElevage, setNomElevage] = useState('');

  const CAT_SANTE = new Set(['sante', 'veterinaire', 'vétérinaire', 'vet']);

  useEffect(() => {
    async function load() {
      const { data: profile } = await supabase.from('users')
        .select('name_elevage, firstname, lastname').eq('uid', uid).maybeSingle();
      setNomElevage(
        (profile?.name_elevage as string)?.trim() ||
        `${profile?.firstname ?? ''} ${profile?.lastname ?? ''}`.trim()
      );
      const { data } = await supabase.from('users')
        .select('uid, firstname, lastname, name_elevage, is_elevage, is_pro, cat_pro, profile_picture_url, profile_picture_url_elevage')
        .neq('uid', uid).limit(500);
      const filtered = (data ?? []).filter((u: UserProfile) => {
        if (u.is_pro && CAT_SANTE.has((u.cat_pro ?? '').toLowerCase().trim())) return false;
        return true;
      });
      setAllUsers(filtered as UserProfile[]);
      setLoading(false);
    }
    load();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [uid]);

  function search(q: string) {
    setQuery(q);
    if (q.trim().length < 2) { setResults([]); return; }
    const lq = q.toLowerCase();
    setResults(
      allUsers.filter(u =>
        `${u.firstname ?? ''} ${u.lastname ?? ''} ${u.name_elevage ?? ''}`.toLowerCase().includes(lq)
      ).slice(0, 15) as UserProfile[]
    );
  }

  async function ajouter(u: UserProfile) {
    setAdding(u.uid);
    try {
      const { data: existing } = await supabase.from('employes')
        .select().eq('uid_eleveur', uid).eq('uid_employe', u.uid).maybeSingle();
      if (existing) {
        if (existing.actif) { alert('Cette personne est déjà dans votre équipe.'); return; }
        await supabase.from('employes').update({ actif: true }).eq('id', existing.id);
      } else {
        await supabase.from('employes').insert({ uid_employe: u.uid, uid_eleveur: uid, actif: true });
      }
      // Notification in-app
      await supabase.from('notifications').insert({
        uid: u.uid, type: 'employee_invite',
        title: 'Invitation à rejoindre une équipe',
        body: `Vous avez été ajouté à l'équipe de ${nomElevage}`,
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
          <h3 className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Ajouter un employé</h3>
          <button onClick={onClose} className="p-1.5 rounded-xl hover:bg-gray-100 transition-colors">
            <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
        <div className="p-4">
          <input value={query} onChange={e => search(e.target.value)} autoFocus
            placeholder="Rechercher par prénom ou nom…" className={iCls} />
        </div>
        <div className="flex-1 overflow-y-auto px-4 pb-4">
          {loading && <div className="flex justify-center py-8"><div className="w-5 h-5 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>}
          {!loading && query.length < 2 && (
            <p className="text-xs text-gray-400 text-center py-6">Tapez au moins 2 lettres pour rechercher.</p>
          )}
          {!loading && query.length >= 2 && results.length === 0 && (
            <p className="text-sm text-gray-400 text-center py-6">Aucun utilisateur trouvé</p>
          )}
          <div className="space-y-2">
            {results.map(u => {
              const nom = nomUser(u);
              const photo = photoUser(u);
              return (
                <div key={u.uid} className="flex items-center gap-3 p-3 rounded-xl hover:bg-gray-50 transition-colors">
                  <Avatar src={photo} nom={nom} size={40} />
                  <span className="flex-1 text-sm font-medium text-[#1F2A2E]">{nom}</span>
                  <button onClick={() => ajouter(u)} disabled={adding === u.uid}
                    className="text-sm font-semibold text-[#0C5C6C] border border-[#0C5C6C] hover:bg-[#E8F4F6] px-3 py-1.5 rounded-xl transition-colors disabled:opacity-50">
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

// ── Modal permissions ─────────────────────────────────────────────────────────

function PermissionsModal({ emp, onClose }: { emp: Employee; onClose: () => void }) {
  const nom = emp.user ? nomUser(emp.user) : 'Employé';
  const [modifierAnimaux, setModifierAnimaux] = useState(emp.permissions.modifier_animaux ?? false);
  const [gererTaches, setGererTaches] = useState(emp.permissions.gerer_taches ?? false);
  const [saving, setSaving] = useState(false);

  async function save() {
    setSaving(true);
    await supabase.from('employes').update({
      permissions: { modifier_animaux: modifierAnimaux, gerer_taches: gererTaches },
    }).eq('id', emp.id);
    setSaving(false);
    onClose();
  }

  return (
    <div className="fixed inset-0 bg-black/60 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4">
      <div className="bg-white w-full max-w-md rounded-t-3xl sm:rounded-2xl shadow-2xl">
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <h3 className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Accès de {nom}</h3>
          <button onClick={onClose} className="p-1.5 rounded-xl hover:bg-gray-100 transition-colors">
            <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
        <div className="p-5 space-y-4">
          <p className="text-xs text-gray-400">Définissez ce que cet employé peut faire.</p>
          {([
            ['modifier_animaux', modifierAnimaux, setModifierAnimaux, '🐾', 'Modifier les fiches animaux', 'Peut éditer les informations, poids, santé'] as const,
            ['gerer_taches', gererTaches, setGererTaches, '✅', 'Gérer les tâches', 'Peut créer et modifier ses propres tâches'] as const,
          ]).map(([key, val, setter, icon, title, desc]) => (
            <div key={key} className="flex items-center justify-between py-3 border-b border-gray-100 last:border-0">
              <div className="flex items-center gap-3">
                <span className="text-xl">{icon}</span>
                <div>
                  <p className="text-sm font-semibold text-[#1F2A2E]">{title}</p>
                  <p className="text-xs text-gray-400">{desc}</p>
                </div>
              </div>
              <button onClick={() => setter(!val)}
                className={`w-11 h-6 rounded-full transition-colors relative flex-shrink-0 ${val ? 'bg-[#0C5C6C]' : 'bg-gray-200'}`}>
                <div className={`w-5 h-5 bg-white rounded-full absolute top-0.5 transition-transform shadow-sm ${val ? 'translate-x-5' : 'translate-x-0.5'}`} />
              </button>
            </div>
          ))}
          <button onClick={save} disabled={saving}
            className="w-full bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 text-white font-semibold py-3 rounded-xl transition-colors text-sm mt-2">
            {saving ? 'Enregistrement…' : 'Enregistrer'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Tab Tâches ────────────────────────────────────────────────────────────────

function TachesTab({ uid }: { uid: string }) {
  const [taches, setTaches] = useState<Task[]>([]);
  const [employes, setEmployes] = useState<{ uid: string; nom: string }[]>([]);
  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [loading, setLoading] = useState(true);
  const [showDone, setShowDone] = useState(false);
  const [showCreate, setShowCreate] = useState(false);
  const [editTask, setEditTask] = useState<Task | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [{ data: tachesRaw }, { data: empsRaw }, { data: animauxRaw }] = await Promise.all([
        supabase.from('taches_elevage').select('*').eq('uid_eleveur', uid).order('date'),
        supabase.from('employes').select('*').eq('uid_eleveur', uid).eq('actif', true),
        supabase.from('animaux').select('id, nom').eq('uid_eleveur', uid).order('nom'),
      ]);

      const uidToNom: Record<string, string> = {};
      for (const e of (empsRaw ?? [])) {
        const { data: u } = await supabase.from('users')
          .select('uid, firstname, lastname, name_elevage, is_elevage')
          .eq('uid', e.uid_employe).maybeSingle();
        if (u) uidToNom[u.uid] = u.is_elevage ? (u.name_elevage ?? 'Élevage') : `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim();
      }

      const emps = (empsRaw ?? []).map(e => ({ uid: e.uid_employe as string, nom: uidToNom[e.uid_employe] ?? 'Employé' }));
      const animalNoms: Record<string, string> = {};
      for (const a of (animauxRaw ?? [])) animalNoms[a.id] = a.nom ?? '—';

      const tasks = (tachesRaw ?? []).map(t => ({
        ...t,
        assigne_nom: t.assigne_a ? (uidToNom[t.assigne_a] ?? 'Employé') : null,
        animal_nom: t.animal_id ? (animalNoms[t.animal_id] ?? null) : null,
      })) as Task[];

      setTaches(tasks);
      setEmployes(emps);
      setAnimaux((animauxRaw ?? []) as Animal[]);
    } finally {
      setLoading(false);
    }
  }, [uid]);

  useEffect(() => { load(); }, [load]);

  async function toggleStatut(t: Task) {
    const newStatut = t.statut === 'fait' ? 'a_faire' : 'fait';
    setTaches(prev => prev.map(x => x.id === t.id ? { ...x, statut: newStatut } : x));
    await supabase.from('taches_elevage').update({ statut: newStatut }).eq('id', t.id);
  }

  async function deleteTask(t: Task) {
    if (!confirm(`Supprimer la tâche "${t.titre}" ?`)) return;
    await supabase.from('taches_elevage').delete().eq('id', t.id);
    load();
  }

  const affichees = taches.filter(t => showDone ? t.statut === 'fait' : t.statut !== 'fait');

  if (loading) return <div className="flex justify-center py-16"><div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;

  return (
    <>
      <div className="flex gap-2 mb-4">
        {([['a_faire', 'À faire', '#0C5C6C'], ['fait', 'Terminées', '#6E9E57']] as const).map(([v, l, c]) => {
          const active = showDone === (v === 'fait');
          return (
            <button key={v} onClick={() => setShowDone(v === 'fait')}
              className={`px-4 py-2 rounded-full text-sm font-semibold border-2 transition-colors ${
                active ? 'text-white' : 'bg-white text-gray-500'
              }`}
              style={{ borderColor: c, backgroundColor: active ? c : undefined }}>
              {l}
            </button>
          );
        })}
      </div>

      {affichees.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <div className="text-5xl mb-3">{showDone ? '🎉' : '📋'}</div>
          <p className="font-semibold">{showDone ? 'Aucune tâche terminée' : 'Aucune tâche à faire'}</p>
          {!showDone && <p className="text-sm mt-1">Appuyez sur + pour créer une tâche.</p>}
        </div>
      ) : (
        <div className="space-y-3 mb-4">
          {affichees.map(t => (
            <div key={t.id} className="bg-white rounded-2xl border border-gray-100 shadow-sm p-4">
              <div className="flex items-start gap-3">
                <button onClick={() => toggleStatut(t)}
                  className={`w-6 h-6 rounded-full border-2 flex items-center justify-center flex-shrink-0 mt-0.5 transition-colors ${
                    t.statut === 'fait' ? 'border-[#6E9E57] bg-[#6E9E57]' : 'border-gray-300 hover:border-[#0C5C6C]'
                  }`}>
                  {t.statut === 'fait' && <svg className="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" /></svg>}
                </button>
                <div className="flex-1 min-w-0">
                  <p className={`font-semibold text-sm ${t.statut === 'fait' ? 'line-through text-gray-400' : 'text-[#1F2A2E]'}`}>{t.titre}</p>
                  <div className="flex flex-wrap gap-2 mt-1">
                    <span className="text-xs text-gray-400">📅 {new Date(t.date).toLocaleDateString('fr-FR')}</span>
                    {t.assigne_nom && <span className="text-xs text-[#0C5C6C] bg-[#E8F4F6] px-2 py-0.5 rounded-full">👤 {t.assigne_nom}</span>}
                    {t.animal_nom && <span className="text-xs text-[#6E9E57] bg-[#EEF5EA] px-2 py-0.5 rounded-full">🐾 {t.animal_nom}</span>}
                  </div>
                  {t.notes && <p className="text-xs text-gray-400 mt-1 truncate">{t.notes}</p>}
                </div>
                <div className="flex gap-1">
                  <button onClick={() => setEditTask(t)} className="p-1.5 rounded-lg hover:bg-gray-100 transition-colors">
                    <svg className="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                    </svg>
                  </button>
                  <button onClick={() => deleteTask(t)} className="p-1.5 rounded-lg hover:bg-red-50 transition-colors">
                    <svg className="w-4 h-4 text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                    </svg>
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      <button onClick={() => setShowCreate(true)}
        className="w-full flex items-center justify-center gap-2 bg-[#0C5C6C] text-white font-semibold py-3 rounded-xl hover:bg-[#094F5D] transition-colors text-sm">
        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
        </svg>
        Nouvelle tâche
      </button>

      {(showCreate || editTask) && (
        <TaskModal
          uid={uid}
          task={editTask ?? undefined}
          employes={employes}
          animaux={animaux}
          onClose={() => { setShowCreate(false); setEditTask(null); load(); }}
        />
      )}
    </>
  );
}

// ── Modal tâche (créer / modifier) ───────────────────────────────────────────

function TaskModal({
  uid, task, employes, animaux, onClose,
}: {
  uid: string;
  task?: Task;
  employes: { uid: string; nom: string }[];
  animaux: Animal[];
  onClose: () => void;
}) {
  const [titre, setTitre] = useState(task?.titre ?? '');
  const [date, setDate] = useState(task?.date ?? new Date().toISOString().slice(0, 10));
  const [assigneA, setAssigneA] = useState(task?.assigne_a ?? '');
  const [animalId, setAnimalId] = useState(task?.animal_id ?? '');
  const [notes, setNotes] = useState(task?.notes ?? '');
  const [saving, setSaving] = useState(false);

  async function save() {
    if (!titre.trim() || !date) return;
    setSaving(true);
    const payload = {
      titre: titre.trim(),
      date,
      uid_eleveur: uid,
      assigne_a: assigneA || null,
      animal_id: animalId || null,
      notes: notes.trim() || null,
    };
    if (task) {
      await supabase.from('taches_elevage').update(payload).eq('id', task.id);
    } else {
      await supabase.from('taches_elevage').insert({ ...payload, statut: 'a_faire' });
    }
    setSaving(false);
    onClose();
  }

  return (
    <div className="fixed inset-0 bg-black/60 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4">
      <div className="bg-white w-full max-w-md rounded-t-3xl sm:rounded-2xl shadow-2xl">
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <h3 className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
            {task ? 'Modifier la tâche' : 'Nouvelle tâche'}
          </h3>
          <button onClick={onClose} className="p-1.5 rounded-xl hover:bg-gray-100 transition-colors">
            <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
        <div className="p-5 space-y-4">
          <div>
            <label className="block text-xs font-semibold text-gray-600 mb-1">Titre *</label>
            <input value={titre} onChange={e => setTitre(e.target.value)} placeholder="Ex: Vermifugation chiot…" className={iCls} />
          </div>
          <div>
            <label className="block text-xs font-semibold text-gray-600 mb-1">Date *</label>
            <input type="date" value={date} onChange={e => setDate(e.target.value)} className={iCls} />
          </div>
          {employes.length > 0 && (
            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Assigné à</label>
              <select value={assigneA} onChange={e => setAssigneA(e.target.value)} className={iCls}>
                <option value="">— Personne —</option>
                {employes.map(e => <option key={e.uid} value={e.uid}>{e.nom}</option>)}
              </select>
            </div>
          )}
          {animaux.length > 0 && (
            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Animal concerné</label>
              <select value={animalId} onChange={e => setAnimalId(e.target.value)} className={iCls}>
                <option value="">— Aucun —</option>
                {animaux.map(a => <option key={a.id} value={a.id}>{a.nom}</option>)}
              </select>
            </div>
          )}
          <div>
            <label className="block text-xs font-semibold text-gray-600 mb-1">Notes</label>
            <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={3}
              placeholder="Instructions complémentaires…" className={`${iCls} resize-none`} />
          </div>
          <button onClick={save} disabled={saving || !titre.trim() || !date}
            className="w-full bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 text-white font-semibold py-3 rounded-xl transition-colors text-sm">
            {saving ? 'Enregistrement…' : task ? 'Enregistrer' : 'Créer la tâche'}
          </button>
        </div>
      </div>
    </div>
  );
}
