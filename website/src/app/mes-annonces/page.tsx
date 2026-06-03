'use client';

import { useEffect, useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface Annonce {
  id: string;
  titre?: string;
  espece?: string;
  race?: string;
  type?: string;
  type_vente?: string;
  photos?: string[];
  prix?: number;
  saillie_prix?: number;
  prix_min_portee?: number;
  prix_max_portee?: number;
  ville_eleveur?: string;
  created_at?: string;
  statut?: string;
  vues?: number;
  contacts?: number;
}

const STATUT_LABEL: Record<string, string> = {
  disponible: 'Disponible', reserve: 'Réservé', vendu: 'Vendu',
  archivee: 'Archivée', pause: 'En pause', expiree: 'Expirée',
};
const STATUT_COLOR: Record<string, string> = {
  disponible: 'bg-green-100 text-green-700',
  reserve:    'bg-amber-100 text-amber-700',
  vendu:      'bg-blue-100 text-blue-600',
  archivee:   'bg-gray-100 text-gray-500',
  pause:      'bg-gray-100 text-gray-500',
  expiree:    'bg-red-100 text-red-500',
};

type FilterKey = 'toutes' | 'disponible' | 'archivee' | 'pause';

export default function MesAnnoncesPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const [annonces, setAnnonces] = useState<Annonce[]>([]);
  const [fetching, setFetching] = useState(true);
  const [deleting, setDeleting] = useState<string | null>(null);
  const [filter, setFilter] = useState<FilterKey>('toutes');

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  useEffect(() => {
    if (!user) return;
    const SELECT = 'id, titre, espece, race, type, type_vente, photos, prix, saillie_prix, prix_min_portee, prix_max_portee, ville_eleveur, statut, vues, contacts, created_at';
    supabase
      .from('annonces')
      .select(SELECT)
      .eq('uid_eleveur', user.uid)
      .order('created_at', { ascending: false })
      .then(({ data }) => {
        setAnnonces((data ?? []) as Annonce[]);
        setFetching(false);
      }, () => setFetching(false));

    const channel = supabase
      .channel(`mes-annonces-${user.uid}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'annonces', filter: `uid_eleveur=eq.${user.uid}` },
        (payload) => setAnnonces(prev => [payload.new as Annonce, ...prev])
      )
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'annonces', filter: `uid_eleveur=eq.${user.uid}` },
        (payload) => setAnnonces(prev => prev.map(a => a.id === (payload.new as Annonce).id ? payload.new as Annonce : a))
      )
      .on('postgres_changes', { event: 'DELETE', schema: 'public', table: 'annonces', filter: `uid_eleveur=eq.${user.uid}` },
        (payload) => setAnnonces(prev => prev.filter(a => a.id !== (payload.old as Annonce).id))
      )
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, [user]);

  async function handleDelete(id: string) {
    if (!confirm('Supprimer définitivement cette annonce ?')) return;
    setDeleting(id);
    try {
      await supabase.from('annonces').delete().eq('id', id);
      setAnnonces(prev => prev.filter(a => a.id !== id));
    } finally {
      setDeleting(null);
    }
  }

  async function handlePause(a: Annonce) {
    const newStatut = a.statut === 'pause' ? 'disponible' : 'pause';
    await supabase.from('annonces').update({ statut: newStatut }).eq('id', a.id);
    setAnnonces(prev => prev.map(x => x.id === a.id ? { ...x, statut: newStatut } : x));
  }

  if (loading || !user) {
    return (
      <div className="flex justify-center py-32">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  const filtered = filter === 'toutes' ? annonces : annonces.filter(a => (a.statut ?? 'disponible') === filter);
  const counts = {
    toutes:    annonces.length,
    disponible: annonces.filter(a => (a.statut ?? 'disponible') === 'disponible').length,
    archivee:  annonces.filter(a => a.statut === 'archivee').length,
    pause:     annonces.filter(a => a.statut === 'pause').length,
  };

  return (
    <div className="max-w-4xl mx-auto px-4 py-8">
      {/* En-tête */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
            Mes annonces
          </h1>
          <p className="text-gray-500 text-sm">{annonces.length} annonce{annonces.length !== 1 ? 's' : ''}</p>
        </div>
        <Link href="/annonces/creer"
          className="bg-[#6E9E57] hover:bg-[#5A8A45] text-white font-semibold px-5 py-2.5 rounded-xl transition-colors text-sm flex items-center gap-2">
          <span>+</span> Nouvelle annonce
        </Link>
      </div>

      {/* Filtres */}
      <div className="flex gap-2 mb-5 overflow-x-auto pb-1">
        {(['toutes', 'disponible', 'archivee', 'pause'] as FilterKey[]).map(f => (
          <button key={f} onClick={() => setFilter(f)}
            className={`flex-shrink-0 flex items-center gap-1.5 px-4 py-2 rounded-xl text-sm font-semibold transition-colors ${
              filter === f ? 'bg-[#0C5C6C] text-white' : 'bg-white text-gray-600 border border-gray-200 hover:border-[#0C5C6C]/30'
            }`}>
            {f === 'toutes' ? 'Toutes' : STATUT_LABEL[f]}
            <span className={`text-xs px-1.5 py-0.5 rounded-full ${filter === f ? 'bg-white/20' : 'bg-gray-100 text-gray-500'}`}>
              {counts[f]}
            </span>
          </button>
        ))}
      </div>

      {fetching ? (
        <div className="flex justify-center py-20">
          <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
        </div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-20 bg-white rounded-2xl border border-gray-100">
          <p className="text-5xl mb-4">📋</p>
          <p className="text-gray-500 font-medium mb-2">
            {filter === 'toutes' ? "Vous n'avez pas encore d'annonce." : `Aucune annonce ${STATUT_LABEL[filter]?.toLowerCase()}.`}
          </p>
          {filter === 'toutes' && (
            <Link href="/annonces/creer"
              className="inline-block bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-semibold px-6 py-3 rounded-xl transition-colors mt-2">
              Créer ma première annonce
            </Link>
          )}
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {filtered.map(a => {
            const isSaillie = a.type_vente === 'saillie';
            const isPortee = a.type === 'portee';
            const statut = a.statut ?? 'disponible';
            const photos = (a.photos as unknown as string[]) ?? [];
            const sailliePrixNum = a.saillie_prix != null ? Number(a.saillie_prix) : null;
            const prix = isSaillie
              ? (sailliePrixNum != null && !isNaN(sailliePrixNum) ? `Saillie · ${Math.round(sailliePrixNum)} €` : 'Saillie')
              : isPortee
              ? (a.prix_min_portee != null || a.prix_max_portee != null
                  ? [a.prix_min_portee, a.prix_max_portee].filter(v => v != null).join(' – ') + ' €'
                  : null)
              : (a.prix != null ? `${a.prix} €` : null);

            return (
              <div key={a.id} className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden flex flex-col">
                <div className="aspect-square bg-gray-100 relative">
                  {photos[0] ? (
                    <Image src={photos[0]} alt={a.titre ?? ''} fill className="object-cover" />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center text-5xl">🐾</div>
                  )}
                  <div className="absolute top-2 left-2 flex gap-1.5">
                    <span className={`text-white text-xs font-semibold px-2 py-0.5 rounded-full ${isSaillie ? 'bg-purple-500' : isPortee ? 'bg-amber-500' : 'bg-[#6E9E57]'}`}>
                      {isSaillie ? 'Saillie' : isPortee ? 'Portée' : 'Compagnon'}
                    </span>
                  </div>
                  <div className="absolute top-2 right-2">
                    <span className={`text-xs font-semibold px-2 py-0.5 rounded-full ${STATUT_COLOR[statut] ?? 'bg-gray-100 text-gray-500'}`}>
                      {STATUT_LABEL[statut] ?? statut}
                    </span>
                  </div>
                </div>

                <div className="p-4 flex-1 flex flex-col">
                  <h3 className="font-bold text-[#1F2A2E] text-sm truncate capitalize">
                    {a.titre ?? `${a.espece ?? ''} ${a.race ?? ''}`.trim()}
                  </h3>
                  <p className="text-gray-500 text-xs capitalize">{a.espece}{a.race ? ` · ${a.race}` : ''}</p>
                  {a.ville_eleveur && <p className="text-gray-400 text-xs">📍 {a.ville_eleveur}</p>}
                  {prix && <p className="text-[#0C5C6C] font-bold text-sm mt-1">{prix}</p>}

                  {(a.vues != null || a.contacts != null) && (
                    <div className="flex gap-3 mt-1 text-xs text-gray-400">
                      {a.vues != null && <span>👁 {a.vues} vue{a.vues !== 1 ? 's' : ''}</span>}
                      {a.contacts != null && <span>📞 {a.contacts} contact{a.contacts !== 1 ? 's' : ''}</span>}
                    </div>
                  )}
                  {a.created_at && (
                    <p className="text-gray-400 text-xs mt-0.5">
                      {new Date(a.created_at).toLocaleDateString('fr-FR')}
                    </p>
                  )}

                  <div className="flex gap-1.5 mt-3 pt-3 border-t border-gray-50">
                    <Link href={`/annonces/${a.id}`}
                      className="flex-1 text-center text-xs bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-medium py-2 rounded-xl transition-colors">
                      Voir
                    </Link>
                    <Link href={`/annonces/${a.id}/modifier`}
                      className="flex-1 text-center text-xs border border-[#0C5C6C] text-[#0C5C6C] hover:bg-[#E8F4F6] font-medium py-2 rounded-xl transition-colors">
                      Modifier
                    </Link>
                    <button
                      onClick={() => handlePause(a)}
                      title={statut === 'pause' ? 'Réactiver' : 'Mettre en pause'}
                      className={`px-2.5 py-2 text-xs border rounded-xl transition-colors ${statut === 'pause' ? 'border-[#6E9E57] text-[#6E9E57] hover:bg-[#EEF5EA]' : 'border-gray-200 text-gray-400 hover:border-[#0C5C6C]/40 hover:text-[#0C5C6C]'}`}>
                      {statut === 'pause' ? '▶' : '⏸'}
                    </button>
                    <button
                      onClick={() => handleDelete(a.id)}
                      disabled={deleting === a.id}
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
