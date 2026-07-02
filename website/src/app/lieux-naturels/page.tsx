'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import dynamic from 'next/dynamic';
import { supabase } from '@/lib/supabase';
import type { NaturalPlaceMapItem } from '@/components/NaturalPlacesMap';

const NaturalPlacesMap = dynamic(() => import('@/components/NaturalPlacesMap'), {
  ssr: false,
  loading: () => (
    <div className="flex items-center justify-center h-full bg-gray-100 rounded-2xl">
      <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
    </div>
  ),
});

// ── Types ──────────────────────────────────────────────────────────────────────

interface NaturalPlace {
  id: string;
  nom: string;
  categorie: string;
  lat: number | null;
  lng: number | null;
  alerte_cyano: boolean | null;
  nb_avis: number | null;
  note_moyenne: number | null;
  photo_url?: string | null;
}

// ── Constantes (identiques à l'app) ─────────────────────────────────────────────

const CAT_EMOJI: Record<string, string> = {
  foret: '🌲', plage: '🏖️', parc: '🌿', lac: '💧', riviere: '🏞️',
};
const CAT_LABEL: Record<string, string> = {
  foret: 'Forêt', plage: 'Plage', parc: 'Parc', lac: 'Lac', riviere: 'Rivière',
};
const CAT_COLOR: Record<string, string> = {
  foret: '#2E7D32', plage: '#1565C0', parc: '#558B2F', lac: '#00838F', riviere: '#0277BD',
};
const CAT_GRADIENT: Record<string, string> = {
  foret: 'linear-gradient(135deg, #1B5E20, #388E3C)',
  plage: 'linear-gradient(135deg, #0D47A1, #0288D1)',
  parc: 'linear-gradient(135deg, #33691E, #7CB342)',
  lac: 'linear-gradient(135deg, #006064, #00ACC1)',
  riviere: 'linear-gradient(135deg, #01579B, #039BE5)',
};

const CATEGORIES = Object.keys(CAT_LABEL);

// ── Aide distance ─────────────────────────────────────────────────────────────

function distKm(lat: number, lng: number, userLat: number, userLng: number): number {
  const R = 6371;
  const dLat = (lat - userLat) * Math.PI / 180;
  const dLng = (lng - userLng) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(userLat * Math.PI / 180) * Math.cos(lat * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function distLabel(km: number): string {
  if (km < 1) return '< 1 km';
  if (km < 10) return `${km.toFixed(1)} km`;
  return `${Math.round(km)} km`;
}

// ── Page ───────────────────────────────────────────────────────────────────────

export default function LieuxNaturelsPage() {
  const [places, setPlaces] = useState<NaturalPlace[]>([]);
  const [loading, setLoading] = useState(true);
  const [catFilter, setCatFilter] = useState('tous');
  const [search, setSearch] = useState('');
  const [userPos, setUserPos] = useState<{ lat: number; lng: number } | null>(null);
  const [view, setView] = useState<'liste' | 'carte'>('liste');

  async function loadPlaces() {
    setLoading(true);
    try {
      const { data } = await supabase
        .from('natural_places')
        .select('id, nom, categorie, lat, lng, alerte_cyano, nb_avis, note_moyenne, photo_url')
        .order('nom');
      setPlaces((data ?? []) as NaturalPlace[]);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    loadPlaces();
    if (navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(
        (pos) => setUserPos({ lat: pos.coords.latitude, lng: pos.coords.longitude }),
        () => {},
        { enableHighAccuracy: false, timeout: 8000 },
      );
    }
  }, []);

  let filtered = catFilter === 'tous' ? places : places.filter(p => p.categorie === catFilter);
  if (search.trim()) {
    const q = search.trim().toLowerCase();
    filtered = filtered.filter(p => p.nom.toLowerCase().includes(q));
  }
  if (userPos) {
    filtered = [...filtered].sort((a, b) => {
      const da = a.lat != null && a.lng != null ? distKm(a.lat, a.lng, userPos.lat, userPos.lng) : Infinity;
      const db = b.lat != null && b.lng != null ? distKm(b.lat, b.lng, userPos.lat, userPos.lng) : Infinity;
      return da - db;
    });
  }
  const withCoords: NaturalPlaceMapItem[] = filtered.filter(
    (p): p is NaturalPlace & { lat: number; lng: number } => p.lat != null && p.lng != null,
  );

  return (
    <div className="min-h-screen bg-[#F5F5F0]">
      {/* Hero */}
      <div className="bg-[#0C5C6C] text-white px-4 py-8">
        <div className="max-w-3xl mx-auto">
          <h1 className="text-2xl font-bold mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>
            🌲 Lieux Naturels
          </h1>
          <p className="text-white/70 text-sm mb-4" style={{ fontFamily: 'Galey, sans-serif' }}>
            Plages, lacs, parcs & forêts accessibles avec vos animaux
          </p>
          <input
            value={search}
            onChange={e => setSearch(e.target.value)}
            placeholder="Rechercher un lieu..."
            className="w-full rounded-xl px-4 py-2.5 text-sm bg-white/15 text-white placeholder-white/50 focus:outline-none focus:bg-white/25 transition-colors"
            style={{ fontFamily: 'Galey, sans-serif' }}
          />
        </div>
      </div>

      <div className="max-w-3xl mx-auto px-4 py-6">
        {/* Filtres catégorie */}
        <div className="flex gap-2 overflow-x-auto pb-2 mb-5 scrollbar-hide">
          <button
            onClick={() => setCatFilter('tous')}
            className="flex-shrink-0 px-4 py-1.5 rounded-full text-xs font-semibold transition-all"
            style={{
              fontFamily: 'Galey, sans-serif',
              backgroundColor: catFilter === 'tous' ? '#0C5C6C' : 'transparent',
              color: catFilter === 'tous' ? '#FFFFFF' : '#1E2025',
              border: `1.5px solid ${catFilter === 'tous' ? '#0C5C6C' : '#D1D5DB'}`,
            }}
          >
            Tous
          </button>
          {CATEGORIES.map(cat => (
            <button
              key={cat}
              onClick={() => setCatFilter(cat)}
              className="flex-shrink-0 px-4 py-1.5 rounded-full text-xs font-semibold transition-all"
              style={{
                fontFamily: 'Galey, sans-serif',
                backgroundColor: catFilter === cat ? CAT_COLOR[cat] : 'transparent',
                color: catFilter === cat ? '#FFFFFF' : '#1E2025',
                border: `1.5px solid ${catFilter === cat ? CAT_COLOR[cat] : '#D1D5DB'}`,
              }}
            >
              {CAT_EMOJI[cat]} {CAT_LABEL[cat]}
            </button>
          ))}
        </div>

        {/* Compteur + toggle vue */}
        <div className="flex items-center justify-between mb-4">
          <p className="text-sm text-gray-500" style={{ fontFamily: 'Galey, sans-serif' }}>
            {loading ? '…' : `${filtered.length} lieu${filtered.length > 1 ? 'x' : ''}`}
          </p>
          <div className="flex bg-gray-100 rounded-xl p-1">
            <button
              onClick={() => setView('liste')}
              className={`flex items-center gap-1.5 px-3.5 py-1.5 rounded-lg text-xs font-medium transition-colors ${view === 'liste' ? 'bg-white text-[#1F2A2E] shadow-sm' : 'text-gray-500 hover:text-gray-700'}`}
              style={{ fontFamily: 'Galey, sans-serif' }}
            >
              <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 10h16M4 14h16M4 18h16"/>
              </svg>
              Liste
            </button>
            <button
              onClick={() => setView('carte')}
              className={`flex items-center gap-1.5 px-3.5 py-1.5 rounded-lg text-xs font-medium transition-colors ${view === 'carte' ? 'bg-white text-[#1F2A2E] shadow-sm' : 'text-gray-500 hover:text-gray-700'}`}
              style={{ fontFamily: 'Galey, sans-serif' }}
            >
              <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7"/>
              </svg>
              Carte
            </button>
          </div>
        </div>

        {loading ? (
          <div className="flex justify-center py-20">
            <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : view === 'carte' ? (
          <div className="rounded-2xl overflow-hidden border border-gray-200 shadow-sm" style={{ height: '65vh' }}>
            <NaturalPlacesMap places={withCoords} />
          </div>
        ) : filtered.length === 0 ? (
          <div className="text-center py-20 flex flex-col items-center gap-3">
            <span className="text-6xl">🌲</span>
            <p className="font-bold text-gray-700" style={{ fontFamily: 'Galey, sans-serif' }}>
              Aucun lieu naturel disponible
            </p>
            <p className="text-sm text-gray-400 max-w-xs" style={{ fontFamily: 'Galey, sans-serif' }}>
              Les lieux naturels pet-friendly seront bientôt disponibles près de chez vous.
            </p>
          </div>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            {filtered.map(p => (
              <PlaceCard
                key={p.id}
                place={p}
                distLabel={userPos && p.lat != null && p.lng != null
                  ? distLabel(distKm(p.lat, p.lng, userPos.lat, userPos.lng))
                  : null}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

// ── Card lieu ──────────────────────────────────────────────────────────────────

function PlaceCard({ place, distLabel }: { place: NaturalPlace; distLabel: string | null }) {
  const cat = place.categorie;
  const color = CAT_COLOR[cat] ?? '#0C5C6C';
  const gradient = CAT_GRADIENT[cat] ?? 'linear-gradient(135deg, #0C5C6C, #4CAF50)';
  const cyano = place.alerte_cyano === true;
  const nbAvis = place.nb_avis ?? 0;
  const noteMoy = (place.note_moyenne ?? 0).toFixed(1);

  return (
    <Link
      href={`/lieux-naturels/${place.id}`}
      className="bg-white rounded-2xl overflow-hidden shadow-sm border border-gray-100 hover:shadow-md transition-shadow block"
    >
      <div className="relative h-40" style={{ background: gradient }}>
        {place.photo_url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={place.photo_url} alt={place.nom} className="absolute inset-0 w-full h-full object-cover" />
        ) : (
          <div className="absolute inset-0 flex items-center justify-center text-5xl">
            {CAT_EMOJI[cat] ?? '🌿'}
          </div>
        )}
        <div
          className="absolute inset-0"
          style={{ background: 'linear-gradient(to bottom, transparent 45%, rgba(0,0,0,0.65) 100%)' }}
        />
        <span
          className="absolute top-3 left-3 text-xs font-bold text-white px-2.5 py-1 rounded-full"
          style={{ backgroundColor: color, fontFamily: 'Galey, sans-serif' }}
        >
          {CAT_EMOJI[cat]} {CAT_LABEL[cat] ?? cat}
        </span>
        {cyano && (
          <span
            className="absolute top-3 right-3 text-xs font-bold text-white px-2.5 py-1 rounded-full bg-red-600"
            style={{ fontFamily: 'Galey, sans-serif' }}
          >
            ⚠️ Cyano
          </span>
        )}
        <div className="absolute bottom-3 left-3.5 right-3.5 flex items-end justify-between gap-2">
          <p className="text-white font-extrabold text-[17px] leading-snug drop-shadow" style={{ fontFamily: 'Galey, sans-serif' }}>
            {place.nom}
          </p>
          {distLabel && (
            <span className="flex-shrink-0 text-[11px] text-white bg-black/45 px-2 py-1 rounded-full" style={{ fontFamily: 'Galey, sans-serif' }}>
              📍 {distLabel}
            </span>
          )}
        </div>
      </div>
      {nbAvis > 0 && (
        <div className="px-3.5 py-2.5 flex items-center gap-1.5">
          <span className="text-[#FDD835]">★</span>
          <span className="text-xs font-semibold text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>
            {noteMoy} ({nbAvis} avis)
          </span>
        </div>
      )}
    </Link>
  );
}
