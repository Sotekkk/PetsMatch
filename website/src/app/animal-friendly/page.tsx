'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import dynamic from 'next/dynamic';
import { supabase } from '@/lib/supabase';
import { ESPECES_LIEUX } from '@/lib/especes-lieux';
import { referencementLieu, LIBELLE_REFERENCEMENT } from '@/lib/lieux-categories';

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
  uid_pro?: string | null;
  verification?: string | null;
}

// Pictogramme de référencement (trait sobre) : communauté / vérifié / partenaire.
function IconeReferencement({ r }: { r: 'communaute' | 'verifie' | 'partenaire' }) {
  const d = r === 'communaute'
    ? 'M9 11a3 3 0 100-6 3 3 0 000 6zM3 19c0-3 3-5 6-5s6 2 6 5M17 11.5a2.5 2.5 0 100-5M15.5 14.5c3 0 5.5 1.5 5.5 4.5'
    : r === 'verifie' ? 'M12 3l7 3v5c0 5-3.5 8.5-7 10-3.5-1.5-7-5-7-10V6zM9 12l2 2 4-4'
    : 'M12 3l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.4 6.8 19.1l1-5.8L3.5 9.2l5.9-.9z';
  return (
    <svg className="w-3.5 h-3.5 flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d={d} />
    </svg>
  );
}
const COULEUR_REF = { communaute: 'text-gray-600', verifie: 'text-[#0C5C6C]', partenaire: 'text-[#4E7A3B]' } as const;

// ── Constantes ─────────────────────────────────────────────────────────────────

const CATEGORIES: { value: string; label: string }[] = [
  { value: 'tous', label: 'Tout' },
  { value: 'hebergement', label: 'Hébergements' },
  { value: 'restauration', label: 'Cafés & Restos' },
  { value: 'commerce', label: 'Commerces' },
  { value: 'activite', label: 'Activités' },
];

const REFERENCEMENTS: { value: 'tous' | 'communaute' | 'verifie' | 'partenaire'; label: string }[] = [
  { value: 'tous', label: 'Tous les lieux' },
  { value: 'communaute', label: 'Communauté' },
  { value: 'verifie', label: 'Établissements vérifiés' },
  { value: 'partenaire', label: 'Partenaires PetsMatch' },
];

const ESPECES = ESPECES_LIEUX;

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
  const ref = referencementLieu(lieu);
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
          </div>
        )}
        {ouvert && (
          <span className="absolute top-3 left-3 text-[11px] font-semibold text-white bg-black/55 px-2.5 py-1 rounded-full">
            {ouvert}
          </span>
        )}
      </div>
      <div className="px-3.5 py-3">
        <p className="font-bold text-[13px] text-[#1E2025] line-clamp-2" style={{ fontFamily: 'Galey, sans-serif' }}>
          {lieu.nom}
        </p>
        {lieu.ville && <p className="text-[11px] text-gray-500 mt-1">{lieu.ville}</p>}
        <p className={`text-[11px] font-semibold mt-1 flex items-center gap-1 ${COULEUR_REF[ref]}`}>
          <IconeReferencement r={ref} /> {LIBELLE_REFERENCEMENT[ref]}
        </p>
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
  const [referencement, setReferencement] = useState<'tous' | 'communaute' | 'verifie' | 'partenaire'>('tous');
  // Espèces cochées (aucune = toutes) : un lieu correspond s'il accepte au moins l'une d'elles.
  const [especes, setEspeces] = useState<string[]>([]);
  const [view, setView] = useState<'liste' | 'carte'>('liste');

  async function loadLieux() {
    setLoading(true);
    try {
      const { data } = await supabase
        .from('petfriendly_places')
        .select('id, nom, categorie, ville, lat, lng, especes_acceptees, horaires, photo_profil_url, banniere_url, photos, note_moyenne, nb_avis, plan, uid_pro, verification')
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
  if (referencement !== 'tous') filtered = filtered.filter(l => referencementLieu(l) === referencement);
  if (especes.length) {
    filtered = filtered.filter(l => (l.especes_acceptees ?? []).some(e => especes.includes(e)));
  }
  const withCoords = filtered.filter(
    (p): p is Lieu & { lat: number; lng: number } => p.lat != null && p.lng != null,
  );

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Hero */}
      <div className="bg-[#0C5C6C] text-white px-4 py-8">
        <div className="max-w-3xl mx-auto text-center">
          <h1 className="text-2xl font-bold mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>
            Lieux Pet-Friendly
          </h1>
          <p className="text-white/70 text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>
            Hébergements, cafés, restaurants, commerces et activités qui accueillent vos animaux
          </p>
          <Link href="/animal-friendly/recommander"
            className="inline-flex items-center gap-2 mt-4 px-4 py-2 rounded-xl border border-white/50 text-white text-sm font-semibold hover:bg-white/10"
            style={{ fontFamily: 'Galey, sans-serif' }}>
            <svg className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden><path strokeLinecap="round" d="M12 5v14M5 12h14" /></svg>
            Recommander un lieu
          </Link>
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
              {c.label}
            </button>
          ))}
        </div>

        {/* Filtre de référencement (combinable avec catégorie et espèces) */}
        <div role="group" aria-label="Référencement" className="flex gap-2 overflow-x-auto pb-2 mb-3 scrollbar-hide">
          {REFERENCEMENTS.map(r => (
            <button key={r.value} type="button" onClick={() => setReferencement(r.value)} aria-pressed={referencement === r.value}
              className={`flex-shrink-0 flex items-center gap-1.5 px-3.5 py-1.5 rounded-full text-xs font-semibold border transition-colors ${
                referencement === r.value ? 'bg-[#0C5C6C]/10 text-[#0C5C6C] border-[#0C5C6C]' : 'bg-white text-gray-600 border-gray-200'}`}
              style={{ fontFamily: 'Galey, sans-serif' }}>
              {r.value !== 'tous' && <IconeReferencement r={r.value} />}{r.label}
            </button>
          ))}
        </div>

        {/* Filtres espèce */}
        <details className="group relative mb-5 w-full sm:w-72 border border-gray-200 rounded-xl bg-white" style={{ fontFamily: 'Galey, sans-serif' }}>
          <summary className="list-none cursor-pointer flex items-center justify-between gap-3 px-3 py-2.5 text-sm">
            <span className={especes.length ? 'text-[#1F2A2E]' : 'text-gray-500'}>
              {especes.length === 0 || especes.length === ESPECES.length ? 'Toutes espèces'
                : ESPECES.filter(e => especes.includes(e.value)).map(e => e.label).join(', ')}
            </span>
            <svg className="w-4 h-4 text-gray-400 shrink-0 transition-transform group-open:rotate-180" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden>
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
            </svg>
          </summary>
          <div className="absolute left-0 right-0 top-full mt-1 z-20 bg-white border border-gray-200 rounded-xl shadow-lg py-1">
            <label className="flex items-center gap-3 px-3 py-2 text-sm font-semibold cursor-pointer hover:bg-gray-50">
              <input type="checkbox" className="w-4 h-4 accent-[#0C5C6C]"
                checked={especes.length === ESPECES.length}
                onChange={ev => setEspeces(ev.target.checked ? ESPECES.map(e => e.value) : [])} />
              Tout cocher
            </label>
            <div className="border-t border-gray-100 my-1" />
            {ESPECES.map(e => (
              <label key={e.value} className="flex items-center gap-3 px-3 py-2 text-sm cursor-pointer hover:bg-gray-50">
                <input type="checkbox" className="w-4 h-4 accent-[#0C5C6C]"
                  checked={especes.includes(e.value)}
                  onChange={() => setEspeces(prev => prev.includes(e.value) ? prev.filter(x => x !== e.value) : [...prev, e.value])} />
                {e.label}
              </label>
            ))}
          </div>
        </details>

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
            <PetFriendlyPlacesMap places={withCoords.map(p => ({ ...p, referencement: referencementLieu(p) }))} />
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
