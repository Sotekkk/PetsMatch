'use client';

import { useEffect, useState, useCallback } from 'react';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

// ── Types ──────────────────────────────────────────────────────────────────────

interface Tache {
  id: string;
  label: string;
  date?: string;
  statut?: string;
  animal_nom?: string;
}

interface Benevole {
  id: string;
  uid_employe?: string;
  prenom: string;
  nom: string;
  email?: string;
  telephone?: string;
  notes?: string;
  actif: boolean;
  photo?: string | null;
  taches?: Tache[];
}

interface Employe {
  id: string;
  uid_employe: string;
  actif: boolean;
  nom: string;
  photo?: string | null;
  taches?: Tache[];
}

interface UserProfile {
  uid: string;
  firstname: string | null;
  lastname: string | null;
  name_elevage: string | null;
  is_elevage: boolean;
  profile_picture_url: string | null;
  profile_picture_url_elevage: string | null;
  phone_number?: string | null;
}

interface Animal { id: string; nom: string; espece?: string | null; }
interface Enclos { id: string; nom: string; }

interface MembreEquipe {
  id: string;
  uid_employe?: string;
  type: 'employe' | 'benevole';
  nom: string;
  prenom: string;
  email?: string;
  telephone?: string;
  notes?: string;
  actif: boolean;
  photo?: string | null;
  taches?: Tache[];
}

const inp = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300';

// Charge les tâches depuis plan_taches ET taches_elevage pour un uid_employe
async function fetchTachesPersonne(uid_employe: string, uid_eleveur: string): Promise<Tache[]> {
  const [planRes, tacheRes] = await Promise.all([
    supabase.from('plan_taches')
      .select('id, label, type_acte, date_prevue, statut, animal_nom')
      .eq('assigned_to', uid_employe)
      .eq('uid_eleveur', uid_eleveur)
      .eq('profil_source', 'association')
      .neq('statut', 'fait')
      .order('date_prevue'),
    supabase.from('taches_elevage')
      .select('id, titre, date, statut, animal_id')
      .eq('assigne_a', uid_employe)
      .eq('uid_eleveur', uid_eleveur)
      .eq('profil_source', 'association')
      .neq('statut', 'fait')
      .order('date'),
  ]);

  const planTaches: Tache[] = (planRes.data ?? []).map((t: { id: string; label?: string; type_acte?: string; date_prevue?: string; statut?: string; animal_nom?: string }) => ({
    id: `plan_${t.id}`,
    label: t.label || t.type_acte || 'Tâche',
    date: t.date_prevue,
    statut: t.statut,
    animal_nom: t.animal_nom,
  }));

  const tachesArr: Tache[] = (tacheRes.data ?? []).map((t: { id: string; titre?: string; date?: string; statut?: string }) => ({
    id: `tache_${t.id}`,
    label: t.titre || 'Tâche',
    date: t.date,
    statut: t.statut,
  }));

  return [...planTaches, ...tachesArr];
}

// ── Page principale ───────────────────────────────────────────────────────────

export default function EquipeWebPage() {
  const { user } = useAuth();
  const uid = user?.uid ?? '';

  return (
    <div className="max-w-2xl mx-auto px-4 py-8">
      <h1 className="text-2xl font-bold font-galey text-teal-800 mb-6">Équipe</h1>
      <EquipeUnifiee uid={uid} />
    </div>
  );
}

// ── Vue unifiée équipe ────────────────────────────────────────────────────────

function EquipeUnifiee({ uid }: { uid: string }) {
  const [membres, setMembres] = useState<MembreEquipe[]>([]);
  const [loading, setLoading] = useState(true);
  const [dbError, setDbError] = useState<string | null>(null);
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const [showAddEmploye, setShowAddEmploye] = useState(false);
  const [showAddBenevole, setShowAddBenevole] = useState(false);
  const [showFormBenevole, setShowFormBenevole] = useState(false);
  const [editing, setEditing] = useState<MembreEquipe | null>(null);
  const [assigning, setAssigning] = useState<MembreEquipe | null>(null);
  const [form, setForm] = useState({ prenom: '', nom: '', email: '', telephone: '', notes: '' });
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    if (!uid) return;
    setLoading(true);
    setDbError(null);
    try {
      const { data: rows, error } = await supabase
        .from('employes').select('*')
        .eq('uid_eleveur', uid)
        .eq('actif', true)
        .or('profil_source.eq.association,profil_source.is.null')
        .order('created_at');

      if (error) { setDbError(`${error.message} (${error.code})`); setLoading(false); return; }

      const result: MembreEquipe[] = [];
      for (const row of (rows ?? [])) {
        const isBenevole = row.type === 'benevole';
        let nom = row.nom ?? '';
        let prenom = row.prenom ?? '';
        let photo: string | null = null;
        let email = row.email ?? undefined;
        const telephone = row.telephone ?? undefined;
        let taches: Tache[] = [];

        if (row.uid_employe) {
          const { data: u } = await supabase.from('users')
            .select('firstname, lastname, name_elevage, is_elevage, profile_picture_url, profile_picture_url_elevage, phone_number')
            .eq('uid', row.uid_employe).maybeSingle();
          const p = u as Omit<UserProfile, 'uid'> | null;
          const fullNom = p?.is_elevage
            ? (p.name_elevage?.trim() || 'Élevage')
            : `${p?.firstname ?? ''} ${p?.lastname ?? ''}`.trim() || 'Utilisateur';
          prenom = fullNom.split(' ')[0] ?? fullNom;
          nom = fullNom.split(' ').slice(1).join(' ') || '';
          photo = (p?.is_elevage ? p.profile_picture_url_elevage : p?.profile_picture_url) ?? null;
          taches = await fetchTachesPersonne(row.uid_employe, uid);
        }

        result.push({
          id: row.id,
          uid_employe: row.uid_employe ?? undefined,
          type: isBenevole ? 'benevole' : 'employe',
          nom, prenom, email, telephone,
          notes: row.notes ?? undefined,
          actif: row.actif ?? true,
          photo, taches,
        });
      }
      setMembres(result);
    } finally {
      setLoading(false);
    }
  }, [uid]);

  useEffect(() => { load(); }, [load]);

  const handleAddBenevoleManuel = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!uid || !form.prenom.trim() || !form.nom.trim()) return;
    setSaving(true);
    const { error } = await supabase.from('employes').insert({
      uid_eleveur: uid, prenom: form.prenom.trim(), nom: form.nom.trim(),
      email: form.email.trim() || null, telephone: form.telephone.trim() || null,
      notes: form.notes.trim() || null, actif: true, type: 'benevole', profil_source: 'association',
    });
    setSaving(false);
    if (error) { alert(`Erreur: ${error.message}`); return; }
    setForm({ prenom: '', nom: '', email: '', telephone: '', notes: '' });
    setShowFormBenevole(false);
    load();
  };

  const toggleActif = async (id: string, actif: boolean, uidEmploye?: string) => {
    await supabase.from('employes').update({ actif: !actif }).eq('id', id);
    if (actif && uidEmploye) {
      await supabase.from('notifications').insert({
        uid: uidEmploye, type: 'employee_revoked',
        title: 'Statut bénévole modifié',
        body: 'Votre statut de bénévole a été désactivé',
        data: {},
        read: false,
      });
    }
    load();
  };

  const handleDelete = async (id: string) => {
    if (!confirm('Supprimer ce membre ?')) return;
    await supabase.from('employes').delete().eq('id', id);
    load();
  };

  const actifs   = membres.filter(m => m.actif);
  const inactifs = membres.filter(m => !m.actif);

  const renderCard = (m: MembreEquipe) => {
    const displayName = `${m.prenom} ${m.nom}`.trim() || (m.type === 'benevole' ? 'Bénévole' : 'Employé');
    const isOpen = expanded[m.id] ?? false;
    const taches = m.taches ?? [];

    return (
      <div key={m.id} className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="p-4 flex items-center gap-3 cursor-pointer hover:bg-gray-50 transition-colors"
          onClick={() => m.uid_employe && setExpanded(prev => ({ ...prev, [m.id]: !isOpen }))}>
          <div className="w-10 h-10 rounded-full bg-teal-50 flex items-center justify-center flex-shrink-0 overflow-hidden">
            {m.photo
              ? <Image src={m.photo} alt={displayName} width={40} height={40} className="w-full h-full object-cover" unoptimized />
              : <span className="font-bold font-galey text-sm text-teal-600">{displayName[0]?.toUpperCase() ?? '?'}</span>}
          </div>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <p className="font-semibold font-galey text-gray-900 text-sm truncate">{displayName}</p>
              {/* Flag type */}
              <span className={`text-xs px-2 py-0.5 rounded-full font-galey font-semibold ${m.type === 'benevole' ? 'bg-purple-100 text-purple-700' : 'bg-teal-100 text-teal-700'}`}>
                {m.type === 'benevole' ? '🤝 Bénévole' : '👔 Employé'}
              </span>
            </div>
            <div className="flex items-center gap-3 text-xs text-gray-500 font-galey">
              {m.email && <span>📧 {m.email}</span>}
              {m.telephone && <span>📞 {m.telephone}</span>}
            </div>
            {m.uid_employe && (
              <p className="text-xs text-gray-400 font-galey mt-0.5">
                {taches.length === 0 ? 'Aucune tâche' : `${taches.length} tâche${taches.length > 1 ? 's' : ''} en cours`}
              </p>
            )}
          </div>
          {m.uid_employe && <span className="text-gray-400 text-xs">{isOpen ? '▲' : '▼'}</span>}
          {m.uid_employe && (
            <button onClick={ev => { ev.stopPropagation(); setAssigning(m); }}
              className="text-xs text-teal-600 hover:text-teal-800 font-galey px-2 py-1 rounded-lg hover:bg-teal-50 transition-colors">
              + Tâche
            </button>
          )}
          <button onClick={ev => { ev.stopPropagation(); setEditing(m); }}
            className="text-xs text-teal-500 hover:text-teal-700 px-1.5 py-1 rounded-lg hover:bg-teal-50 transition-colors">✏️</button>
          <button onClick={ev => { ev.stopPropagation(); handleDelete(m.id); }}
            className="text-red-400 hover:text-red-600 text-sm px-1">🗑</button>
        </div>

        {isOpen && m.uid_employe && (
          <div className="border-t border-gray-100 bg-gray-50 px-4 py-3 space-y-2">
            {taches.length === 0
              ? <p className="text-xs text-gray-400 text-center py-2 font-galey">Aucune tâche assignée</p>
              : taches.map(t => <TacheRow key={t.id} t={t} />)}
          </div>
        )}
      </div>
    );
  };

  if (loading) return <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-teal-700" /></div>;

  return (
    <div className="space-y-4">
      {dbError && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-3 text-xs text-red-700 font-galey break-all">
          ⚠️ {dbError} — uid: {uid || '(vide)'}
        </div>
      )}

      {/* Boutons d'ajout */}
      <div className="flex gap-2 flex-wrap">
        <button onClick={() => setShowAddEmploye(true)}
          className="bg-teal-700 text-white px-4 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800 transition-colors">
          🔍 Inviter un employé
        </button>
        <button onClick={() => setShowAddBenevole(true)}
          className="bg-purple-600 text-white px-4 py-2 rounded-full text-sm font-galey font-semibold hover:bg-purple-700 transition-colors">
          🔍 Bénévole PetsMatch
        </button>
        <button onClick={() => setShowFormBenevole(!showFormBenevole)}
          className="border border-purple-400 text-purple-600 px-4 py-2 rounded-full text-sm font-galey font-semibold hover:bg-purple-50 transition-colors">
          + Bénévole manuel
        </button>
      </div>

      {showFormBenevole && (
        <form onSubmit={handleAddBenevoleManuel} className="bg-white rounded-2xl shadow-sm p-5 space-y-4 border border-purple-100">
          <h2 className="font-bold font-galey text-purple-800">Nouveau bénévole</h2>
          <div className="grid grid-cols-2 gap-4">
            <input placeholder="Prénom *" required value={form.prenom} onChange={e => setForm({ ...form, prenom: e.target.value })} className={inp} />
            <input placeholder="Nom *" required value={form.nom} onChange={e => setForm({ ...form, nom: e.target.value })} className={inp} />
            <input placeholder="Email" type="email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} className={inp} />
            <input placeholder="Téléphone" value={form.telephone} onChange={e => setForm({ ...form, telephone: e.target.value })} className={inp} />
          </div>
          <textarea placeholder="Notes" rows={2} value={form.notes} onChange={e => setForm({ ...form, notes: e.target.value })} className={inp + ' resize-none'} />
          <div className="flex gap-3">
            <button type="submit" disabled={saving} className="bg-purple-600 text-white px-6 py-2 rounded-full text-sm font-galey font-semibold hover:bg-purple-700 disabled:opacity-50">
              {saving ? 'Enregistrement…' : 'Ajouter'}
            </button>
            <button type="button" onClick={() => setShowFormBenevole(false)} className="text-gray-500 px-6 py-2 rounded-full text-sm font-galey border border-gray-200 hover:bg-gray-50">
              Annuler
            </button>
          </div>
        </form>
      )}

      {/* Liste actifs */}
      {actifs.length === 0 && inactifs.length === 0 ? (
        <div className="text-center py-12 text-gray-400">
          <p className="text-4xl mb-3">👥</p>
          <p className="font-galey">Aucun membre dans votre équipe</p>
        </div>
      ) : (
        <div className="space-y-4">
          {actifs.length > 0 && (
            <div className="space-y-2">
              <p className="text-xs font-galey text-gray-400 uppercase tracking-wide">Actifs ({actifs.length})</p>
              {actifs.map(m => renderCard(m))}
            </div>
          )}
          {inactifs.length > 0 && (
            <div className="space-y-2">
              <p className="text-xs font-galey text-gray-400 uppercase tracking-wide">Inactifs ({inactifs.length})</p>
              {inactifs.map(m => renderCard(m))}
            </div>
          )}
        </div>
      )}

      {showAddEmploye && <AddPetsMatchModal uid={uid} type="employe" onClose={() => { setShowAddEmploye(false); load(); }} />}
      {showAddBenevole && <AddPetsMatchModal uid={uid} type="benevole" onClose={() => { setShowAddBenevole(false); load(); }} />}
      {editing && (
        editing.type === 'benevole'
          ? <EditBenevoleModal benevole={{ ...editing, id: editing.id, prenom: editing.prenom, nom: editing.nom, actif: editing.actif }} onClose={() => { setEditing(null); load(); }} />
          : <EditEmployeModal employe={{ id: editing.id, uid_employe: editing.uid_employe!, nom: `${editing.prenom} ${editing.nom}`.trim(), actif: editing.actif }} onClose={() => { setEditing(null); load(); }} />
      )}
      {assigning && assigning.uid_employe && (
        <AssignTaskModal uid={uid} assigneeUid={assigning.uid_employe}
          assigneeName={`${assigning.prenom} ${assigning.nom}`.trim()}
          onClose={() => { setAssigning(null); load(); }} />
      )}
    </div>
  );
}

// ── Onglet Employés (conservé pour compatibilité interne) ─────────────────────

function EmployesTab({ uid }: { uid: string }) {
  const [employes, setEmployes] = useState<Employe[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAdd, setShowAdd] = useState(false);
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const [editing, setEditing] = useState<Employe | null>(null);
  const [assigning, setAssigning] = useState<Employe | null>(null);

  const load = useCallback(async () => {
    if (!uid) return;
    setLoading(true);
    try {
      const { data: rows } = await supabase
        .from('employes').select('*').eq('uid_eleveur', uid).eq('actif', true)
        .or('profil_source.eq.association,profil_source.is.null')
        .or('type.is.null,type.neq.benevole')
        .order('created_at');

      const result: Employe[] = [];
      for (const e of (rows ?? [])) {
        const { data: u } = await supabase.from('users')
          .select('uid, firstname, lastname, name_elevage, is_elevage, profile_picture_url, profile_picture_url_elevage')
          .eq('uid', e.uid_employe).maybeSingle();
        const p = u as UserProfile | null;
        const nom = p?.is_elevage
          ? (p.name_elevage?.trim() || 'Élevage')
          : `${p?.firstname ?? ''} ${p?.lastname ?? ''}`.trim() || 'Utilisateur';
        const photo = p?.is_elevage ? p.profile_picture_url_elevage : p?.profile_picture_url;
        const taches = await fetchTachesPersonne(e.uid_employe, uid);
        result.push({ id: e.id, uid_employe: e.uid_employe, actif: e.actif, nom, photo, taches });
      }
      setEmployes(result);
    } finally {
      setLoading(false);
    }
  }, [uid]);

  useEffect(() => { load(); }, [load]);

  async function revoquer(emp: Employe) {
    if (!confirm(`Retirer ${emp.nom} de votre équipe ?`)) return;
    await supabase.from('employes').update({ actif: false }).eq('id', emp.id);
    await supabase.from('notifications').insert({
      uid: emp.uid_employe, type: 'employee_revoked',
      title: 'Accès retiré',
      body: `Vous avez été retiré de l'équipe`,
      data: { eleveurUid: uid },
      read: false,
    });
    load();
  }

  if (loading) return <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-teal-700" /></div>;

  return (
    <div className="space-y-3">
      {employes.length === 0 ? (
        <div className="text-center py-12 text-gray-400">
          <p className="text-4xl mb-3">👥</p>
          <p className="font-galey">Aucun employé dans votre équipe</p>
          <p className="text-sm mt-1">Invitez des utilisateurs PetsMatch pour leur assigner des tâches.</p>
        </div>
      ) : employes.map(e => {
        const isOpen = expanded[e.id] ?? false;
        const pendingTaches = e.taches ?? [];
        return (
          <div key={e.id} className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
            <div className="p-4 flex items-center gap-3 cursor-pointer hover:bg-gray-50 transition-colors"
              onClick={() => setExpanded(prev => ({ ...prev, [e.id]: !isOpen }))}>
              <div className="w-10 h-10 rounded-full bg-teal-50 flex items-center justify-center flex-shrink-0 overflow-hidden">
                {e.photo
                  ? <Image src={e.photo} alt={e.nom} width={40} height={40} className="w-full h-full object-cover" unoptimized />
                  : <span className="text-teal-600 font-bold text-sm">{e.nom[0]?.toUpperCase()}</span>}
              </div>
              <div className="flex-1 min-w-0">
                <p className="font-semibold font-galey text-gray-800 text-sm truncate">{e.nom}</p>
                <p className="text-xs text-gray-400 font-galey">
                  {pendingTaches.length === 0 ? 'Aucune tâche' : `${pendingTaches.length} tâche${pendingTaches.length > 1 ? 's' : ''} en cours`}
                </p>
              </div>
              <span className="text-gray-400 text-xs mr-1">{isOpen ? '▲' : '▼'}</span>
              <button onClick={ev => { ev.stopPropagation(); setAssigning(e); }}
                className="text-xs text-teal-600 hover:text-teal-800 font-galey px-2 py-1 rounded-lg hover:bg-teal-50 transition-colors">
                + Tâche
              </button>
              <button onClick={ev => { ev.stopPropagation(); setEditing(e); }}
                className="text-xs text-teal-600 hover:text-teal-800 font-galey px-2 py-1 rounded-lg hover:bg-teal-50 transition-colors">
                ✏️
              </button>
              <button onClick={ev => { ev.stopPropagation(); revoquer(e); }}
                className="text-xs text-red-400 hover:text-red-600 font-galey px-2 py-1 rounded-lg hover:bg-red-50 transition-colors">
                Révoquer
              </button>
            </div>

            {isOpen && (
              <div className="border-t border-gray-100 bg-gray-50 px-4 py-3 space-y-2">
                {pendingTaches.length === 0 ? (
                  <p className="text-xs text-gray-400 text-center py-2 font-galey">Aucune tâche assignée</p>
                ) : pendingTaches.map(t => <TacheRow key={t.id} t={t} />)}
              </div>
            )}
          </div>
        );
      })}

      <button onClick={() => setShowAdd(true)}
        className="w-full flex items-center justify-center gap-2 bg-teal-700 text-white font-galey font-semibold py-3 rounded-xl hover:bg-teal-800 transition-colors text-sm">
        + Inviter un employé
      </button>

      {showAdd && <AddPetsMatchModal uid={uid} type="employe" onClose={() => { setShowAdd(false); load(); }} />}
      {editing && <EditEmployeModal employe={editing} onClose={() => { setEditing(null); load(); }} />}
      {assigning && (
        <AssignTaskModal uid={uid} assigneeUid={assigning.uid_employe} assigneeName={assigning.nom}
          onClose={() => { setAssigning(null); load(); }} />
      )}
    </div>
  );
}

// ── Onglet Bénévoles ──────────────────────────────────────────────────────────

function BenevolesTab({ uid }: { uid: string }) {
  const [benevoles, setBenevoles] = useState<Benevole[]>([]);
  const [loading, setLoading] = useState(true);
  const [showPetsMatch, setShowPetsMatch] = useState(false);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<Benevole | null>(null);
  const [assigning, setAssigning] = useState<Benevole | null>(null);
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const [form, setForm] = useState({ prenom: '', nom: '', email: '', telephone: '', notes: '' });
  const [saving, setSaving] = useState(false);
  const [dbError, setDbError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!uid) return;
    setLoading(true);
    setDbError(null);
    try {
      const { data: rows, error } = await supabase
        .from('employes').select('*').eq('uid_eleveur', uid)
        .eq('type', 'benevole').order('created_at', { ascending: false });

      if (error) { setDbError(`Lecture: ${error.message} (code: ${error.code})`); setLoading(false); return; }

      const result: Benevole[] = [];
      for (const row of (rows ?? [])) {
        if (row.uid_employe) {
          const { data: u } = await supabase.from('users')
            .select('firstname, lastname, name_elevage, is_elevage, profile_picture_url, profile_picture_url_elevage, phone_number')
            .eq('uid', row.uid_employe).maybeSingle();
          const p = u as Omit<UserProfile, 'uid'> | null;
          const nom = p?.is_elevage
            ? (p.name_elevage?.trim() || 'Élevage')
            : `${p?.firstname ?? ''} ${p?.lastname ?? ''}`.trim() || 'Bénévole';
          const photo = p?.is_elevage ? p.profile_picture_url_elevage : p?.profile_picture_url;
          const taches = await fetchTachesPersonne(row.uid_employe, uid);
          result.push({
            id: row.id, uid_employe: row.uid_employe, actif: row.actif ?? true,
            prenom: nom.split(' ')[0] ?? nom, nom: nom.split(' ').slice(1).join(' ') || '',
            email: row.email, telephone: row.telephone || p?.phone_number || undefined,
            notes: row.notes, photo, taches,
          });
        } else {
          result.push({
            id: row.id, actif: row.actif ?? true,
            prenom: row.prenom ?? '', nom: row.nom ?? '',
            email: row.email, telephone: row.telephone, notes: row.notes,
          });
        }
      }
      setBenevoles(result);
    } finally {
      setLoading(false);
    }
  }, [uid]);

  useEffect(() => { load(); }, [load]);

  const handleAdd = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!uid || !form.prenom.trim() || !form.nom.trim()) return;
    setSaving(true);
    const { error } = await supabase.from('employes').insert({
      uid_eleveur: uid,
      prenom: form.prenom.trim(), nom: form.nom.trim(),
      email: form.email.trim() || null,
      telephone: form.telephone.trim() || null,
      notes: form.notes.trim() || null,
      actif: true, type: 'benevole',
      profil_source: 'association',
    });
    setSaving(false);
    if (error) { alert(`Erreur ajout: ${error.message} (${error.code})`); return; }
    setForm({ prenom: '', nom: '', email: '', telephone: '', notes: '' });
    setShowForm(false);
    load();
  };

  const toggleActif = async (id: string, actif: boolean, uidEmploye?: string) => {
    await supabase.from('employes').update({ actif: !actif }).eq('id', id);
    if (actif && uidEmploye) {
      await supabase.from('notifications').insert({
        uid: uidEmploye, type: 'employee_revoked',
        title: 'Statut bénévole modifié',
        body: 'Votre statut de bénévole a été désactivé',
        data: {},
        read: false,
      });
    }
    load();
  };

  const handleDelete = async (id: string) => {
    if (!confirm('Supprimer ce bénévole ?')) return;
    await supabase.from('employes').delete().eq('id', id);
    load();
  };

  const actifs   = benevoles.filter(b => b.actif);
  const inactifs = benevoles.filter(b => !b.actif);

  return (
    <div className="space-y-4">
      {dbError && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-3 text-xs text-red-700 font-galey break-all">
          ⚠️ {dbError}
          <br /><span className="text-red-400">uid: {uid || '(vide – non connecté?)'}</span>
        </div>
      )}
      <div className="flex gap-2 flex-wrap">
        <button onClick={() => setShowPetsMatch(true)}
          className="bg-teal-700 text-white px-4 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800 transition-colors">
          🔍 Chercher sur PetsMatch
        </button>
        <button onClick={() => setShowForm(!showForm)}
          className="border border-teal-700 text-teal-700 px-4 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-50 transition-colors">
          + Saisir manuellement
        </button>
      </div>

      {showForm && (
        <form onSubmit={handleAdd} className="bg-white rounded-2xl shadow-sm p-5 space-y-4 border border-teal-100">
          <h2 className="font-bold font-galey text-teal-800">Nouveau bénévole</h2>
          <div className="grid grid-cols-2 gap-4">
            <input placeholder="Prénom *" required value={form.prenom} onChange={e => setForm({ ...form, prenom: e.target.value })} className={inp} />
            <input placeholder="Nom *" required value={form.nom} onChange={e => setForm({ ...form, nom: e.target.value })} className={inp} />
            <input placeholder="Email" type="email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} className={inp} />
            <input placeholder="Téléphone" value={form.telephone} onChange={e => setForm({ ...form, telephone: e.target.value })} className={inp} />
          </div>
          <textarea placeholder="Notes" rows={2} value={form.notes} onChange={e => setForm({ ...form, notes: e.target.value })}
            className={inp + ' w-full resize-none'} />
          <div className="flex gap-3">
            <button type="submit" disabled={saving}
              className="bg-teal-700 text-white px-6 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800 disabled:opacity-50">
              {saving ? 'Enregistrement…' : 'Ajouter'}
            </button>
            <button type="button" onClick={() => setShowForm(false)}
              className="text-gray-500 px-6 py-2 rounded-full text-sm font-galey border border-gray-200 hover:bg-gray-50">
              Annuler
            </button>
          </div>
        </form>
      )}

      {loading ? (
        <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-teal-700" /></div>
      ) : benevoles.length === 0 ? (
        <div className="text-center py-12 text-gray-400">
          <p className="text-4xl mb-3">🤝</p>
          <p className="font-galey">Aucun bénévole enregistré</p>
        </div>
      ) : (
        <div className="space-y-4">
          {actifs.length > 0 && (
            <div>
              <h2 className="font-bold font-galey text-teal-700 mb-3">Actifs ({actifs.length})</h2>
              <div className="space-y-2">
                {actifs.map(b => (
                  <BenevoleCard key={b.id} b={b} uid={uid}
                    isOpen={expanded[b.id] ?? false}
                    onToggleOpen={() => setExpanded(prev => ({ ...prev, [b.id]: !(prev[b.id] ?? false) }))}
                    onToggle={() => toggleActif(b.id, b.actif, b.uid_employe)}
                    onEdit={() => setEditing(b)}
                    onDelete={() => handleDelete(b.id)}
                    onAssign={() => setAssigning(b)} />
                ))}
              </div>
            </div>
          )}
          {inactifs.length > 0 && (
            <div>
              <h2 className="font-bold font-galey text-gray-400 mb-3">Inactifs ({inactifs.length})</h2>
              <div className="space-y-2">
                {inactifs.map(b => (
                  <BenevoleCard key={b.id} b={b} uid={uid}
                    isOpen={expanded[b.id] ?? false}
                    onToggleOpen={() => setExpanded(prev => ({ ...prev, [b.id]: !(prev[b.id] ?? false) }))}
                    onToggle={() => toggleActif(b.id, b.actif, b.uid_employe)}
                    onEdit={() => setEditing(b)}
                    onDelete={() => handleDelete(b.id)}
                    onAssign={() => setAssigning(b)} />
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {showPetsMatch && <AddPetsMatchModal uid={uid} type="benevole" onClose={() => { setShowPetsMatch(false); load(); }} />}
      {editing && <EditBenevoleModal benevole={editing} onClose={() => { setEditing(null); load(); }} />}
      {assigning && assigning.uid_employe && (
        <AssignTaskModal uid={uid}
          assigneeUid={assigning.uid_employe}
          assigneeName={`${assigning.prenom} ${assigning.nom}`.trim()}
          onClose={() => { setAssigning(null); load(); }} />
      )}
    </div>
  );
}

// ── Ligne tâche ───────────────────────────────────────────────────────────────

function TacheRow({ t }: { t: Tache }) {
  const icon = t.statut === 'en_cours' ? '🔄' : t.statut === 'en_retard' ? '⚠️' : '📋';
  return (
    <div className="flex items-start gap-2 bg-white rounded-xl px-3 py-2 shadow-sm">
      <span className="text-xs mt-0.5">{icon}</span>
      <div className="flex-1 min-w-0">
        <p className="text-xs font-semibold text-gray-700 font-galey truncate">{t.label}</p>
        <div className="flex items-center gap-2 mt-0.5">
          {t.date && (
            <span className="text-xs text-gray-400 font-galey">
              📅 {new Date(t.date).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' })}
            </span>
          )}
          {t.animal_nom && <span className="text-xs text-teal-600 font-galey">🐾 {t.animal_nom}</span>}
        </div>
      </div>
    </div>
  );
}

// ── Card bénévole (expansible) ────────────────────────────────────────────────

function BenevoleCard({ b, uid: _uid, isOpen, onToggleOpen, onToggle, onEdit, onDelete, onAssign }: {
  b: Benevole; uid: string; isOpen: boolean;
  onToggleOpen: () => void; onToggle: () => void; onEdit: () => void; onDelete: () => void; onAssign: () => void;
}) {
  const displayName = `${b.prenom} ${b.nom}`.trim() || 'Bénévole';
  const taches = b.taches ?? [];

  return (
    <div className={`bg-white rounded-xl shadow-sm border overflow-hidden ${b.actif ? 'border-gray-100' : 'border-gray-100 opacity-60'}`}>
      <div className="p-4 flex items-center gap-3 cursor-pointer hover:bg-gray-50 transition-colors" onClick={onToggleOpen}>
        <div className="w-10 h-10 rounded-full bg-teal-50 flex items-center justify-center flex-shrink-0 overflow-hidden">
          {b.photo
            ? <Image src={b.photo} alt={displayName} width={40} height={40} className="w-full h-full object-cover" unoptimized />
            : <span className={`font-bold font-galey text-sm ${b.actif ? 'text-teal-600' : 'text-gray-400'}`}>{displayName[0]?.toUpperCase() ?? '?'}</span>}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <p className="font-semibold font-galey text-gray-900 truncate text-sm">{displayName}</p>
            {b.uid_employe && <span className="text-xs bg-teal-50 text-teal-600 px-1.5 py-0.5 rounded font-galey">PetsMatch</span>}
          </div>
          <div className="flex items-center gap-3 text-xs text-gray-500 font-galey">
            {b.email && <span>📧 {b.email}</span>}
            {b.telephone && <span>📞 {b.telephone}</span>}
          </div>
          {b.uid_employe && (
            <p className="text-xs text-gray-400 font-galey mt-0.5">
              {taches.length === 0 ? 'Aucune tâche' : `${taches.length} tâche${taches.length > 1 ? 's' : ''} en cours`}
            </p>
          )}
        </div>
        {b.uid_employe && <span className="text-gray-400 text-xs">{isOpen ? '▲' : '▼'}</span>}
        {b.uid_employe && (
          <button onClick={ev => { ev.stopPropagation(); onAssign(); }}
            className="text-xs text-teal-600 hover:text-teal-800 font-galey px-2 py-1 rounded-lg hover:bg-teal-50 transition-colors">
            + Tâche
          </button>
        )}
        <button onClick={ev => { ev.stopPropagation(); onToggle(); }}
          className={`text-xs px-2 py-1 rounded-full font-galey font-semibold transition-colors ${b.actif ? 'bg-green-100 text-green-700 hover:bg-green-200' : 'bg-gray-100 text-gray-500 hover:bg-gray-200'}`}>
          {b.actif ? 'Actif' : 'Inactif'}
        </button>
        <button onClick={ev => { ev.stopPropagation(); onEdit(); }} className="text-xs text-teal-500 hover:text-teal-700 px-1.5 py-1 rounded-lg hover:bg-teal-50 transition-colors">✏️</button>
        <button onClick={ev => { ev.stopPropagation(); onDelete(); }} className="text-red-400 hover:text-red-600 text-sm px-1">🗑</button>
      </div>

      {isOpen && b.uid_employe && (
        <div className="border-t border-gray-100 bg-gray-50 px-4 py-3 space-y-2">
          {taches.length === 0 ? (
            <p className="text-xs text-gray-400 text-center py-2 font-galey">Aucune tâche assignée — cliquez + Tâche pour en ajouter</p>
          ) : taches.map(t => <TacheRow key={t.id} t={t} />)}
        </div>
      )}
    </div>
  );
}

// ── Modal assignation de tâche ────────────────────────────────────────────────

function AssignTaskModal({ uid, assigneeUid, assigneeName, onClose }: {
  uid: string; assigneeUid: string; assigneeName: string; onClose: () => void;
}) {
  const activeProfileId = useActiveProfile();
  const today = new Date().toISOString().split('T')[0];
  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [enclos, setEnclos] = useState<Enclos[]>([]);
  const [form, setForm] = useState({
    titre: '', date: today, notes: '',
    cible: 'aucun' as 'aucun' | 'animal' | 'enclos',
    animal_id: '', enclos_id: '',
  });
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    Promise.all([
      supabase.from('animaux').select('id, nom, espece').eq('uid_eleveur', uid).order('nom'),
      supabase.from('chenil_enclos').select('id, nom').eq('uid_eleveur', uid).order('nom'),
    ]).then(([anRes, encRes]) => {
      setAnimaux((anRes.data ?? []) as Animal[]);
      setEnclos((encRes.data ?? []) as Enclos[]);
    });
  }, [uid]);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (!form.titre.trim() || !form.date) return;
    setSaving(true);
    const payload: Record<string, unknown> = {
      uid_eleveur: uid,
      ...(activeProfileId ? { eleveur_profile_id: activeProfileId } : {}),
      titre: form.titre.trim(),
      date: form.date,
      statut: 'a_faire',
      assigne_a: assigneeUid,
      profil_source: 'association',
      notes: form.notes.trim() || null,
      animal_id: form.cible === 'animal' && form.animal_id ? form.animal_id : null,
    };
    if (form.cible === 'enclos' && form.enclos_id) {
      const e = enclos.find(x => x.id === form.enclos_id);
      if (e) payload.notes = `${payload.notes ? payload.notes + '\n' : ''}Enclos: ${e.nom}`;
    }
    const { data: inserted, error } = await supabase.from('taches_elevage').insert(payload).select().single();
    setSaving(false);
    if (error) { alert(`Erreur: ${error.message}`); return; }
    if (assigneeUid) {
      await supabase.from('notifications').insert({
        uid: assigneeUid, type: 'tache',
        title: 'Nouvelle tâche assignée',
        body: form.titre.trim(),
        data: { eleveurUid: uid, tacheId: (inserted as { id: string }).id },
        read: false,
      });
    }
    onClose();
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white w-full max-w-sm rounded-2xl shadow-2xl p-6 space-y-4" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between">
          <h3 className="font-bold font-galey text-gray-800">Assigner une tâche</h3>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600">✕</button>
        </div>
        <p className="text-sm text-teal-700 font-galey font-semibold">→ {assigneeName}</p>
        <form onSubmit={save} className="space-y-3">
          <div>
            <label className="text-xs font-galey text-gray-500 mb-1 block">Titre *</label>
            <input required value={form.titre} onChange={e => setForm({ ...form, titre: e.target.value })}
              placeholder="Ex: Nettoyage, Soins, Promenade…" className={inp} />
          </div>
          <div>
            <label className="text-xs font-galey text-gray-500 mb-1 block">Date *</label>
            <input type="date" required value={form.date} onChange={e => setForm({ ...form, date: e.target.value })} className={inp} />
          </div>

          {/* Lien animal ou box */}
          <div>
            <label className="text-xs font-galey text-gray-500 mb-1 block">Concerne</label>
            <div className="flex gap-2">
              {(['aucun', 'animal', 'enclos'] as const).map(v => (
                <button key={v} type="button"
                  onClick={() => setForm({ ...form, cible: v, animal_id: '', enclos_id: '' })}
                  className={`flex-1 py-1.5 rounded-lg text-xs font-galey font-semibold border transition-colors ${form.cible === v ? 'bg-teal-700 text-white border-teal-700' : 'border-gray-200 text-gray-600 hover:bg-gray-50'}`}>
                  {v === 'aucun' ? 'Rien' : v === 'animal' ? '🐾 Animal' : '🏠 Box'}
                </button>
              ))}
            </div>
          </div>

          {form.cible === 'animal' && animaux.length > 0 && (
            <div>
              <label className="text-xs font-galey text-gray-500 mb-1 block">Animal</label>
              <select value={form.animal_id} onChange={e => setForm({ ...form, animal_id: e.target.value })} className={inp}>
                <option value="">— Sélectionner —</option>
                {animaux.map(a => (
                  <option key={a.id} value={a.id}>{a.nom}{a.espece ? ` (${a.espece})` : ''}</option>
                ))}
              </select>
            </div>
          )}

          {form.cible === 'enclos' && enclos.length > 0 && (
            <div>
              <label className="text-xs font-galey text-gray-500 mb-1 block">Box / Enclos</label>
              <select value={form.enclos_id} onChange={e => setForm({ ...form, enclos_id: e.target.value })} className={inp}>
                <option value="">— Sélectionner —</option>
                {enclos.map(enc => (
                  <option key={enc.id} value={enc.id}>{enc.nom}</option>
                ))}
              </select>
            </div>
          )}

          {form.cible === 'enclos' && enclos.length === 0 && (
            <p className="text-xs text-gray-400 font-galey">Aucun box/enclos configuré dans le chenil.</p>
          )}

          <div>
            <label className="text-xs font-galey text-gray-500 mb-1 block">Notes</label>
            <textarea rows={2} value={form.notes} onChange={e => setForm({ ...form, notes: e.target.value })}
              placeholder="Instructions supplémentaires…" className={inp + ' w-full resize-none'} />
          </div>

          <div className="flex gap-3 pt-1">
            <button type="submit" disabled={saving}
              className="flex-1 bg-teal-700 text-white py-2 rounded-xl text-sm font-galey font-semibold hover:bg-teal-800 disabled:opacity-50">
              {saving ? 'Enregistrement…' : 'Assigner'}
            </button>
            <button type="button" onClick={onClose}
              className="flex-1 border border-gray-200 text-gray-600 py-2 rounded-xl text-sm font-galey hover:bg-gray-50">
              Annuler
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ── Modal recherche PetsMatch (employé ou bénévole) ───────────────────────────

function AddPetsMatchModal({ uid, type, onClose }: { uid: string; type: 'employe' | 'benevole'; onClose: () => void }) {
  const [query, setQuery] = useState('');
  const [allUsers, setAllUsers] = useState<UserProfile[]>([]);
  const [results, setResults] = useState<UserProfile[]>([]);
  const [loading, setLoading] = useState(true);
  const [adding, setAdding] = useState<string | null>(null);

  useEffect(() => {
    supabase.from('users')
      .select('uid, firstname, lastname, name_elevage, is_elevage, profile_picture_url, profile_picture_url_elevage, phone_number')
      .neq('uid', uid).limit(500)
      .then(({ data }) => { setAllUsers((data ?? []) as UserProfile[]); setLoading(false); });
  }, [uid]);

  function search(q: string) {
    setQuery(q);
    if (q.trim().length < 2) { setResults([]); return; }
    const lq = q.toLowerCase();
    setResults(allUsers.filter(u =>
      `${u.firstname ?? ''} ${u.lastname ?? ''} ${u.name_elevage ?? ''}`.toLowerCase().includes(lq)
    ).slice(0, 15));
  }

  async function ajouter(u: UserProfile) {
    setAdding(u.uid);
    try {
      const { data: existing } = await supabase.from('employes')
        .select('id, actif').eq('uid_eleveur', uid).eq('uid_employe', u.uid)
        .eq('profil_source', 'association').maybeSingle();
      if (existing) {
        if ((existing as { actif: boolean }).actif) { alert('Cette personne est déjà dans votre équipe.'); setAdding(null); return; }
        await supabase.from('employes').update({ actif: true }).eq('id', (existing as { id: string }).id);
      } else {
        await supabase.from('employes').insert({
          uid_employe: u.uid, uid_eleveur: uid, actif: true,
          profil_source: 'association',
          type: type === 'benevole' ? 'benevole' : null,
          telephone: u.phone_number || null,
        });
      }
      await supabase.from('notifications').insert({
        uid: u.uid, type: 'employee_invite',
        title: type === 'benevole' ? 'Invitation bénévole' : 'Invitation à rejoindre une équipe',
        body: type === 'benevole'
          ? 'Vous avez été ajouté comme bénévole dans une association'
          : 'Vous avez été ajouté à l\'équipe d\'une association',
        data: { assoUid: uid },
        read: false,
      });
      onClose();
    } finally {
      setAdding(null);
    }
  }

  const nomUser   = (u: UserProfile) => u.is_elevage ? (u.name_elevage?.trim() || 'Élevage') : `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim() || 'Utilisateur';
  const photoUser = (u: UserProfile) => u.is_elevage ? u.profile_picture_url_elevage : u.profile_picture_url;

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4" onClick={onClose}>
      <div className="bg-white w-full max-w-md rounded-t-3xl sm:rounded-2xl shadow-2xl max-h-[85vh] flex flex-col" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <h3 className="font-bold font-galey text-gray-800">
            {type === 'benevole' ? 'Ajouter un bénévole PetsMatch' : 'Inviter un employé'}
          </h3>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl leading-none">✕</button>
        </div>
        <div className="p-4">
          <input type="text" placeholder="Rechercher par prénom ou nom…" value={query}
            onChange={e => search(e.target.value)} autoFocus
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
        </div>
        <div className="flex-1 overflow-y-auto px-4 pb-4 space-y-1">
          {loading ? (
            <div className="flex justify-center py-8"><div className="animate-spin rounded-full h-6 w-6 border-b-2 border-teal-700" /></div>
          ) : query.length < 2 ? (
            <p className="text-sm text-gray-400 font-galey text-center py-4">Tapez au moins 2 lettres pour rechercher</p>
          ) : results.length === 0 ? (
            <p className="text-sm text-gray-400 font-galey text-center py-4">Aucun utilisateur trouvé</p>
          ) : results.map(u => {
            const nom   = nomUser(u);
            const photo = photoUser(u);
            return (
              <button key={u.uid} onClick={() => ajouter(u)} disabled={adding === u.uid}
                className="w-full flex items-center gap-3 p-3 rounded-xl hover:bg-teal-50 transition-colors text-left disabled:opacity-50">
                <div className="w-9 h-9 rounded-full bg-teal-50 flex items-center justify-center flex-shrink-0 overflow-hidden">
                  {photo
                    ? <Image src={photo} alt={nom} width={36} height={36} className="w-full h-full object-cover" unoptimized />
                    : <span className="text-teal-600 font-bold text-sm">{nom[0]?.toUpperCase()}</span>}
                </div>
                <div className="flex-1">
                  <p className="font-galey font-semibold text-sm text-gray-800">{nom}</p>
                  {u.phone_number && <p className="text-xs text-gray-400 font-galey">📞 {u.phone_number}</p>}
                </div>
                <span className="text-teal-600 text-xl">{adding === u.uid ? '…' : '+'}</span>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

// ── Modal édition employé ─────────────────────────────────────────────────────

function EditEmployeModal({ employe, onClose }: { employe: Employe; onClose: () => void }) {
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    supabase.from('employes').select('notes').eq('id', employe.id).maybeSingle()
      .then(({ data }) => {
        if (data) { setNotes((data as { notes?: string }).notes ?? ''); }
      });
  }, [employe.id]);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    await supabase.from('employes').update({ notes: notes.trim() || null }).eq('id', employe.id);
    setSaving(false);
    onClose();
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white w-full max-w-sm rounded-2xl shadow-2xl p-6 space-y-4" onClick={e => e.stopPropagation()}>
        <h3 className="font-bold font-galey text-gray-800">Notes — {employe.nom}</h3>
        <form onSubmit={save} className="space-y-3">
          <div>
            <label className="text-xs font-galey text-gray-500 mb-1 block">Notes internes</label>
            <textarea rows={4} value={notes} onChange={e => setNotes(e.target.value)} placeholder="Notes visibles uniquement par vous…" className={inp + ' w-full resize-none'} />
          </div>
          <div className="flex gap-3 pt-2">
            <button type="submit" disabled={saving} className="flex-1 bg-teal-700 text-white py-2 rounded-xl text-sm font-galey font-semibold hover:bg-teal-800 disabled:opacity-50">
              {saving ? 'Enregistrement…' : 'Enregistrer'}
            </button>
            <button type="button" onClick={onClose} className="flex-1 border border-gray-200 text-gray-600 py-2 rounded-xl text-sm font-galey hover:bg-gray-50">
              Annuler
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ── Modal édition bénévole ────────────────────────────────────────────────────

function EditBenevoleModal({ benevole, onClose }: { benevole: Benevole; onClose: () => void }) {
  const [form, setForm] = useState({
    prenom: benevole.prenom, nom: benevole.nom,
    email: benevole.email ?? '', telephone: benevole.telephone ?? '', notes: benevole.notes ?? '',
  });
  const [saving, setSaving] = useState(false);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    await supabase.from('employes').update({
      prenom: form.prenom.trim() || null,
      nom:    form.nom.trim()    || null,
      email:  form.email.trim()  || null,
      telephone: form.telephone.trim() || null,
      notes: form.notes.trim()   || null,
    }).eq('id', benevole.id);
    setSaving(false);
    onClose();
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white w-full max-w-sm rounded-2xl shadow-2xl p-6 space-y-4" onClick={e => e.stopPropagation()}>
        <h3 className="font-bold font-galey text-gray-800">
          Modifier — {`${benevole.prenom} ${benevole.nom}`.trim() || 'Bénévole'}
        </h3>
        <form onSubmit={save} className="space-y-3">
          {!benevole.uid_employe && (
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs font-galey text-gray-500 mb-1 block">Prénom</label>
                <input value={form.prenom} onChange={e => setForm({ ...form, prenom: e.target.value })} className={inp} />
              </div>
              <div>
                <label className="text-xs font-galey text-gray-500 mb-1 block">Nom</label>
                <input value={form.nom} onChange={e => setForm({ ...form, nom: e.target.value })} className={inp} />
              </div>
            </div>
          )}
          <div>
            <label className="text-xs font-galey text-gray-500 mb-1 block">Email</label>
            <input type="email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} className={inp} />
          </div>
          <div>
            <label className="text-xs font-galey text-gray-500 mb-1 block">Téléphone</label>
            <input value={form.telephone} onChange={e => setForm({ ...form, telephone: e.target.value })} className={inp} />
          </div>
          <div>
            <label className="text-xs font-galey text-gray-500 mb-1 block">Notes</label>
            <textarea rows={2} value={form.notes} onChange={e => setForm({ ...form, notes: e.target.value })} className={inp + ' w-full resize-none'} />
          </div>
          <div className="flex gap-3 pt-2">
            <button type="submit" disabled={saving} className="flex-1 bg-teal-700 text-white py-2 rounded-xl text-sm font-galey font-semibold hover:bg-teal-800 disabled:opacity-50">
              {saving ? 'Enregistrement…' : 'Enregistrer'}
            </button>
            <button type="button" onClick={onClose} className="flex-1 border border-gray-200 text-gray-600 py-2 rounded-xl text-sm font-galey hover:bg-gray-50">
              Annuler
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
