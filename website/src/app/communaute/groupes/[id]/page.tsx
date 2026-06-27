'use client';

import { useState, useEffect, useCallback } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';

const TYPE_LABELS: Record<string, string> = { race: 'Race', region: 'Région', loisir: 'Loisir', autre: 'Autre' };

interface Groupe {
  id: string; nom: string; description: string; type: string;
  prive: boolean; createur_uid: string; regles: string[];
}
interface Post {
  id: string; groupe_id: string; auteur_uid: string; contenu: string;
  like_count: number; comment_count: number; epingle: boolean; created_at: string;
}
interface Commentaire {
  id: string; post_id: string; auteur_uid: string; contenu: string; created_at: string;
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

  // Admin state
  const [showAdmin, setShowAdmin] = useState(false);
  const [adminTab, setAdminTab] = useState<'membres' | 'demandes' | 'regles'>('membres');
  const [membres, setMembres] = useState<{ user_uid: string; role: string; statut: string }[]>([]);
  const [editRegles, setEditRegles] = useState<string[]>([]);
  const [newRegle, setNewRegle] = useState('');
  const [savingRegles, setSavingRegles] = useState(false);

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

  async function publishPost() {
    if (!user?.uid || !newPost.trim() || !isMember) return;
    setPosting(true);
    try {
      const { data } = await supabase.from('groupe_posts').insert({
        groupe_id: id, auteur_uid: user.uid, contenu: newPost.trim(),
        created_at: new Date().toISOString(),
      }).select().single();
      if (data) setPosts(prev => [data as Post, ...prev]);
      setNewPost('');
    } finally { setPosting(false); }
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
    setComments((data ?? []) as Commentaire[]);
    setLoadingComments(false);
  }

  async function sendComment() {
    if (!user?.uid || !newComment.trim() || !openCommentPost) return;
    setCommenting(true);
    try {
      const { data } = await supabase.from('groupe_post_commentaires').insert({
        post_id: openCommentPost.id, auteur_uid: user.uid, contenu: newComment.trim(),
        created_at: new Date().toISOString(),
      }).select().single();
      if (data) setComments(prev => [...prev, data as Commentaire]);
      const newCount = comments.length + 1;
      await supabase.from('groupe_posts').update({ comment_count: newCount }).eq('id', openCommentPost.id);
      setPosts(prev => prev.map(p => p.id === openCommentPost.id ? { ...p, comment_count: newCount } : p));
      setNewComment('');
    } finally { setCommenting(false); }
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

  if (loading) return (
    <div className="flex justify-center items-center py-40">
      <div className="w-8 h-8 border-2 border-[#00ACC1] border-t-transparent rounded-full animate-spin" />
    </div>
  );

  if (!groupe) return null;

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Header */}
      <div className="bg-[#00ACC1] text-white px-4 py-8">
        <div className="max-w-2xl mx-auto">
          <button onClick={() => router.back()} className="text-white/70 hover:text-white text-sm mb-4 flex items-center gap-1">
            ← Retour
          </button>
          <div className="flex items-start gap-4">
            <div className="w-16 h-16 rounded-2xl bg-white/20 flex items-center justify-center flex-shrink-0 text-3xl">
              {groupe.type === 'race' ? '🐾' : groupe.type === 'region' ? '📍' : groupe.type === 'loisir' ? '🎯' : '💬'}
            </div>
            <div className="flex-1">
              <div className="flex items-center gap-2 flex-wrap">
                <h1 className="text-xl font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>{groupe.nom}</h1>
                {groupe.prive && <span className="text-xs bg-white/20 px-2 py-0.5 rounded-full">🔒 Privé</span>}
              </div>
              <span className="inline-block text-xs bg-white/20 px-2 py-0.5 rounded-full mt-1">
                {TYPE_LABELS[groupe.type] ?? groupe.type}
              </span>
              <p className="text-white/80 text-sm mt-2">
                {membresCount} membre{membresCount > 1 ? 's' : ''}
                {friendsCount > 0 && ` · ${friendsCount} ami${friendsCount > 1 ? 's' : ''}`}
              </p>
            </div>
            {isAdmin && (
              <button
                onClick={() => { setShowAdmin(true); loadAdminMembres(); }}
                className="p-2 bg-white/20 rounded-xl hover:bg-white/30 transition-colors"
              >
                ⚙️
              </button>
            )}
          </div>
          {groupe.description && (
            <p className="text-white/80 text-sm mt-3">{groupe.description}</p>
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
            <div className="flex justify-end mt-2">
              <button
                onClick={publishPost}
                disabled={posting || !newPost.trim()}
                className="px-4 py-2 bg-[#00ACC1] text-white rounded-xl text-sm font-bold disabled:opacity-50"
                style={{ fontFamily: 'Galey, sans-serif' }}
              >
                {posting ? '…' : 'Publier'}
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

              return (
                <div key={post.id} className={`bg-white rounded-2xl shadow-sm border overflow-hidden ${post.epingle ? 'border-[#00ACC1]/40' : 'border-gray-100'}`}>
                  <div className="p-4">
                    <div className="flex items-center gap-3 mb-3">
                      <div className="w-9 h-9 rounded-full bg-[#E0F7FA] flex items-center justify-center flex-shrink-0">
                        <span className="text-lg">👤</span>
                      </div>
                      <div className="flex-1">
                        <p className="text-sm font-bold text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>
                          {isMe ? 'Moi' : 'Membre'}
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
                    <p className="text-sm text-[#1E2025] leading-relaxed" style={{ fontFamily: 'Galey, sans-serif' }}>{post.contenu}</p>
                  </div>
                  <div className="border-t border-gray-100 flex">
                    <button
                      onClick={() => toggleLike(post.id)}
                      className={`flex-1 flex items-center justify-center gap-2 py-2.5 text-sm transition-colors ${liked ? 'text-red-500' : 'text-gray-500 hover:text-red-400'}`}
                      style={{ fontFamily: 'Galey, sans-serif' }}
                    >
                      {liked ? '❤️' : '🤍'} {post.like_count > 0 ? post.like_count : 'J\'aime'}
                    </button>
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
                    return (
                      <div key={c.id} className={`flex ${isMe ? 'justify-end' : 'justify-start'}`}>
                        <div className={`max-w-[75%] px-3 py-2 rounded-2xl text-sm ${isMe ? 'bg-[#E0F7FA] text-[#1E2025]' : 'bg-gray-100 text-[#1E2025]'}`} style={{ fontFamily: 'Galey, sans-serif' }}>
                          <p>{c.contenu}</p>
                          <p className="text-xs text-gray-400 mt-1">{fmtDate(c.created_at)}</p>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
            {isMember && (
              <div className="border-t border-gray-100 p-3 flex gap-2">
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
                  disabled={commenting || !newComment.trim()}
                  className="w-9 h-9 bg-[#00ACC1] rounded-full flex items-center justify-center text-white disabled:opacity-50"
                >
                  {commenting ? '…' : '➤'}
                </button>
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
              {(['membres', 'demandes', 'regles'] as const).map(t => (
                <button
                  key={t}
                  onClick={() => setAdminTab(t)}
                  className={`flex-1 py-3 text-sm font-semibold transition-colors ${adminTab === t ? 'text-[#00ACC1] border-b-2 border-[#00ACC1]' : 'text-gray-500'}`}
                  style={{ fontFamily: 'Galey, sans-serif' }}
                >
                  {t === 'membres' ? 'Membres' : t === 'demandes' ? 'Demandes' : 'Règles'}
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
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
