'use client';

import { useEffect, useState, useCallback, useRef } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { collection, query, where, getDocs, addDoc, serverTimestamp } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

// ── Types ──────────────────────────────────────────────────────────────────────

interface RawBebe {
  nom?: string;
  sexe?: string;
  couleur?: string;
  prix?: number;
  statut?: string;
  photos?: string[];
  description?: string;
}

interface RawAnnonce {
  id: string;
  titre?: string;
  espece?: string;
  race?: string;
  type?: string;
  type_vente?: string;
  photos?: string[];
  animaux_portee?: RawBebe[];
  prix?: number;
  saillie_prix?: number;
  prix_min_portee?: number;
  prix_max_portee?: number;
  ville_eleveur?: string;
  sexe?: string;
  nom_eleveur?: string;
  uid_eleveur?: string;
}

interface FeedItem {
  annonceId: string;
  bebeIndex: number | null;
  photos: string[];
  nom: string;
  race?: string;
  espece?: string;
  sexe?: string;
  prix?: number | null;
  statut?: string;
  description?: string;
  ville?: string;
  nomEleveur?: string;
  uidEleveur?: string;
  photoEleveur?: string;
  isSaillie?: boolean;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function buildFeedItems(annonces: RawAnnonce[]): FeedItem[] {
  const items: FeedItem[] = [];
  for (const a of annonces) {
    const bebes = (a.animaux_portee as RawBebe[] | undefined) ?? [];
    const aPhotos = (a.photos as string[] | undefined) ?? [];
    const isSaillie = a.type_vente === 'saillie';

    if (a.type === 'portee' && bebes.length > 0) {
      bebes.forEach((b, i) => {
        const bPhotos = (b.photos as string[] | undefined) ?? [];
        const photos = bPhotos.length > 0 ? bPhotos : aPhotos;
        if (photos.length > 0) {
          items.push({
            annonceId: a.id, bebeIndex: i, photos,
            nom: b.nom || `Bébé ${i + 1}`,
            race: a.race, espece: a.espece,
            sexe: b.sexe,
            prix: b.prix ?? null,
            statut: b.statut, description: b.description,
            ville: a.ville_eleveur, nomEleveur: a.nom_eleveur,
            uidEleveur: a.uid_eleveur, isSaillie: false,
          });
        }
      });
    } else if (aPhotos.length > 0) {
      const rawPrix = isSaillie ? a.saillie_prix : a.prix;
      const prix = rawPrix != null ? Number(rawPrix) : null;
      items.push({
        annonceId: a.id, bebeIndex: null, photos: aPhotos,
        nom: a.titre || `${a.espece ?? ''} ${a.race ?? ''}`.trim(),
        race: a.race, espece: a.espece,
        sexe: a.sexe, prix,
        ville: a.ville_eleveur, nomEleveur: a.nom_eleveur,
        uidEleveur: a.uid_eleveur, isSaillie,
      });
    }
  }
  return items;
}

const ESPECES = ['tous', 'chien', 'chat', 'lapin', 'oiseau', 'reptile', 'autre'];
const ESPECE_EMOJI: Record<string, string> = {
  tous: '🐾', chien: '🐕', chat: '🐈', lapin: '🐇',
  oiseau: '🐦', reptile: '🦎', autre: '🐾',
};
const ESPECE_LABEL: Record<string, string> = {
  tous: 'Toutes', chien: 'Chien', chat: 'Chat', lapin: 'Lapin',
  oiseau: 'Oiseau', reptile: 'Reptile', autre: 'Autre',
};

// ── Page principale ───────────────────────────────────────────────────────────

export default function FeedPage() {
  const { user, userData } = useAuth();
  const router = useRouter();

  const [step, setStep] = useState<'filters' | 'feed'>('filters');
  const [filtreEspece, setFiltreEspece] = useState('tous');
  const [filtreType, setFiltreType] = useState('tous');

  const pendingIndex = useRef<number | null>(null);

  const [items, setItems] = useState<FeedItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [itemIndex, setItemIndex] = useState(0);
  const [photoIndex, setPhotoIndex] = useState(0);

  const [likedKeys, setLikedKeys] = useState<Set<string>>(new Set());
  const [likeAnim, setLikeAnim] = useState(false);
  const [favoritedKeys, setFavoritedKeys] = useState<Set<string>>(new Set());
  const [favAnim, setFavAnim] = useState(false);

  const [descExpanded, setDescExpanded] = useState(false);
  const [shareItem, setShareItem] = useState<FeedItem | null>(null);
  const [openingMessage, setOpeningMessage] = useState(false);
  const [showLoginBanner, setShowLoginBanner] = useState(false);
  const [loginBannerAction, setLoginBannerAction] = useState('');
  const loginBannerTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const wheelLocked = useRef(false);

  // ── Charger le feed ─────────────────────────────────────────────────────────

  const loadFeed = useCallback(async (overrideEspece?: string, overrideType?: string) => {
    const espece = overrideEspece ?? filtreEspece;
    const type   = overrideType   ?? filtreType;
    setLoading(true);
    let q = supabase
      .from('annonces')
      .select('id, titre, espece, race, type, type_vente, photos, animaux_portee, prix, saillie_prix, prix_min_portee, prix_max_portee, ville_eleveur, sexe, nom_eleveur, uid_eleveur')
      .eq('statut', 'disponible')
      .order('created_at', { ascending: false });

    if (espece !== 'tous') q = q.eq('espece', espece);
    if (type === 'saillie') q = q.eq('type_vente', 'saillie');
    if (type === 'vente') q = q.neq('type_vente', 'saillie');

    const { data } = await q;
    let feed = buildFeedItems((data ?? []) as RawAnnonce[]);

    // Batch fetch photos éleveur
    const uids = [...new Set(feed.map(f => f.uidEleveur).filter(Boolean))] as string[];
    if (uids.length > 0) {
      const { data: users } = await supabase
        .from('users')
        .select('uid, profile_picture_url_elevage, profile_picture_url')
        .in('uid', uids);
      if (users) {
        const photoMap: Record<string, string> = {};
        for (const u of users) {
          photoMap[u.uid] = u.profile_picture_url_elevage ?? u.profile_picture_url ?? '';
        }
        feed = feed.map(f => ({ ...f, photoEleveur: f.uidEleveur ? photoMap[f.uidEleveur] : undefined }));
      }
    }

    setItems(feed);
    const targetIndex = pendingIndex.current ?? 0;
    pendingIndex.current = null;
    setItemIndex(Math.min(targetIndex, Math.max(feed.length - 1, 0)));
    setPhotoIndex(0);

    if (user) {
      const [{ data: likes }, { data: favs }] = await Promise.all([
        supabase.from('likes').select('annonce_id, bebe_index').eq('user_uid', user.uid),
        supabase.from('favoris').select('annonce_id, bebe_index').eq('user_uid', user.uid),
      ]);
      if (likes) setLikedKeys(new Set(likes.map((l) => `${l.annonce_id}_${l.bebe_index ?? 'null'}`)));
      if (favs) setFavoritedKeys(new Set(favs.map((f) => `${f.annonce_id}_${f.bebe_index ?? 'null'}`)));
    }

    setLoading(false);
    setStep('feed');
  }, [filtreEspece, filtreType, user]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Restaurer depuis messages ────────────────────────────────────────────────

  useEffect(() => {
    const saved = sessionStorage.getItem('feedReturn');
    if (!saved) return;
    sessionStorage.removeItem('feedReturn');
    const state = JSON.parse(saved) as { itemIndex: number; filtreEspece: string; filtreType: string };
    setFiltreEspece(state.filtreEspece);
    setFiltreType(state.filtreType);
    pendingIndex.current = state.itemIndex;
    loadFeed(state.filtreEspece, state.filtreType);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Navigation ──────────────────────────────────────────────────────────────

  const goNext = useCallback(() => {
    setItemIndex((i) => {
      const next = Math.min(i + 1, items.length - 1);
      if (next !== i) { setPhotoIndex(0); setDescExpanded(false); setShareItem(null); }
      return next;
    });
  }, [items.length]);

  const goPrev = useCallback(() => {
    setItemIndex((i) => {
      const prev = Math.max(i - 1, 0);
      if (prev !== i) { setPhotoIndex(0); setDescExpanded(false); setShareItem(null); }
      return prev;
    });
  }, []);

  const goNextPhoto = useCallback(() => {
    const item = items[itemIndex];
    if (item) setPhotoIndex((p) => Math.min(p + 1, item.photos.length - 1));
  }, [items, itemIndex]);

  const goPrevPhoto = useCallback(() => {
    setPhotoIndex((p) => Math.max(p - 1, 0));
  }, []);

  // ── Clavier ─────────────────────────────────────────────────────────────────

  useEffect(() => {
    if (step !== 'feed') return;
    function onKey(e: KeyboardEvent) {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); e.key === 'ArrowDown' ? goNext() : goPrev(); }
      if (e.key === 'ArrowRight') goNextPhoto();
      if (e.key === 'ArrowLeft') goPrevPhoto();
      if (e.key === 'Escape') { if (shareItem) { setShareItem(null); } else setStep('filters'); }
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [step, goNext, goPrev, goNextPhoto, goPrevPhoto]);

  // ── Molette ──────────────────────────────────────────────────────────────────

  useEffect(() => {
    if (step !== 'feed') return;
    function onWheel(e: WheelEvent) {
      e.preventDefault();
      if (wheelLocked.current) return;
      wheelLocked.current = true;
      e.deltaY > 0 ? goNext() : goPrev();
      setTimeout(() => { wheelLocked.current = false; }, 600);
    }
    window.addEventListener('wheel', onWheel, { passive: false });
    return () => window.removeEventListener('wheel', onWheel);
  }, [step, goNext, goPrev]);

  useEffect(() => () => { if (loginBannerTimer.current) clearTimeout(loginBannerTimer.current); }, []);

  // ── Helpers login guard ──────────────────────────────────────────────────────

  function requireLogin(action: string): boolean {
    if (user) return false;
    setLoginBannerAction(action);
    setShowLoginBanner(true);
    if (loginBannerTimer.current) clearTimeout(loginBannerTimer.current);
    loginBannerTimer.current = setTimeout(() => setShowLoginBanner(false), 3500);
    return true;
  }

  // ── Like ────────────────────────────────────────────────────────────────────

  async function toggleLike(item: FeedItem) {
    if (requireLogin('aimer')) return;
    const key = `${item.annonceId}_${item.bebeIndex ?? 'null'}`;
    const isLiked = likedKeys.has(key);
    setLikedKeys((prev) => { const n = new Set(prev); isLiked ? n.delete(key) : n.add(key); return n; });
    if (!isLiked) { setLikeAnim(true); setTimeout(() => setLikeAnim(false), 600); }
    if (isLiked) {
      const q = supabase.from('likes').delete().eq('user_uid', user!.uid).eq('annonce_id', item.annonceId);
      item.bebeIndex !== null ? await q.eq('bebe_index', item.bebeIndex) : await q.is('bebe_index', null);
    } else {
      await supabase.from('likes').upsert({ user_uid: user!.uid, annonce_id: item.annonceId, bebe_index: item.bebeIndex });
      if (item.uidEleveur && item.uidEleveur !== user!.uid) {
        const likerName = userData?.firstname
          ? `${userData.firstname}${userData.lastname ? ' ' + userData.lastname : ''}`
          : 'Quelqu\'un';
        await supabase.from('notifications').insert({
          uid: item.uidEleveur, type: 'like',
          title: '❤️ Nouveau like sur votre annonce',
          body: `${likerName} a aimé "${item.nom}"`,
          data: { annonceId: item.annonceId, bebeIndex: item.bebeIndex, fromUid: user!.uid },
          read: false,
        });
      }
    }
  }

  // ── Favori ──────────────────────────────────────────────────────────────────

  async function toggleFavorite(item: FeedItem) {
    if (requireLogin('sauvegarder')) return;
    const key = `${item.annonceId}_${item.bebeIndex ?? 'null'}`;
    const isFav = favoritedKeys.has(key);
    setFavoritedKeys((prev) => { const n = new Set(prev); isFav ? n.delete(key) : n.add(key); return n; });
    if (!isFav) { setFavAnim(true); setTimeout(() => setFavAnim(false), 600); }
    if (isFav) {
      const q = supabase.from('favoris').delete().eq('user_uid', user!.uid).eq('annonce_id', item.annonceId);
      item.bebeIndex !== null ? await q.eq('bebe_index', item.bebeIndex) : await q.is('bebe_index', null);
    } else {
      await supabase.from('favoris').upsert({ user_uid: user!.uid, annonce_id: item.annonceId, bebe_index: item.bebeIndex });
    }
  }

  // ── Message ─────────────────────────────────────────────────────────────────

  async function openMessage(item: FeedItem) {
    if (requireLogin('envoyer un message')) return;
    if (!item.uidEleveur || item.uidEleveur === user!.uid) return;
    setOpeningMessage(true);
    try {
      const sortedIds = [user!.uid, item.uidEleveur].sort();
      const participantIds = sortedIds.join('_');
      const snap = await getDocs(query(collection(db, 'conversations'), where('participantIds', '==', participantIds)));
      let convId: string;
      if (snap.empty) {
        const ref = await addDoc(collection(db, 'conversations'), {
          participants: [user!.uid, item.uidEleveur],
          participantIds,
          lastMessage: '',
          timestamp: serverTimestamp(),
          unreadCount: {},
          categorie: 'annonces',
        });
        convId = ref.id;
      } else {
        convId = snap.docs[0].id;
      }
      sessionStorage.setItem('feedReturn', JSON.stringify({ itemIndex, filtreEspece, filtreType }));
      router.push(`/messages?conv=${convId}`);
    } finally {
      setOpeningMessage(false);
    }
  }

  // ── Partage ──────────────────────────────────────────────────────────────────

  async function handleShare(item: FeedItem) {
    const origin = window.location.origin;
    const url = `${origin}/annonces/${item.annonceId}`;
    const title = item.nom;
    const text = [item.race, item.prix != null ? `${item.prix} €` : null, item.ville ? `📍 ${item.ville}` : null]
      .filter(Boolean).join(' · ');

    if (typeof navigator.share === 'function') {
      try {
        // Sur mobile : essayer avec photo
        if (item.photos[0] && typeof navigator.canShare === 'function') {
          try {
            const resp = await fetch(item.photos[0]);
            const blob = await resp.blob();
            const file = new File([blob], 'animal.jpg', { type: 'image/jpeg' });
            if (navigator.canShare({ files: [file] })) {
              await navigator.share({ title, text, url, files: [file] });
              return;
            }
          } catch { /* fall through */ }
        }
        await navigator.share({ title, text, url });
        return;
      } catch (err) {
        if ((err as Error).name === 'AbortError') return;
        // Fall through to bottom sheet
      }
    }
    setShareItem(item);
  }

  // ── Étape filtres ────────────────────────────────────────────────────────────

  if (step === 'filters') {
    return (
      <div className="min-h-screen bg-[#F5F5F0] flex flex-col">
        <div className="max-w-lg mx-auto w-full px-4 py-10 flex-1 flex flex-col">
          <div className="mb-8">
            <Link href="/annonces" className="text-sm text-[#0C5C6C] hover:underline">← Annonces</Link>
            <h1 className="text-2xl font-bold text-[#1F2A2E] mt-3" style={{ fontFamily: 'Galey, sans-serif' }}>
              Fil d&apos;actualité
            </h1>
            <p className="text-gray-500 text-sm mt-1">Personnalise ton feed puis défile les bébés.</p>
          </div>

          <div className="mb-6">
            <p className="text-sm font-semibold text-gray-700 mb-3">Espèce</p>
            <div className="grid grid-cols-4 gap-2">
              {ESPECES.map((esp) => (
                <button key={esp} onClick={() => setFiltreEspece(esp)}
                  className={`flex flex-col items-center gap-1 py-3 rounded-2xl border-2 transition-colors ${
                    filtreEspece === esp
                      ? 'border-[#0C5C6C] bg-[#E8F4F6] text-[#0C5C6C]'
                      : 'border-gray-200 bg-white text-gray-500 hover:border-gray-300'
                  }`}>
                  <span className="text-2xl">{ESPECE_EMOJI[esp]}</span>
                  <span className="text-xs font-medium">{ESPECE_LABEL[esp]}</span>
                </button>
              ))}
            </div>
          </div>

          <div className="mb-8">
            <p className="text-sm font-semibold text-gray-700 mb-3">Type d&apos;annonce</p>
            <div className="flex gap-3">
              {[
                { value: 'tous', label: 'Tous' },
                { value: 'vente', label: '🐾 Compagnon' },
                { value: 'saillie', label: '💜 Saillie' },
              ].map((t) => (
                <button key={t.value} onClick={() => setFiltreType(t.value)}
                  className={`flex-1 py-3 rounded-2xl border-2 text-sm font-medium transition-colors ${
                    filtreType === t.value
                      ? 'border-[#0C5C6C] bg-[#E8F4F6] text-[#0C5C6C]'
                      : 'border-gray-200 bg-white text-gray-600 hover:border-gray-300'
                  }`}>
                  {t.label}
                </button>
              ))}
            </div>
          </div>

          <button onClick={() => loadFeed()} disabled={loading}
            className="w-full bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 text-white font-bold py-4 rounded-2xl text-base transition-colors">
            {loading ? 'Chargement…' : 'Lancer le feed →'}
          </button>
        </div>
      </div>
    );
  }

  // ── Feed vide ────────────────────────────────────────────────────────────────

  if (items.length === 0) {
    return (
      <div className="min-h-screen bg-black flex flex-col items-center justify-center gap-4">
        <p className="text-white text-lg">Aucune annonce avec photos pour ces filtres.</p>
        <button onClick={() => setStep('filters')}
          className="text-white/60 border border-white/20 px-5 py-2 rounded-full hover:bg-white/10">
          Modifier les filtres
        </button>
      </div>
    );
  }

  const item = items[itemIndex];
  const likeKey = `${item.annonceId}_${item.bebeIndex ?? 'null'}`;
  const isLiked = likedKeys.has(likeKey);
  const isFavorited = favoritedKeys.has(likeKey);
  const currentPhoto = item.photos[photoIndex] ?? item.photos[0];

  return (
    <div className="fixed inset-0 bg-black z-40 flex items-center justify-center overflow-hidden"
      onClick={() => shareItem && setShareItem(null)}>
      <div className="relative w-full h-full max-w-sm mx-auto">

        {/* Photo fond flouté + photo nette */}
        {currentPhoto && (
          <>
            <Image
              key={`${itemIndex}-${photoIndex}-bg`}
              src={currentPhoto} alt=""
              fill className="object-cover scale-110 blur-2xl opacity-60"
              aria-hidden="true"
            />
            <div className="absolute inset-0 bg-black/30" />
            <Image
              key={`${itemIndex}-${photoIndex}`}
              src={currentPhoto} alt={item.nom}
              fill className="object-contain relative z-10"
              priority
            />
          </>
        )}

        {/* Zones de tap pour changer de photo */}
        <div className="absolute inset-0 flex pointer-events-none">
          <div className="flex-1 pointer-events-auto" onClick={goPrevPhoto} />
          <div className="flex-1 pointer-events-auto" onClick={goNextPhoto} />
        </div>

        {/* Dégradés */}
        <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-black/20 pointer-events-none" />

        {/* ── Barre du haut ── */}
        <div className="absolute top-0 left-0 right-0 flex items-center justify-between p-4 pointer-events-auto z-10">
          <button onClick={() => setStep('filters')}
            className="w-10 h-10 rounded-full bg-black/40 backdrop-blur-sm text-white flex items-center justify-center hover:bg-black/60 transition-colors">
            ✕
          </button>
          <span className="text-white/60 text-xs">{itemIndex + 1} / {items.length}</span>
        </div>

        {/* ── Colonne d'actions droite (style TikTok) ── */}
        <div className="absolute right-2 bottom-28 flex flex-col items-center gap-1.5 z-10 pointer-events-auto">

          {/* Photo éleveur */}
          {item.uidEleveur && (
            <Link href={`/elevages/${item.uidEleveur}`}
              className="w-10 h-10 rounded-full border-2 border-white bg-[#EEF5EA] overflow-hidden flex-shrink-0 shadow-lg block mb-1"
              onClick={(e) => e.stopPropagation()}>
              {item.photoEleveur ? (
                <Image src={item.photoEleveur} alt={item.nomEleveur ?? ''} width={40} height={40} className="object-cover w-full h-full" />
              ) : (
                <div className="w-full h-full flex items-center justify-center text-base">🏡</div>
              )}
            </Link>
          )}

          {/* Like */}
          <button onClick={(e) => { e.stopPropagation(); toggleLike(item); }}
            className="group">
            <div className={`w-11 h-11 rounded-full backdrop-blur-sm flex items-center justify-center transition-all duration-200 ${likeAnim ? 'scale-125' : 'hover:scale-110 active:scale-95'} ${isLiked ? 'bg-red-500/30' : 'bg-black/40'}`}>
              <span className={`text-xl ${isLiked ? 'drop-shadow-[0_0_8px_rgba(239,68,68,0.9)]' : ''}`}>
                {isLiked ? '❤️' : '🤍'}
              </span>
            </div>
          </button>

          {/* Favoris */}
          <button onClick={(e) => { e.stopPropagation(); toggleFavorite(item); }}
            className="group">
            <div className={`w-11 h-11 rounded-full backdrop-blur-sm flex items-center justify-center transition-all duration-200 ${favAnim ? 'scale-125' : 'hover:scale-110 active:scale-95'} ${isFavorited ? 'bg-yellow-500/30' : 'bg-black/40'}`}>
              <span className="text-xl">{isFavorited ? '🔖' : '🔖'}</span>
            </div>
          </button>

          {/* Message */}
          <button onClick={(e) => { e.stopPropagation(); openMessage(item); }}
            disabled={openingMessage}
            className="group">
            <div className="w-11 h-11 rounded-full bg-black/40 backdrop-blur-sm flex items-center justify-center hover:scale-110 active:scale-95 transition-all duration-200">
              {openingMessage
                ? <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                : <svg className="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"/>
                  </svg>
              }
            </div>
          </button>

          {/* Partager */}
          <button onClick={(e) => { e.stopPropagation(); handleShare(item); }}
            className="group">
            <div className="w-11 h-11 rounded-full bg-black/40 backdrop-blur-sm flex items-center justify-center hover:scale-110 active:scale-95 transition-all duration-200">
              <svg className="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8.684 13.342C8.886 12.938 9 12.482 9 12c0-.482-.114-.938-.316-1.342m0 2.684a3 3 0 110-2.684m0 2.684l6.632 3.316m-6.632-6l6.632-3.316m0 0a3 3 0 105.367-2.684 3 3 0 00-5.367 2.684zm0 9.316a3 3 0 105.368 2.684 3 3 0 00-5.368-2.684z"/>
              </svg>
            </div>
          </button>
        </div>


        {/* ── Banner connexion ── */}
        {showLoginBanner && (
          <div className="absolute bottom-44 right-20 z-50 pointer-events-auto" style={{ animation: 'popIn 0.25s ease-out' }}>
            <div className="bg-white rounded-2xl shadow-2xl px-4 py-3 flex flex-col items-center gap-2 w-48">
              <span className="text-xl">🔒</span>
              <p className="text-[#1F2A2E] font-semibold text-xs text-center" style={{ fontFamily: 'Galey, sans-serif' }}>
                Connectez-vous pour {loginBannerAction}
              </p>
              <Link href="/connexion"
                className="text-xs bg-[#0C5C6C] text-white px-3 py-1.5 rounded-full hover:bg-[#094F5D] transition-colors whitespace-nowrap">
                Se connecter →
              </Link>
            </div>
          </div>
        )}

        {/* ── Infos bas de page ── */}
        <div className="absolute bottom-0 left-0 right-0 pr-16 pointer-events-auto z-10">
          <div className="p-4 pb-6">

            {/* Badge saillie */}
            {item.isSaillie && (
              <span className="inline-block text-white text-[10px] font-bold px-2 py-0.5 rounded-full bg-purple-500 mb-2">
                💜 Saillie
              </span>
            )}

            {/* Nom + sexe + prix */}
            <div className="flex items-end justify-between gap-3 mb-1">
              <div className="flex items-center gap-2 min-w-0">
                {item.sexe && (
                  <span className="text-white text-xl font-bold leading-none flex-shrink-0">
                    {item.sexe === 'male' ? '♂' : '♀'}
                  </span>
                )}
                <h2 className="text-white font-bold text-xl leading-tight truncate"
                  style={{ textShadow: '0 1px 6px rgba(0,0,0,0.7)' }}>
                  {item.nom}
                </h2>
              </div>
              {item.prix != null && (
                <span className="text-white font-bold text-lg flex-shrink-0"
                  style={{ textShadow: '0 1px 6px rgba(0,0,0,0.7)' }}>
                  {item.prix} €
                </span>
              )}
            </div>

            {/* Race + ville */}
            <div className="flex items-center gap-2 mb-1">
              {item.race && (
                <p className="text-white/80 text-sm capitalize truncate"
                  style={{ textShadow: '0 1px 3px rgba(0,0,0,0.6)' }}>
                  {item.race}
                </p>
              )}
              {item.race && item.ville && <span className="text-white/40 text-sm">·</span>}
              {item.ville && (
                <p className="text-white/60 text-xs truncate"
                  style={{ textShadow: '0 1px 3px rgba(0,0,0,0.6)' }}>
                  📍 {item.ville}
                </p>
              )}
            </div>

            {/* Nom éleveur */}
            {item.nomEleveur && (
              <p className="text-white/60 text-xs mb-2 truncate"
                style={{ textShadow: '0 1px 3px rgba(0,0,0,0.6)' }}>
                🏡 {item.nomEleveur}
              </p>
            )}

            {/* Description */}
            {item.description && (
              <div className="mb-2">
                <div className={`overflow-hidden transition-all duration-300 ease-in-out ${descExpanded ? 'max-h-40' : 'max-h-9'}`}>
                  <p className="text-white/85 text-sm leading-snug"
                    style={{ textShadow: '0 1px 4px rgba(0,0,0,0.6)' }}>
                    {item.description}
                  </p>
                </div>
                <button onClick={() => setDescExpanded(v => !v)}
                  className="text-white/70 text-xs font-bold hover:text-white transition-colors mt-0.5">
                  {descExpanded ? '↑ Moins' : '… Plus'}
                </button>
              </div>
            )}

            {/* Voir l'annonce */}
            <Link href={`/annonces/${item.annonceId}`}
              className="inline-block text-white text-xs border border-white/40 bg-white/10 backdrop-blur-sm px-4 py-1.5 rounded-full hover:bg-white/20 transition-colors">
              Voir l&apos;annonce →
            </Link>

            {/* Barre de progression photos */}
            {item.photos.length > 1 && (
              <div className="flex gap-1 mt-3">
                {item.photos.map((_, pi) => (
                  <div key={pi}
                    className={`flex-1 h-0.5 rounded-full transition-colors ${pi === photoIndex ? 'bg-white' : 'bg-white/30'}`} />
                ))}
              </div>
            )}
          </div>
        </div>

        {/* ── Hint clavier ── */}
        <KeyboardHint />
      </div>

      {/* ── Bottom sheet partage (fixed overlay, z-[70]) ── */}
      {shareItem && (
        <div className="fixed inset-0 z-[70] bg-black/60 flex items-end sm:items-center justify-center"
          onClick={() => setShareItem(null)}>
          <div className="w-full max-w-sm bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}>
            {/* Aperçu photo */}
            {shareItem.photos[0] && (
              <div className="relative h-52">
                <Image src={shareItem.photos[0]} alt={shareItem.nom} fill className="object-cover" />
                <div className="absolute inset-0 bg-gradient-to-t from-black/75 to-transparent" />
                <div className="absolute bottom-4 left-4 right-4">
                  <div className="flex items-center gap-2">
                    {shareItem.sexe && (
                      <span className="text-white text-lg font-bold">{shareItem.sexe === 'male' ? '♂' : '♀'}</span>
                    )}
                    <p className="text-white font-bold text-xl leading-tight" style={{ fontFamily: 'Galey, sans-serif' }}>
                      {shareItem.nom}
                    </p>
                    {shareItem.prix != null && (
                      <span className="ml-auto text-white font-bold text-base flex-shrink-0">{shareItem.prix} €</span>
                    )}
                  </div>
                  {shareItem.race && <p className="text-white/80 text-sm capitalize">{shareItem.race}</p>}
                  {shareItem.ville && <p className="text-white/60 text-xs mt-0.5">📍 {shareItem.ville}</p>}
                </div>
              </div>
            )}
            {/* Boutons */}
            <div className="p-5 pb-8">
              <p className="text-gray-400 text-xs text-center mb-4">Partager cette annonce</p>
              <div className="grid grid-cols-4 gap-3 mb-5">
                <ShareIconBtn emoji="💬" label="WhatsApp" onClick={() => {
                  const u = `${window.location.origin}/annonces/${shareItem.annonceId}`;
                  window.open(`https://wa.me/?text=${encodeURIComponent(`${shareItem.nom}${shareItem.race ? ' · ' + shareItem.race : ''}\n\n${u}`)}`, '_blank');
                  setShareItem(null);
                }} />
                <ShareIconBtn emoji="📘" label="Facebook" onClick={() => {
                  const u = `${window.location.origin}/annonces/${shareItem.annonceId}`;
                  window.open(`https://www.facebook.com/sharer/sharer.php?u=${encodeURIComponent(u)}`, '_blank');
                  setShareItem(null);
                }} />
                <ShareIconBtn emoji="✉️" label="Email" onClick={() => {
                  const u = `${window.location.origin}/annonces/${shareItem.annonceId}`;
                  window.open(`mailto:?subject=${encodeURIComponent(shareItem.nom + ' sur PetsMatch')}&body=${encodeURIComponent(`Découvre cette annonce : ${u}`)}`, '_blank');
                  setShareItem(null);
                }} />
                <ShareIconBtn emoji="📋" label="Copier" onClick={async () => {
                  const u = `${window.location.origin}/annonces/${shareItem.annonceId}`;
                  await navigator.clipboard.writeText(u).catch(() => {});
                  setShareItem(null);
                }} />
              </div>
              <button onClick={() => setShareItem(null)}
                className="w-full py-3 text-gray-500 text-sm font-medium border border-gray-200 rounded-2xl hover:bg-gray-50 transition-colors">
                Annuler
              </button>
            </div>
          </div>
        </div>
      )}

      <style jsx global>{`
        @keyframes popIn {
          from { opacity: 0; transform: scale(0.8) translateY(8px); }
          to   { opacity: 1; transform: scale(1) translateY(0); }
        }
      `}</style>
    </div>
  );
}

// ── Share icon button ─────────────────────────────────────────────────────────

function ShareIconBtn({ emoji, label, onClick }: { emoji: string; label: string; onClick: () => void }) {
  return (
    <button onClick={onClick}
      className="flex flex-col items-center gap-1.5 group">
      <div className="w-14 h-14 rounded-2xl bg-gray-100 group-hover:bg-gray-200 transition-colors flex items-center justify-center text-2xl">
        {emoji}
      </div>
      <span className="text-gray-600 text-[10px] font-medium">{label}</span>
    </button>
  );
}

// ── Hint clavier ──────────────────────────────────────────────────────────────

function KeyboardHint() {
  const [visible, setVisible] = useState(true);
  useEffect(() => {
    const t = setTimeout(() => setVisible(false), 3000);
    return () => clearTimeout(t);
  }, []);
  if (!visible) return null;
  return (
    <div className="absolute bottom-36 left-6 flex flex-col items-start gap-1 pointer-events-none animate-pulse">
      <div className="flex gap-3 text-white/50 text-[10px]">
        <span>← → photos</span>
        <span>·</span>
        <span>↑ ↓ ou molette</span>
      </div>
    </div>
  );
}
