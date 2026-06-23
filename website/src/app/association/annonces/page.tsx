'use client';

import { useEffect, useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface Annonce {
  id: string;
  titre?: string;
  type_vente?: string;
  espece?: string;
  race?: string;
  statut?: string;
  photos?: string[];
  vues?: number;
  contacts?: number;
  created_at?: string;
}

const STATUT_LABEL: Record<string, string> = {
  disponible: 'Disponible',
  pause:      'En pause',
  cede:       'Cédé',
  archive:    'Archivée',
  expiree:    'Expirée',
};
const STATUT_COLOR: Record<string, string> = {
  disponible: 'bg-green-100 text-green-700',
  pause:      'bg-gray-100 text-gray-500',
  cede:       'bg-teal-100 text-teal-700',
  archive:    'bg-gray-100 text-gray-500',
  expiree:    'bg-red-100 text-red-500',
};

type Tab = 'toutes' | 'disponible' | 'pause' | 'cede';

export default function AnnoncesAssoPage() {
  const { user } = useAuth();
  const [annonces, setAnnonces] = useState<Annonce[]>([]);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<Tab>('toutes');
  const [deleting, setDeleting] = useState<string | null>(null);

  const load = () => {
    if (!user) return;
    supabase
      .from('annonces')
      .select('id, titre, type_vente, espece, race, statut, photos, vues, contacts, created_at')
      .eq('uid_eleveur', user.uid)
      .eq('profil_source', 'association')
      .order('created_at', { ascending: false })
      .then(({ data }) => { setAnnonces(data ?? []); setLoading(false); });
  };

  useEffect(() => { load(); }, [user]);

  // Realtime
  useEffect(() => {
    if (!user) return;
    const channel = supabase.channel(`asso-annonces-${user.uid}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'annonces', filter: `uid_eleveur=eq.${user.uid}` },
        (p) => setAnnonces(prev => prev.map(a => a.id === (p.new as Annonce).id ? { ...a, ...p.new as Annonce } : a)))
      .on('postgres_changes', { event: 'DELETE', schema: 'public', table: 'annonces', filter: `uid_eleveur=eq.${user.uid}` },
        (p) => setAnnonces(prev => prev.filter(a => a.id !== (p.old as Annonce).id)))
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [user]);

  const handlePause = async (a: Annonce) => {
    const next = a.statut === 'pause' ? 'disponible' : 'pause';
    await supabase.from('annonces').update({ statut: next }).eq('id', a.id);
    setAnnonces(prev => prev.map(x => x.id === a.id ? { ...x, statut: next } : x));
  };

  const handleDelete = async (id: string) => {
    if (!confirm('Supprimer définitivement cette annonce ?')) return;
    setDeleting(id);
    await supabase.from('annonces').delete().eq('id', id);
    setAnnonces(prev => prev.filter(a => a.id !== id));
    setDeleting(null);
  };

  const counts = {
    toutes:    annonces.length,
    disponible: annonces.filter(a => a.statut === 'disponible').length,
    pause:     annonces.filter(a => a.statut === 'pause').length,
    cede:      annonces.filter(a => a.statut === 'cede' || a.statut === 'archive' || a.statut === 'expiree').length,
  };

  const filtered = tab === 'toutes' ? annonces
    : tab === 'cede' ? annonces.filter(a => a.statut === 'cede' || a.statut === 'archive' || a.statut === 'expiree')
    : annonces.filter(a => a.statut === tab);

  return (
    <div className="space-y-5">
      {/* En-tête */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold font-galey text-teal-800">Mes annonces</h1>
          <p className="text-xs text-gray-400 font-galey mt-0.5">{annonces.length} annonce{annonces.length !== 1 ? 's' : ''}</p>
        </div>
        <Link href="/association/annonces/creer"
          className="bg-teal-700 text-white px-4 py-2.5 rounded-full text-sm font-galey font-semibold hover:bg-teal-800 transition-colors flex items-center gap-1.5">
          <span className="text-base leading-none">+</span> Déposer
        </Link>
      </div>

      {/* Onglets */}
      <div className="flex gap-2 overflow-x-auto pb-1">
        {([
          ['toutes', 'Toutes'],
          ['disponible', 'Disponible'],
          ['pause', 'En pause'],
          ['cede', 'Cédées'],
        ] as [Tab, string][]).map(([key, label]) => (
          <button key={key} onClick={() => setTab(key)}
            className={`flex-shrink-0 flex items-center gap-1.5 px-4 py-2 rounded-xl text-sm font-semibold font-galey transition-colors ${
              tab === key ? 'bg-teal-700 text-white' : 'bg-white text-gray-600 border border-gray-200 hover:border-teal-300'
            }`}>
            {label}
            <span className={`text-xs px-1.5 py-0.5 rounded-full ${tab === key ? 'bg-white/20' : 'bg-gray-100 text-gray-500'}`}>
              {counts[key]}
            </span>
          </button>
        ))}
      </div>

      {/* Contenu */}
      {loading ? (
        <div className="flex justify-center py-20">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
        </div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-16 bg-white rounded-2xl border border-gray-100 text-gray-400">
          <p className="text-4xl mb-3">📣</p>
          <p className="font-galey mb-4">
            {tab === 'toutes' ? 'Aucune annonce publiée' : `Aucune annonce ${tab === 'pause' ? 'en pause' : tab === 'cede' ? 'cédée' : 'disponible'}`}
          </p>
          {tab === 'toutes' && (
            <Link href="/association/annonces/creer"
              className="bg-teal-700 text-white px-6 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800">
              Déposer une annonce
            </Link>
          )}
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {filtered.map(a => {
            const statut = a.statut ?? 'disponible';
            const photos = (a.photos as string[]) ?? [];
            return (
              <div key={a.id} className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden flex flex-col">
                {/* Photo */}
                <div className="aspect-square bg-gray-100 relative">
                  {photos[0] ? (
                    <Image src={photos[0]} alt={a.titre ?? ''} fill className="object-cover" unoptimized />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center text-5xl">🐾</div>
                  )}
                  <div className="absolute top-2 left-2">
                    <span className="bg-teal-700/90 text-white text-xs font-galey font-semibold px-2 py-0.5 rounded-full">
                      Adoption
                    </span>
                  </div>
                  <div className="absolute top-2 right-2">
                    <span className={`text-xs font-galey font-semibold px-2 py-0.5 rounded-full ${STATUT_COLOR[statut] ?? 'bg-gray-100 text-gray-500'}`}>
                      {STATUT_LABEL[statut] ?? statut}
                    </span>
                  </div>
                </div>

                <div className="p-4 flex-1 flex flex-col">
                  <h3 className="font-bold font-galey text-gray-900 text-sm truncate">
                    {a.titre ?? (`${a.espece ?? ''} ${a.race ?? ''}`.trim() || 'Sans titre')}
                  </h3>
                  <p className="text-gray-500 text-xs font-galey capitalize">
                    {a.espece}{a.race ? ` · ${a.race}` : ''}
                  </p>

                  {/* Vues & contacts */}
                  <div className="flex gap-3 mt-2 text-xs text-gray-400 font-galey">
                    <span>👁 {a.vues ?? 0} vue{(a.vues ?? 0) !== 1 ? 's' : ''}</span>
                    <span>📩 {a.contacts ?? 0} contact{(a.contacts ?? 0) !== 1 ? 's' : ''}</span>
                  </div>
                  {a.created_at && (
                    <p className="text-gray-400 text-xs font-galey mt-0.5">
                      {new Date(a.created_at).toLocaleDateString('fr-FR')}
                    </p>
                  )}

                  {/* Actions */}
                  <div className="flex gap-1.5 mt-3 pt-3 border-t border-gray-50">
                    <Link href={`/annonces/${a.id}`}
                      className="flex-1 text-center text-xs bg-teal-700 hover:bg-teal-800 text-white font-galey font-medium py-2 rounded-xl transition-colors">
                      Voir
                    </Link>
                    <Link href={`/association/annonces/creer?edit=${a.id}`}
                      className="flex-1 text-center text-xs border border-teal-200 text-teal-700 hover:bg-teal-50 font-galey font-medium py-2 rounded-xl transition-colors">
                      Modifier
                    </Link>
                    <button onClick={() => handlePause(a)}
                      title={statut === 'pause' ? 'Réactiver' : 'Mettre en pause'}
                      className={`px-2.5 py-2 text-xs border rounded-xl transition-colors ${
                        statut === 'pause'
                          ? 'border-teal-500 text-teal-600 hover:bg-teal-50'
                          : 'border-gray-200 text-gray-400 hover:border-teal-300 hover:text-teal-600'
                      }`}>
                      {statut === 'pause' ? '▶' : '⏸'}
                    </button>
                    <button onClick={() => handleDelete(a.id)} disabled={deleting === a.id}
                      className="px-2.5 py-2 text-xs border border-red-100 hover:bg-red-50 text-red-400 rounded-xl transition-colors disabled:opacity-50">
                      {deleting === a.id ? '…' : '🗑'}
                    </button>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
