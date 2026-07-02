'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import dynamic from 'next/dynamic';
import { supabase } from '@/lib/supabase';

const PetFriendlyPlacesMap = dynamic(() => import('@/components/PetFriendlyPlacesMap'), {
  ssr: false,
  loading: () => (
    <div className="flex items-center justify-center h-full bg-gray-100 rounded-2xl">
      <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
    </div>
  ),
});

// ── Types ──────────────────────────────────────────────────────────────────────

interface Lieu {
  id: string;
  nom: string;
  categorie: string;
  ville?: string | null;
  lat?: number | null;
  lng?: number | null;
  especes_acceptees?: string[] | null;
  horaires?: Record<string, string> | null;
  photo_profil_url?: string | null;
  banniere_url?: string | null;
  photos?: string[] | null;
  note_moyenne?: number | null;
  nb_avis?: number | null;
  plan?: string | null;
}

// ── Constantes ─────────────────────────────────────────────────────────────────

const CATEGORIES: { value: string; label: string; icon: string }[] = [
  { value: 'tous', label: 'Tout', icon: '🧭' },
  { value: 'hebergement', label: 'Hébergements', icon: '🏨' },
  { value: 'restauration', label: 'Cafés & Restos', icon: '🍽️' },
];

const ESPECES: { value: string; label: string }[] = [
  { value: 'tous', label: 'Toutes espèces' },
  { value: 'chien', label: '🐶 Chien' },
  { value: 'chat', label: '🐱 Chat' },
  { value: 'cheval', label: '🐴 Cheval' },
  { value: 'lapin', label: '🐰 Lapin' },
];

const DAYS = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

function parseMins(s: string): number {
  const [h, m] = s.trim().split(':');
  return parseInt(h, 10) * 60 + parseInt(m, 10);
}

function ouvertLabel(horaires?: Record<string, string> | null): string {
  if (!horaires || Object.keys(horaires).length === 0) return '';
  const now = new Date();
  const dayKey = DAYS[(now.getDay() + 6) % 7];
  const val = horaires[dayKey];
  if (!val || val.toLowerCase().startsWith('ferm')) return '🔴 Fermé';
  const parts = val.split('-');
  if (parts.length < 2) return '';
  try {
    const t = now.getHours() * 60 + now.getMinutes();
    const open = parseMins(parts[0]);
    const close = parseMins(parts[1]);
    if (t >= open && t < close) return '🟢 Ouvert';
    return '🔴 Fermé';
  } catch {
    return '';
  }
}

function photoUrl(lieu: Lieu): string {
  if (lieu.banniere_url) return lieu.banniere_url;
  if (lieu.photos && lieu.photos.length > 0) return lieu.photos[0];
  return lieu.photo_profil_url ?? '';
}

// ── Composants ─────────────────────────────────────────────────────────────────

function LieuCard({ lieu }: { lieu: Lieu }) {
  const isHeb = lieu.categorie === 'hebergement';
  const photo = photoUrl(lieu);
  const ouvert = ouvertLabel(lieu.horaires);
  const isPremium = lieu.plan === 'premium';
  const note = lieu.note_moyenne ?? 0;

  return (
    <Link
      href={`/animal-friendly/${lieu.id}`}
      className="bg-white rounded-2xl overflow-hidden shadow-sm border border-gray-100 hover:shadow-md transition-shadow block"
    >
      <div className="relative h-40">
        {photo ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={photo} alt={lieu.nom} className="absolute inset-0 w-full h-full object-cover" />
        ) : (
          <div
            className="absolute inset-0 flex items-center justify-center text-5xl"
            style={{ backgroundColor: isHeb ? '#E3F2FD' : '#FFF3E0' }}
          >
            {isHeb ? '🏨' : '🍽️'}
          </div>
        )}
        {ouvert && (
          <span className="absolute top-3 left-3 text-[11px] font-semibold text-white bg-black/55 px-2.5 py-1 rounded-full">
            {ouvert}
          </span>
        )}
        {isPremium && (
          <span className="absolute top-3 right-3 text-[11px] font-bold text-white px-2.5 py-1 rounded-full bg-[#FFA000]">
            ⭐ Recommandé
          </span>
        )}
      </div>
      <div className="px-3.5 py-3">
        <p className="font-bold text-[13px] text-[#1E2025] line-clamp-2" style={{ fontFamily: 'Galey, sans-serif' }}>
          {lieu.nom}
        </p>
        {lieu.ville && (
          <p className="text-[11px] text-gray-500 mt-1 flex items-center gap-1">
            📍 {lieu.ville}
          </p>
        )}
        {note > 0 && (
          <p className="text-[11px] text-gray-700 mt-1 flex items-center gap-1">
            <span className="text-[#FFA000]">★</span> {note.toFixed(1)} <span className="text-gray-400">({lieu.nb_avis ?? 0})</span>
          </p>
        )}
      </div>
    </Link>
  );
}

// ── Page ───────────────────────────────────────────────────────────────────────

export default function AnimalFriendlyPage() {
  const [lieux, setLieux] = useState<Lieu[]>([]);
  const [loading, setLoading] = useState(true);
  const [categorie, setCategorie] = useState('tous');
  const [espece, setEspece] = useState('tous');
  const [view, setView] = useState<'liste' | 'carte'>('liste');

  async function loadLieux() {
    setLoading(true);
    try {
      const { data } = await supabase
        .from('petfriendly_places')
        .select('id, nom, categorie, ville, lat, lng, especes_acceptees, horaires, photo_profil_url, banniere_url, photos, note_moyenne, nb_avis, plan')
        .eq('statut', 'actif')
        .order('created_at', { ascending: false })
        .limit(300);
      setLieux((data ?? []) as Lieu[]);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { loadLieux(); }, []);

  let filtered = categorie === 'tous' ? lieux : lieux.filter(l => l.categorie === categorie);
  if (espece !== 'tous') {
    filtered = filtered.filter(l => (l.especes_acceptees ?? []).includes(espece));
  }
  const withCoords = filtered.filter(
    (p): p is Lieu & { lat: number; lng: number } => p.lat != null && p.lng != null,
  );

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Hero */}
      <div className="bg-[#0C5C6C] text-white px-4 py-8">
        <div className="max-w-3xl mx-auto text-center">
          <p className="text-4xl mb-2">🐾</p>
          <h1 className="text-2xl font-bold mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>
            Lieux Pet-Friendly
          </h1>
          <p className="text-white/70 text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>
            Hébergements, cafés & restaurants qui accueillent vos animaux
          </p>
        </div>
      </div>

      <div className="max-w-4xl mx-auto px-4 py-6">
        {/* Filtres catégorie */}
        <div className="flex gap-2 overflow-x-auto pb-2 mb-3 scrollbar-hide">
          {CATEGORIES.map(c => (
            <button
              key={c.value}
              onClick={() => setCategorie(c.value)}
              className="flex-shrink-0 flex items-center gap-1.5 px-4 py-2 rounded-full text-sm font-semibold transition-all"
              style={{
                fontFamily: 'Galey, sans-serif',
                backgroundColor: categorie === c.value ? '#0C5C6C' : '#FFFFFF',
                color: categorie === c.value ? '#FFFFFF' : '#6B7280',
                border: `1.5px solid ${categorie === c.value ? '#0C5C6C' : '#E5E7EB'}`,
              }}
            >
              {c.icon} {c.label}
            </button>
          ))}
        </div>

        {/* Filtres espèce */}
        <div className="flex gap-2 overflow-x-auto pb-2 mb-5 scrollbar-hide">
          {ESPECES.map(e => (
            <button
              key={e.value}
              onClick={() => setEspece(e.value)}
              className="flex-shrink-0 px-3.5 py-1.5 rounded-full text-xs font-medium transition-all"
              style={{
                fontFamily: 'Galey, sans-serif',
                backgroundColor: espece === e.value ? '#0C5C6C1A' : 'transparent',
                color: espece === e.value ? '#0C5C6C' : '#6B7280',
                border: `1px solid ${espece === e.value ? '#0C5C6C' : '#E5E7EB'}`,
              }}
            >
              {e.label}
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

        {/* Contenu */}
        {loading ? (
          <div className="flex justify-center py-20">
            <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : view === 'carte' ? (
          <div className="rounded-2xl overflow-hidden border border-gray-200 shadow-sm" style={{ height: '65vh' }}>
            <PetFriendlyPlacesMap places={withCoords} />
          </div>
        ) : filtered.length === 0 ? (
          <div className="text-center py-20 flex flex-col items-center gap-3">
            <span className="text-6xl">📍</span>
            <p className="font-bold text-gray-700" style={{ fontFamily: 'Galey, sans-serif' }}>
              Aucun lieu pet-friendly pour l&apos;instant
            </p>
            <p className="text-sm text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>
              Revenez bientôt, de nouveaux établissements arrivent régulièrement.
            </p>
          </div>
        ) : (
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-4">
            {filtered.map(lieu => <LieuCard key={lieu.id} lieu={lieu} />)}
          </div>
        )}
      </div>
    </div>
  );
}
