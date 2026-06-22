'use client';

import { useEffect, useState, useCallback } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface Animal { id: string; nom: string; statut?: string }

interface FA {
  id: string;
  fa_uid?: string;
  prenom: string;
  nom: string;
  email?: string;
  telephone?: string;
  ville?: string;
  code_postal?: string;
  adresse?: string;
  capacite_max: number;
  notes?: string;
  actif: boolean;
  animaux?: Animal[];
}

interface PetsMatchUser {
  uid: string;
  firstname?: string;
  lastname?: string;
  email?: string;
  phone_number?: string;
  profile_picture_url?: string;
}

const EMPTY_FORM = {
  prenom: '', nom: '', email: '', telephone: '',
  adresse: '', ville: '', code_postal: '', notes: '', capacite_max: 1,
};

export default function FamillesAccueilWebPage() {
  const { user } = useAuth();
  const [fas, setFas] = useState<FA[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState(EMPTY_FORM);
  const [saving, setSaving] = useState(false);

  // PetsMatch user search
  const [allUsers, setAllUsers] = useState<PetsMatchUser[]>([]);
  const [userSearch, setUserSearch] = useState('');
  const [userResults, setUserResults] = useState<PetsMatchUser[]>([]);
  const [linkedUid, setLinkedUid] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!user) return;
    const { data } = await supabase
      .from('familles_accueil')
      .select('*, animaux(id, nom, statut)')
      .eq('association_uid', user.uid)
      .eq('actif', true)
      .order('nom');
    setFas(data ?? []);
    setLoading(false);
  }, [user]);

  const loadUsers = useCallback(async () => {
    if (!user) return;
    const { data } = await supabase
      .from('users')
      .select('uid, firstname, lastname, email, phone_number, profile_picture_url')
      .neq('uid', user.uid)
      .limit(500);
    setAllUsers(data ?? []);
  }, [user]);

  useEffect(() => { load(); loadUsers(); }, [load, loadUsers]);

  const handleUserSearch = (q: string) => {
    setUserSearch(q);
    if (q.trim().length < 2) { setUserResults([]); return; }
    const query = q.toLowerCase();
    setUserResults(
      allUsers
        .filter(u => `${u.firstname ?? ''} ${u.lastname ?? ''} ${u.email ?? ''}`.toLowerCase().includes(query))
        .slice(0, 8)
    );
  };

  const selectUser = (u: PetsMatchUser) => {
    setLinkedUid(u.uid);
    setForm(f => ({
      ...f,
      prenom: u.firstname ?? '',
      nom: u.lastname ?? '',
      email: u.email ?? '',
      telephone: u.phone_number ?? '',
    }));
    setUserSearch(`${u.firstname ?? ''} ${u.lastname ?? ''}`.trim());
    setUserResults([]);
  };

  const resetForm = () => {
    setForm(EMPTY_FORM);
    setLinkedUid(null);
    setUserSearch('');
    setUserResults([]);
    setShowForm(false);
  };

  const handleAdd = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user || !form.prenom.trim() || !form.nom.trim()) return;
    setSaving(true);
    await supabase.from('familles_accueil').insert({
      association_uid: user.uid,
      fa_uid: linkedUid ?? null,
      prenom: form.prenom.trim(),
      nom: form.nom.trim(),
      email: form.email.trim() || null,
      telephone: form.telephone.trim() || null,
      adresse: form.adresse.trim() || null,
      ville: form.ville.trim() || null,
      code_postal: form.code_postal.trim() || null,
      capacite_max: form.capacite_max,
      notes: form.notes.trim() || null,
      actif: true,
    });
    resetForm();
    setSaving(false);
    load();
  };

  const handleDelete = async (id: string) => {
    if (!confirm('Supprimer cette famille d\'accueil ?')) return;
    await supabase.from('familles_accueil').update({ actif: false }).eq('id', id);
    load();
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold font-galey text-teal-800">Familles d&apos;accueil</h1>
        <button onClick={() => setShowForm(!showForm)}
          className="bg-teal-700 text-white px-4 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800 transition-colors">
          + Ajouter une FA
        </button>
      </div>

      {showForm && (
        <form onSubmit={handleAdd} className="bg-white rounded-2xl shadow-sm p-5 space-y-4 border border-teal-100">
          <h2 className="font-bold font-galey text-teal-800">Nouvelle famille d&apos;accueil</h2>

          {/* Recherche utilisateur PetsMatch */}
          <div className="bg-teal-50 rounded-xl p-4 border border-teal-100 space-y-2">
            <p className="text-xs font-semibold font-galey text-teal-700 flex items-center gap-1">
              <span>🔍</span> Lier un utilisateur PetsMatch (optionnel)
            </p>
            <div className="relative">
              <input
                type="text"
                placeholder="Chercher par nom, prénom ou email…"
                value={userSearch}
                onChange={e => handleUserSearch(e.target.value)}
                className="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300 bg-white"
              />
              {userResults.length > 0 && (
                <div className="absolute z-10 w-full bg-white border border-gray-200 rounded-xl shadow-lg mt-1 overflow-hidden">
                  {userResults.map(u => (
                    <button key={u.uid} type="button" onClick={() => selectUser(u)}
                      className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-teal-50 transition-colors text-left">
                      <div className="w-8 h-8 rounded-full bg-teal-700 flex items-center justify-center text-white text-xs font-bold font-galey flex-shrink-0">
                        {(u.firstname?.[0] ?? u.email?.[0] ?? '?').toUpperCase()}
                      </div>
                      <div>
                        <p className="text-sm font-semibold font-galey text-gray-800">
                          {u.firstname} {u.lastname}
                        </p>
                        {u.email && <p className="text-xs text-gray-500 font-galey">{u.email}</p>}
                      </div>
                    </button>
                  ))}
                </div>
              )}
            </div>
            {linkedUid && (
              <p className="text-xs text-teal-700 font-galey flex items-center gap-1">
                <span>✓</span> Compte PetsMatch lié — infos pré-remplies
              </p>
            )}
          </div>

          {/* Champs manuels */}
          <div className="grid grid-cols-2 gap-4">
            <input placeholder="Prénom *" required value={form.prenom}
              onChange={e => setForm({ ...form, prenom: e.target.value })}
              className="px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
            <input placeholder="Nom *" required value={form.nom}
              onChange={e => setForm({ ...form, nom: e.target.value })}
              className="px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
            <input placeholder="Email" type="email" value={form.email}
              onChange={e => setForm({ ...form, email: e.target.value })}
              className="px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
            <input placeholder="Téléphone" value={form.telephone}
              onChange={e => setForm({ ...form, telephone: e.target.value })}
              className="px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
            <input placeholder="Adresse" value={form.adresse}
              onChange={e => setForm({ ...form, adresse: e.target.value })}
              className="px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
            <div className="flex gap-2">
              <input placeholder="Ville" value={form.ville}
                onChange={e => setForm({ ...form, ville: e.target.value })}
                className="flex-1 px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
              <input placeholder="CP" value={form.code_postal}
                onChange={e => setForm({ ...form, code_postal: e.target.value })}
                className="w-24 px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
            </div>
          </div>

          <div className="flex items-center gap-3">
            <label className="text-sm font-galey text-gray-700">Capacité max :</label>
            <button type="button" onClick={() => setForm(f => ({ ...f, capacite_max: Math.max(1, f.capacite_max - 1) }))}
              className="w-8 h-8 rounded-full bg-gray-100 hover:bg-gray-200 flex items-center justify-center font-bold">−</button>
            <span className="font-bold font-galey text-teal-800 w-6 text-center">{form.capacite_max}</span>
            <button type="button" onClick={() => setForm(f => ({ ...f, capacite_max: f.capacite_max + 1 }))}
              className="w-8 h-8 rounded-full bg-gray-100 hover:bg-gray-200 flex items-center justify-center font-bold">+</button>
          </div>

          <textarea placeholder="Notes (espèces acceptées, contraintes…)" rows={2} value={form.notes}
            onChange={e => setForm({ ...form, notes: e.target.value })}
            className="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />

          <div className="flex gap-3">
            <button type="submit" disabled={saving}
              className="bg-teal-700 text-white px-6 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800 disabled:opacity-50">
              {saving ? 'Enregistrement…' : 'Ajouter'}
            </button>
            <button type="button" onClick={resetForm}
              className="text-gray-500 px-6 py-2 rounded-full text-sm font-galey border border-gray-200 hover:bg-gray-50">
              Annuler
            </button>
          </div>
        </form>
      )}

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
        </div>
      ) : fas.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <p className="text-4xl mb-3">🏡</p>
          <p className="font-galey">Aucune famille d&apos;accueil enregistrée</p>
          <button onClick={() => setShowForm(true)}
            className="mt-4 bg-teal-700 text-white px-5 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800">
            + Ajouter une FA
          </button>
        </div>
      ) : (
        <div className="grid md:grid-cols-2 gap-4">
          {fas.map((fa) => {
            const nbAnimaux = fa.animaux?.length ?? 0;
            const dispo = fa.capacite_max - nbAnimaux;
            return (
              <div key={fa.id} className="bg-white rounded-2xl shadow-sm p-5 border border-gray-100">
                <div className="flex items-start justify-between mb-3">
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-full bg-teal-700 flex items-center justify-center font-bold font-galey text-white">
                      {fa.prenom[0]?.toUpperCase()}
                    </div>
                    <div>
                      <div className="flex items-center gap-2">
                        <p className="font-bold font-galey text-gray-900">{fa.prenom} {fa.nom}</p>
                        {fa.fa_uid && (
                          <span className="text-xs bg-purple-100 text-purple-700 px-1.5 py-0.5 rounded-full font-galey">
                            🐾 PetsMatch
                          </span>
                        )}
                      </div>
                      {fa.ville && <p className="text-xs text-gray-500 font-galey">{fa.ville} {fa.code_postal}</p>}
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className={`text-xs font-bold font-galey px-2 py-1 rounded-full ${
                      dispo > 0 ? 'bg-green-100 text-green-700' : 'bg-orange-100 text-orange-700'
                    }`}>
                      {nbAnimaux}/{fa.capacite_max}
                    </span>
                    <button onClick={() => handleDelete(fa.id)} className="text-red-400 hover:text-red-600 text-sm">🗑</button>
                  </div>
                </div>

                <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-gray-500 font-galey mb-3">
                  {fa.email && <span>📧 {fa.email}</span>}
                  {fa.telephone && <span>📞 {fa.telephone}</span>}
                </div>

                {fa.animaux && fa.animaux.length > 0 && (
                  <div>
                    <p className="text-xs font-semibold font-galey text-teal-700 mb-1">En accueil :</p>
                    <div className="flex flex-wrap gap-1">
                      {fa.animaux.map((a) => (
                        <span key={a.id} className="text-xs bg-teal-50 text-teal-800 px-2 py-0.5 rounded-full font-galey">
                          {a.nom}
                        </span>
                      ))}
                    </div>
                  </div>
                )}

                {fa.notes && (
                  <p className="text-xs text-gray-400 font-galey mt-2 line-clamp-2">{fa.notes}</p>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
