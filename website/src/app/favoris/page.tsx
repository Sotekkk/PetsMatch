'use client';

import { useEffect, useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface SavedItem {
  annonceId: string;
  bebeIndex: number | null;
  photo: string;
  nom: string;
  race?: string;
  espece?: string;
  sexe?: string;
  prix?: number | null;
  ville?: string;
  nomEleveur?: string;
}

type Tab = 'likes' | 'favoris';

async function loadItems(userUid: string, table: 'likes' | 'favoris'): Promise<SavedItem[]> {
  const { data: rows } = await supabase
    .from(table)
    .select('annonce_id, bebe_index')
    .eq('user_uid', userUid)
    .order('created_at', { ascending: false });

  if (!rows || rows.length === 0) return [];

  const annonceIds = [...new Set(rows.map((r) => r.annonce_id as string))];
  const { data: annonces } = await supabase
    .from('annonces')
    .select('id, titre, espece, race, type, photos, animaux_portee, prix, saillie_prix, ville_eleveur, sexe, nom_eleveur')
    .in('id', annonceIds);

  const annonceMap = new Map((annonces ?? []).map((a) => [a.id, a]));
  const result: SavedItem[] = [];

  for (const row of rows) {
    const a = annonceMap.get(row.annonce_id);
    if (!a) continue;
    const aPhotos: string[] = a.photos ?? [];
    const bebes: Record<string, unknown>[] = a.animaux_portee ?? [];
    const bi = row.bebe_index;

    if (bi !== null && bi !== undefined && bebes[bi]) {
      const b = bebes[bi];
      const bPhotos: string[] = (b.photos as string[]) ?? [];
      const photo = bPhotos[0] ?? aPhotos[0] ?? '';
      if (!photo) continue;
      result.push({
        annonceId: row.annonce_id, bebeIndex: bi, photo,
        nom: (b.nom as string) || `Bébé ${bi + 1}`,
        race: a.race, espece: a.espece,
        sexe: b.sexe as string | undefined,
        prix: b.prix as number | undefined,
        ville: a.ville_eleveur, nomEleveur: a.nom_eleveur,
      });
    } else if (bi === null) {
      const photo = aPhotos[0] ?? '';
      if (!photo) continue;
      result.push({
        annonceId: row.annonce_id, bebeIndex: null, photo,
        nom: a.titre || `${a.espece ?? ''} ${a.race ?? ''}`.trim(),
        race: a.race, espece: a.espece, sexe: a.sexe,
        prix: a.saillie_prix ?? a.prix,
        ville: a.ville_eleveur, nomEleveur: a.nom_eleveur,
      });
    }
  }
  return result;
}

export default function FavorisPage() {
  const { user } = useAuth();
  const [tab, setTab] = useState<Tab>('favoris');
  const [likeItems, setLikeItems]   = useState<SavedItem[]>([]);
  const [favItems, setFavItems]     = useState<SavedItem[]>([]);
  const [loadingLikes, setLoadingLikes]   = useState(false);
  const [loadingFavs, setLoadingFavs]     = useState(false);
  const [loadedLikes, setLoadedLikes]     = useState(false);
  const [loadedFavs, setLoadedFavs]       = useState(false);

  useEffect(() => {
    if (!user) return;
    // Charger les favoris (🔖) au démarrage
    loadTab('favoris');
  }, [user]);

  useEffect(() => {
    if (!user) return;
    if (tab === 'likes' && !loadedLikes) loadTab('likes');
    if (tab === 'favoris' && !loadedFavs) loadTab('favoris');
  }, [tab, user]);

  async function loadTab(t: Tab) {
    if (!user) return;
    if (t === 'likes') {
      setLoadingLikes(true);
      const items = await loadItems(user.uid, 'likes');
      setLikeItems(items);
      setLoadingLikes(false);
      setLoadedLikes(true);
    } else {
      setLoadingFavs(true);
      const items = await loadItems(user.uid, 'favoris');
      setFavItems(items);
      setLoadingFavs(false);
      setLoadedFavs(true);
    }
  }

  async function removeItem(item: SavedItem, t: Tab) {
    const table = t === 'likes' ? 'likes' : 'favoris';
    if (t === 'likes') {
      setLikeItems((prev) => prev.filter((i) => !(i.annonceId === item.annonceId && i.bebeIndex === item.bebeIndex)));
    } else {
      setFavItems((prev) => prev.filter((i) => !(i.annonceId === item.annonceId && i.bebeIndex === item.bebeIndex)));
    }
    const q = supabase.from(table).delete().eq('user_uid', user!.uid).eq('annonce_id', item.annonceId);
    if (item.bebeIndex !== null) await q.eq('bebe_index', item.bebeIndex);
    else await q.is('bebe_index', null);
  }

  if (!user) {
    return (
      <div className="min-h-screen bg-[#F5F5F0] flex items-center justify-center">
        <div className="text-center">
          <p className="text-gray-500 mb-4">Connectez-vous pour voir vos likes et sauvegardés</p>
          <Link href="/connexion" className="bg-[#0C5C6C] text-white px-6 py-3 rounded-full hover:bg-[#094F5D] transition-colors">
            Se connecter
          </Link>
        </div>
      </div>
    );
  }

  const items      = tab === 'likes' ? likeItems : favItems;
  const isLoading  = tab === 'likes' ? loadingLikes : loadingFavs;

  return (
    <div className="min-h-screen bg-[#F5F5F0]">
      <div className="max-w-2xl mx-auto px-4 py-8">

        {/* En-tête */}
        <div className="mb-6">
          <Link href="/profil" className="text-sm text-[#0C5C6C] hover:underline">← Mon profil</Link>
          <h1 className="text-2xl font-bold text-[#1F2A2E] mt-3" style={{ fontFamily: 'Galey, sans-serif' }}>
            Mes interactions
          </h1>
        </div>

        {/* Onglets */}
        <div className="flex gap-2 mb-6 bg-white rounded-2xl p-1.5 shadow-sm border border-gray-100">
          <button
            onClick={() => setTab('favoris')}
            className={`flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl text-sm font-semibold transition-all ${
              tab === 'favoris'
                ? 'bg-yellow-50 text-yellow-700 shadow-sm'
                : 'text-gray-500 hover:text-gray-700'
            }`}>
            🔖 Sauvegardés
            {loadedFavs && favItems.length > 0 && (
              <span className="bg-yellow-100 text-yellow-700 text-xs px-1.5 py-0.5 rounded-full font-bold">
                {favItems.length}
              </span>
            )}
          </button>
          <button
            onClick={() => setTab('likes')}
            className={`flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl text-sm font-semibold transition-all ${
              tab === 'likes'
                ? 'bg-red-50 text-red-600 shadow-sm'
                : 'text-gray-500 hover:text-gray-700'
            }`}>
            ❤️ J&apos;aime
            {loadedLikes && likeItems.length > 0 && (
              <span className="bg-red-100 text-red-600 text-xs px-1.5 py-0.5 rounded-full font-bold">
                {likeItems.length}
              </span>
            )}
          </button>
        </div>

        {/* Contenu */}
        {isLoading ? (
          <div className="flex justify-center py-20">
            <div className="w-8 h-8 border-4 border-[#0C5C6C]/20 border-t-[#0C5C6C] rounded-full animate-spin" />
          </div>
        ) : items.length === 0 ? (
          <div className="text-center py-20">
            <div className="text-5xl mb-4">{tab === 'favoris' ? '🔖' : '🤍'}</div>
            <p className="text-gray-400 text-sm">
              {tab === 'favoris'
                ? 'Aucun animal sauvegardé pour l\'instant.'
                : 'Aucun like pour l\'instant.'}
            </p>
            <Link href="/annonces/feed"
              className="mt-6 inline-block bg-[#0C5C6C] text-white px-6 py-3 rounded-full text-sm hover:bg-[#094F5D] transition-colors">
              Découvrir le feed →
            </Link>
          </div>
        ) : (
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
            {items.map((item) => (
              <div key={`${item.annonceId}_${item.bebeIndex ?? 'null'}`} className="relative group rounded-2xl overflow-hidden bg-white shadow-sm">
                <Link href={`/annonces/${item.annonceId}`}>
                  <div className="relative aspect-[3/4]">
                    <Image src={item.photo} alt={item.nom} fill className="object-cover" sizes="(max-width: 640px) 50vw, 33vw" />
                    <div className="absolute inset-0 bg-gradient-to-t from-black/70 via-transparent to-transparent" />
                    <div className="absolute bottom-0 left-0 right-0 p-3">
                      <div className="flex items-center gap-1 mb-0.5">
                        {item.sexe && (
                          <span className="text-white text-sm font-bold">{item.sexe === 'male' ? '♂' : '♀'}</span>
                        )}
                        <p className="text-white font-semibold text-sm truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
                          {item.nom}
                        </p>
                      </div>
                      {item.race && <p className="text-white/70 text-xs truncate capitalize">{item.race}</p>}
                      {item.prix != null && (
                        <p className="text-white font-bold text-sm mt-0.5">{item.prix} €</p>
                      )}
                      {item.nomEleveur && (
                        <p className="text-white/60 text-[10px] mt-0.5 truncate">🏡 {item.nomEleveur}</p>
                      )}
                    </div>
                  </div>
                </Link>
                {/* Bouton retirer */}
                <button
                  onClick={() => removeItem(item, tab)}
                  title={tab === 'favoris' ? 'Retirer des sauvegardés' : 'Retirer des likes'}
                  className={`absolute top-2 right-2 w-8 h-8 rounded-full bg-black/50 backdrop-blur-sm flex items-center justify-center text-sm hover:scale-110 transition-transform ${
                    tab === 'favoris' ? 'text-yellow-400' : 'text-red-400'
                  }`}>
                  {tab === 'favoris' ? '🔖' : '❤️'}
                </button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
