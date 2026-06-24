'use client';

import { useEffect, useState, useRef, useCallback } from 'react';
import { useRouter } from 'next/navigation';
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
  promenades_participants: { count: number }[];
}

const ESPECES = ['Toutes', 'Chiens', 'Chevaux'];

function especeEmoji(e: string) {
  switch (e) {
    case 'Chiens':  return '🐕 Chiens';
    case 'Chevaux': return '🐴 Chevaux';
    default:        return '🌍 Toutes';
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

const NIVEAU_COLOR: Record<string, string> = {
  facile: '#6E9E57',
  moyen: '#EF6C00',
  difficile: '#E53935',
};

function fmtDate(iso: string) {
  try {
    return new Date(iso).toLocaleString('fr-FR', {
      day: '2-digit', month: '2-digit', year: 'numeric',
      hour: '2-digit', minute: '2-digit',
    });
  } catch { return iso; }
}

function openNav(lat: number, lng: number) {
  const latS = lat.toFixed(6);
  const lngS = lng.toFixed(6);
  // Waze universal link — ouvre l'app si installée, sinon le site web
  window.open(`https://waze.com/ul?ll=${latS},${lngS}&navigate=yes`, '_blank');
}

// ── Carte promenade ────────────────────────────────────────────────────────────

function PromenadesCard({
  p, myStatut, onToggle, loading, onClick,
}: {
  p: Promenade;
  myStatut?: string;
  onToggle: () => void;
  loading: boolean;
  onClick: () => void;
}) {
  const nb = p.promenades_participants?.[0]?.count ?? 0;
  const isFull = !myStatut && !!p.participants_max && nb >= p.participants_max;
  const couleur = NIVEAU_COLOR[p.niveau] ?? '#888';

  return (
    <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 flex flex-col gap-2 cursor-pointer" onClick={onClick}>
      {/* Header */}
      <div className="flex items-start justify-between gap-2">
        <h3 className="font-bold text-[15px] text-gray-800 leading-tight">{p.titre}</h3>
        <span
          className="shrink-0 text-[11px] font-bold px-2 py-0.5 rounded-full"
          style={{ color: couleur, backgroundColor: couleur + '20' }}
        >
          {p.niveau}
        </span>
      </div>

      {/* Date */}
      <div className="flex items-center gap-1.5 text-gray-400 text-[12px]">
        <span>🗓</span>
        <span>{fmtDate(p.date_heure)}</span>
      </div>

      {/* Lieu + Y aller */}
      {p.lieu_rdv && (
        <div className="flex items-center gap-1.5 text-gray-400 text-[12px]">
          <span>📍</span>
          <span className="flex-1 truncate">{p.lieu_rdv}</span>
          {p.lat && p.lng && (
            <button
              onClick={() => openNav(p.lat!, p.lng!)}
              className="shrink-0 flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-bold"
              style={{ color: '#2E7D5E', backgroundColor: '#2E7D5E18' }}
            >
              <span>🗺</span> Y aller
            </button>
          )}
        </div>
      )}

      {/* Espèce */}
      {p.espece && p.espece !== 'Toutes' && p.espece !== 'Toutes espèces' && (
        <div className="flex items-center gap-2">
          <span className="px-2.5 py-0.5 rounded-full text-[11px] font-semibold"
            style={{ backgroundColor: '#2E7D5E18', color: '#2E7D5E' }}>
            {especeEmoji(p.espece)}
          </span>
          {!p.toutes_races && p.races && (
            <span className="text-[11px] text-gray-400 truncate">• {p.races}</span>
          )}
        </div>
      )}

      {/* Méta : durée + distance + participants */}
      <div className="flex items-center gap-3 text-gray-400 text-[12px]">
        {p.duree_minutes && <span>⏱ {p.duree_minutes} min</span>}
        {p.distance_km && <span>📏 {p.distance_km.toFixed(1)} km</span>}
        {(nb > 0 || p.participants_max) && (
          <span
            className="font-semibold"
            style={{ color: isFull ? '#E53935' : '#888' }}
          >
            👥 {nb}{p.participants_max ? ` / ${p.participants_max}` : ''}
            {isFull && ' · Complet'}
          </span>
        )}
      </div>

      {/* Description */}
      {p.description && (
        <p className="text-[13px] text-gray-500 line-clamp-2">{p.description}</p>
      )}

      {/* Bouton rejoindre */}
      <div className="flex justify-end mt-1">
        {myStatut === 'en_attente' ? (
          <span className="px-4 py-1.5 rounded-full text-[12px] font-bold"
            style={{ backgroundColor: '#FFFDE7', color: '#F57F17', border: '1px solid #FFD54F' }}>
            ⏳ En attente
          </span>
        ) : isFull ? (
          <span className="px-4 py-1.5 rounded-full text-[13px] font-bold bg-gray-100 text-gray-400">
            Complet
          </span>
        ) : (
          <button
            onClick={e => { e.stopPropagation(); onToggle(); }}
            disabled={loading}
            className="px-4 py-1.5 rounded-full text-[13px] font-bold transition-colors"
            style={myStatut === 'accepte'
              ? { backgroundColor: '#EF6C00', color: '#fff' }
              : { border: '1.5px solid #EF6C00', color: '#EF6C00', backgroundColor: 'transparent' }
            }
          >
            {loading ? '…' : myStatut === 'accepte' ? 'Inscrit ✓' : 'Rejoindre'}
          </button>
        )}
      </div>
    </div>
  );
}

// ── Modal création ─────────────────────────────────────────────────────────────

function CreateModal({ onClose, onCreated }: { onClose: () => void; onCreated: () => void }) {
  const { user } = useAuth();

  const [titre, setTitre] = useState('');
  const [lieu, setLieu] = useState('');
  const [lat, setLat] = useState<number | null>(null);
  const [lng, setLng] = useState<number | null>(null);
  const [dateHeure, setDateHeure] = useState('');
  const [niveau, setNiveau] = useState('facile');
  const [duree, setDuree] = useState('60');
  const [maxParticipants, setMaxParticipants] = useState('');
  const [description, setDescription] = useState('');
  const [espece, setEspece] = useState('Toutes');
  const [toutesRaces, setToutesRaces] = useState(true);
  const [races, setRaces] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  // Google Places
  const autocompleteService = useRef<google.maps.places.AutocompleteService | null>(null);
  const placesService = useRef<google.maps.places.PlacesService | null>(null);
  const [predictions, setPredictions] = useState<google.maps.places.AutocompletePrediction[]>([]);
  const [loadingPred, setLoadingPred] = useState(false);
  const debounce = useRef<ReturnType<typeof setTimeout> | null>(null);

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
    setLieu(val);
    setLat(null); setLng(null);
    if (debounce.current) clearTimeout(debounce.current);
    if (val.trim().length < 3) { setPredictions([]); setLoadingPred(false); return; }
    setLoadingPred(true);
    debounce.current = setTimeout(() => {
      autocompleteService.current?.getPlacePredictions(
        { input: val, componentRestrictions: { country: ['fr', 'be', 'ch', 'lu'] }, language: 'fr' } as google.maps.places.AutocompletionRequest,
        (preds, status) => {
          setLoadingPred(false);
          if (status === window.google.maps.places.PlacesServiceStatus.OK && preds) {
            setPredictions(preds);
          } else {
            setPredictions([]);
          }
        }
      );
    }, 400);
  }

  function selectPrediction(pred: google.maps.places.AutocompletePrediction) {
    setLieu(pred.description);
    setPredictions([]);
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
    if (!titre.trim() || !lieu.trim() || !dateHeure) {
      setError('Titre, lieu et date sont obligatoires.');
      return;
    }
    setSaving(true); setError('');
    try {
      const row: Record<string, unknown> = {
        organisateur_uid: user!.uid,
        titre: titre.trim(),
        lieu_rdv: lieu.trim(),
        description: description.trim() || null,
        niveau,
        date_heure: new Date(dateHeure).toISOString(),
        duree_minutes: parseInt(duree) || 60,
        statut: 'ouvert',
        created_at: new Date().toISOString(),
      };
      if (lat !== null) row.lat = lat;
      if (lng !== null) row.lng = lng;
      const maxN = parseInt(maxParticipants);
      if (maxN >= 2) row.participants_max = maxN;
      row.espece = espece;
      row.toutes_races = toutesRaces;
      if (!toutesRaces && races.trim()) row.races = races.trim();

      const { error: err } = await supabase.from('promenades').insert(row);
      if (err) throw err;
      onCreated();
      onClose();
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
          <h2 className="font-bold text-lg" style={{ fontFamily: 'Galey, sans-serif' }}>
            Organiser une promenade
          </h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl">✕</button>
        </div>

        <div className="p-5 flex flex-col gap-4">
          {/* Titre */}
          <div>
            <label className="block text-[12px] font-semibold text-gray-500 mb-1">Titre *</label>
            <input
              value={titre} onChange={e => setTitre(e.target.value)}
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-[14px] focus:outline-none focus:border-[#2E7D5E]"
              placeholder="Ex : Balade au bord du lac"
            />
          </div>

          {/* Lieu avec Google Places */}
          <div className="relative">
            <label className="block text-[12px] font-semibold text-gray-500 mb-1">Lieu de rendez-vous *</label>
            <div className="relative">
              <span className="absolute left-3 top-1/2 -translate-y-1/2 text-[#2E7D5E] text-[15px]">🔍</span>
              <input
                value={lieu} onChange={e => onLieuChange(e.target.value)}
                className="w-full border border-gray-200 rounded-xl pl-8 pr-8 py-2.5 text-[14px] focus:outline-none focus:border-[#2E7D5E]"
                placeholder="Rechercher une adresse…"
              />
              {loadingPred && (
                <span className="absolute right-3 top-1/2 -translate-y-1/2">
                  <span className="w-4 h-4 border-2 border-[#2E7D5E] border-t-transparent rounded-full animate-spin inline-block" />
                </span>
              )}
              {!loadingPred && lat !== null && (
                <span className="absolute right-3 top-1/2 -translate-y-1/2 text-[#2E7D5E] text-[16px]">✓</span>
              )}
            </div>
            {predictions.length > 0 && (
              <div className="absolute z-10 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg overflow-hidden">
                {predictions.slice(0, 5).map(pred => (
                  <button
                    key={pred.place_id}
                    onClick={() => selectPrediction(pred)}
                    className="w-full text-left px-4 py-2.5 text-[13px] hover:bg-gray-50 border-b border-gray-50 last:border-0 flex items-center gap-2"
                  >
                    <span className="text-[#2E7D5E]">📍</span>
                    <span className="truncate">{pred.description}</span>
                  </button>
                ))}
              </div>
            )}
            {lat !== null && (
              <p className="text-[11px] text-[#2E7D5E] mt-1 flex items-center gap-1">
                <span>🧭</span> Position géolocalisée — bouton Y aller disponible
              </p>
            )}
          </div>

          {/* Date + heure */}
          <div>
            <label className="block text-[12px] font-semibold text-gray-500 mb-1">Date et heure *</label>
            <input
              type="datetime-local"
              value={dateHeure} onChange={e => setDateHeure(e.target.value)}
              min={new Date().toISOString().slice(0, 16)}
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-[14px] focus:outline-none focus:border-[#2E7D5E]"
            />
          </div>

          {/* Niveau + Durée + Max participants */}
          <div className="grid grid-cols-3 gap-3">
            <div>
              <label className="block text-[12px] font-semibold text-gray-500 mb-1">Niveau</label>
              <select
                value={niveau} onChange={e => setNiveau(e.target.value)}
                className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-[14px] focus:outline-none focus:border-[#2E7D5E] bg-white"
              >
                <option value="facile">Facile</option>
                <option value="moyen">Moyen</option>
                <option value="difficile">Difficile</option>
              </select>
            </div>
            <div>
              <label className="block text-[12px] font-semibold text-gray-500 mb-1">Durée (min)</label>
              <input
                type="number" min="10" max="480"
                value={duree} onChange={e => setDuree(e.target.value)}
                className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-[14px] focus:outline-none focus:border-[#2E7D5E]"
                placeholder="60"
              />
            </div>
            <div>
              <label className="block text-[12px] font-semibold text-gray-500 mb-1">Max participants</label>
              <input
                type="number" min="2" max="50"
                value={maxParticipants} onChange={e => setMaxParticipants(e.target.value)}
                className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-[14px] focus:outline-none focus:border-[#2E7D5E]"
                placeholder="Illimité"
              />
            </div>
          </div>

          {/* Description */}
          <div>
            <label className="block text-[12px] font-semibold text-gray-500 mb-1">Description</label>
            <textarea
              value={description} onChange={e => setDescription(e.target.value)}
              rows={3}
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-[14px] focus:outline-none focus:border-[#2E7D5E] resize-none"
              placeholder="Parcours, équipement recommandé…"
            />
          </div>

          {/* Espèce */}
          <div>
            <label className="block text-[12px] font-semibold text-gray-500 mb-2">Espèce concernée</label>
            <div className="flex flex-wrap gap-2">
              {ESPECES.map(e => (
                <button key={e} type="button" onClick={() => setEspece(e)}
                  className="px-3 py-1.5 rounded-full text-[12px] font-semibold transition-colors"
                  style={espece === e
                    ? { backgroundColor: '#2E7D5E', color: '#fff' }
                    : { backgroundColor: '#F5F5F5', color: '#555' }}>
                  {especeEmoji(e)}
                </button>
              ))}
            </div>
          </div>

          {/* Toutes races */}
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
            <input
              value={races} onChange={e => setRaces(e.target.value)}
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-[14px] focus:outline-none focus:border-[#2E7D5E]"
              placeholder="Ex : Golden Retriever, Labrador…"
            />
          )}

          {error && <p className="text-red-500 text-[13px]">{error}</p>}

          <button
            onClick={handleSave}
            disabled={saving}
            className="w-full py-3 rounded-xl font-bold text-white text-[15px] transition-opacity"
            style={{ backgroundColor: '#EF6C00', opacity: saving ? 0.6 : 1 }}
          >
            {saving ? 'Publication…' : 'Publier la promenade'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Page principale ────────────────────────────────────────────────────────────

export default function PromenadePage() {
  const { user } = useAuth();
  const router = useRouter();

  const [promenades, setPromenades] = useState<Promenade[]>([]);
  const [mesParticipations, setMesParticipations] = useState<Record<string, string>>({});
  const [loadingToggle, setLoadingToggle] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [showCreate, setShowCreate] = useState(false);
  const [filterEspece, setFilterEspece] = useState('Toutes');
  const [filterLieu, setFilterLieu] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const cutoff = new Date(Date.now() - 86400000).toISOString();
      const { data: promData } = await supabase
        .from('promenades')
        .select('*, promenades_participants(count)')
        .eq('statut', 'ouvert')
        .gte('date_heure', cutoff)
        .order('date_heure');

      setPromenades((promData ?? []) as Promenade[]);

      if (user) {
        const { data: partData } = await supabase
          .from('promenades_participants')
          .select('promenade_id, statut')
          .eq('user_uid', user.uid);
        const map: Record<string, string> = {};
        (partData ?? []).forEach((r: { promenade_id: string; statut: string }) => {
          map[r.promenade_id] = r.statut ?? 'accepte';
        });
        setMesParticipations(map);
      }
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => { load(); }, [load]);

  async function toggleParticipation(id: string) {
    if (!user) return;
    const estDedans = !!mesParticipations[id];
    setLoadingToggle(id);
    setMesParticipations(prev => {
      const next = { ...prev };
      if (estDedans) delete next[id]; else next[id] = 'en_attente';
      return next;
    });
    try {
      if (estDedans) {
        await supabase.from('promenades_participants')
          .delete().eq('promenade_id', id).eq('user_uid', user.uid);
      } else {
        await supabase.from('promenades_participants').insert({
          promenade_id: id, user_uid: user.uid,
          statut: 'en_attente', rejoint_at: new Date().toISOString(),
        });
        // Notifier l'organisateur
        const promenade = promenades.find(p => p.id === id);
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
            read: false, created_at: new Date().toISOString(),
          });
        }
      }
      await load();
    } catch {
      setMesParticipations(prev => {
        const next = { ...prev };
        if (estDedans) next[id] = 'accepte'; else delete next[id];
        return next;
      });
    } finally {
      setLoadingToggle(null);
    }
  }

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-[#2E7D5E] text-white px-4 py-4 flex items-center justify-between shadow-sm">
        <div className="flex items-center gap-3">
          <button onClick={() => history.back()} className="text-white/80 hover:text-white">
            ←
          </button>
          <h1 className="font-bold text-lg" style={{ fontFamily: 'Galey, sans-serif' }}>
            🐕🐴 Promenades & Randonnées
          </h1>
        </div>
        {user && (
          <button
            onClick={() => setShowCreate(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-full font-bold text-[13px]"
            style={{ backgroundColor: '#EF6C00', color: '#fff' }}
          >
            + Organiser
          </button>
        )}
      </div>

      {/* Filtres */}
      <div className="bg-white border-b border-gray-100 px-4 py-3 flex flex-col gap-2 max-w-2xl mx-auto">
        {/* Lieu */}
        <div className="relative">
          <span className="absolute left-3 top-1/2 -translate-y-1/2 text-[#2E7D5E] text-[14px]">📍</span>
          <input
            value={filterLieu} onChange={e => setFilterLieu(e.target.value)}
            className="w-full bg-gray-50 rounded-xl pl-8 pr-8 py-2 text-[13px] focus:outline-none focus:ring-1 focus:ring-[#2E7D5E] border-none"
            placeholder="Filtrer par ville, département, région…"
          />
          {filterLieu && (
            <button onClick={() => setFilterLieu('')}
              className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 text-[14px]">✕</button>
          )}
        </div>
        {/* Espèce chips */}
        <div className="flex gap-2 overflow-x-auto pb-0.5 scrollbar-hide">
          {ESPECES.map(e => (
            <button key={e} onClick={() => setFilterEspece(e)}
              className="shrink-0 px-3 py-1 rounded-full text-[12px] font-semibold transition-colors"
              style={filterEspece === e
                ? { backgroundColor: '#2E7D5E', color: '#fff' }
                : { backgroundColor: '#F0F0F0', color: '#666' }}>
              {especeEmoji(e)}
            </button>
          ))}
        </div>
      </div>

      {/* Contenu */}
      <div className="max-w-2xl mx-auto px-4 py-5">
        {loading ? (
          <div className="flex justify-center py-20">
            <div className="w-8 h-8 border-2 border-[#EF6C00] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : (() => {
          const filtered = promenades.filter(p => {
            const esp = p.espece ?? 'Toutes espèces';
            if (filterEspece !== 'Toutes' && esp !== 'Toutes' && esp !== 'Toutes espèces' && esp !== filterEspece) return false;
            if (filterLieu.trim()) {
              const adresse = (p.lieu_rdv ?? '').toLowerCase();
              if (!adresse.includes(filterLieu.toLowerCase().trim())) return false;
            }
            return true;
          });
          return filtered.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-24 text-gray-400">
              <span className="text-6xl mb-4">🦮</span>
              <p className="font-bold text-lg text-gray-500">Aucune promenade à venir</p>
              <p className="text-[14px] mt-1">Organisez la première !</p>
              {user && (
                <button
                  onClick={() => setShowCreate(true)}
                  className="mt-6 px-6 py-2.5 rounded-full font-bold text-white text-[14px]"
                  style={{ backgroundColor: '#EF6C00' }}
                >
                  + Organiser une promenade
                </button>
              )}
            </div>
          ) : (
            <div className="flex flex-col gap-3">
              {filtered.map(p => (
                <PromenadesCard
                  key={p.id}
                  p={p}
                  myStatut={mesParticipations[p.id]}
                  onToggle={() => toggleParticipation(p.id)}
                  loading={loadingToggle === p.id}
                  onClick={() => router.push(`/promenades/${p.id}`)}
                />
              ))}
            </div>
          );
        })()}
      </div>

      {showCreate && (
        <CreateModal onClose={() => setShowCreate(false)} onCreated={load} />
      )}
    </div>
  );
}
