'use client';

import { useEffect, useState, useCallback } from 'react';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

interface Animal { id: string; nom: string; espece?: string; race?: string; statut?: string; photo_url?: string }

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
  rue?: string;
  ville_elevage?: string;
  code_postal_elevage?: string;
}

interface AnimalDispo { id: string; nom: string; espece?: string; race?: string; photo_url?: string }

const EMPTY_FORM = {
  prenom: '', nom: '', email: '', telephone: '',
  adresse: '', ville: '', code_postal: '', notes: '', capacite_max: 1,
};

export default function FamillesAccueilWebPage() {
  const { user } = useAuth();
  const profileId = useActiveProfile();
  const [fas, setFas] = useState<FA[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editingFa, setEditingFa] = useState<FA | null>(null);
  const [form, setForm] = useState(EMPTY_FORM);
  const [saving, setSaving] = useState(false);
  const [linkedUid, setLinkedUid] = useState<string | null>(null);

  // Recherche utilisateur
  const [allUsers, setAllUsers] = useState<PetsMatchUser[]>([]);
  const [userSearch, setUserSearch] = useState('');
  const [userResults, setUserResults] = useState<PetsMatchUser[]>([]);

  // Placement animal
  const [placingFa, setPlacingFa] = useState<FA | null>(null);
  const [animauxDispo, setAnimauxDispo] = useState<AnimalDispo[]>([]);
  const [loadingAnimaux, setLoadingAnimaux] = useState(false);
  const [placing, setPlacing] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!user) return;
    let q = supabase.from('familles_accueil')
      .select('*, animaux(id, nom, espece, race, statut, photo_url)')
      .eq('actif', true).order('nom');
    if (profileId) {
      q = q.eq('association_profile_id', profileId) as typeof q;
    } else {
      q = q.eq('association_uid', user.uid) as typeof q;
    }
    const { data } = await q;
    setFas(data ?? []);
    setLoading(false);
  }, [user, profileId]);

  const loadUsers = useCallback(async () => {
    if (!user) return;
    const [{ data: profiles }, { data: emails }] = await Promise.all([
      supabase.from('user_profiles')
        .select('uid, firstname, lastname, phone_number, avatar_url, rue, ville_pro, code_postal_pro')
        .neq('uid', user.uid).eq('is_main', true).limit(500),
      supabase.from('users').select('uid, email').neq('uid', user.uid).limit(500),
    ]);
    const emailByUid = new Map((emails ?? []).map(u => [u.uid, u.email as string]));
    setAllUsers((profiles ?? []).map(p => ({
      uid: p.uid, firstname: p.firstname, lastname: p.lastname,
      email: emailByUid.get(p.uid), phone_number: p.phone_number,
      profile_picture_url: p.avatar_url,
      rue: p.rue, ville_elevage: p.ville_pro, code_postal_elevage: p.code_postal_pro,
    })));
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
      adresse: u.rue ?? f.adresse,
      ville: u.ville_elevage ?? f.ville,
      code_postal: u.code_postal_elevage ?? f.code_postal,
    }));
    setUserSearch(`${u.firstname ?? ''} ${u.lastname ?? ''}`.trim());
    setUserResults([]);
  };

  const openAdd = () => {
    setEditingFa(null);
    setForm(EMPTY_FORM);
    setLinkedUid(null);
    setUserSearch('');
    setShowForm(true);
  };

  const openEdit = (fa: FA) => {
    setEditingFa(fa);
    setForm({
      prenom: fa.prenom, nom: fa.nom, email: fa.email ?? '',
      telephone: fa.telephone ?? '', adresse: fa.adresse ?? '',
      ville: fa.ville ?? '', code_postal: fa.code_postal ?? '',
      notes: fa.notes ?? '', capacite_max: fa.capacite_max,
    });
    setLinkedUid(fa.fa_uid ?? null);
    setUserSearch('');
    setShowForm(true);
  };

  const resetForm = () => {
    setForm(EMPTY_FORM);
    setLinkedUid(null);
    setUserSearch('');
    setUserResults([]);
    setShowForm(false);
    setEditingFa(null);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user || !form.prenom.trim() || !form.nom.trim()) return;
    setSaving(true);
    const payload = {
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
    };
    if (editingFa) {
      await supabase.from('familles_accueil').update(payload).eq('id', editingFa.id);
    } else {
      await supabase.from('familles_accueil').insert({
        ...payload,
        association_uid: user.uid,
        ...(profileId ? { association_profile_id: profileId } : {}),
        actif: true,
      });
    }
    resetForm();
    setSaving(false);
    load();
  };

  const handleDelete = async (id: string) => {
    if (!confirm('Supprimer cette famille d\'accueil ?')) return;
    await supabase.from('familles_accueil').update({ actif: false }).eq('id', id);
    load();
  };

  const openPlaceAnimal = async (fa: FA) => {
    setPlacingFa(fa);
    setLoadingAnimaux(true);
    const { data } = await supabase
      .from('animaux')
      .select('id, nom, espece, race, photo_url')
      .eq('uid_eleveur', user!.uid)
      .eq('is_association', true)
      .in('statut', ['disponible', 'en_soin'])
      .is('fa_id', null)
      .order('nom');
    setAnimauxDispo(data ?? []);
    setLoadingAnimaux(false);
  };

  const handlePlaceAnimal = async (animal: AnimalDispo) => {
    if (!placingFa) return;
    setPlacing(animal.id);
    await supabase.from('animaux').update({
      fa_id: placingFa.id,
      date_entree: new Date().toISOString().split('T')[0],
    }).eq('id', animal.id);

    if (placingFa.fa_uid) {
      await supabase.from('notifications').insert({
        uid: placingFa.fa_uid,
        type: 'animal_en_accueil',
        title: 'Un animal vous a été confié',
        body: `${animal.nom} a été placé dans votre famille d'accueil`,
        data: { animal_id: animal.id, fa_id: placingFa.id },
        read: false,
      });
    }

    setPlacingFa(null);
    setPlacing(null);
    load();
  };

  const handleRetirerAnimal = async (animal: Animal, faId: string) => {
    if (!confirm(`Retirer ${animal.nom} de cette famille d'accueil ?`)) return;
    await supabase.from('animaux').update({
      fa_id: null,
      date_sortie: new Date().toISOString().split('T')[0],
    }).eq('id', animal.id);
    load();
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold font-galey text-teal-800">Familles d&apos;accueil</h1>
        <button onClick={openAdd}
          className="bg-teal-700 text-white px-4 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800 transition-colors">
          + Ajouter une FA
        </button>
      </div>

      {/* Formulaire ajout/édition */}
      {showForm && (
        <form onSubmit={handleSave} className="bg-white rounded-2xl shadow-sm p-5 space-y-4 border border-teal-100">
          <h2 className="font-bold font-galey text-teal-800">
            {editingFa ? `Modifier ${editingFa.prenom} ${editingFa.nom}` : 'Nouvelle famille d\'accueil'}
          </h2>

          {/* Recherche utilisateur PetsMatch */}
          <div className="bg-teal-50 rounded-xl p-4 border border-teal-100 space-y-2">
            <p className="text-xs font-semibold font-galey text-teal-700 flex items-center gap-1">
              🔍 Lier un utilisateur PetsMatch (optionnel)
            </p>
            <div className="relative">
              <input type="text" placeholder="Chercher par nom, prénom ou email…"
                value={userSearch} onChange={e => handleUserSearch(e.target.value)}
                className="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300 bg-white" />
              {userResults.length > 0 && (
                <div className="absolute z-10 w-full bg-white border border-gray-200 rounded-xl shadow-lg mt-1 overflow-hidden">
                  {userResults.map(u => (
                    <button key={u.uid} type="button" onClick={() => selectUser(u)}
                      className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-teal-50 transition-colors text-left">
                      <div className="w-8 h-8 rounded-full bg-teal-700 flex items-center justify-center text-white text-xs font-bold flex-shrink-0">
                        {(u.firstname?.[0] ?? u.email?.[0] ?? '?').toUpperCase()}
                      </div>
                      <div>
                        <p className="text-sm font-semibold font-galey text-gray-800">{u.firstname} {u.lastname}</p>
                        {u.email && <p className="text-xs text-gray-500 font-galey">{u.email}</p>}
                      </div>
                    </button>
                  ))}
                </div>
              )}
            </div>
            {linkedUid && (
              <div className="flex items-center justify-between">
                <p className="text-xs text-teal-700 font-galey">✓ Compte PetsMatch lié</p>
                <button type="button" onClick={() => { setLinkedUid(null); setUserSearch(''); }}
                  className="text-xs text-gray-400 hover:text-gray-600 font-galey">Délier</button>
              </div>
            )}
          </div>

          {/* Champs */}
          <div className="grid grid-cols-2 gap-3">
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
              className="px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300 col-span-2" />
            <input placeholder="Ville" value={form.ville}
              onChange={e => setForm({ ...form, ville: e.target.value })}
              className="px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
            <input placeholder="Code postal" value={form.code_postal}
              onChange={e => setForm({ ...form, code_postal: e.target.value })}
              className="px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
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
              {saving ? 'Enregistrement…' : editingFa ? 'Enregistrer' : 'Ajouter'}
            </button>
            <button type="button" onClick={resetForm}
              className="text-gray-500 px-6 py-2 rounded-full text-sm font-galey border border-gray-200 hover:bg-gray-50">
              Annuler
            </button>
          </div>
        </form>
      )}

      {/* Modal placement animal */}
      {placingFa && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-end md:items-center justify-center p-4">
          <div className="bg-white rounded-2xl w-full max-w-lg max-h-[80vh] flex flex-col">
            <div className="flex items-center justify-between p-5 border-b border-gray-100">
              <div>
                <h3 className="font-bold font-galey text-teal-800">Placer un animal</h3>
                <p className="text-xs text-gray-500 font-galey">
                  chez {placingFa.prenom} {placingFa.nom}
                </p>
              </div>
              <button onClick={() => setPlacingFa(null)} className="text-gray-400 hover:text-gray-600 text-xl">✕</button>
            </div>
            <div className="overflow-y-auto flex-1 p-4">
              {loadingAnimaux ? (
                <div className="flex justify-center py-8">
                  <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-teal-700" />
                </div>
              ) : animauxDispo.length === 0 ? (
                <div className="text-center py-8 text-gray-400 font-galey">
                  <p className="text-3xl mb-2">🐾</p>
                  <p>Aucun animal disponible à placer</p>
                </div>
              ) : (
                <div className="space-y-2">
                  {animauxDispo.map(a => (
                    <div key={a.id} className="flex items-center gap-3 p-3 rounded-xl border border-gray-100 hover:border-teal-200 transition-colors">
                      <div className="w-12 h-12 rounded-xl overflow-hidden bg-gray-100 flex-shrink-0">
                        {a.photo_url ? (
                          <Image src={a.photo_url} alt={a.nom} width={48} height={48}
                            className="w-full h-full object-cover" unoptimized />
                        ) : (
                          <div className="w-full h-full flex items-center justify-center text-xl">🐾</div>
                        )}
                      </div>
                      <div className="flex-1">
                        <p className="font-bold font-galey text-gray-900 text-sm">{a.nom}</p>
                        <p className="text-xs text-gray-500 font-galey">{a.race ?? a.espece}</p>
                      </div>
                      <button
                        onClick={() => handlePlaceAnimal(a)}
                        disabled={placing === a.id}
                        className="bg-teal-700 text-white px-4 py-1.5 rounded-full text-xs font-galey font-semibold hover:bg-teal-800 disabled:opacity-50">
                        {placing === a.id ? '…' : 'Placer'}
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Liste FA */}
      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
        </div>
      ) : fas.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <p className="text-4xl mb-3">🏡</p>
          <p className="font-galey">Aucune famille d&apos;accueil enregistrée</p>
          <button onClick={openAdd}
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
                      {(fa.ville || fa.adresse) && (
                        <p className="text-xs text-gray-500 font-galey">
                          {fa.adresse ? `${fa.adresse}, ` : ''}{fa.ville} {fa.code_postal}
                        </p>
                      )}
                    </div>
                  </div>
                  <span className={`text-xs font-bold font-galey px-2 py-1 rounded-full ${
                    dispo > 0 ? 'bg-green-100 text-green-700' : 'bg-orange-100 text-orange-700'
                  }`}>
                    {nbAnimaux}/{fa.capacite_max}
                  </span>
                </div>

                <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-gray-500 font-galey mb-3">
                  {fa.email && <span>📧 {fa.email}</span>}
                  {fa.telephone && <span>📞 {fa.telephone}</span>}
                </div>

                {/* Animaux en accueil */}
                {fa.animaux && fa.animaux.length > 0 && (
                  <div className="mb-3">
                    <p className="text-xs font-semibold font-galey text-teal-700 mb-1">En accueil :</p>
                    <div className="flex flex-wrap gap-1">
                      {fa.animaux.map((a) => (
                        <button key={a.id}
                          onClick={() => handleRetirerAnimal(a, fa.id)}
                          title="Cliquer pour retirer"
                          className="text-xs bg-teal-50 text-teal-800 px-2 py-0.5 rounded-full font-galey hover:bg-red-50 hover:text-red-600 transition-colors">
                          {a.nom} ✕
                        </button>
                      ))}
                    </div>
                  </div>
                )}

                {fa.notes && (
                  <p className="text-xs text-gray-400 font-galey mb-3 line-clamp-2">{fa.notes}</p>
                )}

                {/* Actions */}
                <div className="flex gap-2 pt-3 border-t border-gray-50">
                  <button
                    onClick={() => openPlaceAnimal(fa)}
                    disabled={dispo <= 0}
                    className="flex-1 text-xs border border-green-200 text-green-700 hover:bg-green-50 font-galey font-medium py-1.5 rounded-xl transition-colors disabled:opacity-40 disabled:cursor-not-allowed">
                    🐾 Placer un animal
                  </button>
                  <button onClick={() => openEdit(fa)}
                    className="text-xs border border-teal-200 text-teal-700 hover:bg-teal-50 font-galey font-medium py-1.5 px-4 rounded-xl transition-colors">
                    ✏️ Modifier
                  </button>
                  <button onClick={() => handleDelete(fa.id)}
                    className="text-xs border border-red-100 text-red-400 hover:bg-red-50 font-galey py-1.5 px-3 rounded-xl transition-colors">
                    🗑
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
