'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { usePensionAccess } from '@/hooks/usePensionAccess';
import { supabase } from '@/lib/supabase';

interface Logement {
  id: string;
  nom: string;
  type: string;
  capacite: number;
  notes?: string | null;
}

interface Entree {
  id: string;
  animal_nom: string;
  espece?: string | null;
  logement_id?: string | null;
}

const TYPES = [
  { value: 'box', label: 'Box' },
  { value: 'enclos', label: 'Enclos' },
  { value: 'parc', label: 'Parc' },
  { value: 'chatterie', label: 'Chatterie' },
  { value: 'cage', label: 'Cage' },
];
const TYPE_LABEL = Object.fromEntries(TYPES.map(t => [t.value, t.label]));

const EMPTY_FORM = { nom: '', type: 'box', capacite: 1, notes: '' };

export default function PensionChenilPage() {
  const { user, userData, isPension } = usePensionAccess();
  const router = useRouter();
  const [logements, setLogements] = useState<Logement[]>([]);
  const [entrees, setEntrees] = useState<Entree[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<Logement | null>(null);
  const [form, setForm] = useState(EMPTY_FORM);
  const [assigningTo, setAssigningTo] = useState<Logement | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);

  useEffect(() => {
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isPension) { router.push('/'); return; }
  }, [user, userData, isPension, router]);

  const load = useCallback(async () => {
    if (!user) return;
    const [{ data: log }, { data: ent }] = await Promise.all([
      supabase.from('enclos_chenil').select('*').eq('uid_eleveur', user.uid).order('nom'),
      supabase.from('pension_entrees').select('id, animal_nom, espece, logement_id')
        .eq('pro_uid', user.uid).eq('statut', 'en_pension').order('date_entree'),
    ]);
    setLogements(log ?? []);
    setEntrees(ent ?? []);
    setLoading(false);
  }, [user]);

  useEffect(() => { load(); }, [load]);

  const occupants = (logementId: string) => entrees.filter(e => e.logement_id === logementId);
  const nonAssignes = entrees.filter(e => !e.logement_id);

  const openAdd = () => { setEditing(null); setForm(EMPTY_FORM); setSaveError(null); setShowForm(true); };
  const openEdit = (l: Logement) => {
    setEditing(l);
    setForm({ nom: l.nom, type: l.type, capacite: l.capacite, notes: l.notes ?? '' });
    setSaveError(null);
    setShowForm(true);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user || !form.nom.trim()) return;
    setSaveError(null);
    const payload = {
      nom: form.nom.trim(), type: form.type, capacite: form.capacite,
      notes: form.notes.trim() || null, updated_at: new Date().toISOString(),
    };
    const { error } = editing
      ? await supabase.from('enclos_chenil').update(payload).eq('id', editing.id)
      : await supabase.from('enclos_chenil').insert({ ...payload, uid_eleveur: user.uid });
    if (error) {
      setSaveError(error.message);
      return;
    }
    setShowForm(false);
    load();
  };

  const handleDelete = async (id: string) => {
    if (!confirm('Supprimer ce logement ? Les animaux qui y sont assignés seront libérés.')) return;
    await supabase.from('pension_entrees').update({ logement_id: null }).eq('logement_id', id);
    await supabase.from('enclos_chenil').delete().eq('id', id);
    load();
  };

  const assign = async (entreeId: string, logementId: string | null) => {
    await supabase.from('pension_entrees').update({ logement_id: logementId }).eq('id', entreeId);
    setAssigningTo(null);
    load();
  };

  if (!user || !userData) return null;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold font-galey text-teal-800">Logements / Chenil</h1>
        <button onClick={openAdd}
          className="bg-teal-700 text-white px-4 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800 transition-colors">
          + Ajouter un logement
        </button>
      </div>

      {showForm && (
        <form onSubmit={handleSave} className="bg-white rounded-2xl shadow-sm p-5 space-y-4 border border-teal-100">
          <h2 className="font-bold font-galey text-teal-800">
            {editing ? `Modifier ${editing.nom}` : 'Nouveau logement'}
          </h2>
          <input placeholder="Nom (ex : Box 3)" required value={form.nom}
            onChange={e => setForm({ ...form, nom: e.target.value })}
            className="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
          <div className="flex gap-2 flex-wrap">
            {TYPES.map(t => (
              <button key={t.value} type="button" onClick={() => setForm({ ...form, type: t.value })}
                className={`px-3.5 py-1.5 rounded-full text-sm font-galey font-medium border transition-colors ${
                  form.type === t.value ? 'bg-teal-700 text-white border-teal-700' : 'bg-white text-gray-600 border-gray-200'
                }`}>
                {t.label}
              </button>
            ))}
          </div>
          <div className="flex items-center gap-3">
            <label className="text-sm font-galey text-gray-700">Capacité :</label>
            <button type="button" onClick={() => setForm(f => ({ ...f, capacite: Math.max(1, f.capacite - 1) }))}
              className="w-8 h-8 rounded-full bg-gray-100 hover:bg-gray-200 flex items-center justify-center font-bold">−</button>
            <span className="font-bold font-galey text-teal-800 w-6 text-center">{form.capacite}</span>
            <button type="button" onClick={() => setForm(f => ({ ...f, capacite: f.capacite + 1 }))}
              className="w-8 h-8 rounded-full bg-gray-100 hover:bg-gray-200 flex items-center justify-center font-bold">+</button>
          </div>
          <textarea placeholder="Notes (optionnel)" rows={2} value={form.notes}
            onChange={e => setForm({ ...form, notes: e.target.value })}
            className="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
          {saveError && (
            <p className="text-sm font-galey text-red-600 bg-red-50 border border-red-100 rounded-lg px-3 py-2">
              {saveError}
            </p>
          )}
          <div className="flex gap-3">
            <button type="submit" className="bg-teal-700 text-white px-6 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800">
              {editing ? 'Enregistrer' : 'Ajouter'}
            </button>
            <button type="button" onClick={() => setShowForm(false)}
              className="text-gray-500 px-6 py-2 rounded-full text-sm font-galey border border-gray-200 hover:bg-gray-50">
              Annuler
            </button>
          </div>
        </form>
      )}

      {assigningTo && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-end md:items-center justify-center p-4">
          <div className="bg-white rounded-2xl w-full max-w-lg max-h-[80vh] flex flex-col">
            <div className="flex items-center justify-between p-5 border-b border-gray-100">
              <h3 className="font-bold font-galey text-teal-800">Assigner à {assigningTo.nom}</h3>
              <button onClick={() => setAssigningTo(null)} className="text-gray-400 hover:text-gray-600 text-xl">✕</button>
            </div>
            <div className="overflow-y-auto flex-1 p-4">
              {nonAssignes.length === 0 ? (
                <p className="text-center text-gray-400 font-galey py-8">Aucun animal en pension non assigné.</p>
              ) : (
                <div className="space-y-2">
                  {nonAssignes.map(e => (
                    <div key={e.id} className="flex items-center justify-between p-3 rounded-xl border border-gray-100 hover:border-teal-200">
                      <div>
                        <p className="font-bold font-galey text-sm">{e.animal_nom}</p>
                        <p className="text-xs text-gray-500 font-galey">{e.espece}</p>
                      </div>
                      <button onClick={() => assign(e.id, assigningTo.id)}
                        className="bg-teal-700 text-white px-4 py-1.5 rounded-full text-xs font-galey font-semibold hover:bg-teal-800">
                        Placer
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
        </div>
      ) : logements.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <p className="text-4xl mb-3">🏘️</p>
          <p className="font-galey">Aucun logement enregistré</p>
          <p className="text-sm font-galey mt-1">Créez vos box, enclos ou chatterie pour suivre l&apos;occupation.</p>
        </div>
      ) : (
        <div className="grid md:grid-cols-2 gap-4">
          {logements.map(l => {
            const occ = occupants(l.id);
            const dispo = l.capacite - occ.length;
            return (
              <div key={l.id} className="bg-white rounded-2xl shadow-sm p-5 border border-gray-100">
                <div className="flex items-center gap-2 mb-2">
                  <span className="text-xs font-galey font-semibold px-2 py-1 rounded-lg bg-teal-50 text-teal-700">
                    {TYPE_LABEL[l.type] ?? l.type}
                  </span>
                  <p className="font-bold font-galey text-gray-900 flex-1">{l.nom}</p>
                  <span className={`text-xs font-bold font-galey px-2 py-1 rounded-full ${
                    dispo > 0 ? 'bg-green-100 text-green-700' : 'bg-orange-100 text-orange-700'
                  }`}>
                    {occ.length}/{l.capacite}
                  </span>
                  <button onClick={() => openEdit(l)} className="text-gray-400 hover:text-teal-700 text-sm">✏️</button>
                  <button onClick={() => handleDelete(l.id)} className="text-gray-400 hover:text-red-500 text-sm">🗑</button>
                </div>
                {occ.length > 0 && (
                  <div className="flex flex-wrap gap-1 mb-3">
                    {occ.map(e => (
                      <button key={e.id} onClick={() => assign(e.id, null)}
                        title="Cliquer pour retirer"
                        className="text-xs bg-teal-50 text-teal-800 px-2 py-0.5 rounded-full font-galey hover:bg-red-50 hover:text-red-600 transition-colors">
                        {e.animal_nom} ✕
                      </button>
                    ))}
                  </div>
                )}
                <button
                  onClick={() => setAssigningTo(l)}
                  disabled={dispo <= 0}
                  className="w-full text-xs border border-green-200 text-green-700 hover:bg-green-50 font-galey font-medium py-1.5 rounded-xl transition-colors disabled:opacity-40 disabled:cursor-not-allowed">
                  🐾 Assigner un animal
                </button>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
