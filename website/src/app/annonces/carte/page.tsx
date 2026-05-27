'use client';

import { useEffect, useState, useRef, Suspense } from 'react';
import { useSearchParams } from 'next/navigation';
import Link from 'next/link';
import dynamic from 'next/dynamic';
import { supabase } from '@/lib/supabase';
import { PAYS_LIST, REGIONS_BY_PAYS, departmentsInRegion } from '@/lib/french-geo';
import type { AnnonceMapItem } from '@/components/AnnoncesMap';

const AnnoncesMap = dynamic(() => import('@/components/AnnoncesMap'), {
  ssr: false,
  loading: () => (
    <div className="flex items-center justify-center h-full bg-gray-100">
      <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
    </div>
  ),
});

interface RawAnnonce {
  id: string;
  titre?: string;
  espece?: string;
  race?: string;
  type?: string;
  type_vente?: string;
  photos?: string[];
  prix?: number;
  prix_min_portee?: number;
  prix_max_portee?: number;
  ville_eleveur?: string;
  region_eleveur?: string;
  departement_eleveur?: string;
  pays_eleveur?: string;
  nom_eleveur?: string;
  lat?: number;
  lng?: number;
}

const CACHE_KEY = 'annonces_geocode_cache';
const ESPECES = ['tous', 'chien', 'chat', 'lapin', 'oiseau', 'reptile', 'autre'];
const ESPECE_LABEL: Record<string, string> = {
  tous: 'Toutes', chien: 'Chien', chat: 'Chat', lapin: 'Lapin',
  oiseau: 'Oiseau', reptile: 'Reptile', autre: 'Autre',
};
const BREED_FILES: Record<string, string> = {
  chien: 'dog_breeds', chat: 'cat_breeds', cheval: 'horse_breeds',
  lapin: 'rabbit_breeds', oiseau: 'bird_breeds', nac: 'nac_breeds',
  ovin: 'sheep_breeds', caprin: 'goat_breeds', porcin: 'pig_breeds',
  reptile: 'nac_breeds',
};

function loadCache(): Record<string, { lat: number; lng: number } | null> {
  try { return JSON.parse(sessionStorage.getItem(CACHE_KEY) ?? '{}'); } catch { return {}; }
}

function saveCache(cache: Record<string, { lat: number; lng: number } | null>) {
  try { sessionStorage.setItem(CACHE_KEY, JSON.stringify(cache)); } catch { /* noop */ }
}

async function geocodeCity(city: string): Promise<{ lat: number; lng: number } | null> {
  try {
    const resp = await fetch(
      `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(city + ', France')}&format=json&limit=1`,
      { headers: { 'User-Agent': 'PetsMatch/1.0 contact@petsmatch.fr' } }
    );
    const data = await resp.json();
    if (data[0]) return { lat: parseFloat(data[0].lat), lng: parseFloat(data[0].lon) };
  } catch { /* noop */ }
  return null;
}

export default function AnnoncesCartePageWrapper() {
  return (
    <Suspense fallback={<div className="flex items-center justify-center h-screen"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>}>
      <AnnoncesCartePage />
    </Suspense>
  );
}

function AnnoncesCartePage() {
  const searchParams = useSearchParams();

  const [items, setItems] = useState<(AnnonceMapItem & { espece?: string; race?: string; pays_eleveur?: string; region_eleveur?: string; departement_eleveur?: string })[]>([]);
  const [loading, setLoading] = useState(true);
  const [progress, setProgress] = useState('');
  const [filtreType, setFiltreType] = useState(() => searchParams.get('type') ?? 'tous');
  const [filtreEspece, setFiltreEspece] = useState(() => searchParams.get('espece') ?? 'tous');
  const [showAdvanced, setShowAdvanced] = useState(() =>
    !!(searchParams.get('race') || searchParams.get('pays') || searchParams.get('region') || searchParams.get('dept') || searchParams.get('ville'))
  );
  const [filtreRace, setFiltreRace] = useState(() => searchParams.get('race') ?? '');
  const [filtrePays, setFiltrePays] = useState(() => searchParams.get('pays') ?? '');
  const [filtreRegion, setFiltreRegion] = useState(() => searchParams.get('region') ?? '');
  const [filtreDept, setFiltreDept] = useState(() => searchParams.get('dept') ?? '');
  const [filtreVille, setFiltreVille] = useState(() => searchParams.get('ville') ?? '');

  // Race autocomplete
  const [breeds, setBreeds] = useState<string[]>([]);
  const [raceSugg, setRaceSugg] = useState<string[]>([]);
  const [showRaceSugg, setShowRaceSugg] = useState(false);
  const raceRef = useRef<HTMLDivElement>(null);

  const abortRef = useRef(false);

  useEffect(() => {
    abortRef.current = false;
    supabase
      .from('annonces')
      .select('id, titre, espece, race, type, type_vente, photos, prix, prix_min_portee, prix_max_portee, ville_eleveur, region_eleveur, departement_eleveur, pays_eleveur, nom_eleveur, lat, lng')
      .eq('statut', 'disponible')
      .then(async ({ data }) => {
        const rows = (data ?? []) as RawAnnonce[];
        setLoading(false);

        const ready = rows
          .filter(a => a.lat != null && a.lng != null)
          .map(a => ({ ...(a as AnnonceMapItem & RawAnnonce), lat: a.lat!, lng: a.lng! }));
        setItems([...ready]);

        const needsGeocode = rows.filter(a => (a.lat == null || a.lng == null) && a.ville_eleveur);
        const uniqueCities = [...new Set(needsGeocode.map(a => a.ville_eleveur!))];
        const cache = loadCache();

        for (let i = 0; i < uniqueCities.length; i++) {
          if (abortRef.current) break;
          const city = uniqueCities[i];
          setProgress(`Localisation ${i + 1}/${uniqueCities.length}…`);

          if (!(city in cache)) {
            cache[city] = await geocodeCity(city);
            saveCache(cache);
            if (i < uniqueCities.length - 1) {
              await new Promise(r => setTimeout(r, 1100));
            }
          }

          const coords = cache[city];
          if (coords) {
            const newItems = needsGeocode
              .filter(a => a.ville_eleveur === city)
              .map(a => ({ ...(a as AnnonceMapItem & RawAnnonce), lat: coords.lat, lng: coords.lng }));
            setItems(prev => [...prev, ...newItems]);
          }
        }
        setProgress('');
      });

    return () => { abortRef.current = true; };
  }, []);

  // Load breeds when espece changes
  useEffect(() => {
    const file = BREED_FILES[filtreEspece];
    if (!file) { setBreeds([]); return; }
    fetch(`/breeds/${file}.json`).then(r => r.json()).then(setBreeds).catch(() => setBreeds([]));
  }, [filtreEspece]);

  // Close race suggestions on outside click
  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (raceRef.current && !raceRef.current.contains(e.target as Node)) {
        setShowRaceSugg(false);
      }
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, []);

  const regions = filtrePays ? (REGIONS_BY_PAYS[filtrePays] ?? []) : [];
  const departments = filtreRegion ? departmentsInRegion(filtreRegion) : [];

  const activeFilterCount = [filtreEspece !== 'tous' ? filtreEspece : '', filtreRace, filtrePays, filtreRegion, filtreDept, filtreVille].filter(Boolean).length;

  const filtered = items.filter(a => {
    if (filtreType === 'saillie') { if (a.type_vente !== 'saillie') return false; }
    else if (filtreType === 'vente') { if (a.type_vente === 'saillie') return false; }
    if (filtreEspece !== 'tous' && a.espece?.toLowerCase() !== filtreEspece) return false;
    if (filtreRace && !a.race?.toLowerCase().includes(filtreRace.toLowerCase())) return false;
    if (filtrePays && a.pays_eleveur && !a.pays_eleveur.toLowerCase().includes(filtrePays.toLowerCase())) return false;
    if (filtreRegion && a.region_eleveur && !a.region_eleveur.toLowerCase().includes(filtreRegion.toLowerCase())) return false;
    if (filtreDept && a.departement_eleveur && !a.departement_eleveur.toLowerCase().includes(filtreDept.toLowerCase())) return false;
    if (filtreVille && a.ville_eleveur && !a.ville_eleveur.toLowerCase().includes(filtreVille.toLowerCase())) return false;
    return true;
  });

  function onRaceInput(val: string) {
    setFiltreRace(val);
    if (!val) { setRaceSugg([]); setShowRaceSugg(false); return; }
    const q = val.toLowerCase();
    const m = breeds.filter(b => b.toLowerCase().includes(q)).slice(0, 5);
    setRaceSugg(m); setShowRaceSugg(m.length > 0);
  }

  function resetAdvanced() {
    setFiltreRace(''); setFiltrePays(''); setFiltreRegion('');
    setFiltreDept(''); setFiltreVille('');
    setRaceSugg([]); setShowRaceSugg(false);
  }

  return (
    <div className="flex flex-col" style={{ height: '100dvh' }}>
      {/* Header */}
      <div className="bg-[#0C5C6C] text-white px-4 py-3 flex items-center gap-3 flex-shrink-0">
        <Link href="/annonces"
          className="w-8 h-8 rounded-full bg-white/20 hover:bg-white/30 flex items-center justify-center transition-colors text-sm font-bold">
          ←
        </Link>
        <div className="flex-1">
          <h1 className="font-bold text-base leading-none" style={{ fontFamily: 'Galey, sans-serif' }}>
            Carte des annonces
          </h1>
          {progress ? (
            <p className="text-white/60 text-xs mt-0.5">{progress}</p>
          ) : (
            <p className="text-white/60 text-xs mt-0.5">{filtered.length} annonce{filtered.length !== 1 ? 's' : ''} affichée{filtered.length !== 1 ? 's' : ''}</p>
          )}
        </div>
        {(loading || progress) && (
          <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin flex-shrink-0" />
        )}
        <Link href="/annonces/feed"
          className="flex items-center gap-1.5 bg-white/15 hover:bg-white/25 px-3 py-1.5 rounded-xl text-xs font-semibold transition-colors flex-shrink-0">
          ▶ Feed
        </Link>
      </div>

      {/* Filtres */}
      <div className="bg-white border-b border-gray-100 px-4 py-2 flex flex-col gap-2 flex-shrink-0">
        {/* Row 1: type + espèce + filtres button */}
        <div className="flex gap-2 overflow-x-auto items-center">
          {[
            { value: 'tous', label: 'Tous' },
            { value: 'vente', label: '🐾 Compagnon' },
            { value: 'saillie', label: '💜 Saillie' },
          ].map(t => (
            <button key={t.value} onClick={() => setFiltreType(t.value)}
              className={`flex-shrink-0 px-3 py-1 rounded-full text-xs font-medium transition-colors border ${
                filtreType === t.value
                  ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]'
                  : 'bg-white text-gray-600 border-gray-200 hover:border-[#0C5C6C]'
              }`}>
              {t.label}
            </button>
          ))}
          <div className="w-px h-4 bg-gray-200 flex-shrink-0" />
          {ESPECES.map(esp => (
            <button key={esp} onClick={() => setFiltreEspece(esp)}
              className={`flex-shrink-0 px-3 py-1 rounded-full text-xs font-medium transition-colors border ${
                filtreEspece === esp
                  ? 'bg-[#6E9E57] text-white border-[#6E9E57]'
                  : 'bg-white text-gray-600 border-gray-200 hover:border-[#6E9E57]'
              }`}>
              {ESPECE_LABEL[esp] ?? esp}
            </button>
          ))}
          <div className="w-px h-4 bg-gray-200 flex-shrink-0" />
          <button
            onClick={() => setShowAdvanced(v => !v)}
            className={`relative flex-shrink-0 flex items-center gap-1 px-3 py-1 rounded-full text-xs font-medium transition-colors border ${
              showAdvanced || activeFilterCount > 0
                ? 'bg-[#1F2A2E] text-white border-[#1F2A2E]'
                : 'bg-white text-gray-600 border-gray-200 hover:border-[#1F2A2E]'
            }`}>
            ⚙ Filtres
            {activeFilterCount > 0 && (
              <span className="ml-0.5 w-4 h-4 bg-[#6E9E57] rounded-full text-white text-[10px] font-bold inline-flex items-center justify-center">
                {activeFilterCount}
              </span>
            )}
          </button>
        </div>

        {/* Advanced panel */}
        {showAdvanced && (
          <div className="flex flex-col gap-2 pb-1">
            {/* Race */}
            <div ref={raceRef} className="relative">
              <input
                type="text"
                placeholder={filtreEspece === 'tous' ? 'Race (toutes espèces)' : `Race · ${ESPECE_LABEL[filtreEspece]}`}
                value={filtreRace}
                onChange={(e) => onRaceInput(e.target.value)}
                onFocus={() => raceSugg.length > 0 && setShowRaceSugg(true)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-xs focus:outline-none focus:border-[#0C5C6C] bg-white"
              />
              {showRaceSugg && raceSugg.length > 0 && (
                <div className="absolute z-20 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-lg shadow-lg overflow-hidden">
                  {raceSugg.map(b => (
                    <button key={b} onMouseDown={() => { setFiltreRace(b); setShowRaceSugg(false); }}
                      className="w-full text-left px-3 py-2 text-xs hover:bg-gray-50 text-[#1F2A2E]">
                      {b}
                    </button>
                  ))}
                </div>
              )}
            </div>
            {/* Pays + Région + Département + Ville */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
              <select
                value={filtrePays}
                onChange={(e) => { setFiltrePays(e.target.value); setFiltreRegion(''); setFiltreDept(''); }}
                className="border border-gray-200 rounded-lg px-2 py-2 text-xs focus:outline-none focus:border-[#0C5C6C] bg-white">
                <option value="">Tous les pays</option>
                {PAYS_LIST.map(p => <option key={p} value={p}>{p}</option>)}
              </select>
              <select
                value={filtreRegion}
                onChange={(e) => { setFiltreRegion(e.target.value); setFiltreDept(''); }}
                disabled={regions.length === 0}
                className="border border-gray-200 rounded-lg px-2 py-2 text-xs focus:outline-none focus:border-[#0C5C6C] bg-white disabled:opacity-50">
                <option value="">{filtrePays ? 'Toutes régions' : 'Pays d\'abord'}</option>
                {regions.map(r => <option key={r} value={r}>{r}</option>)}
              </select>
              <select
                value={filtreDept}
                onChange={(e) => setFiltreDept(e.target.value)}
                disabled={departments.length === 0}
                className="border border-gray-200 rounded-lg px-2 py-2 text-xs focus:outline-none focus:border-[#0C5C6C] bg-white disabled:opacity-50">
                <option value="">{filtreRegion ? 'Tous depts.' : 'Région d\'abord'}</option>
                {departments.map(d => <option key={d} value={d}>{d}</option>)}
              </select>
              <input
                type="text"
                placeholder="Ville…"
                value={filtreVille}
                onChange={(e) => setFiltreVille(e.target.value)}
                className="border border-gray-200 rounded-lg px-3 py-2 text-xs focus:outline-none focus:border-[#0C5C6C] bg-white"
              />
            </div>
            {activeFilterCount > 0 && (
              <button onClick={resetAdvanced} className="self-start text-xs text-gray-400 hover:text-gray-600 underline">
                Réinitialiser les filtres
              </button>
            )}
          </div>
        )}
      </div>

      {/* Carte */}
      <div className="flex-1 relative overflow-hidden">
        {loading ? (
          <div className="absolute inset-0 flex items-center justify-center bg-gray-100">
            <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : (
          <AnnoncesMap annonces={filtered} />
        )}

        {/* Légende */}
        <div className="absolute bottom-4 left-4 bg-white rounded-xl shadow-lg border border-gray-200 px-3 py-2 z-[1000] pointer-events-none">
          <div className="flex items-center gap-1.5 mb-1">
            <div className="w-3 h-3 rounded-full bg-[#6E9E57]" />
            <span className="text-xs text-gray-600">Compagnon / Portée</span>
          </div>
          <div className="flex items-center gap-1.5">
            <div className="w-3 h-3 rounded-full bg-[#8B5CF6]" />
            <span className="text-xs text-gray-600">Saillie</span>
          </div>
        </div>
      </div>
    </div>
  );
}
