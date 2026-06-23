'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface FriendRow {
  relId: string;
  uid: string;
  statut: string;
  direction: 'sent' | 'received';
  firstname?: string;
  lastname?: string;
  photoUrl?: string;
  city?: string;
}

interface SearchUser {
  uid: string;
  firstname?: string;
  lastname?: string;
  profile_picture_url?: string;
  city?: string;
}

function Avatar({ url, name, size = 48 }: { url?: string; name?: string; size?: number }) {
  return url ? (
    <Image src={url} alt={name ?? ''} width={size} height={size}
      className="rounded-full object-cover shrink-0" style={{ width: size, height: size }} />
  ) : (
    <div className="rounded-full bg-[#E8F5E9] flex items-center justify-center shrink-0"
      style={{ width: size, height: size }}>
      <span className="text-[#2E7D5E]" style={{ fontSize: size * 0.4 }}>👤</span>
    </div>
  );
}

export default function PetFriendsPage() {
  const { user } = useAuth();
  const myUid = user?.uid ?? '';
  const router = useRouter();
  const [tab, setTab] = useState<'friends' | 'requests'>('friends');

  const [friends, setFriends] = useState<FriendRow[]>([]);
  const [received, setReceived] = useState<FriendRow[]>([]);
  const [sent, setSent] = useState<FriendRow[]>([]);
  const [loading, setLoading] = useState(true);

  // Search — tous les users chargés une fois
  const [allUsers, setAllUsers] = useState<SearchUser[]>([]);
  const [loadingUsers, setLoadingUsers] = useState(true);
  const [searchVal, setSearchVal] = useState('');
  const [searchResults, setSearchResults] = useState<SearchUser[]>([]);
  const [searchStatuts, setSearchStatuts] = useState<Record<string, string | null>>({});

  async function load() {
    if (!myUid) return;
    setLoading(true);
    try {
      const { data: sentRels } = await supabase.from('petfriends')
        .select('id, uid_recepteur, statut').eq('uid_demandeur', myUid);
      const { data: recvRels } = await supabase.from('petfriends')
        .select('id, uid_demandeur, statut').eq('uid_recepteur', myUid);

      const byUid: Record<string, { id: string; statut: string; dir: 'sent' | 'received'; other: string }> = {};
      for (const r of sentRels ?? []) byUid[r.uid_recepteur] = { id: r.id, statut: r.statut, dir: 'sent', other: r.uid_recepteur };
      for (const r of recvRels ?? []) if (!byUid[r.uid_demandeur]) byUid[r.uid_demandeur] = { id: r.id, statut: r.statut, dir: 'received', other: r.uid_demandeur };

      const uids = Object.keys(byUid);
      if (uids.length === 0) { setFriends([]); setReceived([]); setSent([]); setLoading(false); return; }

      const { data: profiles } = await supabase.from('users')
        .select('uid, firstname, lastname, profile_picture_url, city')
        .in('uid', uids);
      const profMap: Record<string, { firstname?: string; lastname?: string; profile_picture_url?: string; city?: string }> = {};
      for (const p of profiles ?? []) profMap[p.uid] = p;

      const fr: FriendRow[] = [], rc: FriendRow[] = [], sn: FriendRow[] = [];
      for (const [uid, rel] of Object.entries(byUid)) {
        const prof = profMap[uid];
        if (!prof) continue;
        const row: FriendRow = {
          relId: rel.id, uid, statut: rel.statut, direction: rel.dir,
          firstname: prof.firstname, lastname: prof.lastname,
          photoUrl: prof.profile_picture_url, city: prof.city,
        };
        if (rel.statut === 'accepte') fr.push(row);
        else if (rel.dir === 'received') rc.push(row);
        else sn.push(row);
      }
      setFriends(fr); setReceived(rc); setSent(sn);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { load(); }, [myUid]);

  useEffect(() => {
    if (!myUid) return;
    supabase.from('users').select('uid, firstname, lastname, profile_picture_url, city')
      .neq('uid', myUid).limit(500)
      .then(({ data }) => { setAllUsers((data ?? []) as SearchUser[]); setLoadingUsers(false); });
  }, [myUid]);

  function onSearchChange(val: string) {
    setSearchVal(val);
    const q = val.toLowerCase().trim();
    if (q.length < 2) { setSearchResults([]); return; }
    const filtered = allUsers.filter(u =>
      `${u.firstname ?? ''} ${u.lastname ?? ''}`.toLowerCase().includes(q)
    ).slice(0, 20);
    // Statuts depuis les relations déjà chargées
    const statuts: Record<string, string | null> = {};
    for (const u of filtered) {
      const isFriend = friends.some(f => f.uid === u.uid);
      const isPending = received.some(f => f.uid === u.uid) || sent.some(f => f.uid === u.uid);
      statuts[u.uid] = isFriend ? 'accepte' : isPending ? 'en_attente' : null;
    }
    setSearchResults(filtered); setSearchStatuts(statuts);
  }

  async function sendRequest(targetUid: string) {
    await supabase.from('petfriends').insert({
      uid_demandeur: myUid, uid_recepteur: targetUid,
      statut: 'en_attente', created_at: new Date().toISOString(), updated_at: new Date().toISOString(),
    });
    const { data: me } = await supabase.from('users').select('firstname, lastname').eq('uid', myUid).maybeSingle();
    const nom = me ? `${me.firstname ?? ''} ${me.lastname ?? ''}`.trim() || 'Quelqu\'un' : 'Quelqu\'un';
    await supabase.from('notifications').insert({
      uid: targetUid, type: 'petfriend_request',
      title: '🐾 Nouvelle demande PetFriend',
      body: `${nom} veut être ton PetFriend !`,
      data: { fromUid: myUid }, read: false, created_at: new Date().toISOString(),
    });
    setSearchStatuts(s => ({ ...s, [targetUid]: 'en_attente' }));
  }

  async function accept(row: FriendRow) {
    await supabase.from('petfriends').update({ statut: 'accepte', updated_at: new Date().toISOString() }).eq('id', row.relId);
    const { data: me } = await supabase.from('users').select('firstname, lastname').eq('uid', myUid).maybeSingle();
    const nom = me ? `${me.firstname ?? ''} ${me.lastname ?? ''}`.trim() || 'Quelqu\'un' : 'Quelqu\'un';
    await supabase.from('notifications').insert({
      uid: row.uid, type: 'petfriend_accepted',
      title: '🐾 PetFriend accepté !',
      body: `${nom} a accepté ta demande PetFriend.`,
      data: { fromUid: myUid }, read: false, created_at: new Date().toISOString(),
    });
    load();
  }

  async function decline(row: FriendRow) {
    await supabase.from('petfriends').delete().eq('id', row.relId);
    load();
  }

  const pendingCount = received.length;
  const fullName = (f: FriendRow | SearchUser) =>
    `${'firstname' in f ? f.firstname ?? '' : ''} ${'lastname' in f ? f.lastname ?? '' : ''}`.trim() || '—';

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-[#2E7D5E] text-white px-4 pt-4 shadow-sm">
        <div className="flex items-center gap-3 pb-3">
          <button onClick={() => router.back()} className="text-white/80 hover:text-white shrink-0">←</button>
          <h1 className="font-bold text-base" style={{ fontFamily: 'Galey, sans-serif' }}>Mes PetFriends</h1>
        </div>
        <div className="flex border-b border-white/20">
          {(['friends', 'requests'] as const).map(t => (
            <button key={t} onClick={() => setTab(t)}
              className={`flex-1 pb-2.5 text-[13px] font-semibold transition-all ${tab === t ? 'border-b-2 border-[#EF6C00] text-white' : 'text-white/60'}`}
              style={{ fontFamily: 'Galey, sans-serif' }}>
              {t === 'friends' ? `Amis (${friends.length})` : (
                <span className="flex items-center justify-center gap-1.5">
                  Demandes
                  {pendingCount > 0 && (
                    <span className="bg-[#EF6C00] text-white text-[10px] font-bold w-4 h-4 rounded-full flex items-center justify-center">
                      {pendingCount}
                    </span>
                  )}
                </span>
              )}
            </button>
          ))}
        </div>
      </div>

      <div className="max-w-lg mx-auto px-4 py-4">
        {loading ? (
          <div className="flex justify-center py-12">
            <div className="w-8 h-8 border-2 border-[#2E7D5E] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : tab === 'friends' ? (
          <>
            {/* Recherche */}
            <div className="relative mb-4">
              <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400">🔍</span>
              <input value={searchVal} onChange={e => onSearchChange(e.target.value)}
                placeholder="Rechercher un utilisateur…"
                className="w-full pl-9 pr-4 py-2.5 border border-gray-200 rounded-xl bg-white text-[14px] focus:outline-none focus:border-[#2E7D5E]"
                style={{ fontFamily: 'Galey, sans-serif' }} />
              {searchVal && (
                <button onClick={() => { setSearchVal(''); setSearchResults([]); }}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400">✕</button>
              )}
            </div>

            {searchVal.trim().length >= 2 ? (
              loadingUsers ? (
                <div className="flex justify-center py-8">
                  <div className="w-6 h-6 border-2 border-[#2E7D5E] border-t-transparent rounded-full animate-spin" />
                </div>
              ) : searchResults.length === 0 ? (
                <p className="text-center text-gray-400 py-8 text-[14px]">Aucun résultat</p>
              ) : (
                <div className="flex flex-col gap-3">
                  {searchResults.map(u => {
                    const statut = searchStatuts[u.uid];
                    return (
                      <div key={u.uid} className="bg-white rounded-xl p-3 shadow-sm flex items-center gap-3 cursor-pointer"
                        onClick={() => router.push(`/profil/${u.uid}`)}>
                        <Avatar url={u.profile_picture_url} name={u.firstname} size={44} />
                        <div className="flex-1 min-w-0">
                          <p className="font-bold text-[14px] truncate" style={{ fontFamily: 'Galey, sans-serif' }}>{fullName(u)}</p>
                          {u.city && <p className="text-[12px] text-gray-400 truncate">{u.city}</p>}
                        </div>
                        <div onClick={e => e.stopPropagation()}>
                          {statut === 'accepte' ? (
                            <span className="text-[12px] font-semibold text-[#2E7D5E] bg-[#E8F5E9] px-2.5 py-1 rounded-full">✓ PetFriend</span>
                          ) : statut === 'en_attente' ? (
                            <span className="text-[11px] font-semibold text-amber-700 bg-amber-50 border border-amber-200 px-2.5 py-1 rounded-full">⏳ En attente</span>
                          ) : (
                            <button onClick={() => sendRequest(u.uid)}
                              className="text-[12px] font-bold text-white px-3 py-1.5 rounded-full"
                              style={{ backgroundColor: '#2E7D5E' }}>
                              + Ajouter
                            </button>
                          )}
                        </div>
                      </div>
                    );
                  })}
                </div>
              )
            ) : friends.length === 0 ? (
              <div className="flex flex-col items-center gap-3 py-16 text-center">
                <span className="text-6xl">👥</span>
                <p className="text-gray-500 text-[15px]" style={{ fontFamily: 'Galey, sans-serif' }}>Vous n&apos;avez pas encore de PetFriends</p>
                <p className="text-gray-400 text-[13px]">Recherchez des utilisateurs pour commencer</p>
              </div>
            ) : (
              <div className="flex flex-col gap-3">
                {friends.map(f => (
                  <div key={f.relId} onClick={() => router.push(`/profil/${f.uid}`)}
                    className="bg-white rounded-xl p-3 shadow-sm flex items-center gap-3 cursor-pointer hover:bg-gray-50">
                    <Avatar url={f.photoUrl} name={f.firstname} size={44} />
                    <div className="flex-1 min-w-0">
                      <p className="font-bold text-[14px] truncate" style={{ fontFamily: 'Galey, sans-serif' }}>{fullName(f)}</p>
                      {f.city && <p className="text-[12px] text-gray-400 truncate">{f.city}</p>}
                    </div>
                    <span className="text-gray-300">›</span>
                  </div>
                ))}
              </div>
            )}
          </>
        ) : (
          // Onglet Demandes
          <>
            {received.length === 0 && sent.length === 0 ? (
              <div className="flex flex-col items-center gap-3 py-16 text-center">
                <span className="text-6xl">🔍</span>
                <p className="text-gray-500 text-[15px]" style={{ fontFamily: 'Galey, sans-serif' }}>Aucune demande en cours</p>
              </div>
            ) : (
              <div className="flex flex-col gap-6">
                {received.length > 0 && (
                  <div>
                    <h3 className="font-bold text-[14px] mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>Reçues</h3>
                    <div className="flex flex-col gap-3">
                      {received.map(r => (
                        <div key={r.relId} className="bg-white rounded-xl p-3 shadow-sm">
                          <div className="flex items-center gap-3 cursor-pointer mb-3" onClick={() => router.push(`/profil/${r.uid}`)}>
                            <Avatar url={r.photoUrl} name={r.firstname} size={44} />
                            <div className="flex-1 min-w-0">
                              <p className="font-bold text-[14px] truncate" style={{ fontFamily: 'Galey, sans-serif' }}>{fullName(r)}</p>
                              {r.city && <p className="text-[12px] text-gray-400 truncate">{r.city}</p>}
                            </div>
                          </div>
                          <div className="flex gap-2">
                            <button onClick={() => accept(r)}
                              className="flex-1 py-2 rounded-xl font-bold text-white text-[13px]"
                              style={{ backgroundColor: '#2E7D5E', fontFamily: 'Galey, sans-serif' }}>
                              Accepter
                            </button>
                            <button onClick={() => decline(r)}
                              className="flex-1 py-2 rounded-xl font-bold text-red-500 border border-red-300 text-[13px]"
                              style={{ fontFamily: 'Galey, sans-serif' }}>
                              Refuser
                            </button>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
                {sent.length > 0 && (
                  <div>
                    <h3 className="font-bold text-[14px] mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>Envoyées</h3>
                    <div className="flex flex-col gap-3">
                      {sent.map(s => (
                        <div key={s.relId} onClick={() => router.push(`/profil/${s.uid}`)}
                          className="bg-white rounded-xl p-3 shadow-sm flex items-center gap-3 cursor-pointer">
                          <Avatar url={s.photoUrl} name={s.firstname} size={44} />
                          <div className="flex-1 min-w-0">
                            <p className="font-bold text-[14px] truncate" style={{ fontFamily: 'Galey, sans-serif' }}>{fullName(s)}</p>
                            {s.city && <p className="text-[12px] text-gray-400 truncate">{s.city}</p>}
                          </div>
                          <span className="text-[11px] font-semibold text-amber-700 bg-amber-50 border border-amber-200 px-2.5 py-1 rounded-full shrink-0">
                            ⏳ En attente
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
