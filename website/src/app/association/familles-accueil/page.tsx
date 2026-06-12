'use client';

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface FA {
  id: string;
  prenom: string;
  nom: string;
  email?: string;
  telephone?: string;
  ville?: string;
  code_postal?: string;
  adresse?: string;
  capacite_max: number;
  notes?: string;
  animaux?: any[];
}

export default function FamillesAccueilWebPage() {
  const { user } = useAuth();
  const [fas, setFas] = useState<FA[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({
    prenom: '', nom: '', email: '', telephone: '', adresse: '', ville: '', code_postal: '', notes: '', capacite_max: 1,
  });
  const [saving, setSaving] = useState(false);

  const load = async () => {
    if (!user) return;
    const { data } = await supabase
      .from('familles_accueil')
      .select('*, animaux(id, nom, statut)')
      .eq('association_uid', user.uid)
      .eq('actif', true)
      .order('nom');
    setFas(data ?? []);
    setLoading(false);
  };

  useEffect(() => { load(); }, [user]);

  const handleAdd = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user || !form.prenom.trim() || !form.nom.trim()) return;
    setSaving(true);
    await supabase.from('familles_accueil').insert({
      association_uid: user.uid,
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
    setForm({ prenom: '', nom: '', email: '', telephone: '', adresse: '', ville: '', code_postal: '', notes: '', capacite_max: 1 });
    setShowForm(false);
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
          <div className="grid grid-cols-2 gap-4">
            <input placeholder="Prénom *" required value={form.prenom} onChange={e => setForm({ ...form, prenom: e.target.value })}
              className="px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
            <input placeholder="Nom *" required value={form.nom} onChange={e => setForm({ ...form, nom: e.target.value })}
              className="px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
            <input placeholder="Email" type="email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value })}
              className="px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
            <input placeholder="Téléphone" value={form.telephone} onChange={e => setForm({ ...form, telephone: e.target.value })}
              className="px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
            <input placeholder="Adresse" value={form.adresse} onChange={e => setForm({ ...form, adresse: e.target.value })}
              className="px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
            <div className="flex gap-2">
              <input placeholder="Ville" value={form.ville} onChange={e => setForm({ ...form, ville: e.target.value })}
                className="flex-1 px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
              <input placeholder="CP" value={form.code_postal} onChange={e => setForm({ ...form, code_postal: e.target.value })}
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
            <button type="button" onClick={() => setShowForm(false)}
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
                      <p className="font-bold font-galey text-gray-900">{fa.prenom} {fa.nom}</p>
                      {fa.ville && <p className="text-xs text-gray-500 font-galey">{fa.ville} {fa.code_postal}</p>}
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className={`text-xs font-bold font-galey px-2 py-1 rounded-full ${dispo > 0 ? 'bg-green-100 text-green-700' : 'bg-orange-100 text-orange-700'}`}>
                      {nbAnimaux}/{fa.capacite_max}
                    </span>
                    <button onClick={() => handleDelete(fa.id)} className="text-red-400 hover:text-red-600 text-sm">🗑</button>
                  </div>
                </div>
                <div className="flex items-center gap-4 text-xs text-gray-500 font-galey mb-3">
                  {fa.email && <span>📧 {fa.email}</span>}
                  {fa.telephone && <span>📞 {fa.telephone}</span>}
                </div>
                {fa.animaux && fa.animaux.length > 0 && (
                  <div>
                    <p className="text-xs font-semibold font-galey text-teal-700 mb-1">En accueil :</p>
                    <div className="flex flex-wrap gap-1">
                      {fa.animaux.map((a: any) => (
                        <span key={a.id} className="text-xs bg-teal-50 text-teal-800 px-2 py-0.5 rounded-full font-galey">{a.nom}</span>
                      ))}
                    </div>
                  </div>
                )}
                {fa.notes && <p className="text-xs text-gray-400 font-galey mt-2 line-clamp-2">{fa.notes}</p>}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
