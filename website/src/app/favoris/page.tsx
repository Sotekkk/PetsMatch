'use client';

import { useEffect, useState } from 'react';
import Image from 'next/image';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

// ── Types ─────────────────────────────────────────────────────────────────────

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

type Tab = 'favoris' | 'likes';

// ── Data fetching ─────────────────────────────────────────────────────────────

async function loadItems(userUid: string, table: Tab, activeProfileId: string | null, profileType: string): Promise<SavedItem[]> {
  const base = supabase.from(table).select('annonce_id, bebe_index').eq('user_uid', userUid);
  // Filtre par profile_id (précis) avec fallback sur données sans profile_id
  const q = activeProfileId
    ? base.or(`profile_id.eq.${activeProfileId},profile_id.is.null`)
    : base.or(`profile_type.eq.${profileType},profile_type.is.null`);
  const { data: rows } = await q.order('created_at', { ascending: false });

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
    const bi = row.bebe_index as number | null;

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

// ── Page ──────────────────────────────────────────────────────────────────────

export default function FavorisPage() {
  const { user, userData } = useAuth();
  const router = useRouter();
  const activeProfileId = useActiveProfile();
  const [tab, setTab] = useState<Tab>('favoris');
  const [likeItems, setLikeItems]   = useState<SavedItem[]>([]);
  const [favItems, setFavItems]     = useState<SavedItem[]>([]);
  const [loadingLikes, setLoadingLikes] = useState(false);
  const [loadingFavs, setLoadingFavs]   = useState(false);
  const [loadedLikes, setLoadedLikes]   = useState(false);
  const [loadedFavs, setLoadedFavs]     = useState(false);
  const [profileType, setProfileType] = useState('');

  // Résoudre le type du profil actif
  useEffect(() => {
    if (!activeProfileId) {
      setProfileType(
        userData?.isElevage ? 'eleveur'
        : userData?.isAssociation ? 'association'
        : 'particulier'
      );
    } else {
      supabase.from('user_profiles').select('profile_type').eq('id', activeProfileId).single()
        .then(({ data }) => setProfileType((data as Record<string, unknown>)?.profile_type as string ?? 'particulier'));
    }
  }, [activeProfileId, userData]);

  // Recharger quand le profil change
  useEffect(() => {
    if (user && profileType) {
      setLoadedFavs(false);
      setLoadedLikes(false);
      doLoad('favoris');
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [profileType, user]);

  useEffect(() => {
    if (!user || !profileType) return;
    if (tab === 'likes'   && !loadedLikes) doLoad('likes');
    if (tab === 'favoris' && !loadedFavs)  doLoad('favoris');
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab, user, profileType]);

  async function doLoad(t: Tab) {
    if (!user || !profileType) return;
    const isPrimary = !activeProfileId;
    if (t === 'likes') {
      setLoadingLikes(true);
      const items = await loadItems(user.uid, 'likes', activeProfileId ?? null, profileType);
      setLikeItems(items); setLoadingLikes(false); setLoadedLikes(true);
    } else {
      setLoadingFavs(true);
      const items = await loadItems(user.uid, 'favoris', activeProfileId ?? null, profileType);
      setFavItems(items); setLoadingFavs(false); setLoadedFavs(true);
    }
  }

  async function removeItem(item: SavedItem, t: Tab) {
    if (t === 'likes') setLikeItems(p => p.filter(i => !(i.annonceId === item.annonceId && i.bebeIndex === item.bebeIndex)));
    else               setFavItems(p  => p.filter(i => !(i.annonceId === item.annonceId && i.bebeIndex === item.bebeIndex)));
    const q = supabase.from(t).delete().eq('user_uid', user!.uid).eq('annonce_id', item.annonceId);
    item.bebeIndex !== null ? await q.eq('bebe_index', item.bebeIndex) : await q.is('bebe_index', null);
  }

  function openInFeed(item: SavedItem) {
    sessionStorage.setItem('feedJump', JSON.stringify({
      annonceId: item.annonceId,
      bebeIndex: item.bebeIndex,
      espece: item.espece ?? 'tous',
    }));
    router.push('/annonces/feed');
  }

  if (!user) {
    return (
      <div className="min-h-screen bg-[#F5F5F0] flex items-center justify-center">
        <div className="text-center px-6">
          <div className="text-5xl mb-4">❤️</div>
          <p className="text-gray-500 mb-6 font-medium">Connectez-vous pour voir vos interactions</p>
          <Link href="/connexion"
            className="bg-[#0C5C6C] text-white px-8 py-3 rounded-full font-semibold hover:bg-[#094F5D] transition-colors">
            Se connecter
          </Link>
        </div>
      </div>
    );
  }

  const items     = tab === 'likes' ? likeItems : favItems;
  const isLoading = tab === 'likes' ? loadingLikes : loadingFavs;

  return (
    <div className="min-h-screen bg-[#F5F5F0]">

      {/* ── Barre teal (miroir AppBar Flutter) ── */}
      <div className="bg-[#0C5C6C] px-4 pt-4 pb-0 sticky top-16 z-40">
        <div className="max-w-3xl mx-auto">
          <h1 className="text-white text-xl font-bold mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>
            Mes interactions
          </h1>
          {/* TabBar style Flutter */}
          <div className="flex">
            <button
              onClick={() => setTab('favoris')}
              className={`flex-1 flex items-center justify-center gap-1.5 py-3 text-sm font-semibold border-b-2 transition-colors ${
                tab === 'favoris'
                  ? 'border-white text-white'
                  : 'border-transparent text-white/50 hover:text-white/75'
              }`}>
              <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                <path d="M17 3H7c-1.1 0-2 .9-2 2v16l7-3 7 3V5c0-1.1-.9-2-2-2z"/>
              </svg>
              Sauvegardés
              {loadedFavs && favItems.length > 0 && (
                <span className="ml-1 bg-white/20 text-white text-[10px] px-1.5 py-0.5 rounded-full font-bold">
                  {favItems.length}
                </span>
              )}
            </button>
            <button
              onClick={() => setTab('likes')}
              className={`flex-1 flex items-center justify-center gap-1.5 py-3 text-sm font-semibold border-b-2 transition-colors ${
                tab === 'likes'
                  ? 'border-white text-white'
                  : 'border-transparent text-white/50 hover:text-white/75'
              }`}>
              <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                <path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/>
              </svg>
              J&apos;aime
              {loadedLikes && likeItems.length > 0 && (
                <span className="ml-1 bg-white/20 text-white text-[10px] px-1.5 py-0.5 rounded-full font-bold">
                  {likeItems.length}
                </span>
              )}
            </button>
          </div>
        </div>
      </div>

      {/* ── Contenu ── */}
      <div className="max-w-3xl mx-auto px-3 py-4">

        {isLoading ? (
          <div className="flex justify-center py-24">
            <div className="w-8 h-8 border-4 border-[#0C5C6C]/20 border-t-[#0C5C6C] rounded-full animate-spin" />
          </div>

        ) : items.length === 0 ? (
          <div className="flex flex-col items-center py-24 text-center">
            <svg className="w-20 h-20 text-gray-200 mb-5" fill="currentColor" viewBox="0 0 24 24">
              {tab === 'favoris'
                ? <path d="M17 3H7c-1.1 0-2 .9-2 2v16l7-3 7 3V5c0-1.1-.9-2-2-2z"/>
                : <path d="M16.5 3c-1.74 0-3.41.81-4.5 2.09C10.91 3.81 9.24 3 7.5 3 4.42 3 2 5.42 2 8.5c0 3.78 3.4 6.86 8.55 11.54L12 21.35l1.45-1.32C18.6 15.36 22 12.28 22 8.5 22 5.42 19.58 3 16.5 3zm-4.4 15.55l-.1.1-.1-.1C7.14 14.24 4 11.39 4 8.5 4 6.5 5.5 5 7.5 5c1.54 0 3.04.99 3.57 2.36h1.87C13.46 5.99 14.96 5 16.5 5c2 0 3.5 1.5 3.5 3.5 0 2.89-3.14 5.74-7.9 10.05z"/>}
            </svg>
            <p className="text-gray-400 text-base font-medium mb-1">
              {tab === 'favoris' ? 'Aucun animal sauvegardé' : 'Aucun like pour l\'instant'}
            </p>
            <p className="text-gray-300 text-sm mb-8">Utilise le feed pour découvrir des annonces.</p>
            <Link href="/annonces/feed"
              className="bg-[#0C5C6C] text-white px-7 py-3 rounded-full text-sm font-semibold hover:bg-[#094F5D] transition-colors">
              Découvrir le feed →
            </Link>
          </div>

        ) : (
          <div className="grid grid-cols-2 gap-2.5">
            {items.map((item) => (
              <SavedCard
                key={`${item.annonceId}_${item.bebeIndex ?? 'null'}`}
                item={item}
                isFavori={tab === 'favoris'}
                onRemove={() => removeItem(item, tab)}
                onOpen={() => openInFeed(item)}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

// ── Carte (miroir _SavedCard Flutter) ─────────────────────────────────────────

function SavedCard({
  item, isFavori, onRemove, onOpen,
}: {
  item: SavedItem;
  isFavori: boolean;
  onRemove: () => void;
  onOpen: () => void;
}) {
  return (
    <div className="relative rounded-2xl overflow-hidden bg-[#1A1A1A] shadow-sm"
      style={{ aspectRatio: '0.72' }}>

      {/* Blurred background */}
      <div className="absolute inset-0 overflow-hidden">
        <Image src={item.photo} alt="" fill className="object-cover scale-110"
          style={{ filter: 'blur(20px)' }} sizes="200px" />
      </div>
      <div className="absolute inset-0 bg-black/25" />

      {/* Tap → feed */}
      <button onClick={onOpen} className="absolute inset-0 w-full h-full overflow-hidden">
        {/* fitWidth: fill full width, crop top/bottom if needed */}
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={item.photo} alt={item.nom}
          className="absolute w-full h-auto top-0" />
        {/* Gradient bas */}
        <div className="absolute inset-0"
          style={{ background: 'linear-gradient(to bottom, transparent 50%, rgba(0,0,0,0.73) 100%)' }} />
        {/* Infos bas */}
        <div className="absolute bottom-0 left-0 right-0 p-2.5 text-left">
          <div className="flex items-center gap-1">
            {item.sexe && (
              <span className="text-white text-sm font-bold leading-none">
                {item.sexe === 'male' ? '♂' : '♀'}
              </span>
            )}
            <p className="text-white font-bold text-[13px] truncate leading-tight"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              {item.nom}
            </p>
          </div>
          {item.race && (
            <p className="text-white/70 text-[11px] truncate capitalize mt-0.5">{item.race}</p>
          )}
          {item.prix != null && (
            <p className="text-white font-bold text-[13px] mt-0.5">{item.prix} €</p>
          )}
          {item.nomEleveur && (
            <p className="text-white/60 text-[10px] mt-0.5 truncate">🏡 {item.nomEleveur}</p>
          )}
        </div>
      </button>

      {/* Badge retirer haut-droite */}
      <button
        onClick={onRemove}
        title={isFavori ? 'Retirer des sauvegardés' : 'Retirer des likes'}
        className="absolute top-2 right-2 w-8 h-8 rounded-full bg-black/45 flex items-center justify-center hover:scale-110 transition-transform z-10">
        {isFavori ? (
          <svg className="w-4 h-4 text-amber-400" fill="currentColor" viewBox="0 0 24 24">
            <path d="M17 3H7c-1.1 0-2 .9-2 2v16l7-3 7 3V5c0-1.1-.9-2-2-2z"/>
          </svg>
        ) : (
          <svg className="w-4 h-4 text-red-400" fill="currentColor" viewBox="0 0 24 24">
            <path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/>
          </svg>
        )}
      </button>
    </div>
  );
}
