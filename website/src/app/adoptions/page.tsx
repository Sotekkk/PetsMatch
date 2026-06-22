'use client';

import { useEffect, useState, useCallback } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

const ESPECES = ['tous', 'chien', 'chat', 'lapin', 'oiseau', 'cheval', 'nac', 'autre'];
const ESPECE_LABEL: Record<string, string> = {
  tous: 'Toutes', chien: 'Chiens', chat: 'Chats', lapin: 'Lapins',
  oiseau: 'Oiseaux', cheval: 'Chevaux', nac: 'NAC', autre: 'Autres',
};
const ESPECE_EMOJI: Record<string, string> = {
  tous: '🐾', chien: '🐕', chat: '🐈', lapin: '🐇',
  oiseau: '🦜', cheval: '🐴', nac: '🦎', autre: '🐾',
};

interface Annonce {
  id: string;
  titre?: string;
  espece?: string;
  race?: string;
  sexe?: string;
  photos?: string[];
  ville_eleveur?: string;
  nom_eleveur?: string;
  uid_eleveur?: string;
  date_naissance_animal?: string;
}

function ageLabel(dateStr?: string) {
  if (!dateStr) return null;
  const days = Math.floor((Date.now() - new Date(dateStr).getTime()) / 86400000);
  if (days < 0) return null;
  if (days < 91) return `${Math.floor(days / 7)} sem.`;
  const months = Math.floor(days / 30.44);
  if (months < 12) return `${months} mois`;
  return `${Math.floor(days / 365)} ans`;
}

export default function AdoptionsPage() {
  const { user } = useAuth();
  const [annonces, setAnnonces]   = useState<Annonce[]>([]);
  const [loading, setLoading]     = useState(true);
  const [espece, setEspece]       = useState('tous');
  const [race, setRace]           = useState('toutes');
  const [search, setSearch]       = useState('');
  const [likedIds, setLikedIds]   = useState<Set<string>>(new Set());
  const [likeCounts, setLikeCounts] = useState<Record<string, number>>({});

  useEffect(() => {
    supabase
      .from('annonces')
      .select('id, titre, espece, race, sexe, photos, ville_eleveur, nom_eleveur, uid_eleveur, date_naissance_animal')
      .eq('statut', 'disponible')
      .eq('profil_source', 'association')
      .order('created_at', { ascending: false })
      .then(({ data }) => {
        setAnnonces((data ?? []) as Annonce[]);
        setLoading(false);
      });
  }, []);

  // Charger likes
  useEffect(() => {
    if (!user) return;
    supabase.from('likes').select('annonce_id').eq('user_uid', user.uid)
      .then(({ data }) => {
        if (data) setLikedIds(new Set(data.map((r: { annonce_id: string }) => r.annonce_id)));
      });
    supabase.from('likes').select('annonce_id')
      .then(({ data }) => {
        if (!data) return;
        const counts: Record<string, number> = {};
        data.forEach((r: { annonce_id: string }) => { counts[r.annonce_id] = (counts[r.annonce_id] ?? 0) + 1; });
        setLikeCounts(counts);
      });
  }, [user]);

  const toggleLike = useCallback(async (id: string) => {
    if (!user) return;
    const wasLiked = likedIds.has(id);
    setLikedIds(prev => { const s = new Set(prev); wasLiked ? s.delete(id) : s.add(id); return s; });
    setLikeCounts(prev => ({ ...prev, [id]: Math.max(0, (prev[id] ?? 0) + (wasLiked ? -1 : 1)) }));
    if (wasLiked) {
      await supabase.from('likes').delete().eq('annonce_id', id).eq('user_uid', user.uid);
    } else {
      await supabase.from('likes').insert({ annonce_id: id, user_uid: user.uid, bebe_index: -1 });
    }
  }, [user, likedIds]);

  // Races disponibles pour le filtre dynamique
  const availableRaces = ['toutes', ...new Set(
    annonces.filter(a => espece === 'tous' || a.espece === espece)
      .map(a => a.race ?? '').filter(Boolean)
  )];

  const filtered = annonces.filter((a) => {
    if (espece !== 'tous' && a.espece !== espece) return false;
    if (race !== 'toutes' && a.race !== race) return false;
    if (search) {
      const q = search.toLowerCase();
      return (
        (a.titre ?? '').toLowerCase().includes(q) ||
        (a.race ?? '').toLowerCase().includes(q) ||
        (a.nom_eleveur ?? '').toLowerCase().includes(q)
      );
    }
    return true;
  });

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-4">
      {/* En-tête */}
      <div className="text-center space-y-1">
        <h1 className="text-3xl font-bold font-galey text-teal-800">💚 Animaux à adopter</h1>
        <p className="text-gray-500 font-galey text-sm">Annonces publiées par les associations &amp; refuges</p>
      </div>

      {/* Recherche */}
      <input
        type="search"
        placeholder="Rechercher un animal, une race, une association…"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        className="w-full px-4 py-3 rounded-2xl border border-gray-200 text-sm font-galey focus:outline-none focus:border-teal-400 shadow-sm"
      />

      {/* Filtres espèce */}
      <div className="flex gap-2 flex-wrap">
        {ESPECES.map((e) => (
          <button key={e} onClick={() => { setEspece(e); setRace('toutes'); }}
            className={`px-4 py-1.5 rounded-full text-sm font-galey font-semibold border transition-all ${
              espece === e ? 'bg-teal-700 text-white border-teal-700' : 'bg-white text-gray-600 border-gray-200 hover:border-teal-300'
            }`}>
            {ESPECE_EMOJI[e]} {ESPECE_LABEL[e]}
          </button>
        ))}
      </div>

      {/* Filtre race */}
      {availableRaces.length > 1 && (
        <div className="flex gap-2 flex-wrap">
          {availableRaces.map((r) => (
            <button key={r} onClick={() => setRace(r)}
              className={`px-3 py-1 rounded-full text-xs font-galey border transition-all ${
                race === r ? 'bg-green-100 text-green-700 border-green-400 font-semibold' : 'bg-white text-gray-500 border-gray-200 hover:border-green-300'
              }`}>
              {r === 'toutes' ? 'Toutes races' : r}
            </button>
          ))}
        </div>
      )}

      {/* Résultats */}
      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
        </div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-16 text-gray-400 font-galey">
          <p className="text-5xl mb-4">🐾</p>
          <p className="text-lg">Aucun animal disponible à l&apos;adoption pour le moment.</p>
        </div>
      ) : (
        <>
          <p className="text-sm text-gray-400 font-galey">
            {filtered.length} animal{filtered.length !== 1 ? 'x' : ''} disponible{filtered.length !== 1 ? 's' : ''}
          </p>
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
            {filtered.map((a) => (
              <div key={a.id} className="bg-white rounded-2xl overflow-hidden shadow-sm border border-gray-100 hover:border-teal-200 hover:shadow-md transition-all group">
                {/* Photo */}
                <Link href={`/annonces/${a.id}`}>
                  <div className="aspect-square bg-gray-100 relative overflow-hidden">
                    {a.photos?.[0] ? (
                      <Image src={a.photos[0]} alt={a.titre ?? 'Animal'} fill
                        className="object-cover group-hover:scale-105 transition-transform duration-300" unoptimized />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center text-4xl">
                        {ESPECE_EMOJI[a.espece ?? 'autre'] ?? '🐾'}
                      </div>
                    )}
                    <div className="absolute top-2 left-2 bg-teal-700/90 text-white text-xs font-galey font-semibold px-2 py-0.5 rounded-full">
                      Adoption
                    </div>
                    {(a.sexe === 'male' || a.sexe === 'femelle') && (
                      <div className="absolute top-2 right-8 bg-white/80 rounded-full p-1 text-xs">
                        {a.sexe === 'male' ? '♂' : '♀'}
                      </div>
                    )}
                    {/* Bouton like */}
                    <button
                      onClick={(e) => { e.preventDefault(); toggleLike(a.id); }}
                      className="absolute top-2 right-2 bg-black/40 rounded-lg px-1.5 py-1 flex items-center gap-1 text-white text-xs hover:bg-black/60 transition-colors"
                    >
                      <span className={likedIds.has(a.id) ? 'text-red-400' : ''}>{likedIds.has(a.id) ? '❤️' : '🤍'}</span>
                      {(likeCounts[a.id] ?? 0) > 0 && <span className="font-galey">{likeCounts[a.id]}</span>}
                    </button>
                  </div>
                </Link>
                {/* Infos */}
                <div className="p-3">
                  <Link href={`/annonces/${a.id}`}>
                    <p className="font-bold font-galey text-sm text-gray-900 truncate hover:text-teal-700">
                      {a.titre ?? `${a.espece ?? ''} à adopter`}
                    </p>
                    {a.race && <p className="text-xs text-gray-500 font-galey truncate">{a.race}</p>}
                  </Link>
                  <div className="flex items-center justify-between mt-1.5">
                    {ageLabel(a.date_naissance_animal) ? (
                      <span className="text-xs text-teal-700 font-galey">{ageLabel(a.date_naissance_animal)}</span>
                    ) : <span />}
                    {a.ville_eleveur && (
                      <span className="text-xs text-gray-400 font-galey truncate">📍 {a.ville_eleveur}</span>
                    )}
                  </div>
                  {a.nom_eleveur && a.uid_eleveur && (
                    <Link href={`/associations/${a.uid_eleveur}`}
                      className="text-xs text-teal-600 font-galey mt-1 truncate block hover:text-teal-800 hover:underline">
                      🏠 {a.nom_eleveur}
                    </Link>
                  )}
                </div>
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
