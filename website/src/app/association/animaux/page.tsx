'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

const STATUTS = [
  { key: 'tous',      label: 'Tous',        color: 'bg-gray-100 text-gray-700' },
  { key: 'en_soin',   label: 'En soin',     color: 'bg-orange-100 text-orange-700' },
  { key: 'disponible',label: 'Disponible',  color: 'bg-green-100 text-green-700' },
  { key: 'en_fa',     label: 'En FA',       color: 'bg-purple-100 text-purple-700' },
  { key: 'adopte',    label: 'Adopté',      color: 'bg-teal-100 text-teal-700' },
  { key: 'transfere', label: 'Transféré',   color: 'bg-blue-100 text-blue-700' },
  { key: 'decede',    label: 'Décédé',      color: 'bg-red-100 text-red-700' },
];

const STATUT_MAP = Object.fromEntries(STATUTS.map(s => [s.key, s]));

export default function AnimauxAssoPage() {
  const { user } = useAuth();
  const [animaux, setAnimaux] = useState<any[]>([]);
  const [filtered, setFiltered] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [filterStatut, setFilterStatut] = useState('tous');
  const [search, setSearch] = useState('');

  useEffect(() => {
    if (!user) return;
    supabase
      .from('animaux')
      .select('id, nom, espece, race, sexe, statut, date_naissance, photo_url, date_entree')
      .eq('uid_eleveur', user.uid)
      .order('nom')
      .then(({ data }) => {
        setAnimaux(data ?? []);
        setLoading(false);
      });
  }, [user]);

  useEffect(() => {
    setFiltered(
      animaux.filter(a => {
        const matchS = filterStatut === 'tous' || a.statut === filterStatut;
        const q = search.toLowerCase();
        const matchQ = !q || a.nom?.toLowerCase().includes(q) || a.espece?.toLowerCase().includes(q) || a.race?.toLowerCase().includes(q);
        return matchS && matchQ;
      })
    );
  }, [animaux, filterStatut, search]);

  const age = (dn: string | null) => {
    if (!dn) return '';
    const mois = Math.floor((Date.now() - new Date(dn).getTime()) / (1000 * 60 * 60 * 24 * 30));
    return mois < 12 ? `${mois}m` : `${Math.floor(mois / 12)}a`;
  };

  const handleChangeStatut = async (animalId: string, newStatut: string) => {
    await supabase.from('animaux').update({ statut: newStatut }).eq('id', animalId);
    setAnimaux(prev => prev.map(a => a.id === animalId ? { ...a, statut: newStatut } : a));
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold font-galey text-teal-800">Mes Animaux</h1>
        <Link href="/association/animaux/nouveau"
          className="bg-teal-700 text-white px-4 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800 transition-colors">
          + Ajouter
        </Link>
      </div>

      {/* Search */}
      <input
        type="text"
        placeholder="Rechercher un animal…"
        value={search}
        onChange={e => setSearch(e.target.value)}
        className="w-full px-4 py-2.5 rounded-xl border border-gray-200 bg-white text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300"
      />

      {/* Filtres statut */}
      <div className="flex gap-2 flex-wrap">
        {STATUTS.map(s => (
          <button
            key={s.key}
            onClick={() => setFilterStatut(s.key)}
            className={`px-3 py-1.5 rounded-full text-xs font-galey font-semibold transition-all ${
              filterStatut === s.key ? s.color + ' ring-2 ring-offset-1 ring-current' : 'bg-white border border-gray-200 text-gray-500 hover:bg-gray-50'
            }`}
          >
            {s.label}
          </button>
        ))}
      </div>

      {/* Liste */}
      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
        </div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <p className="text-4xl mb-3">🐾</p>
          <p className="font-galey">Aucun animal trouvé</p>
        </div>
      ) : (
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
          {filtered.map((a) => {
            const sc = STATUT_MAP[a.statut] ?? STATUTS[0];
            return (
              <div key={a.id} className="bg-white rounded-2xl shadow-sm overflow-hidden border border-gray-100 hover:border-teal-200 hover:shadow-md transition-all">
                <Link href={`/association/animaux/${a.id}`}>
                  <div className="aspect-square bg-gray-100 relative overflow-hidden">
                    {a.photo_url ? (
                      <img src={a.photo_url} alt={a.nom} className="w-full h-full object-cover" />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center text-4xl text-gray-300">🐾</div>
                    )}
                    <span className={`absolute top-2 right-2 text-xs font-galey font-bold px-2 py-0.5 rounded-full ${sc.color}`}>
                      {sc.label}
                    </span>
                  </div>
                  <div className="p-3">
                    <div className="flex items-center justify-between">
                      <p className="font-bold font-galey text-sm text-gray-900 truncate">{a.nom}</p>
                      {age(a.date_naissance) && <span className="text-xs text-gray-400">{age(a.date_naissance)}</span>}
                    </div>
                    {(a.race || a.espece) && (
                      <p className="text-xs text-gray-500 font-galey truncate">{a.race || a.espece}</p>
                    )}
                  </div>
                </Link>
                {/* Changer statut */}
                <div className="px-3 pb-3">
                  <select
                    value={a.statut}
                    onChange={e => handleChangeStatut(a.id, e.target.value)}
                    className="w-full text-xs border border-gray-200 rounded-lg px-2 py-1 font-galey focus:outline-none focus:ring-1 focus:ring-teal-400"
                  >
                    {STATUTS.filter(s => s.key !== 'tous').map(s => (
                      <option key={s.key} value={s.key}>{s.label}</option>
                    ))}
                  </select>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
