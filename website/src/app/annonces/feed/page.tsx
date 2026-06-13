'use client';

import { useEffect, useState, useCallback, useRef } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { collection, query, where, getDocs, addDoc, serverTimestamp } from 'firebase/firestore';
import { httpsCallable } from 'firebase/functions';
import { db, functions } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

// ── Types ──────────────────────────────────────────────────────────────────────

interface RawBebe {
  nom?: string;
  sexe?: string;
  couleur?: string;
  prix?: number;
  statut?: string;
  photos?: string[];
  description?: string;
  pedigree?: boolean;
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
  description?: string;
  registre_type?: string;
  date_naissance?: string;
  date_naissance_animal?: string;
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
  dateNaissance?: string;
  pedigree?: boolean;
  registreType?: string;
}

function especeLabel(espece: string): string {
  const map: Record<string, string> = {
    chien: '🐕 Chien', chat: '🐈 Chat', lapin: '🐇 Lapin',
    oiseau: '🐦 Oiseau', reptile: '🦎 Reptile', cheval: '🐴 Cheval',
    ane: '🫏 Âne', ovin: '🐑 Ovin', caprin: '🐐 Caprin',
    porcin: '🐷 Porcin', nac: '🐾 NAC', poule: '🐓 Poule',
    canari: '🐦 Canari', perroquet: '🦜 Perroquet', furet: '🦡 Furet',
  };
  return map[espece.toLowerCase()] ?? `🐾 ${espece}`;
}

function pedigreeLabel(registreType?: string): string | null {
  if (!registreType || registreType.startsWith('Non ')) return null;
  return registreType;
}

function ageLabel(dateStr?: string): string | null {
  if (!dateStr) return null;
  const days = Math.floor((Date.now() - new Date(dateStr).getTime()) / 86400000);
  if (days < 0) return null;
  if (days < 91) {
    const w = Math.floor(days / 7);
    return w <= 1 ? '1 semaine' : `${w} semaines`;
  }
  const m = Math.floor(days / 30.44);
  if (m >= 12) {
    const y = Math.floor(days / 365.25);
    return y <= 1 ? '1 an' : `${y} ans`;
  }
  return m <= 1 ? '1 mois' : `${m} mois`;
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
            dateNaissance: a.date_naissance,
            pedigree: b.pedigree ?? false,
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
        description: a.description,
        ville: a.ville_eleveur, nomEleveur: a.nom_eleveur,
        uidEleveur: a.uid_eleveur, isSaillie,
        dateNaissance: a.date_naissance_animal,
        registreType: a.registre_type,
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
  const activeProfileId = useActiveProfile();
  const [profileType, setProfileType] = useState('particulier');

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

  const [step, setStep] = useState<'filters' | 'feed'>('filters');
  const [filtreEspece, setFiltreEspece] = useState('tous');
  const [filtreType, setFiltreType] = useState('tous');

  const pendingIndex = useRef<number | null>(null);
  const pendingJump  = useRef<{ annonceId: string; bebeIndex: number | null } | null>(null);

  const [items, setItems] = useState<FeedItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [itemIndex, setItemIndex] = useState(0);
  const [photoIndex, setPhotoIndex] = useState(0);

  const [likedKeys, setLikedKeys] = useState<Set<string>>(new Set());
  const [likeAnim, setLikeAnim] = useState(false);
  const [favoritedKeys, setFavoritedKeys] = useState<Set<string>>(new Set());
  const [favAnim, setFavAnim] = useState(false);
  const [likeCounts, setLikeCounts] = useState<Record<string, number>>({});
  const [favoriCounts, setFavoriCounts] = useState<Record<string, number>>({});

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
      .select('id, titre, espece, race, type, type_vente, photos, animaux_portee, prix, saillie_prix, prix_min_portee, prix_max_portee, ville_eleveur, sexe, nom_eleveur, uid_eleveur, description, registre_type, date_naissance, date_naissance_animal')
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
    let targetIndex = pendingIndex.current ?? 0;
    pendingIndex.current = null;
    if (pendingJump.current) {
      const pj = pendingJump.current;
      pendingJump.current = null;
      const found = feed.findIndex(f => f.annonceId === pj.annonceId && f.bebeIndex === pj.bebeIndex);
      if (found !== -1) targetIndex = found;
    }
    setItemIndex(Math.min(targetIndex, Math.max(feed.length - 1, 0)));
    setPhotoIndex(0);

    if (user) {
      const pt = profileType || 'particulier';
      const [{ data: likes }, { data: favs }] = await Promise.all([
        supabase.from('likes').select('annonce_id, bebe_index').eq('user_uid', user.uid).or(`profile_type.eq.${pt},profile_type.is.null`),
        supabase.from('favoris').select('annonce_id, bebe_index').eq('user_uid', user.uid).or(`profile_type.eq.${pt},profile_type.is.null`),
      ]);
      if (likes) setLikedKeys(new Set(likes.map((l) => `${l.annonce_id}_${l.bebe_index ?? 'null'}`)));
      if (favs) setFavoritedKeys(new Set(favs.map((f) => `${f.annonce_id}_${f.bebe_index ?? 'null'}`)));
    }

    // Compteurs globaux (tous utilisateurs)
    const annonceIds = [...new Set(feed.map((f) => f.annonceId))];
    if (annonceIds.length > 0) {
      const [{ data: allLikes }, { data: allFavs }] = await Promise.all([
        supabase.from('likes').select('annonce_id, bebe_index').in('annonce_id', annonceIds),
        supabase.from('favoris').select('annonce_id, bebe_index').in('annonce_id', annonceIds),
      ]);
      const lc: Record<string, number> = {};
      for (const l of allLikes ?? []) {
        const k = `${l.annonce_id}_${l.bebe_index ?? 'null'}`;
        lc[k] = (lc[k] ?? 0) + 1;
      }
      setLikeCounts(lc);
      const fc: Record<string, number> = {};
      for (const f of allFavs ?? []) {
        const k = `${f.annonce_id}_${f.bebe_index ?? 'null'}`;
        fc[k] = (fc[k] ?? 0) + 1;
      }
      setFavoriCounts(fc);
    }

    setLoading(false);
    setStep('feed');
  }, [filtreEspece, filtreType, user]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Restaurer depuis messages ────────────────────────────────────────────────

  useEffect(() => {
    const jump = sessionStorage.getItem('feedJump');
    if (jump) {
      sessionStorage.removeItem('feedJump');
      const j = JSON.parse(jump) as { annonceId: string; bebeIndex: number | null; espece?: string };
      pendingJump.current = { annonceId: j.annonceId, bebeIndex: j.bebeIndex };
      const espece = j.espece && j.espece !== 'tous' ? j.espece : 'tous';
      setFiltreEspece(espece);
      loadFeed(espece, 'tous');
      return;
    }
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
    setLikeCounts((prev) => ({ ...prev, [key]: Math.max(0, (prev[key] ?? 0) + (isLiked ? -1 : 1)) }));
    if (!isLiked) { setLikeAnim(true); setTimeout(() => setLikeAnim(false), 600); }
    if (isLiked) {
      const q = supabase.from('likes').delete().eq('user_uid', user!.uid).eq('annonce_id', item.annonceId);
      item.bebeIndex !== null ? await q.eq('bebe_index', item.bebeIndex) : await q.is('bebe_index', null);
    } else {
      await supabase.from('likes').upsert({ user_uid: user!.uid, annonce_id: item.annonceId, bebe_index: item.bebeIndex, profile_type: profileType });
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
        // Push notification via Firebase Cloud Functions (même infra que les alertes perdus)
        httpsCallable(functions, 'sendLikeNotification')({
          receiverUid: item.uidEleveur,
          annonceId: item.annonceId,
          bebeIndex: item.bebeIndex,
          nomAnimal: item.nom,
          senderName: likerName,
        }).catch(() => {});
      }
    }
  }

  // ── Favori ──────────────────────────────────────────────────────────────────

  async function toggleFavorite(item: FeedItem) {
    if (requireLogin('sauvegarder')) return;
    const key = `${item.annonceId}_${item.bebeIndex ?? 'null'}`;
    const isFav = favoritedKeys.has(key);
    setFavoritedKeys((prev) => { const n = new Set(prev); isFav ? n.delete(key) : n.add(key); return n; });
    setFavoriCounts((prev) => ({ ...prev, [key]: Math.max(0, (prev[key] ?? 0) + (isFav ? -1 : 1)) }));
    if (!isFav) { setFavAnim(true); setTimeout(() => setFavAnim(false), 600); }
    if (isFav) {
      const q = supabase.from('favoris').delete().eq('user_uid', user!.uid).eq('annonce_id', item.annonceId);
      item.bebeIndex !== null ? await q.eq('bebe_index', item.bebeIndex) : await q.is('bebe_index', null);
    } else {
      await supabase.from('favoris').upsert({ user_uid: user!.uid, annonce_id: item.annonceId, bebe_index: item.bebeIndex, profile_type: profileType });
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
  const likeCount = likeCounts[likeKey] ?? 0;
  const favoriCount = favoriCounts[likeKey] ?? 0;
  const currentPhoto = item.photos[photoIndex] ?? item.photos[0];

  function fmtCount(n: number) {
    if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
    if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
    return `${n}`;
  }

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

        {/* Dégradé haut */}
        <div className="absolute top-0 left-0 right-0 h-40 bg-gradient-to-b from-black/70 to-transparent pointer-events-none z-10" />
        {/* Dégradé bas */}
        <div className="absolute bottom-0 left-0 right-0 h-72 bg-gradient-to-t from-black/85 to-transparent pointer-events-none z-10" />

        {/* ── Header éleveur ── */}
        <div className="absolute top-0 left-0 right-0 bg-black/55 z-20 pointer-events-auto">
          <div className="flex items-center gap-2.5 px-3 py-3">
            <button onClick={() => setStep('filters')}
              className="w-10 h-10 rounded-full bg-white/10 text-white flex items-center justify-center flex-shrink-0 hover:bg-white/20 transition-colors">
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M6 18L18 6M6 6l12 12"/>
              </svg>
            </button>
            {item.uidEleveur ? (
              <Link href={`/elevages/${item.uidEleveur}`} onClick={(e) => e.stopPropagation()}
                className="w-10 h-10 rounded-full border-2 border-white/70 overflow-hidden flex-shrink-0">
                {item.photoEleveur ? (
                  <Image src={item.photoEleveur} alt={item.nomEleveur ?? ''} width={40} height={40} className="object-cover w-full h-full" />
                ) : (
                  <div className="w-full h-full bg-[#0C5C6C] flex items-center justify-center text-sm">🏡</div>
                )}
              </Link>
            ) : (
              <div className="w-10 h-10 rounded-full border-2 border-white/70 bg-[#0C5C6C] flex items-center justify-center text-sm flex-shrink-0">🏡</div>
            )}
            <div className="flex-1 min-w-0">
              <p className="text-white font-bold text-sm leading-tight truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
                {item.nomEleveur || 'Élevage'}
              </p>
              <p className="text-white/65 text-xs leading-tight truncate">{item.nom}</p>
            </div>
            <span className="text-white/50 text-xs flex-shrink-0 mr-1">{itemIndex + 1} / {items.length}</span>
            <button className="w-9 h-9 rounded-full bg-white/10 text-white flex items-center justify-center hover:bg-white/20 transition-colors">
              <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                <circle cx="12" cy="5" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="12" cy="19" r="1.5"/>
              </svg>
            </button>
          </div>
        </div>

        {/* ── Dots photos (sous le header) ── */}
        {item.photos.length > 1 && (
          <div className="absolute top-[68px] left-0 right-0 flex justify-center gap-1.5 z-20 pointer-events-none">
            {item.photos.map((_, pi) => (
              <div key={pi} className={`rounded-full shadow transition-all duration-220 ${pi === photoIndex ? 'w-2.5 h-2.5 bg-white' : 'w-2 h-2 bg-white/40'}`} />
            ))}
          </div>
        )}

        {/* ── Colonne d'actions droite ── */}
        <div className="absolute right-3 top-1/2 -translate-y-[60%] flex flex-col items-center gap-4 z-20 pointer-events-auto">

          {/* Like */}
          <button onClick={(e) => { e.stopPropagation(); toggleLike(item); }}
            className="flex flex-col items-center gap-0.5">
            <div className={`w-11 h-11 rounded-full backdrop-blur-sm flex items-center justify-center transition-all duration-200 ${likeAnim ? 'scale-125' : 'hover:scale-110 active:scale-95'} ${isLiked ? 'bg-red-500/30' : 'bg-black/40'}`}>
              <span className={`text-xl ${isLiked ? 'drop-shadow-[0_0_8px_rgba(239,68,68,0.9)]' : ''}`}>
                {isLiked ? '❤️' : '🤍'}
              </span>
            </div>
            {likeCount > 0 && (
              <span className="text-white text-[11px] font-bold" style={{ textShadow: '0 1px 4px rgba(0,0,0,0.6)' }}>
                {fmtCount(likeCount)}
              </span>
            )}
          </button>

          {/* Favoris */}
          <button onClick={(e) => { e.stopPropagation(); toggleFavorite(item); }}
            className="flex flex-col items-center gap-0.5">
            <div className={`w-11 h-11 rounded-full backdrop-blur-sm flex items-center justify-center transition-all duration-200 ${favAnim ? 'scale-125' : 'hover:scale-110 active:scale-95'} ${isFavorited ? 'bg-yellow-500/30' : 'bg-black/40'}`}>
              <span className="text-xl">{isFavorited ? '🔖' : '🏷️'}</span>
            </div>
            {favoriCount > 0 && (
              <span className="text-white text-[11px] font-bold" style={{ textShadow: '0 1px 4px rgba(0,0,0,0.6)' }}>
                {fmtCount(favoriCount)}
              </span>
            )}
          </button>

          {/* Message */}
          <button onClick={(e) => { e.stopPropagation(); openMessage(item); }} disabled={openingMessage}>
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
          <button onClick={(e) => { e.stopPropagation(); handleShare(item); }}>
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

        {/* ── Bottom card glassmorphism ── */}
        <div className="absolute bottom-0 left-0 right-0 pr-16 z-20 pointer-events-auto backdrop-blur-[14px] bg-black/42 rounded-t-[28px]">
          <div className="px-5 pt-4 pb-6">

            {/* Badges espèce / saillie / race / pedigree / âge */}
            <div className="flex flex-wrap gap-1.5 mb-2">
              {item.espece && (
                <span className="text-white text-[11px] font-bold px-2.5 py-0.5 rounded-full bg-white/15">
                  {especeLabel(item.espece)}
                </span>
              )}
              {item.isSaillie && (
                <span className="text-white text-[11px] font-bold px-2.5 py-0.5 rounded-full bg-purple-500">
                  💜 Saillie
                </span>
              )}
              {item.race && (
                <span className="text-white/90 text-[11px] font-semibold px-2.5 py-0.5 rounded-full bg-white/10 capitalize">
                  {item.race}
                </span>
              )}
              {(item.pedigree || pedigreeLabel(item.registreType)) && (
                <span className="text-white text-[11px] font-bold px-2.5 py-0.5 rounded-full bg-amber-500/80">
                  🏅 {item.pedigree ? 'Pedigree' : pedigreeLabel(item.registreType)}
                </span>
              )}
              {ageLabel(item.dateNaissance) && (
                <span className="text-white/80 text-[11px] font-semibold px-2.5 py-0.5 rounded-full bg-white/10">
                  🎂 {ageLabel(item.dateNaissance)}
                </span>
              )}
            </div>

            {/* Nom + sexe + prix */}
            <div className="flex items-end justify-between gap-3 mb-1">
              <div className="flex items-center gap-2 min-w-0">
                {item.sexe && (
                  <span className="text-white text-xl font-bold leading-none flex-shrink-0">
                    {item.sexe === 'male' ? '♂' : '♀'}
                  </span>
                )}
                <h2 className="text-white font-bold text-xl leading-tight truncate" style={{ fontFamily: 'Galey, sans-serif', textShadow: '0 1px 6px rgba(0,0,0,0.7)' }}>
                  {item.nom}
                </h2>
              </div>
              {item.prix != null && (
                <span className="text-white font-bold text-lg flex-shrink-0" style={{ textShadow: '0 1px 6px rgba(0,0,0,0.7)' }}>
                  {item.prix} €
                </span>
              )}
            </div>

            {/* Ville */}
            {item.ville && <p className="text-white/60 text-xs truncate mb-1">📍 {item.ville}</p>}

            {/* Description */}
            {item.description && (
              <div className="mb-3">
                <div className={`overflow-hidden transition-all duration-300 ${descExpanded ? 'max-h-36' : 'max-h-9'}`}>
                  <p className="text-white/85 text-sm leading-snug">{item.description}</p>
                </div>
                <button onClick={() => setDescExpanded(v => !v)}
                  className="text-white/65 text-xs font-bold hover:text-white transition-colors mt-0.5">
                  {descExpanded ? '↑ Moins' : '… Plus'}
                </button>
              </div>
            )}

            {/* Boutons action */}
            <div className="flex gap-2 mt-2">
              <Link href={`/annonces/${item.annonceId}`}
                className="flex-1 text-center text-white text-xs font-semibold border border-white/30 bg-white/10 backdrop-blur-sm px-3 py-2 rounded-2xl hover:bg-white/20 transition-colors"
                style={{ fontFamily: 'Galey, sans-serif' }}>
                Voir l&apos;annonce →
              </Link>
              <Link href={`/annonces?espece=${item.espece ?? 'tous'}&race=${encodeURIComponent(item.race ?? '')}`}
                className="flex-1 text-center text-white text-xs font-semibold border border-white/30 bg-white/10 backdrop-blur-sm px-3 py-2 rounded-2xl hover:bg-white/20 transition-colors"
                style={{ fontFamily: 'Galey, sans-serif' }}>
                Similaires
              </Link>
            </div>
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
