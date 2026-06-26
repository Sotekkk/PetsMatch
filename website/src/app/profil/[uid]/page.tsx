'use client';

import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface UserProfile {
  uid: string;
  firstname?: string;
  lastname?: string;
  profile_picture_url?: string;
  ville?: string;
}

interface Animal {
  id: string;
  nom: string;
  espece?: string;
  race?: string;
  date_naissance?: string;
  photo_url?: string;
}

type RelStatut = 'en_attente' | 'accepte' | null;
type RelDir = 'sent' | 'received' | null;

function Avatar({ url, name, size = 48 }: { url?: string; name?: string; size?: number }) {
  return url ? (
    <Image src={url} alt={name ?? ''} width={size} height={size}
      className="rounded-full object-cover" style={{ width: size, height: size }} />
  ) : (
    <div className="rounded-full bg-[#E8F5E9] flex items-center justify-center"
      style={{ width: size, height: size }}>
      <span className="text-[#2E7D5E]" style={{ fontSize: size * 0.45 }}>👤</span>
    </div>
  );
}

export default function PublicProfilePage() {
  const params = useParams<{ uid: string }>();
  const targetUid = params.uid;
  const router = useRouter();
  const { user } = useAuth();
  const myUid = user?.uid ?? '';
  const isMe = targetUid === myUid;

  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [relStatut, setRelStatut] = useState<RelStatut>(null);
  const [relDir, setRelDir] = useState<RelDir>(null);
  const [relId, setRelId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  async function load() {
    setLoading(true);
    try {
      const { data: p } = await supabase.from('users')
        .select('uid, firstname, lastname, profile_picture_url, ville')
        .eq('uid', targetUid).maybeSingle();
      setProfile(p ?? null);

      // Relation
      let rStatut: RelStatut = null, rDir: RelDir = null, rId: string | null = null;
      if (!isMe && myUid) {
        const { data: sent } = await supabase.from('petfriends')
          .select('id, statut').eq('uid_demandeur', myUid).eq('uid_recepteur', targetUid).maybeSingle();
        if (sent) { rId = sent.id; rStatut = sent.statut; rDir = 'sent'; }
        else {
          const { data: recv } = await supabase.from('petfriends')
            .select('id, statut').eq('uid_demandeur', targetUid).eq('uid_recepteur', myUid).maybeSingle();
          if (recv) { rId = recv.id; rStatut = recv.statut; rDir = 'received'; }
        }
      }
      setRelStatut(rStatut); setRelDir(rDir); setRelId(rId);

      // Animaux
      const isFriend = rStatut === 'accepte';
      let animData: Animal[] = [];
      if (isFriend) {
        try {
          const { data: anim } = await supabase.from('animaux')
            .select('id, nom, espece, race, date_naissance, photo_url, couleur')
            .eq('uid_proprietaire', targetUid)
            .not('statut', 'in', '("sorti","decede")');
          animData = (anim ?? []) as Animal[];
        } catch (_) { /* colonnes optionnelles absentes */ }
      }
      // Non-ami : animaux masqués (est_public à ajouter plus tard)
      setAnimaux(animData);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { if (targetUid) load(); }, [targetUid, myUid]);

  async function sendRequest() {
    if (!myUid) return;
    setSaving(true);
    try {
      const { data: rel } = await supabase.from('petfriends').insert({
        uid_demandeur: myUid, uid_recepteur: targetUid,
        statut: 'en_attente', created_at: new Date().toISOString(), updated_at: new Date().toISOString(),
      }).select('id').single();
      const { data: me } = await supabase.from('users').select('firstname, lastname').eq('uid', myUid).maybeSingle();
      const nom = me ? `${me.firstname ?? ''} ${me.lastname ?? ''}`.trim() || 'Quelqu\'un' : 'Quelqu\'un';
      await supabase.from('notifications').insert({
        uid: targetUid, type: 'petfriend_request',
        title: '🐾 Nouvelle demande PetFriend',
        body: `${nom} veut être ton PetFriend !`,
        data: { fromUid: myUid }, read: false, created_at: new Date().toISOString(),
      });
      setRelId(rel.id); setRelStatut('en_attente'); setRelDir('sent');
    } finally {
      setSaving(false);
    }
  }

  async function cancelRequest() {
    if (!relId) return;
    setSaving(true);
    await supabase.from('petfriends').delete().eq('id', relId);
    setRelStatut(null); setRelDir(null); setRelId(null);
    setSaving(false);
  }

  async function acceptRequest() {
    if (!relId || !myUid) return;
    setSaving(true);
    await supabase.from('petfriends').update({
      statut: 'accepte', updated_at: new Date().toISOString()
    }).eq('id', relId);
    const { data: me } = await supabase.from('users').select('firstname, lastname').eq('uid', myUid).maybeSingle();
    const nom = me ? `${me.firstname ?? ''} ${me.lastname ?? ''}`.trim() || 'Quelqu\'un' : 'Quelqu\'un';
    await supabase.from('notifications').insert({
      uid: targetUid, type: 'petfriend_accepted',
      title: '🐾 PetFriend accepté !',
      body: `${nom} a accepté ta demande PetFriend.`,
      data: { fromUid: myUid }, read: false, created_at: new Date().toISOString(),
    });
    setRelStatut('accepte'); setSaving(false);
    load();
  }

  async function removeFriend() {
    if (!relId || !confirm('Supprimer ce PetFriend ?')) return;
    setSaving(true);
    await supabase.from('petfriends').delete().eq('id', relId);
    setRelStatut(null); setRelDir(null); setRelId(null);
    setSaving(false);
  }

  if (loading) return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="w-8 h-8 border-2 border-[#2E7D5E] border-t-transparent rounded-full animate-spin" />
    </div>
  );

  if (!profile) return (
    <div className="min-h-screen flex flex-col items-center justify-center gap-4">
      <p className="text-gray-500">Profil introuvable</p>
      <button onClick={() => router.back()} className="text-[#2E7D5E] underline text-[14px]">Retour</button>
    </div>
  );

  const nom = `${profile.firstname ?? ''} ${profile.lastname ?? ''}`.trim() || '—';
  const isFriend = relStatut === 'accepte';

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-[#2E7D5E] text-white px-4 py-4 flex items-center gap-3 shadow-sm">
        <button onClick={() => router.back()} className="text-white/80 hover:text-white shrink-0">←</button>
        <h1 className="font-bold text-base truncate" style={{ fontFamily: 'Galey, sans-serif' }}>Profil</h1>
      </div>

      <div className="max-w-lg mx-auto px-4 py-6 flex flex-col gap-4">
        {/* Card profil */}
        <div className="bg-white rounded-2xl p-6 shadow-sm flex flex-col items-center gap-3">
          <Avatar url={profile.profile_picture_url} name={nom} size={88} />
          <div className="text-center">
            <p className="font-bold text-[20px]" style={{ fontFamily: 'Galey, sans-serif' }}>{nom}</p>
            {profile.ville && (
              <p className="text-gray-400 text-[13px] mt-0.5">📍 {profile.ville}</p>
            )}
            {isFriend && (
              <span className="inline-block mt-1 px-3 py-1 bg-[#E8F5E9] text-[#2E7D5E] text-[12px] font-semibold rounded-full">
                🐾 PetFriend
              </span>
            )}
          </div>
          {!isMe && myUid && <PetFriendButton
            relStatut={relStatut} relDir={relDir} saving={saving}
            onSend={sendRequest} onCancel={cancelRequest}
            onAccept={acceptRequest} onRemove={removeFriend}
          />}
        </div>

        {/* Animaux */}
        <div>
          <h2 className="font-bold text-[15px] mb-3 flex items-center gap-2" style={{ fontFamily: 'Galey, sans-serif' }}>
            Animaux
            <span className="bg-[#E8F5E9] text-[#2E7D5E] text-[12px] font-semibold px-2 py-0.5 rounded-full">
              {animaux.length}
            </span>
          </h2>
          {animaux.length === 0 ? (
            <div className="bg-white rounded-2xl p-6 shadow-sm text-center text-gray-400 text-[13px]">
              {isFriend ? 'Aucun animal partagé' : 'Devenez PetFriends pour voir ses animaux'}
            </div>
          ) : (
            <div className="bg-white rounded-2xl p-4 shadow-sm flex flex-wrap gap-4">
              {animaux.map(a => (
                <div key={a.id} className="flex flex-col items-center gap-1">
                  {a.photo_url ? (
                    <Image src={a.photo_url} alt={a.nom} width={52} height={52}
                      className="rounded-full object-cover" style={{ width: 52, height: 52 }} />
                  ) : (
                    <div className="w-[52px] h-[52px] rounded-full bg-[#E8F5E9] flex items-center justify-center">
                      <span className="text-[22px]">🐾</span>
                    </div>
                  )}
                  <p className="text-[12px] font-semibold text-center" style={{ fontFamily: 'Galey, sans-serif' }}>{a.nom}</p>
                  {a.espece && <p className="text-[10px] text-gray-400">{a.espece}</p>}
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function PetFriendButton({ relStatut, relDir, saving, onSend, onCancel, onAccept, onRemove }: {
  relStatut: RelStatut; relDir: RelDir; saving: boolean;
  onSend: () => void; onCancel: () => void; onAccept: () => void; onRemove: () => void;
}) {
  if (saving) return <div className="w-6 h-6 border-2 border-[#2E7D5E] border-t-transparent rounded-full animate-spin" />;

  if (!relStatut) return (
    <button onClick={onSend}
      className="flex items-center gap-2 px-5 py-2.5 rounded-xl font-bold text-white text-[14px]"
      style={{ backgroundColor: '#2E7D5E', fontFamily: 'Galey, sans-serif' }}>
      ➕ Ajouter en PetFriend
    </button>
  );

  if (relStatut === 'en_attente' && relDir === 'sent') return (
    <button onClick={onCancel}
      className="flex items-center gap-2 px-5 py-2.5 rounded-xl font-semibold text-gray-500 border border-gray-300 text-[13px]"
      style={{ fontFamily: 'Galey, sans-serif' }}>
      ⏳ En attente… (annuler)
    </button>
  );

  if (relStatut === 'en_attente' && relDir === 'received') return (
    <div className="flex gap-2">
      <button onClick={onAccept}
        className="px-5 py-2.5 rounded-xl font-bold text-white text-[14px]"
        style={{ backgroundColor: '#2E7D5E', fontFamily: 'Galey, sans-serif' }}>
        Accepter
      </button>
      <button onClick={onCancel}
        className="px-5 py-2.5 rounded-xl font-bold text-red-500 border border-red-400 text-[14px]"
        style={{ fontFamily: 'Galey, sans-serif' }}>
        Refuser
      </button>
    </div>
  );

  if (relStatut === 'accepte') return (
    <button onClick={onRemove}
      className="flex items-center gap-2 px-5 py-2.5 rounded-xl font-semibold text-red-500 border border-red-300 text-[13px]"
      style={{ fontFamily: 'Galey, sans-serif' }}>
      Supprimer PetFriend
    </button>
  );

  return null;
}
