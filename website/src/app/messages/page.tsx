'use client';

import { useEffect, useState, useRef, useCallback, Suspense } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import type { RealtimeChannel } from '@supabase/supabase-js';

type ConvCategorie = 'animaux-perdus' | 'annonces' | 'communaute' | 'contact-elevage' | 'service-professionnel' | '__archived__' | null;

const CAT_CONFIG: { key: ConvCategorie; label: string; emoji: string; bg: string; text: string }[] = [
  { key: null,                     label: 'Tous',       emoji: '💬', bg: 'bg-[#0C5C6C]',       text: 'text-white' },
  { key: 'animaux-perdus',         label: 'Perdus',     emoji: '🐾', bg: 'bg-orange-500',      text: 'text-white' },
  { key: 'annonces',               label: 'Annonces',   emoji: '📢', bg: 'bg-blue-500',        text: 'text-white' },
  { key: 'contact-elevage',        label: 'Élevages',   emoji: '🏡', bg: 'bg-[#0C5C6C]',       text: 'text-white' },
  { key: 'service-professionnel',  label: 'Services',   emoji: '🔧', bg: 'bg-violet-600',      text: 'text-white' },
  { key: 'communaute',             label: 'Communauté', emoji: '🌿', bg: 'bg-[#6E9E57]',       text: 'text-white' },
  { key: '__archived__',           label: 'Archivés',   emoji: '📦', bg: 'bg-slate-500',       text: 'text-white' },
];

const CAT_BADGE: Record<string, { bg: string; label: string }> = {
  'animaux-perdus':        { bg: 'bg-orange-100 text-orange-700',    label: '🐾 Perdus' },
  'annonces':              { bg: 'bg-blue-100 text-blue-700',         label: '📢 Annonces' },
  'contact-elevage':       { bg: 'bg-[#CCE8F0] text-[#0C5C6C]',     label: '🏡 Élevage' },
  'service-professionnel': { bg: 'bg-violet-100 text-violet-700',    label: '🔧 Service' },
  'communaute':            { bg: 'bg-[#EEF5EA] text-[#4A7A36]',     label: '🌿 Communauté' },
};

interface Conversation {
  id: string;
  participants: string[];
  participant_ids: string;
  participants_info: Record<string, { name: string; photo?: string }>;
  last_message: string;
  updated_at: string | null;
  unread_count: Record<string, number>;
  categorie?: string;
  pro_profile_id?: string;
  consumer_profile_id?: string;
  pinned_for: Record<string, boolean>;
  archived_for: Record<string, boolean>;
  muted_for: Record<string, number>;
  deleted_for: Record<string, boolean>;
  type: string;
}

interface Message {
  id: string;
  text: string | null;
  sender_id: string;
  created_at: string | null;
  is_read: boolean;
  image_url?: string | null;
  msg_type?: string;
  lat?: number | null;
  lng?: number | null;
}

interface UserInfo { name: string; avatar?: string }

function fmtTime(iso: string | null): string {
  if (!iso) return '';
  const d = new Date(iso);
  const now = new Date();
  if (d.toDateString() === now.toDateString())
    return d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  if (d.toDateString() === yesterday.toDateString()) return 'Hier';
  return d.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' });
}

function fmtDate(iso: string | null): string {
  if (!iso) return '';
  const d = new Date(iso);
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
  const [msgMenu, setMsgMenu] = useState<{ id: string; isMe: boolean } | null>(null);
  const [blockedUsers, setBlockedUsers] = useState<string[]>([]);
  const endRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const convChannelRef = useRef<RealtimeChannel | null>(null);
  const msgChannelRef = useRef<RealtimeChannel | null>(null);

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  // Bloquer les utilisateurs depuis Supabase
  useEffect(() => {
    if (!user) return;
    supabase.from('bloquages').select('blocked_uid').eq('uid', user.uid)
      .then(({ data }) => { if (data) setBlockedUsers(data.map((r: { blocked_uid: string }) => r.blocked_uid)); });
  }, [user]);

  // Profile IDs secondaires
  useEffect(() => {
    if (!user) return;
    supabase.from('user_profiles').select('id').eq('uid', user.uid)
      .then(({ data }) => { if (data) setUserProfileIds(data.map((r: { id: string }) => r.id)); });
  }, [user]);

  // Pré-sélectionner conversation via ?conv=
  useEffect(() => {
    const convId = searchParams.get('conv');
    if (convId) { setSelectedId(convId); setMobileView('thread'); }
  }, [searchParams]);

  // Nom/avatar depuis Supabase users
  const getUserInfo = useCallback(async (uid: string): Promise<UserInfo> => {
    if (userInfoCacheRef.current[uid]) return userInfoCacheRef.current[uid];
    try {
      const { data } = await supabase.from('users')
        .select('firstname, lastname, profile_picture_url, is_elevage, name_elevage')
        .eq('uid', uid).maybeSingle();
      if (data) {
        const isElevage = data.is_elevage === true;
        const name = isElevage && data.name_elevage
          ? data.name_elevage
          : `${data.firstname ?? ''} ${data.lastname ?? ''}`.trim() || 'Utilisateur';
        const info: UserInfo = { name, avatar: data.profile_picture_url ?? undefined };
        userInfoCacheRef.current[uid] = info;
        forceUpdate(n => n + 1);
        return info;
      }
    } catch { /* ignore */ }
    return { name: 'Utilisateur' };
  }, []);

  // Charger les conversations
  const loadConversations = useCallback(async () => {
    if (!user) return;
    const { data } = await supabase
      .from('conversations')
      .select('*')
      .filter('participants', 'cs', `["${user.uid}"]`)
      .eq('type', 'direct')
      .order('updated_at', { ascending: false });
    if (data) {
      const convs = data as Conversation[];
      setConversations(convs);
      for (const conv of convs) {
        const otherUid = conv.participants.find(p => p !== user.uid);
        if (otherUid && !userInfoCacheRef.current[otherUid]) getUserInfo(otherUid);
      }
    }
  }, [user, getUserInfo]);

  // Realtime conversations
  useEffect(() => {
    if (!user) return;
    loadConversations();
    convChannelRef.current?.unsubscribe();
    convChannelRef.current = supabase
      .channel('web_convs')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'conversations' }, () => {
        loadConversations();
      })
      .subscribe();
    return () => { convChannelRef.current?.unsubscribe(); };
  }, [user, loadConversations]);

  // Charger messages + Realtime
  useEffect(() => {
    if (!selectedId) { setMessages([]); return; }
    supabase.from('messages').select('*').eq('conversation_id', selectedId)
      .order('created_at').then(({ data }) => {
        if (data) {
          setMessages(data as Message[]);
          setTimeout(() => endRef.current?.scrollIntoView({ behavior: 'smooth' }), 50);
        }
      });
    msgChannelRef.current?.unsubscribe();
    msgChannelRef.current = supabase
      .channel(`web_msgs_${selectedId}`)
      .on('postgres_changes', {
        event: 'INSERT', schema: 'public', table: 'messages',
        filter: `conversation_id=eq.${selectedId}`,
      }, payload => {
        setMessages(prev => {
          if (prev.some(m => m.id === payload.new.id)) return prev;
          return [...prev, payload.new as Message];
        });
        setTimeout(() => endRef.current?.scrollIntoView({ behavior: 'smooth' }), 50);
      })
      .subscribe();
    return () => { msgChannelRef.current?.unsubscribe(); };
  }, [selectedId]);

  // Marquer comme lu
  useEffect(() => {
    if (!selectedId || !user) return;
    const conv = conversations.find(c => c.id === selectedId);
    if (conv && (conv.unread_count?.[user.uid] ?? 0) > 0) {
      const updated = { ...conv.unread_count, [user.uid]: 0 };
      supabase.from('conversations').update({ unread_count: updated }).eq('id', selectedId).then(() => {});
    }
  }, [selectedId, conversations, user]);

  // ── Actions Supabase ──────────────────────────────────────────────────────────

  async function togglePin(id: string, current: boolean) {
    if (!user) return;
    const conv = conversations.find(c => c.id === id);
    const pinned = { ...(conv?.pinned_for ?? {}), [user.uid]: !current };
    await supabase.from('conversations').update({ pinned_for: pinned }).eq('id', id);
    loadConversations();
  }

  async function toggleArchive(id: string, current: boolean) {
    if (!user) return;
    const conv = conversations.find(c => c.id === id);
    const archived = { ...(conv?.archived_for ?? {}), [user.uid]: !current };
    await supabase.from('conversations').update({ archived_for: archived }).eq('id', id);
    loadConversations();
  }

  async function toggleMute(id: string, current: boolean) {
    if (!user) return;
    const conv = conversations.find(c => c.id === id);
    const until = current ? 0 : Date.now() + 8 * 3600 * 1000;
    const muted = { ...(conv?.muted_for ?? {}), [user.uid]: until };
    await supabase.from('conversations').update({ muted_for: muted }).eq('id', id);
    loadConversations();
  }

  async function blockUser(otherId: string) {
    if (!user) return;
    await supabase.from('bloquages').upsert({ uid: user.uid, blocked_uid: otherId });
    setBlockedUsers(prev => [...prev, otherId]);
  }

  async function deleteConv(id: string) {
    if (!user) return;
    const conv = conversations.find(c => c.id === id);
    const deleted = { ...(conv?.deleted_for ?? {}), [user.uid]: true };
    await supabase.from('conversations').update({ deleted_for: deleted }).eq('id', id);
    if (selectedId === id) setSelectedId(null);
    loadConversations();
  }

  async function sendMessage() {
    if (!text.trim() || !selectedId || !user || sending) return;
    const msg = text.trim();
    setText('');
    setSending(true);
    try {
      await supabase.from('messages').insert({
        conversation_id: selectedId,
        sender_id: user.uid,
        text: msg,
        msg_type: 'text',
        is_read: false,
        ...(activeProfileId ? { sender_profile_id: activeProfileId } : {}),
      });
      const conv = conversations.find(c => c.id === selectedId);
      const unread = { ...(conv?.unread_count ?? {}) };
      for (const p of conv?.participants ?? []) {
        if (p !== user.uid) unread[p] = (unread[p] ?? 0) + 1;
      }
      await supabase.from('conversations').update({
        last_message: msg,
        updated_at: new Date().toISOString(),
        unread_count: unread,
        deleted_for: {},
      }).eq('id', selectedId);
    } finally {
      setSending(false);
      inputRef.current?.focus();
    }
  }

  async function deleteMessage(msgId: string) {
    await supabase.from('messages').delete().eq('id', msgId);
    setMessages(prev => prev.filter(m => m.id !== msgId));
    setMsgMenu(null);
  }

  if (loading || !user) {
    return (
      <div className="flex justify-center py-32">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  const myName = userData?.nameElevage ?? userData?.firstname ?? '';
  const totalUnread = conversations.reduce((s, c) => s + (c.unread_count?.[user.uid] ?? 0), 0);
  const selectedConv = conversations.find(c => c.id === selectedId);
  const otherUid = selectedConv?.participants.find(p => p !== user.uid);
  const otherInfo = otherUid ? (userInfoCacheRef.current[otherUid] ?? { name: '…' }) : null;

  const filteredConvs = conversations
    .filter(conv => {
      if (conv.deleted_for?.[user.uid]) return false;
      const others = conv.participants.filter(p => p !== user.uid);
      if (others.some(p => blockedUsers.includes(p))) return false;

      if (activeProfileId) {
        const isMePro      = conv.pro_profile_id === activeProfileId;
        const isMeConsumer = conv.consumer_profile_id === activeProfileId;
        const isUntagged   = !conv.pro_profile_id && !conv.consumer_profile_id;
        if (!isMePro && !isMeConsumer && !isUntagged) return false;
      } else {
        const proIsMyProfile      = conv.pro_profile_id && userProfileIds.includes(conv.pro_profile_id);
        const consumerIsMyProfile = conv.consumer_profile_id && userProfileIds.includes(conv.consumer_profile_id);
        if (proIsMyProfile || consumerIsMyProfile) return false;
      }

      const isArchived = conv.archived_for?.[user.uid] === true;
      if (activeCategory === '__archived__') return isArchived;
      if (isArchived) return false;

      if (activeCategory !== null) {
        if ((conv.categorie ?? null) !== activeCategory) return false;
      }

      if (!search) return true;
      const oUid = conv.participants.find(p => p !== user.uid);
      const oInfo = oUid ? userInfoCacheRef.current[oUid] : undefined;
      const oName = oInfo?.name ?? '';
      return oName.toLowerCase().includes(search.toLowerCase()) ||
        (conv.last_message ?? '').toLowerCase().includes(search.toLowerCase());
    })
    .sort((a, b) => {
      const ap = a.pinned_for?.[user.uid] === true;
      const bp = b.pinned_for?.[user.uid] === true;
      if (ap && !bp) return -1;
      if (!ap && bp) return 1;
      return new Date(b.updated_at ?? 0).getTime() - new Date(a.updated_at ?? 0).getTime();
    });

  return (
    <div className="h-[calc(100vh-64px)] flex bg-[#F8F8F6] overflow-hidden">

      {/* ── Sidebar ──────────────────────────────────────────────────────────── */}
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
                ? conversations.reduce((s, c) => s + (c.unread_count?.[user.uid] ?? 0), 0)
                : conversations
                    .filter(c => (c.categorie ?? null) === cat.key)
                    .reduce((s, c) => s + (c.unread_count?.[user.uid] ?? 0), 0);
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
              // Utiliser participants_info d'abord (plus rapide), puis le cache
              const infoFromConv = oUid ? conv.participants_info?.[oUid] : undefined;
              const oInfo = oUid
                ? (userInfoCacheRef.current[oUid] ?? { name: infoFromConv?.name ?? '…', avatar: infoFromConv?.photo })
                : { name: '…' };
              const rawUnread = conv.unread_count?.[user.uid] ?? 0;
              const isMuted = (conv.muted_for?.[user.uid] ?? 0) > Date.now();
              const unread = isMuted ? 0 : rawUnread;
              const isPinned = conv.pinned_for?.[user.uid] === true;
              const isSelected = conv.id === selectedId;
              return (
                <div
                  key={conv.id}
                  role="button"
                  tabIndex={0}
                  onClick={() => {
                    setSelectedId(conv.id);
                    setMobileView('thread');
                    setContextMenu(null);
                    if (oUid && !userInfoCacheRef.current[oUid]) getUserInfo(oUid);
                  }}
                  onKeyDown={e => { if (e.key === 'Enter') { setSelectedId(conv.id); setMobileView('thread'); }}}
                  onContextMenu={e => { e.preventDefault(); setContextMenu({ id: conv.id, x: e.clientX, y: e.clientY }); }}
                  className={`group w-full flex items-center gap-3 px-4 py-3.5 text-left hover:bg-gray-50 transition-colors relative cursor-pointer ${
                    isSelected ? 'bg-[#0C5C6C]/5' : isPinned ? 'bg-[#F0F9FF]' : ''
                  }`}>
                  {isSelected && <div className="absolute left-0 top-0 bottom-0 w-0.5 bg-[#0C5C6C]" />}
                  <div className="relative w-12 h-12 flex-shrink-0">
                    <div className="w-12 h-12 rounded-full bg-[#6E9E57] flex items-center justify-center overflow-hidden relative">
                      {oInfo.avatar ? (
                        <Image src={oInfo.avatar} alt="" fill className="object-cover" unoptimized />
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
                      <div className="flex items-center gap-1 flex-shrink-0">
                        <button
                          onClick={e => {
                            e.stopPropagation();
                            const rect = e.currentTarget.getBoundingClientRect();
                            setContextMenu({ id: conv.id, x: rect.left - 180, y: rect.bottom + 4 });
                          }}
                          className="opacity-0 group-hover:opacity-100 transition-opacity p-1 rounded-full hover:bg-gray-200 text-gray-400 hover:text-gray-600"
                          title="Actions">
                          <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                            <circle cx="12" cy="5" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="12" cy="19" r="1.5"/>
                          </svg>
                        </button>
                        <span className="text-xs text-gray-400 group-hover:opacity-0">{fmtTime(conv.updated_at)}</span>
                      </div>
                    </div>
                    <p className={`text-xs truncate ${unread > 0 ? 'text-gray-700 font-medium' : 'text-gray-400'}`}>
                      {conv.last_message ?? ''}
                    </p>
                    {conv.categorie && CAT_BADGE[conv.categorie] && (
                      <span className={`inline-block text-[10px] px-1.5 py-0.5 rounded-full font-medium mt-0.5 ${CAT_BADGE[conv.categorie].bg}`}>
                        {CAT_BADGE[conv.categorie].label}
                      </span>
                    )}
                  </div>
                </div>
              );
            })
          )}
        </div>
      </aside>

      {/* ── Thread ───────────────────────────────────────────────────────────── */}
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
                  <Image src={otherInfo.avatar} alt="" fill className="object-cover" unoptimized />
                ) : (
                  <span className="text-white font-bold">{(otherInfo?.name[0] ?? '?').toUpperCase()}</span>
                )}
              </div>
              <p className="font-semibold text-sm text-[#1F2A2E]">{otherInfo?.name ?? '…'}</p>
            </div>

            {/* Messages */}
            <div className="flex-1 overflow-y-auto px-3 py-4 space-y-1" onClick={() => setMsgMenu(null)}>
              {messages.length === 0 && (
                <p className="text-center text-gray-400 text-sm py-8">Commencez la conversation !</p>
              )}
              {msgMenu && (
                <div className="fixed inset-0 z-40" onClick={() => setMsgMenu(null)} />
              )}
              {messages.map((msg, i) => {
                const isMe = msg.sender_id === user.uid;
                const iso = msg.created_at;
                const prevIso = i > 0 ? messages[i - 1].created_at : null;
                const showDate = i === 0 || fmtDate(iso) !== fmtDate(prevIso);
                const isLocation = msg.msg_type === 'location';
                const isMenuOpen = msgMenu?.id === msg.id;

                const dotsButton = (side: 'left' | 'right') => (
                  <div className="relative flex-shrink-0 self-center" onClick={e => e.stopPropagation()}>
                    <button
                      onClick={() => setMsgMenu(isMenuOpen ? null : { id: msg.id, isMe })}
                      className="w-7 h-7 flex items-center justify-center rounded-full hover:bg-gray-200 text-gray-400 hover:text-gray-600 transition-all"
                    >
                      <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                        <circle cx="4" cy="10" r="1.5"/><circle cx="10" cy="10" r="1.5"/><circle cx="16" cy="10" r="1.5"/>
                      </svg>
                    </button>
                    {isMenuOpen && (
                      <div className={`absolute bottom-8 ${side === 'right' ? 'left-0' : 'right-0'} bg-white rounded-xl shadow-xl border border-gray-100 py-1 w-44 z-50`}>
                        {msg.text && (
                          <button
                            onClick={() => { navigator.clipboard.writeText(msg.text!); setMsgMenu(null); }}
                            className="w-full flex items-center gap-2.5 px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 text-left"
                          >
                            <span>📋</span>Copier
                          </button>
                        )}
                        {isMe && (
                          <button
                            onClick={() => deleteMessage(msg.id)}
                            className="w-full flex items-center gap-2.5 px-4 py-2 text-sm text-red-600 hover:bg-red-50 text-left"
                          >
                            <span>🗑️</span>Supprimer
                          </button>
                        )}
                      </div>
                    )}
                  </div>
                );

                return (
                  <div key={msg.id}>
                    {showDate && iso && (
                      <div className="flex justify-center my-3">
                        <span className="bg-gray-200 text-gray-500 text-xs px-3 py-1 rounded-full">{fmtDate(iso)}</span>
                      </div>
                    )}
                    <div className={`flex ${isMe ? 'justify-end' : 'justify-start'} items-end gap-1 mb-0.5`}>
                      {isMe && dotsButton('left')}
                      <div className={`max-w-[75%] rounded-2xl text-sm ${
                        isMe ? 'bg-[#0C5C6C] text-white rounded-br-md' : 'bg-white text-[#1F2A2E] shadow-sm rounded-bl-md'
                      } ${isLocation || msg.image_url ? 'p-1' : 'px-4 py-2.5'}`}>
                        {msg.image_url && (
                          <a href={msg.image_url} target="_blank" rel="noopener noreferrer">
                            <Image src={msg.image_url} alt="photo" width={200} height={200} className="rounded-xl object-cover" unoptimized />
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
                          <p className={`leading-relaxed ${(msg.image_url || isLocation) ? 'px-3 pt-2 pb-1' : ''}`}>{msg.text}</p>
                        )}
                        <p className={`text-[10px] mt-0.5 text-right ${isMe ? 'text-white/60' : 'text-gray-400'} ${(msg.image_url || isLocation) ? 'px-3 pb-1' : ''}`}>
                          {fmtTime(iso)}
                          {isMe && msg.is_read && ' · Vu'}
                        </p>
                      </div>
                      {!isMe && dotsButton('right')}
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

      {/* ── Context menu (right-click) ────────────────────────────────────────── */}
      {contextMenu && (() => {
        const conv = conversations.find(c => c.id === contextMenu.id);
        if (!conv) return null;
        const isPinned   = conv.pinned_for?.[user.uid] === true;
        const isArchived = conv.archived_for?.[user.uid] === true;
        const isMuted    = (conv.muted_for?.[user.uid] ?? 0) > Date.now();
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
                { icon: isMuted ? '🔔' : '🔕', label: isMuted ? 'Réactiver' : 'Sourdine (8h)', action: () => { toggleMute(contextMenu.id, isMuted); close(); } },
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
