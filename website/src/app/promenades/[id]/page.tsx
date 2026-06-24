'use client';

import { useEffect, useState, useCallback, useRef } from 'react';
import { useParams, useRouter } from 'next/navigation';
import Image from 'next/image';
import { setOptions, importLibrary } from '@googlemaps/js-api-loader';
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
  espece?: string;
  toutes_races?: boolean;
  races?: string;
}

const ESPECES_DETAIL = ['Toutes', 'Chiens', 'Chevaux'];

function especeEmojiDetail(e: string) {
  switch (e) {
    case 'Chiens':  return '🐕 Chiens';
    case 'Chevaux': return '🐴 Chevaux';
    default:        return '🌍 Toutes';
  }
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

// ── Modal édition ─────────────────────────────────────────────────────────────

function EditModal({ promenade, participants, currentUid, onClose, onSaved }: {
  promenade: Promenade;
  participants: Participant[];
  currentUid: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [titre, setTitre] = useState(promenade.titre);
  const [lieu, setLieu] = useState(promenade.lieu_rdv);
  const [lat, setLat] = useState<number | null>(promenade.lat ?? null);
  const [lng, setLng] = useState<number | null>(promenade.lng ?? null);
  const [niveau, setNiveau] = useState(promenade.niveau);
  const [duree, setDuree] = useState(String(promenade.duree_minutes ?? 60));
  const [maxP, setMaxP] = useState(promenade.participants_max ? String(promenade.participants_max) : '');
  const [desc, setDesc] = useState(promenade.description ?? '');
  const [espece, setEspece] = useState(promenade.espece ?? 'Toutes');
  const [toutesRaces, setToutesRaces] = useState(promenade.toutes_races ?? true);
  const [races, setRaces] = useState(promenade.races ?? '');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  // Places
  const autocompleteService = useRef<google.maps.places.AutocompleteService | null>(null);
  const placesService = useRef<google.maps.places.PlacesService | null>(null);
  const [predictions, setPredictions] = useState<google.maps.places.AutocompletePrediction[]>([]);
  const [loadingPred, setLoadingPred] = useState(false);
  const debounce = useRef<ReturnType<typeof setTimeout> | null>(null);

  const [dateVal, setDateVal] = useState(() => {
    const d = new Date(promenade.date_heure);
    return d.toISOString().slice(0, 16);
  });

  useEffect(() => {
    const apiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY;
    if (!apiKey) return;
    setOptions({ key: apiKey, v: 'weekly', language: 'fr' });
    importLibrary('places').then(() => {
      autocompleteService.current = new window.google.maps.places.AutocompleteService();
      const dummyDiv = document.createElement('div');
      placesService.current = new window.google.maps.places.PlacesService(dummyDiv);
    }).catch(() => {});
  }, []);

  function onLieuChange(val: string) {
    setLieu(val); setLat(null); setLng(null);
    if (debounce.current) clearTimeout(debounce.current);
    if (val.trim().length < 3) { setPredictions([]); setLoadingPred(false); return; }
    setLoadingPred(true);
    debounce.current = setTimeout(() => {
      autocompleteService.current?.getPlacePredictions(
        { input: val, componentRestrictions: { country: ['fr', 'be', 'ch', 'lu'] }, language: 'fr' } as google.maps.places.AutocompletionRequest,
        (preds, status) => {
          setLoadingPred(false);
          setPredictions(status === window.google.maps.places.PlacesServiceStatus.OK && preds ? preds : []);
        }
      );
    }, 400);
  }

  function selectPrediction(pred: google.maps.places.AutocompletePrediction) {
    setLieu(pred.description); setPredictions([]);
    placesService.current?.getDetails(
      { placeId: pred.place_id, fields: ['geometry'] },
      (place, status) => {
        if (status !== window.google.maps.places.PlacesServiceStatus.OK || !place?.geometry?.location) return;
        setLat(place.geometry.location.lat());
        setLng(place.geometry.location.lng());
      }
    );
  }

  async function handleSave() {
    if (!titre.trim() || !lieu.trim() || !dateVal) { setError('Titre, lieu et date sont obligatoires.'); return; }
    setSaving(true); setError('');
    try {
      const updates: Record<string, unknown> = {
        titre: titre.trim(), lieu_rdv: lieu.trim(), description: desc.trim() || null,
        niveau, date_heure: new Date(dateVal).toISOString(),
        duree_minutes: parseInt(duree) || 60,
        participants_max: parseInt(maxP) >= 2 ? parseInt(maxP) : null,
      };
      if (lat !== null) updates.lat = lat;
      if (lng !== null) updates.lng = lng;
      updates.espece = espece;
      updates.toutes_races = toutesRaces;
      updates.races = (!toutesRaces && races.trim()) ? races.trim() : null;

      await supabase.from('promenades').update(updates).eq('id', promenade.id);

      // Notifier participants
      const toNotify = participants.filter(p => (p.statut === 'accepte' || p.statut === 'en_attente') && p.user_uid !== currentUid);
      const dateStr = new Date(dateVal).toLocaleString('fr-FR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
      for (const part of toNotify) {
        await supabase.from('notifications').insert({
          uid: part.user_uid, type: 'promenade_modifiee',
          title: 'Promenade modifiée',
          body: `La promenade "${titre.trim()}" a été modifiée. Nouvelles infos : ${lieu.trim()}, ${dateStr}.`,
          data: { promenadeId: promenade.id }, read: false, created_at: new Date().toISOString(),
        });
      }
      onSaved();
    } catch (e: unknown) {
      setError((e as Error).message ?? 'Erreur');
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 p-4">
      <div className="bg-white rounded-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto shadow-xl">
        <div className="flex items-center justify-between p-5 border-b border-gray-100">
          <h2 className="font-bold text-lg">Modifier la promenade</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl">✕</button>
        </div>
        <div className="p-5 flex flex-col gap-4">
          <div>
            <label className="block text-[12px] font-semibold text-gray-500 mb-1">Titre *</label>
            <input value={titre} onChange={e => setTitre(e.target.value)}
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-[14px] focus:outline-none focus:border-[#2E7D5E]" />
          </div>
          <div className="relative">
            <label className="block text-[12px] font-semibold text-gray-500 mb-1">Lieu de rendez-vous *</label>
            <div className="relative">
              <span className="absolute left-3 top-1/2 -translate-y-1/2 text-[#2E7D5E]">🔍</span>
              <input value={lieu} onChange={e => onLieuChange(e.target.value)}
                className="w-full border border-gray-200 rounded-xl pl-8 pr-8 py-2.5 text-[14px] focus:outline-none focus:border-[#2E7D5E]" />
              {loadingPred && <span className="absolute right-3 top-1/2 -translate-y-1/2"><span className="w-4 h-4 border-2 border-[#2E7D5E] border-t-transparent rounded-full animate-spin inline-block" /></span>}
              {!loadingPred && lat !== null && <span className="absolute right-3 top-1/2 -translate-y-1/2 text-[#2E7D5E]">✓</span>}
            </div>
            {predictions.length > 0 && (
              <div className="absolute z-10 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg overflow-hidden">
                {predictions.slice(0, 5).map(pred => (
                  <button key={pred.place_id} onClick={() => selectPrediction(pred)}
                    className="w-full text-left px-4 py-2.5 text-[13px] hover:bg-gray-50 border-b border-gray-50 last:border-0 flex items-center gap-2">
                    <span className="text-[#2E7D5E]">📍</span><span className="truncate">{pred.description}</span>
                  </button>
                ))}
              </div>
            )}
          </div>
          <div>
            <label className="block text-[12px] font-semibold text-gray-500 mb-1">Date et heure *</label>
            <input type="datetime-local" value={dateVal} onChange={e => setDateVal(e.target.value)}
              min={new Date().toISOString().slice(0, 16)}
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-[14px] focus:outline-none focus:border-[#2E7D5E]" />
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div>
              <label className="block text-[12px] font-semibold text-gray-500 mb-1">Niveau</label>
              <select value={niveau} onChange={e => setNiveau(e.target.value)}
                className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-[14px] focus:outline-none focus:border-[#2E7D5E] bg-white">
                <option value="facile">Facile</option><option value="moyen">Moyen</option><option value="difficile">Difficile</option>
              </select>
            </div>
            <div>
              <label className="block text-[12px] font-semibold text-gray-500 mb-1">Durée (min)</label>
              <input type="number" min="10" value={duree} onChange={e => setDuree(e.target.value)}
                className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-[14px] focus:outline-none focus:border-[#2E7D5E]" />
            </div>
            <div>
              <label className="block text-[12px] font-semibold text-gray-500 mb-1">Max participants</label>
              <input type="number" min="2" value={maxP} onChange={e => setMaxP(e.target.value)}
                placeholder="Illimité"
                className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-[14px] focus:outline-none focus:border-[#2E7D5E]" />
            </div>
          </div>
          <div>
            <label className="block text-[12px] font-semibold text-gray-500 mb-1">Description</label>
            <textarea value={desc} onChange={e => setDesc(e.target.value)} rows={3}
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-[14px] focus:outline-none focus:border-[#2E7D5E] resize-none" />
          </div>
          <div>
            <label className="block text-[12px] font-semibold text-gray-500 mb-2">Espèce concernée</label>
            <div className="flex flex-wrap gap-2">
              {ESPECES_DETAIL.map(e => (
                <button key={e} type="button" onClick={() => setEspece(e)}
                  className="px-3 py-1.5 rounded-full text-[12px] font-semibold transition-colors"
                  style={espece === e
                    ? { backgroundColor: '#2E7D5E', color: '#fff' }
                    : { backgroundColor: '#F5F5F5', color: '#555' }}>
                  {especeEmojiDetail(e)}
                </button>
              ))}
            </div>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-[13px] font-semibold text-gray-700">Toutes races acceptées</span>
            <button type="button" onClick={() => setToutesRaces(!toutesRaces)}
              className="relative w-11 h-6 rounded-full transition-colors"
              style={{ backgroundColor: toutesRaces ? '#2E7D5E' : '#D1D5DB' }}>
              <span className="absolute top-0.5 left-0.5 w-5 h-5 bg-white rounded-full shadow transition-transform"
                style={{ transform: toutesRaces ? 'translateX(20px)' : 'none' }} />
            </button>
          </div>
          {!toutesRaces && (
            <input value={races} onChange={e => setRaces(e.target.value)}
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-[14px] focus:outline-none focus:border-[#2E7D5E]"
              placeholder="Ex : Golden Retriever, Labrador…" />
          )}
          {error && <p className="text-red-500 text-[13px]">{error}</p>}
          <button onClick={handleSave} disabled={saving}
            className="w-full py-3 rounded-xl font-bold text-white text-[15px]"
            style={{ backgroundColor: '#EF6C00', opacity: saving ? 0.6 : 1 }}>
            {saving ? 'Enregistrement…' : 'Enregistrer les modifications'}
          </button>
        </div>
      </div>
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
  const [showEdit, setShowEdit] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);

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
          uid: promenade.organisateur_uid,
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
      uid: userUid,
      type: 'promenade_accepte',
      title: 'Participation confirmée',
      body: `Votre demande pour "${promenade?.titre}" a été acceptée !`,
      data: { promenadeId: id },
      read: false,
      created_at: new Date().toISOString(),
    });
    load();
  }

  async function deleteProm() {
    if (!user || !promenade) return;
    setSaving(true);
    try {
      const dateStr = new Date(promenade.date_heure).toLocaleString('fr-FR', {
        day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit'
      });
      const toNotify = participants.filter(p => p.statut === 'accepte' || p.statut === 'en_attente');
      for (const part of toNotify) {
        if (part.user_uid === user.uid) continue;
        await supabase.from('notifications').insert({
          uid: part.user_uid,
          type: 'promenade_annulee',
          title: 'Promenade annulée',
          body: `La promenade "${promenade.titre}" du ${dateStr} a été annulée par l'organisateur.`,
          data: { promenadeId: id },
          read: false, created_at: new Date().toISOString(),
        });
      }
      await supabase.from('promenades').delete().eq('id', id);
      router.push('/promenades');
    } finally {
      setSaving(false);
      setConfirmDelete(false);
    }
  }

  async function refuse(userUid: string) {
    await supabase.from('promenades_participants').delete()
      .eq('promenade_id', id).eq('user_uid', userUid);
    await supabase.from('notifications').insert({
      uid: userUid,
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
        <h1 className="font-bold text-base truncate flex-1" style={{ fontFamily: 'Galey, sans-serif' }}>
          {promenade.titre}
        </h1>
        {isOrganizer && (
          <div className="flex items-center gap-2 shrink-0">
            <button onClick={() => setShowEdit(true)}
              className="text-white/80 hover:text-white text-xl" title="Modifier">✏️</button>
            <button onClick={() => setConfirmDelete(true)}
              className="text-white/80 hover:text-white text-xl" title="Supprimer">🗑</button>
          </div>
        )}
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

      {/* Confirmation suppression */}
      {confirmDelete && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
          <div className="bg-white rounded-2xl p-6 max-w-sm w-full shadow-xl">
            <h3 className="font-bold text-[16px] mb-2">Supprimer la promenade</h3>
            <p className="text-[13px] text-gray-500 mb-5">
              Tous les participants seront notifiés de l&apos;annulation. Cette action est irréversible.
            </p>
            <div className="flex gap-3">
              <button onClick={() => setConfirmDelete(false)}
                className="flex-1 py-2.5 rounded-xl border border-gray-200 text-[14px] font-semibold text-gray-600">
                Annuler
              </button>
              <button onClick={deleteProm} disabled={saving}
                className="flex-1 py-2.5 rounded-xl text-[14px] font-bold text-white"
                style={{ backgroundColor: '#E53935', opacity: saving ? 0.6 : 1 }}>
                {saving ? '…' : 'Supprimer'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Modal édition */}
      {showEdit && (
        <EditModal
          promenade={promenade}
          participants={participants}
          currentUid={user?.uid ?? ''}
          onClose={() => setShowEdit(false)}
          onSaved={() => { setShowEdit(false); load(); }}
        />
      )}

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
