'use client';

import { useEffect, useState, useCallback } from 'react';
import { useParams, useRouter } from 'next/navigation';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

// ── Types ──────────────────────────────────────────────────────────────────────

interface Promenade {
  id: string;
  organisateur_uid: string;
  titre: string;
  lieu_rdv: string;
  lat?: number;
  lng?: number;
  description?: string;
  niveau: string;
  date_heure: string;
  duree_minutes?: number;
  distance_km?: number;
  participants_max?: number;
  statut: string;
}

interface Participant {
  user_uid: string;
  statut: string;
  rejoint_at: string;
  user?: { firstname?: string; lastname?: string; profile_picture_url?: string };
}

interface UserProfile {
  uid: string;
  firstname?: string;
  lastname?: string;
  profile_picture_url?: string;
}

// ── Helpers ────────────────────────────────────────────────────────────────────

const NIVEAU_COLOR: Record<string, string> = {
  facile: '#6E9E57', moyen: '#EF6C00', difficile: '#E53935',
};

function fmtDate(iso: string) {
  try {
    return new Date(iso).toLocaleString('fr-FR', {
      weekday: 'long', day: '2-digit', month: 'long', year: 'numeric',
      hour: '2-digit', minute: '2-digit',
    });
  } catch { return iso; }
}

function Avatar({ url, name, size = 40 }: { url?: string; name?: string; size?: number }) {
  const initials = (name ?? '?').charAt(0).toUpperCase();
  if (url) {
    return (
      <div className="rounded-full overflow-hidden shrink-0" style={{ width: size, height: size }}>
        <Image src={url} alt={name ?? ''} width={size} height={size} className="object-cover w-full h-full" />
      </div>
    );
  }
  return (
    <div
      className="rounded-full shrink-0 flex items-center justify-center font-bold text-white"
      style={{ width: size, height: size, backgroundColor: '#2E7D5E', fontSize: size * 0.4 }}
    >
      {initials}
    </div>
  );
}

// ── Page ──────────────────────────────────────────────────────────────────────

export default function PromenadeDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { user } = useAuth();

  const [promenade, setPromenade] = useState<Promenade | null>(null);
  const [organizer, setOrganizer] = useState<UserProfile | null>(null);
  const [participants, setParticipants] = useState<Participant[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const isOrganizer = promenade?.organisateur_uid === user?.uid;
  const myParticipation = participants.find(p => p.user_uid === user?.uid);
  const accepted = participants.filter(p => p.statut === 'accepte');
  const pending = participants.filter(p => p.statut === 'en_attente');
  const isFull = !!promenade?.participants_max && accepted.length >= promenade.participants_max && myParticipation?.statut !== 'accepte';

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const { data: p } = await supabase.from('promenades').select('*').eq('id', id).single();
      if (!p) { setLoading(false); return; }
      setPromenade(p as Promenade);

      // Organizer profile
      const { data: org } = await supabase.from('users')
        .select('uid, firstname, lastname, profile_picture_url')
        .eq('uid', p.organisateur_uid).maybeSingle();
      setOrganizer(org as UserProfile ?? null);

      // Participants
      const { data: parts } = await supabase.from('promenades_participants')
        .select('user_uid, statut, rejoint_at')
        .eq('promenade_id', id)
        .order('rejoint_at');

      if (parts && parts.length > 0) {
        const uids = parts.map((r: { user_uid: string }) => r.user_uid);
        const { data: users } = await supabase.from('users')
          .select('uid, firstname, lastname, profile_picture_url')
          .in('uid', uids);
        const usersMap: Record<string, UserProfile> = {};
        (users ?? []).forEach((u: UserProfile) => { usersMap[u.uid] = u; });
        setParticipants(parts.map((part: { user_uid: string; statut: string; rejoint_at: string }) => ({
          ...part,
          user: usersMap[part.user_uid],
        })));
      } else {
        setParticipants([]);
      }
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => { load(); }, [load]);

  async function join() {
    if (!user) return;
    setSaving(true);
    try {
      await supabase.from('promenades_participants').insert({
        promenade_id: id,
        user_uid: user.uid,
        statut: 'en_attente',
        rejoint_at: new Date().toISOString(),
      });
      // Notify organizer
      if (promenade && promenade.organisateur_uid !== user.uid) {
        const { data: me } = await supabase.from('users')
          .select('firstname, lastname').eq('uid', user.uid).maybeSingle();
        const nom = me ? `${me.firstname ?? ''} ${me.lastname ?? ''}`.trim() || 'Quelqu\'un' : 'Quelqu\'un';
        await supabase.from('notifications').insert({
          user_uid: promenade.organisateur_uid,
          type: 'promenade_join',
          title: 'Nouvelle demande de participation',
          body: `${nom} veut rejoindre "${promenade.titre}"`,
          data: { promenadeId: id, fromUid: user.uid },
          read: false,
          created_at: new Date().toISOString(),
        });
      }
      await load();
    } finally {
      setSaving(false);
    }
  }

  async function leave() {
    if (!user) return;
    setSaving(true);
    try {
      await supabase.from('promenades_participants').delete()
        .eq('promenade_id', id).eq('user_uid', user.uid);
      await load();
    } finally {
      setSaving(false);
    }
  }

  async function accept(userUid: string) {
    await supabase.from('promenades_participants')
      .update({ statut: 'accepte' })
      .eq('promenade_id', id).eq('user_uid', userUid);
    await supabase.from('notifications').insert({
      user_uid: userUid,
      type: 'promenade_accepte',
      title: 'Participation confirmée',
      body: `Votre demande pour "${promenade?.titre}" a été acceptée !`,
      data: { promenadeId: id },
      read: false,
      created_at: new Date().toISOString(),
    });
    load();
  }

  async function refuse(userUid: string) {
    await supabase.from('promenades_participants').delete()
      .eq('promenade_id', id).eq('user_uid', userUid);
    await supabase.from('notifications').insert({
      user_uid: userUid,
      type: 'promenade_refuse',
      title: 'Participation refusée',
      body: `Votre demande pour "${promenade?.titre}" n'a pas été retenue.`,
      data: { promenadeId: id },
      read: false,
      created_at: new Date().toISOString(),
    });
    load();
  }

  if (loading) return (
    <div className="min-h-screen bg-[#F8F8F8] flex items-center justify-center">
      <div className="w-8 h-8 border-2 border-[#EF6C00] border-t-transparent rounded-full animate-spin" />
    </div>
  );

  if (!promenade) return (
    <div className="min-h-screen flex items-center justify-center text-gray-400">
      Promenade introuvable.
    </div>
  );

  const couleur = NIVEAU_COLOR[promenade.niveau] ?? '#888';

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-[#2E7D5E] text-white px-4 py-4 flex items-center gap-3 shadow-sm">
        <button onClick={() => router.back()} className="text-white/80 hover:text-white shrink-0">←</button>
        <h1 className="font-bold text-base truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
          {promenade.titre}
        </h1>
      </div>

      <div className="max-w-2xl mx-auto px-4 py-5 flex flex-col gap-4 pb-28">

        {/* Organisateur */}
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
          <p className="text-[11px] font-semibold text-gray-400 uppercase tracking-wide mb-2">Organisé par</p>
          <div className="flex items-center gap-3">
            <Avatar url={organizer?.profile_picture_url} name={organizer?.firstname} size={44} />
            <span className="font-bold text-[15px]">
              {[organizer?.firstname, organizer?.lastname].filter(Boolean).join(' ') || 'Organisateur'}
            </span>
          </div>
        </div>

        {/* Infos */}
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 flex flex-col gap-3">
          <div className="flex items-center gap-2 text-[13px]">
            <span>🗓</span>
            <span className="font-semibold">{fmtDate(promenade.date_heure)}</span>
          </div>

          {promenade.lieu_rdv && (
            <div className="flex items-center gap-2 text-[13px]">
              <span>📍</span>
              <span className="flex-1">{promenade.lieu_rdv}</span>
              {promenade.lat && promenade.lng && (
                <a
                  href={`https://waze.com/ul?ll=${promenade.lat.toFixed(6)},${promenade.lng.toFixed(6)}&navigate=yes`}
                  target="_blank" rel="noopener noreferrer"
                  className="flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-bold shrink-0"
                  style={{ color: '#2E7D5E', backgroundColor: '#2E7D5E18' }}
                >
                  🗺 Y aller
                </a>
              )}
            </div>
          )}

          <div className="flex flex-wrap gap-2">
            <span className="px-3 py-1 rounded-full text-[12px] font-bold"
              style={{ color: couleur, backgroundColor: couleur + '18' }}>
              {promenade.niveau}
            </span>
            {promenade.duree_minutes && (
              <span className="px-3 py-1 rounded-full text-[12px] font-semibold bg-gray-100 text-gray-500">
                ⏱ {promenade.duree_minutes} min
              </span>
            )}
            {promenade.distance_km && (
              <span className="px-3 py-1 rounded-full text-[12px] font-semibold bg-gray-100 text-gray-500">
                📏 {promenade.distance_km.toFixed(1)} km
              </span>
            )}
            <span className={`px-3 py-1 rounded-full text-[12px] font-semibold ${isFull ? 'bg-red-50 text-red-400' : 'bg-gray-100 text-gray-500'}`}>
              👥 {accepted.length}{promenade.participants_max ? ` / ${promenade.participants_max}` : ''} participant{accepted.length !== 1 ? 's' : ''}
              {isFull && ' · Complet'}
            </span>
          </div>

          {promenade.description && (
            <>
              <hr className="border-gray-100" />
              <p className="text-[13px] text-gray-600">{promenade.description}</p>
            </>
          )}
        </div>

        {/* Participants acceptés */}
        {accepted.length > 0 && (
          <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
            <p className="font-bold text-[14px] mb-3">
              {accepted.length} participant{accepted.length !== 1 ? 's' : ''}
            </p>
            <div className="flex flex-wrap gap-4">
              {accepted.map(part => (
                <div key={part.user_uid} className="flex flex-col items-center gap-1">
                  <Avatar url={part.user?.profile_picture_url} name={part.user?.firstname} size={40} />
                  <span className="text-[11px] text-gray-400 max-w-[50px] truncate text-center">
                    {part.user?.firstname ?? '?'}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Demandes en attente (organisateur seulement) */}
        {isOrganizer && pending.length > 0 && (
          <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
            <div className="flex items-center gap-2 mb-3">
              <p className="font-bold text-[14px]">Demandes en attente</p>
              <span className="px-2 py-0.5 rounded-full text-[11px] font-bold text-white"
                style={{ backgroundColor: '#EF6C00' }}>
                {pending.length}
              </span>
            </div>
            <div className="flex flex-col gap-3">
              {pending.map(part => (
                <div key={part.user_uid} className="flex items-center gap-3">
                  <Avatar url={part.user?.profile_picture_url} name={part.user?.firstname} size={36} />
                  <span className="flex-1 font-semibold text-[13px]">
                    {[part.user?.firstname, part.user?.lastname].filter(Boolean).join(' ') || 'Utilisateur'}
                  </span>
                  <button
                    onClick={() => accept(part.user_uid)}
                    className="px-3 py-1.5 rounded-full text-[12px] font-bold text-white"
                    style={{ backgroundColor: '#2E7D5E' }}
                  >
                    Accepter
                  </button>
                  <button
                    onClick={() => refuse(part.user_uid)}
                    className="px-3 py-1.5 rounded-full text-[12px] font-bold"
                    style={{ color: '#E53935', backgroundColor: '#FFEBEE' }}
                  >
                    Refuser
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>

      {/* Bouton bas de page (non-organisateur connecté) */}
      {!isOrganizer && user && (
        <div className="fixed bottom-0 left-0 right-0 bg-white border-t border-gray-100 px-4 py-3 shadow-lg">
          <div className="max-w-2xl mx-auto">
            {myParticipation?.statut === 'accepte' ? (
              <button
                onClick={leave}
                disabled={saving}
                className="w-full py-3 rounded-xl font-bold text-white text-[15px]"
                style={{ backgroundColor: '#EF6C00', opacity: saving ? 0.6 : 1 }}
              >
                {saving ? '…' : 'Inscrit ✓ — Se désinscrire'}
              </button>
            ) : myParticipation?.statut === 'en_attente' ? (
              <div className="w-full py-3 rounded-xl text-center" style={{ backgroundColor: '#FFFDE7', border: '1.5px solid #FFD54F' }}>
                <p className="font-bold text-[14px]" style={{ color: '#F57F17' }}>⏳ En attente de validation</p>
                <button onClick={leave} disabled={saving}
                  className="text-[12px] underline mt-0.5" style={{ color: '#F57F17' }}>
                  Annuler ma demande
                </button>
              </div>
            ) : isFull ? (
              <div className="w-full py-3 rounded-xl bg-gray-100 text-center font-bold text-gray-400 text-[15px]">
                Complet
              </div>
            ) : (
              <button
                onClick={join}
                disabled={saving}
                className="w-full py-3 rounded-xl font-bold text-white text-[15px]"
                style={{ backgroundColor: '#2E7D5E', opacity: saving ? 0.6 : 1 }}
              >
                {saving ? '…' : 'Rejoindre la promenade'}
              </button>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
