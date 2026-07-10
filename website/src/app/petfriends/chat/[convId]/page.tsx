'use client';

import { useEffect, useState, useRef, useCallback } from 'react';
import { useParams, useRouter, useSearchParams } from 'next/navigation';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface Message {
  id: string;
  conversation_id: string;
  sender_id: string;
  text?: string;
  image_url?: string;
  msg_type?: string;
  created_at: string;
  is_read?: boolean;
}

interface ParticipantInfo {
  name: string;
  photo?: string;
}

function formatTime(iso: string) {
  const d = new Date(iso);
  const now = new Date();
  const sameDay = d.toDateString() === now.toDateString();
  return sameDay
    ? d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })
    : d.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' }) + ' ' +
      d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
}

export default function PetFriendChatWebPage() {
  const { convId } = useParams<{ convId: string }>();
  const searchParams = useSearchParams();
  const router = useRouter();
  const { user } = useAuth();
  const myUid = user?.uid ?? '';

  const convNom  = searchParams.get('nom')    || 'Discussion';
  const isGroupe = searchParams.get('groupe') === '1';

  const [messages, setMessages] = useState<Message[]>([]);
  const [participantsInfo, setParticipantsInfo] = useState<Record<string, ParticipantInfo>>({});
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);

  // ─── Chargement ──────────────────────────────────────────────────────────

  const loadMessages = useCallback(async () => {
    const { data: conv } = await supabase
      .from('conversations')
      .select('participants_info, unread_count')
      .eq('id', convId)
      .maybeSingle();

    if (conv?.participants_info) {
      setParticipantsInfo(conv.participants_info as Record<string, ParticipantInfo>);
    }

    const { data: msgs } = await supabase
      .from('messages')
      .select('*')
      .eq('conversation_id', convId)
      .order('created_at');

    setMessages((msgs ?? []) as Message[]);
    scrollBottom();

    // Marquer comme lus
    if (conv?.unread_count && (conv.unread_count as Record<string, number>)[myUid] > 0) {
      const updated = { ...(conv.unread_count as Record<string, number>), [myUid]: 0 };
      await supabase.from('conversations').update({ unread_count: updated }).eq('id', convId);
    }
  }, [convId, myUid]);

  useEffect(() => {
    if (!myUid || !convId) return;
    loadMessages();

    // Realtime
    const channel = supabase
      .channel(`web_chat_${convId}`)
      .on('postgres_changes', {
        event: 'INSERT', schema: 'public', table: 'messages',
        filter: `conversation_id=eq.${convId}`,
      }, (payload) => {
        const msg = payload.new as Message;
        setMessages(prev => {
          if (prev.some(m => m.id === msg.id)) return prev;
          return [...prev, msg];
        });
        scrollBottom();
        if (msg.sender_id !== myUid) {
          supabase.from('conversations').select('unread_count').eq('id', convId).maybeSingle()
            .then(({ data }) => {
              if (data?.unread_count) {
                const updated = { ...(data.unread_count as Record<string, number>), [myUid]: 0 };
                supabase.from('conversations').update({ unread_count: updated }).eq('id', convId);
              }
            });
        }
      })
      .subscribe();

    return () => { channel.unsubscribe(); };
  }, [myUid, convId, loadMessages]);

  function scrollBottom() {
    setTimeout(() => bottomRef.current?.scrollIntoView({ behavior: 'smooth' }), 50);
  }

  // ─── Envoi ───────────────────────────────────────────────────────────────

  async function send() {
    const t = text.trim();
    if (!t || !myUid) return;
    setSending(true);
    try {
      await supabase.from('messages').insert({
        conversation_id: convId,
        sender_id: myUid,
        text: t,
        msg_type: 'text',
        is_read: false,
      });

      // Mettre à jour la conversation
      const { data: conv } = await supabase
        .from('conversations')
        .select('participants, unread_count, participants_info')
        .eq('id', convId)
        .maybeSingle();

      if (conv) {
        const members = (conv.participants as string[]) ?? [];
        const unread = { ...(conv.unread_count as Record<string, number>) };
        for (const uid of members) if (uid !== myUid) unread[uid] = (unread[uid] ?? 0) + 1;

        // Enrichir participants_info si mon nom manque
        const info = { ...(conv.participants_info as Record<string, ParticipantInfo> ?? {}) };
        if (!info[myUid]) {
          const { data: me } = await supabase.from('user_profiles')
            .select('firstname, lastname, profile_picture_url:avatar_url').eq('uid', myUid).eq('is_main', true).maybeSingle();
          if (me) {
            const myName = `${me.firstname ?? ''} ${me.lastname ?? ''}`.trim() || 'Utilisateur';
            info[myUid] = { name: myName, ...(me.profile_picture_url ? { photo: me.profile_picture_url } : {}) };
            setParticipantsInfo(info);
          }
        }

        await supabase.from('conversations').update({
          last_message: t,
          updated_at: new Date().toISOString(),
          unread_count: unread,
          participants_info: info,
        }).eq('id', convId);
      }

      setText('');
    } finally {
      setSending(false);
    }
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  return (
    <div className="flex flex-col h-screen bg-[#F5F7F5]">
      {/* AppBar */}
      <div className="bg-[#2E7D5E] text-white px-4 py-3 flex items-center gap-3 shadow-sm shrink-0">
        <button onClick={() => router.back()} className="text-white/80 hover:text-white">←</button>
        <div className="w-8 h-8 rounded-full bg-white/20 flex items-center justify-center shrink-0">
          <span>{isGroupe ? '👥' : '👤'}</span>
        </div>
        <span className="font-bold text-[15px] truncate flex-1" style={{ fontFamily: 'Galey, sans-serif' }}>
          {convNom}
        </span>
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto px-3 py-4 flex flex-col gap-2">
        {messages.length === 0 ? (
          <div className="flex-1 flex items-center justify-center">
            <p className="text-gray-400 text-[14px]" style={{ fontFamily: 'Galey, sans-serif' }}>
              Aucun message, dites bonjour 👋
            </p>
          </div>
        ) : messages.map(msg => {
          const isMe = msg.sender_id === myUid;
          const senderInfo = participantsInfo[msg.sender_id];
          return (
            <div key={msg.id} className={`flex gap-2 items-end ${isMe ? 'flex-row-reverse' : 'flex-row'}`}>
              {/* Avatar groupe */}
              {!isMe && isGroupe && (
                senderInfo?.photo ? (
                  <Image src={senderInfo.photo} alt="" width={28} height={28}
                    className="rounded-full object-cover shrink-0" />
                ) : (
                  <div className="w-7 h-7 rounded-full bg-[#E8F5E9] flex items-center justify-center shrink-0">
                    <span className="text-[#2E7D5E] text-xs">👤</span>
                  </div>
                )
              )}

              <div className={`flex flex-col gap-0.5 max-w-[72%] ${isMe ? 'items-end' : 'items-start'}`}>
                {/* Nom expéditeur groupe */}
                {!isMe && isGroupe && senderInfo?.name && (
                  <span className="text-[11px] font-semibold text-[#2E7D5E] px-1">
                    {senderInfo.name}
                  </span>
                )}

                {msg.image_url ? (
                  <Image src={msg.image_url} alt="photo" width={200} height={200}
                    className="rounded-2xl object-cover" style={{ maxWidth: 200, maxHeight: 200 }} />
                ) : (
                  <div className={`px-3.5 py-2.5 rounded-2xl text-[14px] break-words
                    ${isMe
                      ? 'bg-[#0C5C6C] text-white rounded-br-sm'
                      : 'bg-[#E8F5E9] text-[#1F2A2E] rounded-bl-sm'}`}
                    style={{ fontFamily: 'Galey, sans-serif' }}>
                    {msg.text}
                  </div>
                )}

                <span className="text-[10px] text-gray-400 px-1">
                  {formatTime(msg.created_at)}
                </span>
              </div>
            </div>
          );
        })}
        <div ref={bottomRef} />
      </div>

      {/* Barre de saisie */}
      <div className="bg-white border-t border-gray-100 px-3 py-2.5 flex items-end gap-2 shrink-0">
        <textarea
          value={text}
          onChange={e => setText(e.target.value)}
          onKeyDown={e => {
            if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); }
          }}
          rows={1}
          placeholder="Votre message…"
          className="flex-1 resize-none border border-gray-200 rounded-xl px-3 py-2 text-[14px] focus:outline-none focus:border-[#2E7D5E] max-h-28"
          style={{ fontFamily: 'Galey, sans-serif', minHeight: 40 }}
        />
        <button
          onClick={send}
          disabled={sending || !text.trim()}
          className="shrink-0 w-10 h-10 rounded-full bg-[#2E7D5E] flex items-center justify-center disabled:opacity-40"
        >
          {sending ? (
            <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
          ) : (
            <svg width="18" height="18" viewBox="0 0 24 24" fill="white">
              <path d="M2 21l21-9L2 3v7l15 2-15 2z"/>
            </svg>
          )}
        </button>
      </div>
    </div>
  );
}
