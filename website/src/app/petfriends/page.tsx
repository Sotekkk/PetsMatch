'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

interface FriendRow {
  relId: string;
  uid: string;
  statut: string;
  direction: 'sent' | 'received';
  firstname?: string;
  lastname?: string;
  photoUrl?: string;
  ville?: string;
}

interface SearchUser {
  uid: string;
  firstname?: string;
  lastname?: string;
  profile_picture_url?: string;
  ville?: string;
}

interface ConvRow {
  id: string;
  nom?: string;
  last_message?: string;
  updated_at?: string;
  participants?: string[];
  unread_count?: Record<string, number>;
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
  const activeProfileId = useActiveProfile();
  const router = useRouter();
  const [tab, setTab] = useState<'friends' | 'requests' | 'groupes'>('friends');

  const [friends, setFriends] = useState<FriendRow[]>([]);
  const [received, setReceived] = useState<FriendRow[]>([]);
  const [sent, setSent] = useState<FriendRow[]>([]);
  const [loading, setLoading] = useState(true);

  // Groupes
  const [groupes, setGroupes] = useState<ConvRow[]>([]);
  const [loadingGroupes, setLoadingGroupes] = useState(false);
  const [showCreateGroupe, setShowCreateGroupe] = useState(false);
  const [newGroupeNom, setNewGroupeNom] = useState('');
  const [selectedGroupeUids, setSelectedGroupeUids] = useState<Set<string>>(new Set());
  const [creatingGroupe, setCreatingGroupe] = useState(false);

  // Search
  const [allUsers, setAllUsers] = useState<SearchUser[]>([]);
  const [loadingUsers, setLoadingUsers] = useState(true);
  const [searchVal, setSearchVal] = useState('');
  const [searchResults, setSearchResults] = useState<SearchUser[]>([]);
  const [searchStatuts, setSearchStatuts] = useState<Record<string, string | null>>({});

  // ─── Chargement amis ────────────────────────────────────────────────────

  const load = useCallback(async () => {
    if (!myUid) return;
    setLoading(true);
    try {
      const { data: sentRels } = await supabase.from('petfriends')
        .select('id, uid_recepteur, statut').eq('uid_demandeur', myUid);
      const { data: recvRels } = await supabase.from('petfriends')
        .select('id, uid_demandeur, statut').eq('uid_recepteur', myUid);

      const byUid: Record<string, { id: string; statut: string; dir: 'sent' | 'received' }> = {};
      for (const r of sentRels ?? []) byUid[r.uid_recepteur] = { id: r.id, statut: r.statut, dir: 'sent' };
      for (const r of recvRels ?? []) if (!byUid[r.uid_demandeur]) byUid[r.uid_demandeur] = { id: r.id, statut: r.statut, dir: 'received' };

      const uids = Object.keys(byUid);
      if (uids.length === 0) { setFriends([]); setReceived([]); setSent([]); return; }

      const { data: profiles } = await supabase.from('users')
        .select('uid, firstname, lastname, profile_picture_url, ville').in('uid', uids);
      const profMap: Record<string, { firstname?: string; lastname?: string; profile_picture_url?: string; ville?: string }> = {};
      for (const p of profiles ?? []) profMap[p.uid] = p;

      const fr: FriendRow[] = [], rc: FriendRow[] = [], sn: FriendRow[] = [];
      for (const [uid, rel] of Object.entries(byUid)) {
        const prof = profMap[uid];
        if (!prof) continue;
        const row: FriendRow = {
          relId: rel.id, uid, statut: rel.statut, direction: rel.dir,
          firstname: prof.firstname, lastname: prof.lastname,
          photoUrl: prof.profile_picture_url, ville: prof.ville,
        };
        if (rel.statut === 'accepte') fr.push(row);
        else if (rel.dir === 'received') rc.push(row);
        else sn.push(row);
      }
      setFriends(fr); setReceived(rc); setSent(sn);
    } finally {
      setLoading(false);
    }
  }, [myUid]);

  // ─── Chargement groupes ──────────────────────────────────────────────────

  const loadGroupes = useCallback(async () => {
    if (!myUid) return;
    setLoadingGroupes(true);
    try {
      const { data } = await supabase
        .from('conversations')
        .select('id, nom, last_message, updated_at, participants, unread_count')
        .eq('type', 'groupe')
        .filter('participants', 'cs', `["${myUid}"]`)
        .order('updated_at', { ascending: false });
      setGroupes((data ?? []) as ConvRow[]);
    } finally {
      setLoadingGroupes(false);
    }
  }, [myUid]);

  useEffect(() => { load(); }, [load]);
  useEffect(() => { if (tab === 'groupes') loadGroupes(); }, [tab, loadGroupes]);

  useEffect(() => {
    if (!myUid) return;
    supabase.from('users').select('uid, firstname, lastname, profile_picture_url, ville')
      .neq('uid', myUid).limit(500)
      .then(({ data }) => { setAllUsers((data ?? []) as SearchUser[]); setLoadingUsers(false); });
  }, [myUid]);

  // Realtime groupes
  useEffect(() => {
    if (!myUid) return;
    const ch = supabase.channel('web_pf_groupes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'conversations' }, () => {
        if (tab === 'groupes') loadGroupes();
      })
      .subscribe();
    return () => { ch.unsubscribe(); };
  }, [myUid, tab, loadGroupes]);

  // ─── Actions recherche ───────────────────────────────────────────────────

  function onSearchChange(val: string) {
    setSearchVal(val);
    const q = val.toLowerCase().trim();
    if (q.length < 2) { setSearchResults([]); return; }
    const filtered = allUsers.filter(u =>
      `${u.firstname ?? ''} ${u.lastname ?? ''}`.toLowerCase().includes(q)
    ).slice(0, 20);
    const statuts: Record<string, string | null> = {};
    for (const u of filtered) {
      statuts[u.uid] = friends.some(f => f.uid === u.uid) ? 'accepte'
        : (received.some(f => f.uid === u.uid) || sent.some(f => f.uid === u.uid)) ? 'en_attente' : null;
    }
    setSearchResults(filtered); setSearchStatuts(statuts);
  }

  async function sendRequest(targetUid: string) {
    const myPid = activeProfileId || null;
    let tgPid: string | null = null;
    if (targetUid) {
      const { data: tgRow } = await supabase.from('user_profiles').select('id').eq('uid', targetUid).eq('is_main', true).maybeSingle();
      tgPid = tgRow?.id ?? null;
    }
    await supabase.from('petfriends').insert({
      uid_demandeur: myUid,
      ...(myPid ? { demandeur_profile_id: myPid } : {}),
      uid_recepteur: targetUid,
      ...(tgPid ? { recepteur_profile_id: tgPid } : {}),
      statut: 'en_attente', created_at: new Date().toISOString(), updated_at: new Date().toISOString(),
    });
    const { data: me } = await supabase.from('users').select('firstname, lastname').eq('uid', myUid).maybeSingle();
    const nom = me ? `${me.firstname ?? ''} ${me.lastname ?? ''}`.trim() || 'Quelqu\'un' : 'Quelqu\'un';
    await supabase.from('notifications').insert({
      uid: targetUid, type: 'petfriend_request',
      title: '🐾 Nouvelle demande PetFriend', body: `${nom} veut être ton PetFriend !`,
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
      title: '🐾 PetFriend accepté !', body: `${nom} a accepté ta demande PetFriend.`,
      data: { fromUid: myUid }, read: false, created_at: new Date().toISOString(),
    });
    load();
  }

  async function decline(row: FriendRow) {
    await supabase.from('petfriends').delete().eq('id', row.relId);
    load();
  }

  // ─── Ouvrir DM ──────────────────────────────────────────────────────────

  async function openDm(friendRow: FriendRow) {
    const sorted = [myUid, friendRow.uid].sort().join('_');
    const { data: existing } = await supabase
      .from('conversations')
      .select('id')
      .eq('participant_ids', sorted)
      .or('type.eq.direct,type.is.null')
      .maybeSingle();

    let convId: string;
    if (existing) {
      convId = existing.id;
    } else {
      const { data: otherData } = await supabase.from('users')
        .select('firstname, lastname, profile_picture_url').eq('uid', friendRow.uid).maybeSingle();
      const { data: myData } = await supabase.from('users')
        .select('firstname, lastname, profile_picture_url').eq('uid', myUid).maybeSingle();
      const myName    = `${myData?.firstname ?? ''} ${myData?.lastname ?? ''}`.trim() || 'Utilisateur';
      const otherName = `${otherData?.firstname ?? ''} ${otherData?.lastname ?? ''}`.trim() || 'Utilisateur';
      const participantsInfo: Record<string, unknown> = {
        [myUid]: { name: myName, ...(myData?.profile_picture_url ? { photo: myData.profile_picture_url } : {}) },
        [friendRow.uid]: { name: otherName, ...(otherData?.profile_picture_url ? { photo: otherData.profile_picture_url } : {}) },
      };
      const { data: created } = await supabase.from('conversations').insert({
        type: 'direct',
        participants: [myUid, friendRow.uid],
        participant_ids: sorted,
        participants_info: participantsInfo,
        last_message: '',
        unread_count: { [myUid]: 0, [friendRow.uid]: 0 },
        updated_at: new Date().toISOString(),
      }).select('id').single();
      convId = created!.id;
    }

    const name = `${friendRow.firstname ?? ''} ${friendRow.lastname ?? ''}`.trim();
    router.push(`/petfriends/chat/${convId}?nom=${encodeURIComponent(name)}`);
  }

  // ─── Créer groupe ────────────────────────────────────────────────────────

  async function createGroupe() {
    const nom = newGroupeNom.trim();
    if (!nom) return;
    setCreatingGroupe(true);
    try {
      const members = [myUid, ...selectedGroupeUids];
      const { data: myData } = await supabase.from('users')
        .select('firstname, lastname, profile_picture_url').eq('uid', myUid).maybeSingle();
      const myName = `${myData?.firstname ?? ''} ${myData?.lastname ?? ''}`.trim() || 'Utilisateur';
      const participantsInfo: Record<string, unknown> = {
        [myUid]: { name: myName, ...(myData?.profile_picture_url ? { photo: myData.profile_picture_url } : {}) },
      };
      // Infos des autres membres
      if (selectedGroupeUids.size > 0) {
        const { data: others } = await supabase.from('users')
          .select('uid, firstname, lastname, profile_picture_url').in('uid', [...selectedGroupeUids]);
        for (const o of others ?? []) {
          const oName = `${o.firstname ?? ''} ${o.lastname ?? ''}`.trim() || 'Utilisateur';
          participantsInfo[o.uid] = { name: oName, ...(o.profile_picture_url ? { photo: o.profile_picture_url } : {}) };
        }
      }
      const unread: Record<string, number> = {};
      for (const uid of members) unread[uid] = 0;

      const { data: conv } = await supabase.from('conversations').insert({
        type: 'groupe', nom,
        participants: members,
        participant_ids: members.join(','),
        created_by: myUid,
        participants_info: participantsInfo,
        last_message: '',
        unread_count: unread,
        updated_at: new Date().toISOString(),
      }).select('id').single();

      setShowCreateGroupe(false);
      setNewGroupeNom('');
      setSelectedGroupeUids(new Set());
      if (conv) router.push(`/petfriends/chat/${conv.id}?nom=${encodeURIComponent(nom)}&groupe=1`);
      else loadGroupes();
    } finally {
      setCreatingGroupe(false);
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  const fullName = (f: FriendRow | SearchUser) =>
    `${('firstname' in f ? f.firstname : '') ?? ''} ${('lastname' in f ? f.lastname : '') ?? ''}`.trim() || '—';

  const pendingCount = received.length;

  // ─── UI ──────────────────────────────────────────────────────────────────

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-[#2E7D5E] text-white px-4 pt-4 shadow-sm">
        <div className="flex items-center gap-3 pb-3">
          <button onClick={() => router.back()} className="text-white/80 hover:text-white shrink-0">←</button>
          <h1 className="font-bold text-base" style={{ fontFamily: 'Galey, sans-serif' }}>Mes PetFriends</h1>
        </div>
        <div className="flex border-b border-white/20">
          {(['friends', 'requests', 'groupes'] as const).map(t => (
            <button key={t} onClick={() => setTab(t)}
              className={`flex-1 pb-2.5 text-[13px] font-semibold transition-all ${tab === t ? 'border-b-2 border-[#EF6C00] text-white' : 'text-white/60'}`}
              style={{ fontFamily: 'Galey, sans-serif' }}>
              {t === 'friends' ? `Amis (${friends.length})` : t === 'groupes' ? 'Groupes' : (
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
        {/* ── Amis ── */}
        {tab === 'friends' && (
          loading ? <Spinner /> : (
            <>
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
                loadingUsers ? <Spinner /> : searchResults.length === 0 ? (
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
                            {u.ville && <p className="text-[12px] text-gray-400 truncate">{u.ville}</p>}
                          </div>
                          <div onClick={e => e.stopPropagation()}>
                            {statut === 'accepte' ? (
                              <span className="text-[12px] font-semibold text-[#2E7D5E] bg-[#E8F5E9] px-2.5 py-1 rounded-full">✓ PetFriend</span>
                            ) : statut === 'en_attente' ? (
                              <span className="text-[11px] font-semibold text-amber-700 bg-amber-50 border border-amber-200 px-2.5 py-1 rounded-full">⏳ En attente</span>
                            ) : (
                              <button onClick={() => sendRequest(u.uid)}
                                className="text-[12px] font-bold text-white px-3 py-1.5 rounded-full bg-[#2E7D5E]">
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
                  <p className="text-gray-500 text-[15px]">Vous n&apos;avez pas encore de PetFriends</p>
                  <p className="text-gray-400 text-[13px]">Recherchez des utilisateurs pour commencer</p>
                </div>
              ) : (
                <div className="flex flex-col gap-3">
                  {friends.map(f => (
                    <div key={f.relId} className="bg-white rounded-xl p-3 shadow-sm flex items-center gap-3">
                      <div className="cursor-pointer flex items-center gap-3 flex-1 min-w-0"
                        onClick={() => router.push(`/profil/${f.uid}`)}>
                        <Avatar url={f.photoUrl} name={f.firstname} size={44} />
                        <div className="flex-1 min-w-0">
                          <p className="font-bold text-[14px] truncate" style={{ fontFamily: 'Galey, sans-serif' }}>{fullName(f)}</p>
                          {f.ville && <p className="text-[12px] text-gray-400 truncate">{f.ville}</p>}
                        </div>
                      </div>
                      <button onClick={() => openDm(f)}
                        className="shrink-0 text-[12px] font-bold text-white px-3 py-1.5 rounded-full bg-[#2E7D5E]"
                        style={{ fontFamily: 'Galey, sans-serif' }}>
                        💬 Message
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </>
          )
        )}

        {/* ── Demandes ── */}
        {tab === 'requests' && (
          loading ? <Spinner /> : (
            received.length === 0 && sent.length === 0 ? (
              <div className="flex flex-col items-center gap-3 py-16 text-center">
                <span className="text-6xl">🔍</span>
                <p className="text-gray-500 text-[15px]">Aucune demande en cours</p>
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
                              {r.ville && <p className="text-[12px] text-gray-400 truncate">{r.ville}</p>}
                            </div>
                          </div>
                          <div className="flex gap-2">
                            <button onClick={() => accept(r)}
                              className="flex-1 py-2 rounded-xl font-bold text-white text-[13px] bg-[#2E7D5E]"
                              style={{ fontFamily: 'Galey, sans-serif' }}>Accepter</button>
                            <button onClick={() => decline(r)}
                              className="flex-1 py-2 rounded-xl font-bold text-red-500 border border-red-300 text-[13px]"
                              style={{ fontFamily: 'Galey, sans-serif' }}>Refuser</button>
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
                            {s.ville && <p className="text-[12px] text-gray-400 truncate">{s.ville}</p>}
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
            )
          )
        )}

        {/* ── Groupes ── */}
        {tab === 'groupes' && (
          <div>
            <button onClick={() => setShowCreateGroupe(true)}
              className="w-full mb-4 py-3 rounded-xl font-bold text-white bg-[#2E7D5E] flex items-center justify-center gap-2"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              <span>👥</span> Nouveau groupe
            </button>

            {loadingGroupes ? <Spinner /> : groupes.length === 0 ? (
              <div className="flex flex-col items-center gap-3 py-16 text-center">
                <span className="text-6xl">💬</span>
                <p className="text-gray-500 text-[15px]">Aucun groupe pour le moment</p>
                <p className="text-gray-400 text-[13px]">Créez un groupe pour discuter avec vos PetFriends</p>
              </div>
            ) : (
              <div className="flex flex-col gap-3">
                {groupes.map(g => {
                  const unread = (g.unread_count ?? {})[myUid] ?? 0;
                  const nom = g.nom || 'Groupe';
                  const members = g.participants?.length ?? 0;
                  return (
                    <div key={g.id}
                      onClick={() => router.push(`/petfriends/chat/${g.id}?nom=${encodeURIComponent(nom)}&groupe=1`)}
                      className="bg-white rounded-xl p-3 shadow-sm flex items-center gap-3 cursor-pointer hover:bg-gray-50">
                      <div className="w-11 h-11 rounded-full bg-[#E8F5E9] flex items-center justify-center shrink-0">
                        <span className="text-[#2E7D5E] text-xl">👥</span>
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="font-bold text-[14px] truncate" style={{ fontFamily: 'Galey, sans-serif' }}>{nom}</p>
                        <p className="text-[12px] text-gray-400 truncate">
                          {members} membres{g.last_message ? ` · ${g.last_message}` : ''}
                        </p>
                      </div>
                      {unread > 0 && (
                        <span className="bg-[#EF6C00] text-white text-[10px] font-bold w-5 h-5 rounded-full flex items-center justify-center shrink-0">
                          {unread}
                        </span>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        )}
      </div>

      {/* ── Modal créer groupe ── */}
      {showCreateGroupe && (
        <div className="fixed inset-0 z-50 bg-black/40 flex items-end" onClick={() => setShowCreateGroupe(false)}>
          <div className="bg-white w-full max-w-lg mx-auto rounded-t-2xl p-6 max-h-[80vh] overflow-y-auto"
            onClick={e => e.stopPropagation()}>
            <div className="w-10 h-1 bg-gray-200 rounded-full mx-auto mb-4" />
            <h2 className="font-bold text-[18px] mb-4" style={{ fontFamily: 'Galey, sans-serif' }}>Nouveau groupe</h2>

            <input value={newGroupeNom} onChange={e => setNewGroupeNom(e.target.value)}
              placeholder="Nom du groupe"
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 mb-4 text-[14px] focus:outline-none focus:border-[#2E7D5E]"
              style={{ fontFamily: 'Galey, sans-serif' }} />

            <p className="font-semibold text-[14px] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
              Ajouter des PetFriends
            </p>
            {friends.length === 0 ? (
              <p className="text-gray-400 text-[13px] py-4 text-center">Aucun PetFriend pour le moment</p>
            ) : (
              <div className="flex flex-col gap-2 mb-4 max-h-48 overflow-y-auto">
                {friends.map(f => {
                  const sel = selectedGroupeUids.has(f.uid);
                  return (
                    <label key={f.uid} className="flex items-center gap-3 cursor-pointer p-2 rounded-xl hover:bg-gray-50">
                      <input type="checkbox" checked={sel}
                        onChange={() => {
                          const next = new Set(selectedGroupeUids);
                          if (sel) next.delete(f.uid); else next.add(f.uid);
                          setSelectedGroupeUids(next);
                        }}
                        className="w-4 h-4 accent-[#2E7D5E]" />
                      <Avatar url={f.photoUrl} name={f.firstname} size={36} />
                      <span className="text-[14px] font-semibold" style={{ fontFamily: 'Galey, sans-serif' }}>{fullName(f)}</span>
                    </label>
                  );
                })}
              </div>
            )}

            <button onClick={createGroupe} disabled={creatingGroupe || !newGroupeNom.trim()}
              className="w-full py-3 rounded-xl font-bold text-white bg-[#2E7D5E] disabled:opacity-50"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              {creatingGroupe ? 'Création…' : 'Créer le groupe'}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

function Spinner() {
  return (
    <div className="flex justify-center py-12">
      <div className="w-8 h-8 border-2 border-[#2E7D5E] border-t-transparent rounded-full animate-spin" />
    </div>
  );
}
