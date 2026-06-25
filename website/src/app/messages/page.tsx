'use client';

import { useEffect, useState, useRef, useCallback, Suspense } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import Image from 'next/image';
import {
  collection, query, where, orderBy, onSnapshot,
  addDoc, serverTimestamp, doc, updateDoc, getDoc, setDoc,
  Timestamp,
} from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

// ─── Structure Firestore (identique à l'app Flutter) ─────────────────────────
// conversations/{id} → { participants[], lastMessage, timestamp, unreadCount:{uid:n} }
// conversations/{id}/messages → { text, senderId, timestamp, isRead, imageUrl?, type?, lat?, lng? }

type ConvCategorie = 'animaux-perdus' | 'annonces' | 'communaute' | 'contact-elevage' | 'service-professionnel' | '__archived__' | null;

const CAT_CONFIG: { key: ConvCategorie; label: string; emoji: string; bg: string; text: string }[] = [
  { key: null,                     label: 'Tous',       emoji: '💬', bg: 'bg-[#0C5C6C]',        text: 'text-white' },
  { key: 'animaux-perdus',         label: 'Perdus',     emoji: '🐾', bg: 'bg-orange-500',       text: 'text-white' },
  { key: 'annonces',               label: 'Annonces',   emoji: '📢', bg: 'bg-blue-500',         text: 'text-white' },
  { key: 'contact-elevage',        label: 'Élevages',   emoji: '🏡', bg: 'bg-[#0C5C6C]',        text: 'text-white' },
  { key: 'service-professionnel',  label: 'Services',   emoji: '🔧', bg: 'bg-violet-600',       text: 'text-white' },
  { key: 'communaute',             label: 'Communauté', emoji: '🌿', bg: 'bg-[#6E9E57]',        text: 'text-white' },
  { key: '__archived__',           label: 'Archivés',   emoji: '📦', bg: 'bg-slate-500',        text: 'text-white' },
];

const CAT_BADGE: Record<string, { bg: string; label: string }> = {
  'animaux-perdus':        { bg: 'bg-orange-100 text-orange-700',      label: '🐾 Perdus' },
  'annonces':              { bg: 'bg-blue-100 text-blue-700',           label: '📢 Annonces' },
  'contact-elevage':       { bg: 'bg-[#CCE8F0] text-[#0C5C6C]',       label: '🏡 Élevage' },
  'service-professionnel': { bg: 'bg-violet-100 text-violet-700',      label: '🔧 Service' },
  'communaute':            { bg: 'bg-[#EEF5EA] text-[#4A7A36]',       label: '🌿 Communauté' },
};

interface Conversation {
  id: string;
  participants: string[];
  lastMessage: string;
  timestamp: Timestamp | null;
  unreadCount: Record<string, number>;
  categorie?: string;
  pro_profile_id?: string;
  consumer_profile_id?: string;
  pinnedFor?: Record<string, boolean>;
  archivedFor?: Record<string, boolean>;
  mutedFor?: Record<string, number>;
  deletedFor?: Record<string, boolean>;
}

interface Message {
  id: string;
  text: string;
  senderId: string;
  sender_profile_id?: string;
  timestamp: Timestamp | null;
  isRead: boolean;
  imageUrl?: string;
  type?: string;
  lat?: number;
  lng?: number;
}

interface UserInfo {
  name: string;
  avatar?: string;
}

function fmtTime(ts: Timestamp | null): string {
  if (!ts) return '';
  const d = ts.toDate();
  const now = new Date();
  if (d.toDateString() === now.toDateString())
    return d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  if (d.toDateString() === yesterday.toDateString()) return 'Hier';
  return d.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' });
}

function fmtDate(ts: Timestamp | null): string {
  if (!ts) return '';
  const d = ts.toDate();
  const now = new Date();
  if (d.toDateString() === now.toDateString()) return "Aujourd'hui";
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  if (d.toDateString() === yesterday.toDateString()) return 'Hier';
  return d.toLocaleDateString('fr-FR', { day: '2-digit', month: 'long', year: 'numeric' });
}

function MessagesPageInner() {
  const { user, userData, loading } = useAuth();
  const activeProfileId = useActiveProfile();
  const router = useRouter();
  const searchParams = useSearchParams();
  const [conversations, setConversations] = useState<Conversation[]>([]);
  const [userProfileIds, setUserProfileIds] = useState<string[]>([]);
  const userInfoCacheRef = useRef<Record<string, UserInfo>>({});
  const [, forceUpdate] = useState(0);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const [search, setSearch] = useState('');
  const [activeCategory, setActiveCategory] = useState<ConvCategorie>(null);
  const [mobileView, setMobileView] = useState<'list' | 'thread'>('list');
  const [contextMenu, setContextMenu] = useState<{ id: string; x: number; y: number } | null>(null);
  const [blockedUsers, setBlockedUsers] = useState<string[]>([]);
  const endRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  useEffect(() => {
    if (!user) return;
    getDoc(doc(db, 'bloquer', user.uid)).then(snap => {
      if (snap.exists()) setBlockedUsers(Object.keys(snap.data() ?? {}));
    });
  }, [user]);

  // Charger tous les profile IDs de l'utilisateur (pour filtrer les conversations)
  useEffect(() => {
    if (!user) return;
    supabase.from('user_profiles').select('id').eq('uid', user.uid)
      .then(({ data }) => { if (data) setUserProfileIds(data.map((r: { id: string }) => r.id)); });
  }, [user]);

  // ── Actions Firestore ─────────────────────────────────────────────────────
  async function togglePin(id: string, current: boolean) {
    if (!user) return;
    await updateDoc(doc(db, 'conversations', id), { [`pinnedFor.${user.uid}`]: !current });
  }
  async function toggleArchive(id: string, current: boolean) {
    if (!user) return;
    await updateDoc(doc(db, 'conversations', id), { [`archivedFor.${user.uid}`]: !current });
  }
  async function toggleMute(id: string, current: boolean) {
    if (!user) return;
    const until = current ? 0 : Date.now() + 8 * 3600 * 1000;
    await updateDoc(doc(db, 'conversations', id), { [`mutedFor.${user.uid}`]: until });
  }
  async function blockUser(otherId: string) {
    if (!user) return;
    const ref = doc(db, 'bloquer', user.uid);
    const snap = await getDoc(ref);
    const existing = snap.exists() ? (snap.data() ?? {}) : {};
    await setDoc(ref, { ...existing, [otherId]: true });
    setBlockedUsers(prev => [...prev, otherId]);
  }
  async function deleteConv(id: string) {
    if (!user) return;
    await updateDoc(doc(db, 'conversations', id), { [`deletedFor.${user.uid}`]: true });
    if (selectedId === id) setSelectedId(null);
  }

  // Pré-sélectionner une conversation via ?conv= (depuis le profil éleveur)
  useEffect(() => {
    const convId = searchParams.get('conv');
    if (convId) {
      setSelectedId(convId);
      setMobileView('thread');
    }
  }, [searchParams]);

  // Récupère nom/avatar depuis Firestore users (identique à l'app Flutter)
  const getUserInfo = useCallback(async (uid: string): Promise<UserInfo> => {
    if (userInfoCacheRef.current[uid]) return userInfoCacheRef.current[uid];
    try {
      const snap = await getDoc(doc(db, 'users', uid));
      if (snap.exists()) {
        const d = snap.data();
        const isElevage = d.isElevage === true;
        const name = isElevage
          ? (d.nameElevage ?? 'Élevage')
          : `${d.firstname ?? ''} ${d.lastname ?? ''}`.trim() || 'Utilisateur';
        const rawUrl = isElevage ? d.profilePictureUrlElevage : d.profilePictureUrl;
        const avatar = rawUrl?.startsWith('http') ? rawUrl : undefined;
        const info: UserInfo = { name, avatar };
        userInfoCacheRef.current[uid] = info;
        forceUpdate(n => n + 1);
        return info;
      }
    } catch { /* ignore */ }
    return { name: 'Utilisateur' };
  }, []);

  // Conversations en temps réel (même query que l'app Flutter)
  useEffect(() => {
    if (!user) return;
    const q = query(
      collection(db, 'conversations'),
      where('participants', 'array-contains', user.uid)
    );
    return onSnapshot(q, snap => {
      const convs = snap.docs.map(d => ({ id: d.id, ...d.data() } as Conversation));
      convs.sort((a, b) => (b.timestamp?.toMillis() ?? 0) - (a.timestamp?.toMillis() ?? 0));
      setConversations(convs);
      for (const conv of convs) {
        const otherUid = conv.participants.find(p => p !== user.uid);
        if (otherUid && !userInfoCacheRef.current[otherUid]) getUserInfo(otherUid);
      }
    }, () => {});
  }, [user, getUserInfo]);

  // Messages en temps réel — sous-collection identique à l'app Flutter
  useEffect(() => {
    if (!selectedId) { setMessages([]); return; }
    const q = query(
      collection(db, 'conversations', selectedId, 'messages'),
      orderBy('timestamp', 'asc')
    );
    return onSnapshot(q, snap => {
      setMessages(snap.docs.map(d => ({ id: d.id, ...d.data() } as Message)));
      setTimeout(() => endRef.current?.scrollIntoView({ behavior: 'smooth' }), 50);
    }, () => {});
  }, [selectedId]);

  // Marquer comme lu (identique à l'app : unreadCount.$uid = 0)
  useEffect(() => {
    if (!selectedId || !user) return;
    const conv = conversations.find(c => c.id === selectedId);
    if (conv && (conv.unreadCount?.[user.uid] ?? 0) > 0) {
      updateDoc(doc(db, 'conversations', selectedId), {
        [`unreadCount.${user.uid}`]: 0,
      }).catch(() => {});
    }
  }, [selectedId, conversations, user]);

  async function sendMessage() {
    if (!text.trim() || !selectedId || !user || sending) return;
    const msg = text.trim();
    setText('');
    setSending(true);
    try {
      await addDoc(collection(db, 'conversations', selectedId, 'messages'), {
        text: msg,
        senderId: user.uid,
        timestamp: serverTimestamp(),
        isRead: false,
        ...(activeProfileId ? { sender_profile_id: activeProfileId } : {}),
      });
      const conv = conversations.find(c => c.id === selectedId);
      const unread = { ...(conv?.unreadCount ?? {}) };
      for (const p of conv?.participants ?? []) {
        if (p !== user.uid) unread[p] = (unread[p] ?? 0) + 1;
      }
      await updateDoc(doc(db, 'conversations', selectedId), {
        lastMessage: msg,
        timestamp: serverTimestamp(),
        unreadCount: unread,
      });
    } finally {
      setSending(false);
      inputRef.current?.focus();
    }
  }

  if (loading || !user) {
    return (
      <div className="flex justify-center py-32">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  const myName = userData?.nameElevage ?? userData?.firstname ?? '';
  const totalUnread = conversations.reduce((s, c) => s + (c.unreadCount?.[user.uid] ?? 0), 0);
  const selectedConv = conversations.find(c => c.id === selectedId);
  const otherUid = selectedConv?.participants.find(p => p !== user.uid);
  const otherInfo = otherUid ? (userInfoCacheRef.current[otherUid] ?? { name: '…' }) : null;

  const filteredConvs = conversations
    .filter(conv => {
      if (conv.deletedFor?.[user.uid]) return false;
      const others = conv.participants.filter(p => p !== user.uid);
      if (others.some(p => blockedUsers.includes(p))) return false;

      if (activeProfileId) {
        // Profil secondaire actif : montrer convs où je suis le pro OU le consommateur avec ce profil
        const isMePro      = conv.pro_profile_id === activeProfileId;
        const isMeConsumer = conv.consumer_profile_id === activeProfileId;
        // Fallback : ancienne conv sans tags → inclure si l'utilisateur est concerné
        const isUntagged   = !conv.pro_profile_id && !conv.consumer_profile_id;
        if (!isMePro && !isMeConsumer && !isUntagged) return false;
      } else {
        // Vue particulier (aucun profil secondaire actif) :
        // cacher les convs taguées à l'un des profils secondaires de l'utilisateur
        const proIsMyProfile      = conv.pro_profile_id && userProfileIds.includes(conv.pro_profile_id);
        const consumerIsMyProfile = conv.consumer_profile_id && userProfileIds.includes(conv.consumer_profile_id);
        if (proIsMyProfile || consumerIsMyProfile) return false;
      }

      const isArchived = conv.archivedFor?.[user.uid] === true;
      if (activeCategory === '__archived__') return isArchived;
      if (isArchived) return false;

      if (activeCategory !== null) {
        if ((conv.categorie ?? null) !== activeCategory) return false;
      }

      if (!search) return true;
      const oUid = conv.participants.find(p => p !== user.uid);
      const oName = oUid ? (userInfoCacheRef.current[oUid]?.name ?? '') : '';
      return oName.toLowerCase().includes(search.toLowerCase()) ||
        (conv.lastMessage ?? '').toLowerCase().includes(search.toLowerCase());
    })
    .sort((a, b) => {
      const ap = a.pinnedFor?.[user.uid] === true;
      const bp = b.pinnedFor?.[user.uid] === true;
      if (ap && !bp) return -1;
      if (!ap && bp) return 1;
      return (b.timestamp?.toMillis() ?? 0) - (a.timestamp?.toMillis() ?? 0);
    });

  return (
    <div className="h-[calc(100vh-64px)] flex bg-[#F8F8F6] overflow-hidden">

      {/* ── Sidebar ─────────────────────────────────────────────────────── */}
      <aside className={`${mobileView === 'thread' ? 'hidden md:flex' : 'flex'} flex-col w-full md:w-80 lg:w-96 bg-white border-r border-gray-100 flex-shrink-0`}>
        <div className="px-5 py-4 border-b border-gray-100 flex-shrink-0">
          <div className="flex items-center justify-between mb-3">
            <h1 className="text-lg font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Messages</h1>
            {totalUnread > 0 && (
              <span className="bg-[#0C5C6C] text-white text-xs font-bold px-2 py-0.5 rounded-full">
                {totalUnread > 99 ? '99+' : totalUnread}
              </span>
            )}
          </div>
          <div className="relative">
            <svg className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0"/>
            </svg>
            <input
              value={search}
              onChange={e => setSearch(e.target.value)}
              placeholder="Recherche"
              className="w-full pl-9 pr-4 py-2 bg-[#A7C79A]/10 border border-[#A7C79A] rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-[#6E9E57]/30"
            />
          </div>
          <div className="flex gap-1.5 mt-3 flex-wrap">
            {CAT_CONFIG.map(cat => {
              const isActive = activeCategory === cat.key;
              const catUnread = cat.key === null
                ? conversations.reduce((s, c) => s + (c.unreadCount?.[user.uid] ?? 0), 0)
                : conversations
                    .filter(c => (c.categorie ?? null) === cat.key)
                    .reduce((s, c) => s + (c.unreadCount?.[user.uid] ?? 0), 0);
              return (
                <button
                  key={String(cat.key)}
                  onClick={() => setActiveCategory(cat.key)}
                  className={`flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium transition-all ${
                    isActive
                      ? `${cat.bg} ${cat.text} shadow-sm`
                      : 'bg-gray-100 text-gray-500 hover:bg-gray-200'
                  }`}>
                  <span>{cat.emoji}</span>
                  <span>{cat.label}</span>
                  {catUnread > 0 && (
                    <span className={`ml-0.5 text-[10px] font-bold ${isActive ? 'text-white/80' : 'text-red-500'}`}>
                      {catUnread > 9 ? '9+' : catUnread}
                    </span>
                  )}
                </button>
              );
            })}
          </div>
        </div>

        <div className="flex-1 overflow-y-auto divide-y divide-gray-50">
          {filteredConvs.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-48 text-center px-6">
              <p className="text-4xl mb-3">💬</p>
              <p className="text-gray-500 text-sm font-medium">
                {search ? 'Aucun résultat' : 'Aucune conversation'}
              </p>
              <p className="text-gray-400 text-xs mt-1">
                {!search && 'Vos conversations apparaîtront ici'}
              </p>
            </div>
          ) : (
            filteredConvs.map(conv => {
              const oUid = conv.participants.find(p => p !== user.uid);
              const oInfo = oUid ? (userInfoCacheRef.current[oUid] ?? { name: '…' }) : { name: '…' };
              const rawUnread = conv.unreadCount?.[user.uid] ?? 0;
              const isMuted = (conv.mutedFor?.[user.uid] ?? 0) > Date.now();
              const unread = isMuted ? 0 : rawUnread;
              const isPinned = conv.pinnedFor?.[user.uid] === true;
              const isSelected = conv.id === selectedId;
              return (
                <button
                  key={conv.id}
                  onClick={() => {
                    setSelectedId(conv.id);
                    setMobileView('thread');
                    setContextMenu(null);
                    if (oUid && !userInfoCacheRef.current[oUid]) getUserInfo(oUid);
                  }}
                  onContextMenu={e => { e.preventDefault(); setContextMenu({ id: conv.id, x: e.clientX, y: e.clientY }); }}
                  className={`w-full flex items-center gap-3 px-4 py-3.5 text-left hover:bg-gray-50 transition-colors relative ${
                    isSelected ? 'bg-[#0C5C6C]/5' : isPinned ? 'bg-[#F0F9FF]' : ''
                  }`}>
                  {isSelected && <div className="absolute left-0 top-0 bottom-0 w-0.5 bg-[#0C5C6C]" />}
                  <div className="relative w-12 h-12 flex-shrink-0">
                    <div className="w-12 h-12 rounded-full bg-[#6E9E57] flex items-center justify-center overflow-hidden relative">
                      {oInfo.avatar ? (
                        <Image src={oInfo.avatar} alt="" fill className="object-cover" />
                      ) : (
                        <span className="text-white font-bold text-lg">{(oInfo.name[0] ?? '?').toUpperCase()}</span>
                      )}
                    </div>
                    {unread > 0 && (
                      <span className="absolute -top-0.5 -right-0.5 w-5 h-5 bg-red-500 rounded-full text-white text-[10px] font-bold flex items-center justify-center">
                        {unread > 9 ? '9+' : unread}
                      </span>
                    )}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between gap-1">
                      <div className="flex items-center gap-1 min-w-0">
                        {isPinned && <span className="text-[#0C5C6C] text-xs flex-shrink-0">📌</span>}
                        <span className={`text-sm truncate ${unread > 0 ? 'font-bold text-[#1F2A2E]' : 'font-medium text-gray-700'}`}>
                          {oInfo.name}
                        </span>
                        {isMuted && <span className="text-gray-400 text-xs flex-shrink-0">🔕</span>}
                      </div>
                      <span className="text-xs text-gray-400 flex-shrink-0">{fmtTime(conv.timestamp)}</span>
                    </div>
                    <p className={`text-xs truncate ${unread > 0 ? 'text-gray-700 font-medium' : 'text-gray-400'}`}>
                      {conv.lastMessage ?? ''}
                    </p>
                    {conv.categorie && CAT_BADGE[conv.categorie] && (
                      <span className={`inline-block text-[10px] px-1.5 py-0.5 rounded-full font-medium mt-0.5 ${CAT_BADGE[conv.categorie].bg}`}>
                        {CAT_BADGE[conv.categorie].label}
                      </span>
                    )}
                  </div>
                </button>
              );
            })
          )}
        </div>
      </aside>

      {/* ── Thread ──────────────────────────────────────────────────────── */}
      <main className={`${mobileView === 'list' ? 'hidden md:flex' : 'flex'} flex-1 flex-col overflow-hidden`}>
        {!selectedId ? (
          <div className="flex-1 flex flex-col items-center justify-center text-center p-8">
            <p className="text-7xl mb-4">💬</p>
            <p className="text-gray-500 font-semibold text-lg" style={{ fontFamily: 'Galey, sans-serif' }}>
              {myName ? `Bonjour ${myName} !` : 'Vos messages'}
            </p>
            <p className="text-gray-400 text-sm mt-2">Sélectionnez une conversation</p>
          </div>
        ) : (
          <>
            {/* Header thread */}
            <div className="bg-white border-b border-gray-100 px-4 py-3 flex items-center gap-3 flex-shrink-0">
              <button onClick={() => setMobileView('list')} className="md:hidden p-1 text-gray-500">
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7"/>
                </svg>
              </button>
              <div className="w-10 h-10 rounded-full bg-[#6E9E57] flex-shrink-0 flex items-center justify-center overflow-hidden relative">
                {otherInfo?.avatar ? (
                  <Image src={otherInfo.avatar} alt="" fill className="object-cover"/>
                ) : (
                  <span className="text-white font-bold">{(otherInfo?.name[0] ?? '?').toUpperCase()}</span>
                )}
              </div>
              <p className="font-semibold text-sm text-[#1F2A2E]">{otherInfo?.name ?? '…'}</p>
            </div>

            {/* Messages */}
            <div className="flex-1 overflow-y-auto px-3 py-4 space-y-1">
              {messages.length === 0 && (
                <p className="text-center text-gray-400 text-sm py-8">Commencez la conversation !</p>
              )}
              {messages.map((msg, i) => {
                const isMe = msg.senderId === user.uid;
                const ts = msg.timestamp;
                const prevTs = i > 0 ? messages[i - 1].timestamp : null;
                const showDate = i === 0 || fmtDate(ts) !== fmtDate(prevTs);
                const isLocation = msg.type === 'location';

                return (
                  <div key={msg.id}>
                    {showDate && ts && (
                      <div className="flex justify-center my-3">
                        <span className="bg-gray-200 text-gray-500 text-xs px-3 py-1 rounded-full">{fmtDate(ts)}</span>
                      </div>
                    )}
                    <div className={`flex ${isMe ? 'justify-end' : 'justify-start'} mb-0.5`}>
                      <div className={`max-w-[75%] rounded-2xl text-sm ${
                        isMe ? 'bg-[#0C5C6C] text-white rounded-br-md' : 'bg-white text-[#1F2A2E] shadow-sm rounded-bl-md'
                      } ${isLocation || msg.imageUrl ? 'p-1' : 'px-4 py-2.5'}`}>
                        {msg.imageUrl && (
                          <a href={msg.imageUrl} target="_blank" rel="noopener noreferrer">
                            <Image src={msg.imageUrl} alt="photo" width={200} height={200} className="rounded-xl object-cover" />
                          </a>
                        )}
                        {isLocation && msg.lat != null && msg.lng != null && (
                          <a href={`https://www.google.com/maps/search/?api=1&query=${msg.lat},${msg.lng}`}
                            target="_blank" rel="noopener noreferrer"
                            className={`flex items-center gap-2 px-3 py-2.5 rounded-xl ${isMe ? 'bg-white/15' : 'bg-[#EEF5EA]'}`}>
                            <span className="text-xl">📍</span>
                            <div>
                              <p className={`text-xs font-semibold ${isMe ? 'text-white' : 'text-[#1F2A2E]'}`}>Position GPS partagée</p>
                              <p className={`text-[10px] ${isMe ? 'text-white/70' : 'text-gray-500'}`}>Appuyer pour ouvrir Maps</p>
                            </div>
                          </a>
                        )}
                        {msg.text && (
                          <p className={`leading-relaxed ${(msg.imageUrl || isLocation) ? 'px-3 pt-2 pb-1' : ''}`}>{msg.text}</p>
                        )}
                        <p className={`text-[10px] mt-0.5 text-right ${isMe ? 'text-white/60' : 'text-gray-400'} ${(msg.imageUrl || isLocation) ? 'px-3 pb-1' : ''}`}>
                          {fmtTime(ts)}
                          {isMe && msg.isRead && ' · Vu'}
                        </p>
                      </div>
                    </div>
                  </div>
                );
              })}
              <div ref={endRef} />
            </div>

            {/* Input */}
            <div className="bg-white border-t border-gray-100 px-3 py-3 flex-shrink-0">
              <div className="flex items-end gap-2">
                <textarea
                  ref={inputRef}
                  value={text}
                  onChange={e => setText(e.target.value)}
                  onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendMessage(); } }}
                  placeholder="Votre message…"
                  rows={1}
                  className="flex-1 bg-gray-100 rounded-2xl px-4 py-2.5 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30 max-h-28"
                  style={{ minHeight: '44px' }}
                />
                <button
                  onClick={sendMessage}
                  disabled={!text.trim() || sending}
                  className="w-11 h-11 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-40 text-white rounded-full flex items-center justify-center transition-colors flex-shrink-0">
                  {sending ? (
                    <div className="w-4 h-4 border-2 border-white/40 border-t-white rounded-full animate-spin" />
                  ) : (
                    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M22 2L11 13M22 2l-7 20-4-9-9-4 20-7z"/>
                    </svg>
                  )}
                </button>
              </div>
            </div>
          </>
        )}
      </main>
      {/* ── Context menu (right-click) ──────────────────────────────────── */}
      {contextMenu && (() => {
        const conv = conversations.find(c => c.id === contextMenu.id);
        if (!conv) return null;
        const isPinned   = conv.pinnedFor?.[user.uid] === true;
        const isArchived = conv.archivedFor?.[user.uid] === true;
        const isMuted    = (conv.mutedFor?.[user.uid] ?? 0) > Date.now();
        const oUid       = conv.participants.find(p => p !== user.uid) ?? '';
        const close      = () => setContextMenu(null);
        return (
          <>
            <div className="fixed inset-0 z-40" onClick={close} onContextMenu={e => { e.preventDefault(); close(); }} />
            <div
              className="fixed z-50 bg-white rounded-xl shadow-xl border border-gray-100 py-1 w-56"
              style={{ left: contextMenu.x, top: contextMenu.y }}>
              {[
                { icon: '📌', label: isPinned ? 'Désépingler' : 'Épingler', action: () => { togglePin(contextMenu.id, isPinned); close(); } },
                { icon: isArchived ? '📤' : '📦', label: isArchived ? 'Désarchiver' : 'Archiver', action: () => { toggleArchive(contextMenu.id, isArchived); close(); } },
                { icon: isMuted ? '🔔' : '🔕', label: isMuted ? 'Réactiver les notifications' : 'Mettre en sourdine (8h)', action: () => { toggleMute(contextMenu.id, isMuted); close(); } },
              ].map(item => (
                <button key={item.label} onClick={item.action}
                  className="w-full flex items-center gap-2.5 px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 text-left">
                  <span>{item.icon}</span>{item.label}
                </button>
              ))}
              <div className="my-1 border-t border-gray-100" />
              <button onClick={async () => {
                close();
                if (!confirm('Bloquer cet utilisateur ? Vous ne recevrez plus ses messages.')) return;
                await blockUser(oUid);
              }} className="w-full flex items-center gap-2.5 px-4 py-2 text-sm text-red-600 hover:bg-red-50 text-left">
                <span>🚫</span>Bloquer cet utilisateur
              </button>
              <button onClick={async () => {
                close();
                if (!confirm('Supprimer cette conversation ?')) return;
                await deleteConv(contextMenu.id);
              }} className="w-full flex items-center gap-2.5 px-4 py-2 text-sm text-red-600 hover:bg-red-50 text-left">
                <span>🗑️</span>Supprimer la conversation
              </button>
            </div>
          </>
        );
      })()}
    </div>
  );
}

export default function MessagesPage() {
  return (
    <Suspense>
      <MessagesPageInner />
    </Suspense>
  );
}
