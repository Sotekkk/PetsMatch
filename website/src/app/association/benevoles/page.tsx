'use client';

import { useEffect, useState, useCallback } from 'react';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

// ── Types ──────────────────────────────────────────────────────────────────────

interface Benevole {
  id: string;
  prenom: string;
  nom: string;
  email?: string;
  telephone?: string;
  notes?: string;
  actif: boolean;
}

interface Employe {
  id: string;
  uid_employe: string;
  employe_profile_id?: string | null;
  actif: boolean;
  nom: string;
  photo?: string | null;
}

interface UserProfile {
  uid: string;
  firstname: string | null;
  lastname: string | null;
  name_elevage: string | null;
  is_elevage: boolean;
  profile_picture_url: string | null;
  profile_picture_url_elevage: string | null;
}

const inp = 'px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300';

// ── Page principale ────────────────────────────────────────────────────────────

export default function BenevolesWebPage() {
  const { user } = useAuth();
  const [tab, setTab] = useState<'employes' | 'benevoles'>('employes');

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold font-galey text-teal-800">Équipe & Bénévoles</h1>

      {/* Explication */}
      <div className="bg-teal-50 border border-teal-100 rounded-xl px-4 py-3 text-sm font-galey text-teal-700">
        <p><strong>Employés</strong> : utilisateurs PetsMatch invités dans votre équipe — ils peuvent recevoir des tâches.</p>
        <p className="mt-1"><strong>Bénévoles</strong> : personnes sans compte PetsMatch, saisies manuellement.</p>
      </div>

      {/* Tabs */}
      <div className="flex gap-2">
        {([['employes', '👥 Employés'], ['benevoles', '🤝 Bénévoles']] as const).map(([v, l]) => (
          <button key={v} onClick={() => setTab(v)}
            className={`px-4 py-2 rounded-full text-sm font-galey font-semibold transition-colors ${
              tab === v ? 'bg-teal-700 text-white' : 'bg-white border border-gray-200 text-gray-600 hover:bg-gray-50'
            }`}>
            {l}
          </button>
        ))}
      </div>

      {tab === 'employes'
        ? <EmployesTab uid={user?.uid ?? ''} />
        : <BenevolesTab uid={user?.uid ?? ''} />}
    </div>
  );
}

// ── Tab Employés (utilisateurs PetsMatch liés) ────────────────────────────────

function EmployesTab({ uid }: { uid: string }) {
  const [employes, setEmployes] = useState<Employe[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAdd, setShowAdd] = useState(false);

  const load = useCallback(async () => {
    if (!uid) return;
    setLoading(true);
    try {
      const { data: rows } = await supabase
        .from('employes').select('*').eq('uid_eleveur', uid).eq('actif', true)
        .eq('profil_source', 'association').order('created_at');

      const result: Employe[] = [];
      for (const e of (rows ?? [])) {
        const { data: cp } = await supabase.from('user_profiles')
          .select('uid, firstname, lastname, nom, profile_type, avatar_url, profile_picture_url_pro')
          .eq('uid', e.uid_employe).eq('is_main', true).maybeSingle();
        const p: UserProfile | null = cp ? {
          uid: cp.uid, firstname: cp.firstname, lastname: cp.lastname,
          name_elevage: cp.nom, is_elevage: cp.profile_type === 'eleveur',
          profile_picture_url: cp.avatar_url, profile_picture_url_elevage: cp.profile_picture_url_pro,
        } : null;
        const nom = p?.is_elevage
          ? (p.name_elevage?.trim() || 'Élevage')
          : `${p?.firstname ?? ''} ${p?.lastname ?? ''}`.trim() || 'Utilisateur';
        const photo = p?.is_elevage ? p.profile_picture_url_elevage : p?.profile_picture_url;
        result.push({ id: e.id, uid_employe: e.uid_employe, employe_profile_id: e.employe_profile_id ?? null, actif: e.actif, nom, photo });
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
      body: 'Vous avez été retiré de l\'équipe',
      ...(emp.employe_profile_id ? { profile_id: emp.employe_profile_id } : {}),
      data: { assoUid: uid },
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
      ) : employes.map(e => (
        <div key={e.id} className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 flex items-center gap-3">
          <div className="w-10 h-10 rounded-full bg-teal-50 flex items-center justify-center flex-shrink-0 overflow-hidden">
            {e.photo
              ? <Image src={e.photo} alt={e.nom} width={40} height={40} className="w-full h-full object-cover" unoptimized />
              : <span className="text-teal-600 font-bold text-sm">{e.nom[0]?.toUpperCase()}</span>}
          </div>
          <span className="flex-1 font-semibold font-galey text-gray-800 text-sm">{e.nom}</span>
          <button onClick={() => revoquer(e)}
            className="text-xs text-red-400 hover:text-red-600 font-galey px-2 py-1 rounded-lg hover:bg-red-50 transition-colors">
            Révoquer
          </button>
        </div>
      ))}

      <button onClick={() => setShowAdd(true)}
        className="w-full flex items-center justify-center gap-2 bg-teal-700 text-white font-galey font-semibold py-3 rounded-xl hover:bg-teal-800 transition-colors text-sm">
        + Inviter un employé
      </button>

      {showAdd && <AddEmployeModal uid={uid} onClose={() => { setShowAdd(false); load(); }} />}
    </div>
  );
}

// ── Modal ajout employé ───────────────────────────────────────────────────────

function AddEmployeModal({ uid, onClose, type = 'employe' }: { uid: string; onClose: () => void; type?: 'employe' | 'benevole' }) {
  const [query, setQuery] = useState('');
  const [allUsers, setAllUsers] = useState<UserProfile[]>([]);
  const [results, setResults] = useState<UserProfile[]>([]);
  const [loading, setLoading] = useState(true);
  const [adding, setAdding] = useState<string | null>(null);

  useEffect(() => {
    supabase.from('user_profiles')
      .select('uid, firstname, lastname, nom, profile_type, avatar_url, profile_picture_url_pro')
      .neq('uid', uid).eq('is_main', true).limit(500)
      .then(({ data }) => {
        setAllUsers((data ?? []).map(cp => ({
          uid: cp.uid, firstname: cp.firstname, lastname: cp.lastname,
          name_elevage: cp.nom, is_elevage: cp.profile_type === 'eleveur',
          profile_picture_url: cp.avatar_url, profile_picture_url_elevage: cp.profile_picture_url_pro,
        })));
        setLoading(false);
      });
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
      // Check uniquement dans le profil association
      const { data: existing } = await supabase.from('employes')
        .select().eq('uid_eleveur', uid).eq('uid_employe', u.uid)
        .eq('profil_source', 'association').maybeSingle();
      if (existing) {
        if (existing.actif) { alert('Cette personne est déjà dans votre équipe.'); return; }
        await supabase.from('employes').update({ actif: true }).eq('id', existing.id);
      } else {
        await supabase.from('employes').insert({
          uid_employe: u.uid, uid_eleveur: uid, actif: true,
          profil_source: 'association',
          type: type === 'benevole' ? 'benevole' : null,
        });
      }
      const { data: targetParticulier } = await supabase.from('user_profiles')
        .select('id').eq('uid', u.uid).eq('profile_type', 'particulier').eq('is_main', true).maybeSingle();
      await supabase.from('notifications').insert({
        uid: u.uid, type: 'employee_invite',
        title: type === 'benevole' ? 'Invitation bénévole' : 'Invitation à rejoindre une équipe',
        body: type === 'benevole'
          ? 'Vous avez été ajouté comme bénévole dans une association'
          : 'Vous avez été ajouté à l\'équipe d\'une association',
        ...(targetParticulier?.id ? { profile_id: targetParticulier.id } : {}),
        data: { assoUid: uid },
        read: false,
      });
      onClose();
    } finally {
      setAdding(null);
    }
  }

  const nomUser = (u: UserProfile) => u.is_elevage
    ? (u.name_elevage?.trim() || 'Élevage')
    : `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim() || 'Utilisateur';

  const photoUser = (u: UserProfile) => u.is_elevage ? u.profile_picture_url_elevage : u.profile_picture_url;

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4" onClick={onClose}>
      <div className="bg-white w-full max-w-md rounded-t-3xl sm:rounded-2xl shadow-2xl max-h-[85vh] flex flex-col"
        onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <h3 className="font-bold font-galey text-gray-800">
            {type === 'benevole' ? 'Ajouter un bénévole PetsMatch' : 'Inviter un employé'}
          </h3>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl leading-none">✕</button>
        </div>
        <div className="p-4">
          <input
            type="text" placeholder="Rechercher par prénom ou nom…" value={query}
            onChange={e => search(e.target.value)} autoFocus
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300"
          />
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
                <span className="flex-1 font-galey font-semibold text-sm text-gray-800">{nom}</span>
                <span className="text-teal-600 text-xl">{adding === u.uid ? '…' : '+'}</span>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

// ── Tab Bénévoles (saisie manuelle) ───────────────────────────────────────────

function BenevolesTab({ uid }: { uid: string }) {
  const [benevoles, setBenevoles] = useState<Benevole[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [showAdd, setShowAdd] = useState(false);
  const [form, setForm] = useState({ prenom: '', nom: '', email: '', telephone: '', notes: '' });
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    if (!uid) return;
    const { data } = await supabase
      .from('employes').select('*').eq('uid_eleveur', uid)
      .eq('type', 'benevole').eq('profil_source', 'association').order('nom');
    setBenevoles(data ?? []);
    setLoading(false);
  }, [uid]);

  useEffect(() => { load(); }, [load]);

  const handleAdd = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!uid || !form.prenom.trim() || !form.nom.trim()) return;
    setSaving(true);
    await supabase.from('employes').insert({
      uid_eleveur: uid,
      prenom: form.prenom.trim(), nom: form.nom.trim(),
      email: form.email.trim() || null,
      telephone: form.telephone.trim() || null,
      notes: form.notes.trim() || null,
      actif: true, type: 'benevole',
      profil_source: 'association',
    });
    setForm({ prenom: '', nom: '', email: '', telephone: '', notes: '' });
    setShowForm(false);
    setSaving(false);
    load();
  };

  const toggleActif = async (id: string, actif: boolean) => {
    await supabase.from('employes').update({ actif: !actif }).eq('id', id);
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
      <div className="flex gap-2 flex-wrap">
        <button onClick={() => setShowAdd(true)}
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
                {actifs.map(b => <BenevoleCard key={b.id} b={b} onToggle={() => toggleActif(b.id, b.actif)} onDelete={() => handleDelete(b.id)} />)}
              </div>
            </div>
          )}
          {inactifs.length > 0 && (
            <div>
              <h2 className="font-bold font-galey text-gray-400 mb-3">Inactifs ({inactifs.length})</h2>
              <div className="space-y-2">
                {inactifs.map(b => <BenevoleCard key={b.id} b={b} onToggle={() => toggleActif(b.id, b.actif)} onDelete={() => handleDelete(b.id)} />)}
              </div>
            </div>
          )}
        </div>
      )}

      {showAdd && (
        <AddEmployeModal
          uid={uid}
          type="benevole"
          onClose={() => { setShowAdd(false); load(); }}
        />
      )}
    </div>
  );
}

function BenevoleCard({ b, onToggle, onDelete }: { b: Benevole; onToggle: () => void; onDelete: () => void }) {
  return (
    <div className={`bg-white rounded-xl shadow-sm p-4 flex items-center gap-4 border ${b.actif ? 'border-gray-100' : 'border-gray-100 opacity-60'}`}>
      <div className={`w-10 h-10 rounded-full flex items-center justify-center font-bold font-galey text-white ${b.actif ? 'bg-teal-700' : 'bg-gray-400'}`}>
        {b.prenom[0]?.toUpperCase() ?? '?'}
      </div>
      <div className="flex-1 min-w-0">
        <p className="font-semibold font-galey text-gray-900">{b.prenom} {b.nom}</p>
        <div className="flex items-center gap-3 text-xs text-gray-500 font-galey">
          {b.email && <span>📧 {b.email}</span>}
          {b.telephone && <span>📞 {b.telephone}</span>}
        </div>
        {b.notes && <p className="text-xs text-gray-400 font-galey truncate mt-0.5">{b.notes}</p>}
      </div>
      <div className="flex items-center gap-2">
        <button onClick={onToggle}
          className={`text-xs px-3 py-1 rounded-full font-galey font-semibold transition-colors ${b.actif ? 'bg-green-100 text-green-700 hover:bg-green-200' : 'bg-gray-100 text-gray-500 hover:bg-gray-200'}`}>
          {b.actif ? 'Actif' : 'Inactif'}
        </button>
        <button onClick={onDelete} className="text-red-400 hover:text-red-600 text-sm">🗑</button>
      </div>
    </div>
  );
}
