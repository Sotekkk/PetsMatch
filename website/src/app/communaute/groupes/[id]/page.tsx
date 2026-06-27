'use client';

import { useState, useEffect, useCallback } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';

const TYPE_LABELS: Record<string, string> = { race: 'Race', region: 'Région', loisir: 'Loisir', autre: 'Autre' };

// ── Modération ────────────────────────────────────────────────────────────────
const GROS_MOTS = ['merde', 'putain', 'connard', 'connasse', 'salope', 'pute', 'enculé', 'enculer', 'fdp', 'nique', 'niquer', 'ntm', 'bâtard', 'batard', 'chier', 'bite ', 'branleur', 'branler'];
const COMMERCE_KW = ['prix :', 'prix:', 'tarif ', 'tarif:', '€', ' euro', 'paypal', 'virement', 'paiement', 'vend ', 'vends ', 'achète ', 'a vendre', 'à vendre', 'achat', 'solde', 'livraison gratuite'];
const ADOPTION_KW = ['adoption', 'adopter', 'à donner', 'a donner', 'cherche preneur', 'cession', 'céder', 'ceder'];
const TRANSACTION_KW = ['contrat de vente', 'contrat de cession', 'bon de commande'];

function moderateContent(content: string, isPro: boolean): string | null {
  const low = content.toLowerCase();
  for (const w of GROS_MOTS) if (low.includes(w)) return 'Votre message contient un langage inapproprié.';
  if (!isPro) {
    for (const kw of COMMERCE_KW) if (low.includes(kw)) return 'Prix et transactions non autorisés dans les groupes communautaires. Seuls les professionnels peuvent publier des tarifs.';
    for (const kw of ADOPTION_KW) if (low.includes(kw)) return 'Les propositions d\'adoption ou de cession ne sont pas autorisées ici.';
    for (const kw of TRANSACTION_KW) if (low.includes(kw)) return 'Les transactions commerciales ne sont pas autorisées dans les groupes communautaires.';
  }
  return null;
}

interface UserProfile { uid: string; firstname?: string; lastname?: string; profile_picture_url?: string; is_elevage?: boolean; name_elevage?: string; is_pro?: boolean; }

function profileName(p: UserProfile | undefined, isMe?: boolean): string {
  if (isMe) return 'Moi';
  if (!p) return 'Membre';
  if (p.is_elevage && p.name_elevage) return p.name_elevage;
  const n = `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim();
  return n || 'Membre';
}

function ProfileAvatar({ profile, size = 36 }: { profile?: UserProfile; size?: number }) {
  const photo = profile?.profile_picture_url;
  return photo
    ? /* eslint-disable-next-line @next/next/no-img-element */ <img src={photo} alt="" style={{ width: size, height: size }} className="rounded-full object-cover flex-shrink-0" />
    : <div style={{ width: size, height: size }} className="rounded-full bg-[#E0F7FA] flex items-center justify-center flex-shrink-0"><span style={{ fontSize: size * 0.5 }}>👤</span></div>;
}

interface Groupe {
  id: string; nom: string; description: string; type: string;
  prive: boolean; createur_uid: string; regles: string[];
  avatar_url?: string; photo_cover_url?: string;
}
interface Post {
  id: string; groupe_id: string; auteur_uid: string; contenu: string;
  like_count: number; comment_count: number; epingle: boolean; created_at: string;
  image_url?: string;
}
interface Commentaire {
  id: string; post_id: string; auteur_uid: string; contenu: string; created_at: string;
  like_count?: number; image_url?: string;
}
interface Membership { role: string; statut: string; }

function fmtDate(iso: string) {
  try {
    const dt = new Date(iso);
    const now = new Date();
    const diff = Math.floor((now.getTime() - dt.getTime()) / 1000);
    if (diff < 60) return 'À l\'instant';
    if (diff < 3600) return `Il y a ${Math.floor(diff / 60)} min`;
    if (diff < 86400) return `Il y a ${Math.floor(diff / 3600)}h`;
    if (diff < 604800) return `Il y a ${Math.floor(diff / 86400)}j`;
    return dt.toLocaleDateString('fr-FR');
  } catch { return ''; }
}

export default function GroupeDetailPage() {
  const { id } = useParams<{ id: string }>();
  const { user } = useAuth();
  const router = useRouter();

  const [groupe, setGroupe] = useState<Groupe | null>(null);
  const [posts, setPosts] = useState<Post[]>([]);
  const [membership, setMembership] = useState<Membership | null>(null);
  const [myLikes, setMyLikes] = useState<Set<string>>(new Set());
  const [membresCount, setMembresCount] = useState(0);
  const [friendsCount, setFriendsCount] = useState(0);
  const [loading, setLoading] = useState(true);
  const [newPost, setNewPost] = useState('');
  const [posting, setPosting] = useState(false);

  // Comments state
  const [openCommentPost, setOpenCommentPost] = useState<Post | null>(null);
  const [comments, setComments] = useState<Commentaire[]>([]);
  const [newComment, setNewComment] = useState('');
  const [commenting, setCommenting] = useState(false);
  const [loadingComments, setLoadingComments] = useState(false);

  // User profiles cache
  const [userProfiles, setUserProfiles] = useState<Record<string, UserProfile>>({});
  const [currentUserIsPro, setCurrentUserIsPro] = useState(false);

  // Likes modal
  const [likesModal, setLikesModal] = useState<string | null>(null); // postId
  const [likers, setLikers] = useState<UserProfile[]>([]);
  const [loadingLikers, setLoadingLikers] = useState(false);

  // Moderation error
  const [moderationError, setModerationError] = useState<string | null>(null);

  // Comment likes + image
  const [myCommentLikes, setMyCommentLikes] = useState<Set<string>>(new Set());
  const [commentImage, setCommentImage] = useState<File | null>(null);
  const [commentImagePreview, setCommentImagePreview] = useState<string | null>(null);
  const [uploadingCommentImg, setUploadingCommentImg] = useState(false);

  // Post image state
  const [postImage, setPostImage] = useState<File | null>(null);
  const [postImagePreview, setPostImagePreview] = useState<string | null>(null);
  const [uploadingImg, setUploadingImg] = useState(false);

  // Admin state
  const [showAdmin, setShowAdmin] = useState(false);
  const [adminTab, setAdminTab] = useState<'membres' | 'demandes' | 'regles' | 'photos'>('membres');
  const [membres, setMembres] = useState<{ user_uid: string; role: string; statut: string }[]>([]);
  const [editRegles, setEditRegles] = useState<string[]>([]);
  const [newRegle, setNewRegle] = useState('');
  const [savingRegles, setSavingRegles] = useState(false);
  const [avatarUploading, setAvatarUploading] = useState(false);
  const [bannerUploading, setBannerUploading] = useState(false);

  const isMember = membership?.statut === 'active';
  const isAdmin = membership?.role === 'admin' && isMember;
  const isPending = membership?.statut === 'pending';

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const { data: g } = await supabase.from('groupes').select('*').eq('id', id).single();
      if (!g) { router.replace('/communaute/groupes'); return; }
      setGroupe(g as Groupe);
      setEditRegles((g.regles as string[]) ?? []);

      const { data: membresData } = await supabase
        .from('groupes_membres').select('user_uid').eq('groupe_id', id).eq('statut', 'active');
      setMembresCount((membresData ?? []).length);
      const membresUids = (membresData ?? []).map((m: { user_uid: string }) => m.user_uid);

      let mem: Membership | null = null;
      if (user?.uid) {
        const { data: myMem } = await supabase.from('groupes_membres').select('role, statut')
          .eq('groupe_id', id).eq('user_uid', user.uid).maybeSingle();
        mem = myMem as Membership | null;

        // Amis dans le groupe
        const { data: friends } = await supabase.from('petfriends').select('uid_demandeur, uid_recepteur')
          .or(`uid_demandeur.eq.${user.uid},uid_recepteur.eq.${user.uid}`).eq('statut', 'accepte');
        const fUids = (friends ?? []).map((f: { uid_demandeur: string; uid_recepteur: string }) =>
          f.uid_demandeur === user.uid ? f.uid_recepteur : f.uid_demandeur
        );
        setFriendsCount(fUids.filter((u: string) => membresUids.includes(u)).length);
      }
      setMembership(mem);

      const { data: postsData } = await supabase.from('groupe_posts').select('*')
        .eq('groupe_id', id).order('epingle', { ascending: false }).order('created_at', { ascending: false }).limit(30);
      setPosts((postsData ?? []) as Post[]);

      if (user?.uid && postsData && postsData.length > 0) {
        const pids = postsData.map((p: Post) => p.id);
        const { data: likes } = await supabase.from('groupe_post_likes').select('post_id')
          .eq('user_uid', user.uid).in('post_id', pids);
        setMyLikes(new Set((likes ?? []).map((l: { post_id: string }) => l.post_id)));
      }

      // Load user profiles for post authors + current user
      const authorUids = [...new Set([
        ...(postsData ?? []).map((p: Post) => p.auteur_uid),
        ...(user?.uid ? [user.uid] : []),
      ])];
      if (authorUids.length > 0) {
        const { data: profiles } = await supabase
          .from('users')
          .select('uid, firstname, lastname, profile_picture_url, is_elevage, is_pro, name_elevage')
          .in('uid', authorUids);
        const map: Record<string, UserProfile> = {};
        for (const p of (profiles ?? [])) map[p.uid] = p;
        setUserProfiles(map);
        if (user?.uid && map[user.uid]) {
          setCurrentUserIsPro(map[user.uid].is_elevage === true || map[user.uid].is_pro === true);
        }
      }
    } finally {
      setLoading(false);
    }
  }, [id, user?.uid, router]);

  useEffect(() => { load(); }, [load]);

  async function joinOrLeave() {
    if (!user?.uid || !groupe) return;
    if (isMember || isPending) {
      await supabase.from('groupes_membres').delete().eq('groupe_id', id).eq('user_uid', user.uid);
      setMembership(null);
      setMembresCount(c => c - (isMember ? 1 : 0));
    } else {
      const statut = groupe.prive ? 'pending' : 'active';
      await supabase.from('groupes_membres').insert({
        groupe_id: id, user_uid: user.uid, role: 'membre', statut,
        rejoint_at: new Date().toISOString(),
      });
      setMembership({ role: 'membre', statut });
      if (!groupe.prive) setMembresCount(c => c + 1);
    }
  }

  async function toggleLike(postId: string) {
    if (!user?.uid || !isMember) return;
    const liked = myLikes.has(postId);
    const delta = liked ? -1 : 1;
    setMyLikes(prev => {
      const s = new Set(prev);
      liked ? s.delete(postId) : s.add(postId);
      return s;
    });
    setPosts(prev => prev.map(p => p.id === postId ? { ...p, like_count: p.like_count + delta } : p));
    if (liked) {
      await supabase.from('groupe_post_likes').delete().eq('post_id', postId).eq('user_uid', user.uid);
    } else {
      await supabase.from('groupe_post_likes').insert({ post_id: postId, user_uid: user.uid });
    }
    await supabase.from('groupe_posts').update({ like_count: posts.find(p => p.id === postId)!.like_count + delta }).eq('id', postId);
  }

  async function uploadToStorage(file: File, path: string): Promise<string> {
    const { error } = await supabase.storage.from('media').upload(path, file, {
      contentType: 'image/jpeg', upsert: true,
    });
    if (error) throw error;
    return supabase.storage.from('media').getPublicUrl(path).data.publicUrl;
  }

  function selectPostImage(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setPostImage(file);
    setPostImagePreview(URL.createObjectURL(file));
  }

  async function publishPost() {
    if (!user?.uid || (!newPost.trim() && !postImage) || !isMember) return;
    setModerationError(null);
    if (newPost.trim()) {
      const err = moderateContent(newPost.trim(), currentUserIsPro);
      if (err) { setModerationError(err); return; }
    }
    setPosting(true);
    setUploadingImg(!!postImage);
    try {
      let imageUrl: string | undefined;
      if (postImage) {
        const path = `groupes/posts/${id}/${user.uid}_${Date.now()}.jpg`;
        imageUrl = await uploadToStorage(postImage, path);
        setUploadingImg(false);
      }
      const { data } = await supabase.from('groupe_posts').insert({
        groupe_id: id, auteur_uid: user.uid, contenu: newPost.trim(),
        image_url: imageUrl ?? null,
        created_at: new Date().toISOString(),
      }).select().single();
      if (data) {
        setPosts(prev => [data as Post, ...prev]);
        if (user.uid && !userProfiles[user.uid]) {
          const { data: me } = await supabase.from('users')
            .select('uid, firstname, lastname, profile_picture_url, is_elevage, is_pro, name_elevage')
            .eq('uid', user.uid).single();
          if (me) setUserProfiles(prev => ({ ...prev, [user.uid]: me }));
        }
      }
      setNewPost('');
      setPostImage(null);
      setPostImagePreview(null);
    } finally { setPosting(false); setUploadingImg(false); }
  }

  async function openLikesModal(postId: string) {
    setLikesModal(postId);
    setLoadingLikers(true);
    const { data: likesData } = await supabase.from('groupe_post_likes').select('user_uid').eq('post_id', postId);
    const uids = (likesData ?? []).map((l: { user_uid: string }) => l.user_uid);
    if (uids.length === 0) { setLikers([]); setLoadingLikers(false); return; }
    const missing = uids.filter((u: string) => !userProfiles[u]);
    const profiles = { ...userProfiles };
    if (missing.length > 0) {
      const { data: pd } = await supabase.from('users')
        .select('uid, firstname, lastname, profile_picture_url, is_elevage, name_elevage')
        .in('uid', missing);
      for (const p of (pd ?? [])) profiles[p.uid] = p;
      setUserProfiles(profiles);
    }
    setLikers(uids.map((uid: string) => profiles[uid] ?? { uid }));
    setLoadingLikers(false);
  }

  async function togglePin(post: Post) {
    if (!isAdmin) return;
    await supabase.from('groupe_posts').update({ epingle: !post.epingle }).eq('id', post.id);
    setPosts(prev => {
      const updated = prev.map(p => p.id === post.id ? { ...p, epingle: !p.epingle } : p);
      return [...updated].sort((a, b) => (b.epingle ? 1 : 0) - (a.epingle ? 1 : 0));
    });
  }

  async function deletePost(postId: string) {
    const post = posts.find(p => p.id === postId);
    if (!post) return;
    if (post.auteur_uid !== user?.uid && !isAdmin) return;
    await supabase.from('groupe_posts').delete().eq('id', postId);
    setPosts(prev => prev.filter(p => p.id !== postId));
  }

  async function openComments(post: Post) {
    setOpenCommentPost(post);
    setLoadingComments(true);
    const { data } = await supabase.from('groupe_post_commentaires').select('*')
      .eq('post_id', post.id).order('created_at');
    const commentsList = (data ?? []) as Commentaire[];
    setComments(commentsList);
    setCommentImage(null);
    setCommentImagePreview(null);

    // Charger mes likes de commentaires
    if (user?.uid && commentsList.length > 0) {
      const cIds = commentsList.map(c => c.id);
      const { data: clData } = await supabase.from('groupe_commentaire_likes')
        .select('comment_id').eq('user_uid', user.uid).in('comment_id', cIds);
      setMyCommentLikes(new Set((clData ?? []).map((l: { comment_id: string }) => l.comment_id)));
    }

    // Load missing profiles for comment authors
    const missing = [...new Set(commentsList.map(c => c.auteur_uid))].filter(u => !userProfiles[u]);
    if (missing.length > 0) {
      const { data: pd } = await supabase.from('users')
        .select('uid, firstname, lastname, profile_picture_url, is_elevage, name_elevage')
        .in('uid', missing);
      if (pd) {
        const newProfiles: Record<string, UserProfile> = {};
        for (const p of pd) newProfiles[p.uid] = p;
        setUserProfiles(prev => ({ ...prev, ...newProfiles }));
      }
    }
    setLoadingComments(false);
  }

  async function toggleCommentLike(commentId: string) {
    if (!user?.uid) return;
    const liked = myCommentLikes.has(commentId);
    setMyCommentLikes(prev => { const s = new Set(prev); liked ? s.delete(commentId) : s.add(commentId); return s; });
    setComments(prev => prev.map(c => c.id === commentId ? { ...c, like_count: (c.like_count ?? 0) + (liked ? -1 : 1) } : c));
    if (liked) {
      await supabase.from('groupe_commentaire_likes').delete().eq('comment_id', commentId).eq('user_uid', user.uid);
    } else {
      await supabase.from('groupe_commentaire_likes').insert({ comment_id: commentId, user_uid: user.uid });
    }
    const updated = comments.find(c => c.id === commentId);
    if (updated) {
      await supabase.from('groupe_post_commentaires')
        .update({ like_count: (updated.like_count ?? 0) + (liked ? -1 : 1) }).eq('id', commentId);
    }
  }

  async function sendComment() {
    if (!user?.uid || (!newComment.trim() && !commentImage) || !openCommentPost) return;
    if (newComment.trim()) {
      const err = moderateContent(newComment.trim(), currentUserIsPro);
      if (err) { alert(err); return; }
    }
    setCommenting(true);
    setUploadingCommentImg(!!commentImage);
    try {
      let imageUrl: string | undefined;
      if (commentImage) {
        const path = `groupes/comments/${openCommentPost.id}/${user.uid}_${Date.now()}.jpg`;
        imageUrl = await uploadToStorage(commentImage, path);
        setUploadingCommentImg(false);
      }
      const { data } = await supabase.from('groupe_post_commentaires').insert({
        post_id: openCommentPost.id, auteur_uid: user.uid, contenu: newComment.trim(),
        image_url: imageUrl ?? null,
        created_at: new Date().toISOString(),
      }).select().single();
      if (data) setComments(prev => [...prev, data as Commentaire]);
      const newCount = comments.length + 1;
      await supabase.from('groupe_posts').update({ comment_count: newCount }).eq('id', openCommentPost.id);
      setPosts(prev => prev.map(p => p.id === openCommentPost.id ? { ...p, comment_count: newCount } : p));
      setNewComment('');
      setCommentImage(null);
      setCommentImagePreview(null);
    } finally { setCommenting(false); setUploadingCommentImg(false); }
  }

  async function loadAdminMembres() {
    const { data } = await supabase.from('groupes_membres').select('user_uid, role, statut')
      .eq('groupe_id', id).order('rejoint_at');
    setMembres((data ?? []) as { user_uid: string; role: string; statut: string }[]);
  }

  async function updateMembre(userUid: string, action: string) {
    switch (action) {
      case 'approve': await supabase.from('groupes_membres').update({ statut: 'active' }).eq('groupe_id', id).eq('user_uid', userUid); break;
      case 'promote': await supabase.from('groupes_membres').update({ role: 'admin' }).eq('groupe_id', id).eq('user_uid', userUid); break;
      case 'demote': await supabase.from('groupes_membres').update({ role: 'membre' }).eq('groupe_id', id).eq('user_uid', userUid); break;
      case 'ban': await supabase.from('groupes_membres').update({ statut: 'banned' }).eq('groupe_id', id).eq('user_uid', userUid); break;
      case 'remove': await supabase.from('groupes_membres').delete().eq('groupe_id', id).eq('user_uid', userUid); break;
    }
    await loadAdminMembres();
  }

  async function saveRegles() {
    setSavingRegles(true);
    await supabase.from('groupes').update({ regles: editRegles }).eq('id', id);
    setGroupe(prev => prev ? { ...prev, regles: editRegles } : null);
    setSavingRegles(false);
  }

  async function handleAvatarUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file || !groupe) return;
    setAvatarUploading(true);
    try {
      const url = await uploadToStorage(file, `groupes/${id}/avatar.jpg`);
      await supabase.from('groupes').update({ avatar_url: url }).eq('id', id);
      setGroupe(prev => prev ? { ...prev, avatar_url: url } : null);
    } finally { setAvatarUploading(false); }
  }

  async function handleBannerUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file || !groupe) return;
    setBannerUploading(true);
    try {
      const url = await uploadToStorage(file, `groupes/${id}/banner.jpg`);
      await supabase.from('groupes').update({ photo_cover_url: url }).eq('id', id);
      setGroupe(prev => prev ? { ...prev, photo_cover_url: url } : null);
    } finally { setBannerUploading(false); }
  }

  if (loading) return (
    <div className="flex justify-center items-center py-40">
      <div className="w-8 h-8 border-2 border-[#00ACC1] border-t-transparent rounded-full animate-spin" />
    </div>
  );

  if (!groupe) return null;

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Bannière */}
      <div className="relative">
        <div
          className="h-44 bg-[#00ACC1]"
          style={groupe.photo_cover_url ? {
            backgroundImage: `url(${groupe.photo_cover_url})`,
            backgroundSize: 'cover', backgroundPosition: 'center',
          } : {}}
        >
          <div className="absolute inset-0 bg-gradient-to-b from-black/20 to-black/50" />
          <div className="absolute top-4 left-4">
            <button onClick={() => router.back()} className="text-white/80 hover:text-white text-sm flex items-center gap-1 bg-black/20 px-3 py-1.5 rounded-full">
              ← Retour
            </button>
          </div>
          {isAdmin && (
            <div className="absolute top-4 right-4">
              <button
                onClick={() => { setShowAdmin(true); loadAdminMembres(); }}
                className="text-white/80 hover:text-white bg-black/20 p-2 rounded-full"
              >
                ⚙️
              </button>
            </div>
          )}
        </div>
        {/* Avatar du groupe */}
        <div className="max-w-2xl mx-auto px-4">
          <div className="flex items-end gap-4 -mt-10 pb-4">
            <div className="w-20 h-20 rounded-2xl border-4 border-white shadow-lg overflow-hidden bg-[#00ACC1] flex items-center justify-center flex-shrink-0">
              {groupe.avatar_url
                ? <img src={groupe.avatar_url} alt="" className="w-full h-full object-cover" />
                : <span className="text-3xl">{groupe.type === 'race' ? '🐾' : groupe.type === 'region' ? '📍' : groupe.type === 'loisir' ? '🎯' : '💬'}</span>
              }
            </div>
            <div className="flex-1 pb-1">
              <div className="flex items-center gap-2 flex-wrap">
                <h1 className="text-xl font-bold text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>{groupe.nom}</h1>
                {groupe.prive && <span className="text-xs bg-gray-100 text-gray-500 px-2 py-0.5 rounded-full">🔒 Privé</span>}
              </div>
              <span className="inline-block text-xs bg-[#E0F7FA] text-[#00ACC1] px-2 py-0.5 rounded-full mt-1 font-semibold">
                {TYPE_LABELS[groupe.type] ?? groupe.type}
              </span>
              <p className="text-gray-500 text-sm mt-1">
                {membresCount} membre{membresCount > 1 ? 's' : ''}
                {friendsCount > 0 && <span className="text-[#00ACC1] font-semibold"> · {friendsCount} ami{friendsCount > 1 ? 's' : ''}</span>}
              </p>
            </div>
          </div>
          {groupe.description && (
            <p className="text-gray-600 text-sm mt-2 pb-3">{groupe.description}</p>
          )}
        </div>
      </div>

      <div className="max-w-2xl mx-auto px-4 py-6">
        {/* Bouton rejoindre */}
        {user && (
          <button
            onClick={joinOrLeave}
            className={`w-full py-3 rounded-xl font-bold text-sm mb-5 transition-colors ${
              isMember
                ? 'bg-[#00ACC1] text-white'
                : isPending
                ? 'bg-orange-50 text-orange-600 border border-orange-200'
                : 'bg-[#E0F7FA] text-[#00ACC1] border border-[#00ACC1]'
            }`}
            style={{ fontFamily: 'Galey, sans-serif' }}
          >
            {isAdmin ? '⚙️ Admin' : isMember ? 'Membre ✓ — Quitter' : isPending ? 'Demande en attente…' : groupe.prive ? 'Demander à rejoindre' : 'Rejoindre le groupe'}
          </button>
        )}

        {/* Règles */}
        {groupe.regles && groupe.regles.length > 0 && (
          <details className="bg-white rounded-2xl shadow-sm border border-gray-100 mb-5 overflow-hidden">
            <summary className="px-5 py-4 cursor-pointer font-bold text-sm text-[#1E2025] flex items-center gap-2" style={{ fontFamily: 'Galey, sans-serif' }}>
              📋 Règles du groupe
            </summary>
            <div className="px-5 pb-4 flex flex-col gap-2">
              {groupe.regles.map((r, i) => (
                <div key={i} className="flex items-start gap-3">
                  <span className="w-6 h-6 rounded-full bg-[#00ACC1] text-white text-xs flex items-center justify-center font-bold flex-shrink-0 mt-0.5">{i + 1}</span>
                  <p className="text-sm text-gray-700" style={{ fontFamily: 'Galey, sans-serif' }}>{r}</p>
                </div>
              ))}
            </div>
          </details>
        )}

        {/* Créer un post */}
        {isMember && (
          <div className="bg-white rounded-2xl shadow-sm border border-gray-100 mb-5 p-4">
            <textarea
              value={newPost}
              onChange={e => setNewPost(e.target.value)}
              placeholder="Partagez quelque chose avec le groupe…"
              rows={3}
              className="w-full text-sm text-gray-700 resize-none focus:outline-none"
              style={{ fontFamily: 'Galey, sans-serif' }}
            />
            {postImagePreview && (
              <div className="relative mt-2">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={postImagePreview} alt="" className="w-full max-h-48 object-cover rounded-xl" />
                <button
                  onClick={() => { setPostImage(null); setPostImagePreview(null); }}
                  className="absolute top-2 right-2 w-7 h-7 bg-black/60 text-white rounded-full flex items-center justify-center text-sm hover:bg-black/80"
                >✕</button>
              </div>
            )}
            {moderationError && (
              <p className="text-xs text-red-500 mt-2 px-1" style={{ fontFamily: 'Galey, sans-serif' }}>{moderationError}</p>
            )}
            <div className="flex items-center justify-between mt-3">
              <label className="cursor-pointer flex items-center gap-1.5 text-gray-400 hover:text-[#00ACC1] text-sm transition-colors">
                <span className="text-lg">📷</span>
                <span style={{ fontFamily: 'Galey, sans-serif' }}>Photo</span>
                <input type="file" accept="image/*" className="hidden" onChange={selectPostImage} />
              </label>
              <button
                onClick={publishPost}
                disabled={posting || (!newPost.trim() && !postImage)}
                className="px-4 py-2 bg-[#00ACC1] text-white rounded-xl text-sm font-bold disabled:opacity-50"
                style={{ fontFamily: 'Galey, sans-serif' }}
              >
                {uploadingImg ? '⬆️ Upload…' : posting ? '…' : 'Publier'}
              </button>
            </div>
          </div>
        )}

        {/* Posts */}
        {posts.length === 0 ? (
          <div className="text-center py-16 text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>
            <p className="text-4xl mb-3">📝</p>
            <p>{isMember ? 'Soyez le premier à publier !' : 'Rejoignez le groupe pour voir les publications'}</p>
          </div>
        ) : (
          <div className="flex flex-col gap-4">
            {posts.map(post => {
              const isMe = post.auteur_uid === user?.uid;
              const liked = myLikes.has(post.id);
              const canDelete = isMe || isAdmin;
              const profile = userProfiles[post.auteur_uid];
              const displayName = profileName(profile, isMe);

              return (
                <div key={post.id} className={`bg-white rounded-2xl shadow-sm border overflow-hidden ${post.epingle ? 'border-[#00ACC1]/40' : 'border-gray-100'}`}>
                  <div className="p-4">
                    <div className="flex items-center gap-3 mb-3">
                      <ProfileAvatar profile={profile} size={36} />
                      <div className="flex-1">
                        <p className="text-sm font-bold text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>
                          {displayName}
                        </p>
                        <p className="text-xs text-gray-400">{fmtDate(post.created_at)}</p>
                      </div>
                      {post.epingle && <span className="text-[#00ACC1] text-sm">📌</span>}
                      {(canDelete || isAdmin) && (
                        <div className="relative group">
                          <button className="text-gray-400 hover:text-gray-600 px-2">⋯</button>
                          <div className="absolute right-0 top-6 bg-white rounded-xl shadow-lg border border-gray-100 py-1 z-10 min-w-[140px] hidden group-hover:block">
                            {isAdmin && (
                              <button onClick={() => togglePin(post)} className="w-full text-left px-4 py-2 text-sm hover:bg-gray-50 text-gray-700" style={{ fontFamily: 'Galey, sans-serif' }}>
                                {post.epingle ? '📌 Désépingler' : '📌 Épingler'}
                              </button>
                            )}
                            {canDelete && (
                              <button onClick={() => deletePost(post.id)} className="w-full text-left px-4 py-2 text-sm hover:bg-gray-50 text-red-500" style={{ fontFamily: 'Galey, sans-serif' }}>
                                🗑 Supprimer
                              </button>
                            )}
                          </div>
                        </div>
                      )}
                    </div>
                    {post.contenu && <p className="text-sm text-[#1E2025] leading-relaxed" style={{ fontFamily: 'Galey, sans-serif' }}>{post.contenu}</p>}
                  </div>
                  {/* Photo du post */}
                  {post.image_url && (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      src={post.image_url}
                      alt=""
                      className="w-full max-h-96 object-cover cursor-pointer"
                      onClick={() => window.open(post.image_url, '_blank')}
                    />
                  )}
                  <div className="border-t border-gray-100 flex">
                    <div className="flex-1 flex items-center justify-center">
                      <button
                        onClick={() => toggleLike(post.id)}
                        className={`flex items-center gap-1.5 py-2.5 text-sm transition-colors ${liked ? 'text-red-500' : 'text-gray-500 hover:text-red-400'}`}
                        style={{ fontFamily: 'Galey, sans-serif' }}
                      >
                        {liked ? '❤️' : '🤍'} J&apos;aime
                      </button>
                      {post.like_count > 0 && (
                        <button
                          onClick={() => openLikesModal(post.id)}
                          className={`ml-1 text-sm font-semibold underline-offset-2 hover:underline transition-colors ${liked ? 'text-red-400' : 'text-gray-400 hover:text-gray-600'}`}
                          style={{ fontFamily: 'Galey, sans-serif' }}
                        >
                          {post.like_count}
                        </button>
                      )}
                    </div>
                    <div className="w-px bg-gray-100" />
                    <button
                      onClick={() => openComments(post)}
                      className="flex-1 flex items-center justify-center gap-2 py-2.5 text-sm text-gray-500 hover:text-[#00ACC1] transition-colors"
                      style={{ fontFamily: 'Galey, sans-serif' }}
                    >
                      💬 {post.comment_count > 0 ? post.comment_count : 'Commenter'}
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Modal qui a liké */}
      {likesModal && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-end justify-center" onClick={() => setLikesModal(null)}>
          <div className="bg-white rounded-t-2xl w-full max-w-lg max-h-[60vh] flex flex-col" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
              <h3 className="font-bold text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>❤️ Personnes qui aiment</h3>
              <button onClick={() => setLikesModal(null)} className="text-gray-400 hover:text-gray-600">✕</button>
            </div>
            <div className="flex-1 overflow-y-auto p-4">
              {loadingLikers ? (
                <div className="flex justify-center py-8"><div className="w-6 h-6 border-2 border-[#00ACC1] border-t-transparent rounded-full animate-spin" /></div>
              ) : likers.length === 0 ? (
                <p className="text-center text-gray-400 py-8" style={{ fontFamily: 'Galey, sans-serif' }}>Personne n&apos;a encore aimé</p>
              ) : (
                <div className="flex flex-col gap-3">
                  {likers.map((liker, i) => (
                    <div key={liker.uid ?? i} className="flex items-center gap-3">
                      <ProfileAvatar profile={liker} size={40} />
                      <p className="font-semibold text-sm text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>
                        {profileName(liker)}
                      </p>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Modal commentaires */}
      {openCommentPost && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-end justify-center">
          <div className="bg-white rounded-t-2xl w-full max-w-lg h-[75vh] flex flex-col">
            <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
              <h3 className="font-bold text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>Commentaires</h3>
              <button onClick={() => { setOpenCommentPost(null); setComments([]); }} className="text-gray-400 hover:text-gray-600">✕</button>
            </div>
            <div className="flex-1 overflow-y-auto p-4">
              {loadingComments ? (
                <div className="flex justify-center py-8"><div className="w-6 h-6 border-2 border-[#00ACC1] border-t-transparent rounded-full animate-spin" /></div>
              ) : comments.length === 0 ? (
                <p className="text-center text-gray-400 py-8" style={{ fontFamily: 'Galey, sans-serif' }}>Aucun commentaire</p>
              ) : (
                <div className="flex flex-col gap-2">
                  {comments.map(c => {
                    const isMe = c.auteur_uid === user?.uid;
                    const cProfile = userProfiles[c.auteur_uid];
                    const cName = profileName(cProfile, isMe);
                    const cLiked = myCommentLikes.has(c.id);
                    const cLikeCount = c.like_count ?? 0;
                    return (
                      <div key={c.id} className={`flex gap-2 ${isMe ? 'flex-row-reverse' : 'flex-row'}`}>
                        {!isMe && <ProfileAvatar profile={cProfile} size={28} />}
                        <div className={`flex flex-col ${isMe ? 'items-end' : 'items-start'} max-w-[72%]`}>
                          {!isMe && (
                            <p className="text-[10px] text-gray-400 mb-0.5 px-1" style={{ fontFamily: 'Galey, sans-serif' }}>{cName}</p>
                          )}
                          {/* Bulle texte */}
                          {c.contenu && (
                            <div className={`px-3 py-2 rounded-2xl text-sm ${isMe ? 'bg-[#E0F7FA] text-[#1E2025] rounded-tr-sm' : 'bg-gray-100 text-[#1E2025] rounded-tl-sm'} ${c.image_url ? 'rounded-b-2xl' : ''}`} style={{ fontFamily: 'Galey, sans-serif' }}>
                              <p>{c.contenu}</p>
                              <p className="text-xs text-gray-400 mt-1">{fmtDate(c.created_at)}</p>
                            </div>
                          )}
                          {/* Photo du commentaire */}
                          {c.image_url && (
                            <div className={c.contenu ? 'mt-1' : ''}>
                              {/* eslint-disable-next-line @next/next/no-img-element */}
                              <img
                                src={c.image_url}
                                alt=""
                                className="max-w-full rounded-2xl cursor-pointer object-cover"
                                style={{ maxHeight: 200 }}
                                onClick={() => window.open(c.image_url, '_blank')}
                              />
                              {!c.contenu && <p className="text-xs text-gray-400 mt-1 px-1">{fmtDate(c.created_at)}</p>}
                            </div>
                          )}
                          {/* Like commentaire */}
                          <button
                            onClick={() => toggleCommentLike(c.id)}
                            className={`flex items-center gap-1 mt-1 text-xs px-1 transition-colors ${cLiked ? 'text-red-400' : 'text-gray-400 hover:text-red-400'}`}
                            style={{ fontFamily: 'Galey, sans-serif' }}
                          >
                            {cLiked ? '❤️' : '🤍'}
                            {cLikeCount > 0 && <span className="font-semibold">{cLikeCount}</span>}
                          </button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
            {isMember && (
              <div className="border-t border-gray-100 p-3 flex flex-col gap-2">
                {commentImagePreview && (
                  <div className="relative">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={commentImagePreview} alt="" className="w-full max-h-32 object-cover rounded-xl" />
                    <button
                      onClick={() => { setCommentImage(null); setCommentImagePreview(null); }}
                      className="absolute top-1 right-1 w-6 h-6 bg-black/60 text-white rounded-full flex items-center justify-center text-xs hover:bg-black/80"
                    >✕</button>
                  </div>
                )}
                <div className="flex gap-2 items-center">
                  <label className="cursor-pointer text-[#00ACC1] hover:text-[#0097A7] flex-shrink-0">
                    <span className="text-xl">📷</span>
                    <input type="file" accept="image/*" className="hidden" onChange={e => {
                      const f = e.target.files?.[0];
                      if (f) { setCommentImage(f); setCommentImagePreview(URL.createObjectURL(f)); }
                    }} />
                  </label>
                  <input
                    value={newComment}
                    onChange={e => setNewComment(e.target.value)}
                    onKeyDown={e => e.key === 'Enter' && !e.shiftKey && sendComment()}
                    placeholder="Votre commentaire…"
                    className="flex-1 bg-gray-50 rounded-full px-4 py-2 text-sm focus:outline-none border border-gray-200 focus:border-[#00ACC1]"
                    style={{ fontFamily: 'Galey, sans-serif' }}
                  />
                  <button
                    onClick={sendComment}
                    disabled={commenting || uploadingCommentImg || (!newComment.trim() && !commentImage)}
                    className="w-9 h-9 bg-[#00ACC1] rounded-full flex items-center justify-center text-white disabled:opacity-50 flex-shrink-0"
                  >
                    {commenting || uploadingCommentImg ? '…' : '➤'}
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Modal admin */}
      {showAdmin && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-end justify-center">
          <div className="bg-white rounded-t-2xl w-full max-w-lg h-[85vh] flex flex-col">
            <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
              <h3 className="font-bold text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>Gestion du groupe</h3>
              <button onClick={() => setShowAdmin(false)} className="text-gray-400 hover:text-gray-600">✕</button>
            </div>
            <div className="flex border-b border-gray-100">
              {(['membres', 'demandes', 'regles', 'photos'] as const).map(t => (
                <button
                  key={t}
                  onClick={() => setAdminTab(t)}
                  className={`flex-1 py-3 text-xs font-semibold transition-colors ${adminTab === t ? 'text-[#00ACC1] border-b-2 border-[#00ACC1]' : 'text-gray-500'}`}
                  style={{ fontFamily: 'Galey, sans-serif' }}
                >
                  {t === 'membres' ? 'Membres' : t === 'demandes' ? 'Demandes' : t === 'regles' ? 'Règles' : 'Photos'}
                </button>
              ))}
            </div>
            <div className="flex-1 overflow-y-auto">
              {(adminTab === 'membres' || adminTab === 'demandes') && (
                <div className="p-4 flex flex-col gap-2">
                  {membres
                    .filter(m => adminTab === 'demandes' ? m.statut === 'pending' : m.statut === 'active')
                    .map(m => (
                      <div key={m.user_uid} className="flex items-center gap-3 p-3 bg-gray-50 rounded-xl">
                        <div className="w-9 h-9 rounded-full bg-[#E0F7FA] flex items-center justify-center flex-shrink-0">
                          <span>👤</span>
                        </div>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-semibold text-gray-800 truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
                            {m.user_uid.slice(0, 12)}…
                          </p>
                          {m.role === 'admin' && <span className="text-xs text-[#00ACC1] font-semibold">Admin</span>}
                        </div>
                        <div className="flex gap-1">
                          {m.statut === 'pending' && (
                            <button onClick={() => updateMembre(m.user_uid, 'approve')} className="px-2 py-1 bg-green-50 text-green-600 rounded-lg text-xs font-semibold">✓</button>
                          )}
                          {m.role === 'membre' && m.statut === 'active' && (
                            <button onClick={() => updateMembre(m.user_uid, 'promote')} className="px-2 py-1 bg-[#E0F7FA] text-[#00ACC1] rounded-lg text-xs font-semibold">⭐</button>
                          )}
                          {m.role === 'admin' && (
                            <button onClick={() => updateMembre(m.user_uid, 'demote')} className="px-2 py-1 bg-gray-100 text-gray-600 rounded-lg text-xs font-semibold">−</button>
                          )}
                          <button onClick={() => updateMembre(m.user_uid, 'remove')} className="px-2 py-1 bg-red-50 text-red-500 rounded-lg text-xs font-semibold">✕</button>
                        </div>
                      </div>
                    ))}
                  {membres.filter(m => adminTab === 'demandes' ? m.statut === 'pending' : m.statut === 'active').length === 0 && (
                    <p className="text-center text-gray-400 py-8" style={{ fontFamily: 'Galey, sans-serif' }}>
                      {adminTab === 'demandes' ? 'Aucune demande en attente' : 'Aucun membre'}
                    </p>
                  )}
                </div>
              )}
              {adminTab === 'regles' && (
                <div className="p-4 flex flex-col gap-3">
                  {editRegles.map((r, i) => (
                    <div key={i} className="flex items-start gap-2">
                      <span className="w-6 h-6 rounded-full bg-[#00ACC1] text-white text-xs flex items-center justify-center font-bold flex-shrink-0 mt-0.5">{i + 1}</span>
                      <p className="flex-1 text-sm text-gray-700" style={{ fontFamily: 'Galey, sans-serif' }}>{r}</p>
                      <button onClick={() => setEditRegles(prev => prev.filter((_, j) => j !== i))} className="text-red-400 hover:text-red-600">✕</button>
                    </div>
                  ))}
                  <div className="flex gap-2 mt-2">
                    <input
                      value={newRegle}
                      onChange={e => setNewRegle(e.target.value)}
                      placeholder="Nouvelle règle…"
                      className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#00ACC1]"
                      style={{ fontFamily: 'Galey, sans-serif' }}
                    />
                    <button
                      onClick={() => { if (newRegle.trim()) { setEditRegles(prev => [...prev, newRegle.trim()]); setNewRegle(''); } }}
                      className="px-3 py-2 bg-[#E0F7FA] text-[#00ACC1] rounded-xl font-bold text-sm"
                    >+</button>
                  </div>
                  <button
                    onClick={saveRegles}
                    disabled={savingRegles}
                    className="w-full py-3 bg-[#00ACC1] text-white rounded-xl font-bold text-sm mt-2 disabled:opacity-50"
                    style={{ fontFamily: 'Galey, sans-serif' }}
                  >
                    {savingRegles ? 'Sauvegarde…' : 'Sauvegarder les règles'}
                  </button>
                </div>
              )}
              {adminTab === 'photos' && (
                <div className="p-4 flex flex-col gap-6">
                  {/* Avatar */}
                  <div>
                    <p className="text-sm font-bold text-[#1E2025] mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>Photo de profil du groupe</p>
                    <div className="flex items-center gap-4">
                      <div className="w-20 h-20 rounded-2xl border-2 border-gray-100 overflow-hidden bg-[#E0F7FA] flex items-center justify-center flex-shrink-0">
                        {groupe?.avatar_url
                          ? /* eslint-disable-next-line @next/next/no-img-element */ <img src={groupe.avatar_url} alt="" className="w-full h-full object-cover" />
                          : <span className="text-3xl">{groupe?.type === 'race' ? '🐾' : groupe?.type === 'region' ? '📍' : groupe?.type === 'loisir' ? '🎯' : '💬'}</span>
                        }
                      </div>
                      <label className={`flex-1 flex items-center justify-center gap-2 py-3 border-2 border-dashed rounded-xl cursor-pointer transition-colors ${avatarUploading ? 'border-gray-200 text-gray-300' : 'border-[#00ACC1]/40 text-[#00ACC1] hover:border-[#00ACC1] hover:bg-[#E0F7FA]/30'}`}>
                        <span className="text-lg">📷</span>
                        <span className="text-sm font-semibold" style={{ fontFamily: 'Galey, sans-serif' }}>
                          {avatarUploading ? 'Upload en cours…' : 'Changer la photo'}
                        </span>
                        <input type="file" accept="image/*" className="hidden" disabled={avatarUploading} onChange={handleAvatarUpload} />
                      </label>
                    </div>
                  </div>
                  {/* Bannière */}
                  <div>
                    <p className="text-sm font-bold text-[#1E2025] mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>Bannière du groupe</p>
                    <div className="rounded-xl overflow-hidden h-28 bg-[#00ACC1] relative mb-3">
                      {groupe?.photo_cover_url
                        ? /* eslint-disable-next-line @next/next/no-img-element */ <img src={groupe.photo_cover_url} alt="" className="w-full h-full object-cover" />
                        : <div className="w-full h-full flex items-center justify-center text-white/40 text-sm">Aucune bannière</div>
                      }
                    </div>
                    <label className={`flex items-center justify-center gap-2 py-3 border-2 border-dashed rounded-xl cursor-pointer transition-colors w-full ${bannerUploading ? 'border-gray-200 text-gray-300' : 'border-[#00ACC1]/40 text-[#00ACC1] hover:border-[#00ACC1] hover:bg-[#E0F7FA]/30'}`}>
                      <span className="text-lg">🖼️</span>
                      <span className="text-sm font-semibold" style={{ fontFamily: 'Galey, sans-serif' }}>
                        {bannerUploading ? 'Upload en cours…' : 'Changer la bannière'}
                      </span>
                      <input type="file" accept="image/*" className="hidden" disabled={bannerUploading} onChange={handleBannerUpload} />
                    </label>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
