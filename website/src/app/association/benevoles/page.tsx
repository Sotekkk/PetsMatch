'use client';

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface Benevole {
  id: string;
  prenom: string;
  nom: string;
  email?: string;
  telephone?: string;
  notes?: string;
  actif: boolean;
}

export default function BenevolesWebPage() {
  const { user } = useAuth();
  const [benevoles, setBenevoles] = useState<Benevole[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ prenom: '', nom: '', email: '', telephone: '', notes: '' });
  const [saving, setSaving] = useState(false);

  const load = async () => {
    if (!user) return;
    const { data } = await supabase
      .from('employes')
      .select('*')
      .eq('uid_eleveur', user.uid)
      .eq('type', 'benevole')
      .order('nom');
    setBenevoles(data ?? []);
    setLoading(false);
  };

  useEffect(() => { load(); }, [user]);

  const handleAdd = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user || !form.prenom.trim() || !form.nom.trim()) return;
    setSaving(true);
    await supabase.from('employes').insert({
      uid_eleveur: user.uid,
      prenom: form.prenom.trim(),
      nom: form.nom.trim(),
      email: form.email.trim() || null,
      telephone: form.telephone.trim() || null,
      notes: form.notes.trim() || null,
      actif: true,
      type: 'benevole',
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

  const actifs = benevoles.filter(b => b.actif);
  const inactifs = benevoles.filter(b => !b.actif);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold font-galey text-teal-800">Bénévoles</h1>
        <button
          onClick={() => setShowForm(!showForm)}
          className="bg-teal-700 text-white px-4 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800 transition-colors"
        >
          + Ajouter un bénévole
        </button>
      </div>

      {/* Formulaire ajout */}
      {showForm && (
        <form onSubmit={handleAdd} className="bg-white rounded-2xl shadow-sm p-5 space-y-4 border border-teal-100">
          <h2 className="font-bold font-galey text-teal-800">Nouveau bénévole</h2>
          <div className="grid grid-cols-2 gap-4">
            <input placeholder="Prénom *" required value={form.prenom} onChange={e => setForm({ ...form, prenom: e.target.value })}
              className="px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
            <input placeholder="Nom *" required value={form.nom} onChange={e => setForm({ ...form, nom: e.target.value })}
              className="px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
            <input placeholder="Email" type="email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value })}
              className="px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
            <input placeholder="Téléphone" value={form.telephone} onChange={e => setForm({ ...form, telephone: e.target.value })}
              className="px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
          </div>
          <textarea placeholder="Notes" rows={2} value={form.notes} onChange={e => setForm({ ...form, notes: e.target.value })}
            className="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
          <div className="flex gap-3">
            <button type="submit" disabled={saving}
              className="bg-teal-700 text-white px-6 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800 transition-colors disabled:opacity-50">
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
      ) : benevoles.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <p className="text-4xl mb-3">🤝</p>
          <p className="font-galey">Aucun bénévole enregistré</p>
        </div>
      ) : (
        <div className="space-y-6">
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
