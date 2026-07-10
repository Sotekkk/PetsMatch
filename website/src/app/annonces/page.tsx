'use client';

import { useEffect, useState, useRef } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { PAYS_LIST, REGIONS_BY_PAYS, departmentsInRegion } from '@/lib/french-geo';
import VerificationBadge, { getBadgeLevel } from '@/components/VerificationBadge';

interface RawBebe {
  nom?: string;
  sexe?: string;
  couleur?: string;
  prix?: number;
  statut?: string;
  photos?: string[];
}

interface Annonce {
  id: string;
  titre?: string;
  espece?: string;
  race?: string;
  type?: string;
  type_vente?: string;
  photos?: string[];
  prix?: number;
  saillie_prix?: number;
  prix_min_portee?: number;
  prix_max_portee?: number;
  ville_eleveur?: string;
  region_eleveur?: string;
  departement_eleveur?: string;
  pays_eleveur?: string;
  nombre_bebes?: number;
  created_at?: string;
  statut?: string;
  uid_eleveur?: string;
  profile_id?: string;
  animaux_portee?: RawBebe[];
  profil_source?: string;
}

interface EleveurVerif {
  statut_pro?: string;
  siret?: string;
  is_premium?: boolean;
}

const ESPECES = ['tous', 'chien', 'chat', 'lapin', 'oiseau', 'reptile', 'autre'];
const ESPECE_LABEL: Record<string, string> = {
  tous: 'Toutes espèces', chien: 'Chien', chat: 'Chat', lapin: 'Lapin',
  oiseau: 'Oiseau', reptile: 'Reptile', autre: 'Autre',
};
const TYPES = [
  { value: 'tous', label: 'Tous' },
  { value: 'vente', label: 'Compagnon' },
  { value: 'saillie', label: 'Saillie' },
];
const BREED_FILES: Record<string, string> = {
  chien: 'dog_breeds', chat: 'cat_breeds', cheval: 'horse_breeds',
  lapin: 'rabbit_breeds', oiseau: 'bird_breeds', nac: 'nac_breeds',
  ovin: 'sheep_breeds', caprin: 'goat_breeds', porcin: 'pig_breeds',
  reptile: 'nac_breeds',
};

export default function AnnoncesPage() {
  const { user, userData, activeProfileId } = useAuth();
  const isEleveur = userData?.isElevage === true;
  const [annonces, setAnnonces] = useState<Annonce[]>([]);
  const [eleveurVerifs, setEleveurVerifs] = useState<Record<string, EleveurVerif>>({});
  const [loading, setLoading] = useState(true);
  const [filtreEspece, setFiltreEspece] = useState('tous');
  const [filtreType, setFiltreType] = useState('tous');
  const [search, setSearch] = useState('');

  // Advanced filters
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [filtreRace, setFiltreRace] = useState('');
  const [filtrePays, setFiltrePays] = useState('');
  const [filtreRegion, setFiltreRegion] = useState('');
  const [filtreDept, setFiltreDept] = useState('');
  const [filtreVille, setFiltreVille] = useState('');

  // Race autocomplete
  const [breeds, setBreeds] = useState<string[]>([]);
  const [raceSugg, setRaceSugg] = useState<string[]>([]);
  const [showRaceSugg, setShowRaceSugg] = useState(false);
  const raceRef = useRef<HTMLDivElement>(null);

  // Likes
  const [source, setSource] = useState<'eleveurs' | 'associations'>('eleveurs');

  // Likes
  const [likedKeys, setLikedKeys] = useState<Set<string>>(new Set());
  const [likeCounts, setLikeCounts] = useState<Record<string, number>>({});

  useEffect(() => {
    supabase
      .from('annonces')
      .select('id, titre, espece, race, type, type_vente, photos, prix, saillie_prix, prix_min_portee, prix_max_portee, ville_eleveur, region_eleveur, departement_eleveur, pays_eleveur, nombre_bebes, statut, created_at, uid_eleveur, profile_id, animaux_portee, profil_source')
      .eq('statut', 'disponible')
      .order('created_at', { ascending: false })
      .then(async ({ data }) => {
        const rows = (data ?? []) as Annonce[];
        setAnnonces(rows);
        setLoading(false);
        const uids = [...new Set(rows.map(a => a.uid_eleveur).filter(Boolean))] as string[];
        if (uids.length > 0) {
          const [{ data: profiles }, { data: users }] = await Promise.all([
            supabase.from('user_profiles').select('uid, statut_pro, siret').in('uid', uids).eq('is_main', true),
            supabase.from('users').select('uid, is_premium').in('uid', uids),
          ]);
          const premiumByUid = new Map((users ?? []).map(u => [u.uid, u.is_premium]));
          const map: Record<string, EleveurVerif> = {};
          for (const p of (profiles ?? [])) map[p.uid] = { statut_pro: p.statut_pro, siret: p.siret, is_premium: premiumByUid.get(p.uid) ?? false };
          setEleveurVerifs(map);
        }
        // Load like counts
        const ids = rows.map(a => a.id);
        if (ids.length > 0) {
          const { data: lk } = await supabase.from('likes').select('annonce_id, bebe_index').in('annonce_id', ids);
          const counts: Record<string, number> = {};
          for (const l of (lk ?? [])) {
            const k = `${l.annonce_id}_${l.bebe_index ?? 'null'}`;
            counts[k] = (counts[k] ?? 0) + 1;
          }
          setLikeCounts(counts);
        }
      });
  }, []);

  // Load user's own likes
  useEffect(() => {
    if (!user) { setLikedKeys(new Set()); return; }
    supabase.from('likes').select('annonce_id, bebe_index').eq('user_uid', user.uid)
      .then(({ data }) => {
        if (data) setLikedKeys(new Set(data.map((l: { annonce_id: string; bebe_index: number | null }) => `${l.annonce_id}_${l.bebe_index ?? 'null'}`)));
      });
  }, [user]);

  async function toggleLike(annonceId: string, bebeIndex: number | null, uidEleveur?: string, annonceProfileId?: string) {
    if (!user) return;
    const key = `${annonceId}_${bebeIndex ?? 'null'}`;
    const wasLiked = likedKeys.has(key);
    setLikedKeys(prev => { const n = new Set(prev); wasLiked ? n.delete(key) : n.add(key); return n; });
    setLikeCounts(prev => ({ ...prev, [key]: Math.max(0, (prev[key] ?? 0) + (wasLiked ? -1 : 1)) }));
    try {
      if (wasLiked) {
        const q = supabase.from('likes').delete().eq('user_uid', user.uid).eq('annonce_id', annonceId);
        bebeIndex !== null ? await q.eq('bebe_index', bebeIndex) : await q.is('bebe_index', null);
      } else {
        await supabase.from('likes').upsert({ user_uid: user.uid, annonce_id: annonceId, bebe_index: bebeIndex, ...(activeProfileId ? { profile_id: activeProfileId } : {}) });
        if (uidEleveur && uidEleveur !== user.uid) {
          supabase.from('notifications').insert({
            uid: uidEleveur, type: 'like',
            title: '❤️ Nouveau like sur votre annonce',
            body: 'Quelqu\'un a aimé votre annonce',
            data: { annonceId, bebeIndex },
            read: false,
            ...(annonceProfileId ? { profile_id: annonceProfileId } : {}),
            ...(activeProfileId ? { sender_profile_id: activeProfileId } : {}),
          }).then(() => {});
        }
      }
    } catch {
      setLikedKeys(prev => { const n = new Set(prev); wasLiked ? n.add(key) : n.delete(key); return n; });
      setLikeCounts(prev => ({ ...prev, [key]: Math.max(0, (prev[key] ?? 0) + (wasLiked ? 1 : -1)) }));
    }
  }

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

  const activeFilterCount = [
    filtreRace, filtrePays, filtreRegion, filtreDept, filtreVille,
  ].filter(Boolean).length;

  const filtered = annonces.filter((a) => {
    const isAsso = a.profil_source === 'association';
    if (source === 'eleveurs' && isAsso) return false;
    if (source === 'associations' && !isAsso) return false;
    if (filtreEspece !== 'tous' && a.espece?.toLowerCase() !== filtreEspece) return false;
    if (filtreType === 'saillie' && a.type_vente !== 'saillie') return false;
    if (filtreType === 'vente' && a.type_vente === 'saillie') return false;
    if (search && !`${a.titre ?? ''} ${a.race ?? ''} ${a.ville_eleveur ?? ''}`.toLowerCase().includes(search.toLowerCase())) return false;
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
    const m = breeds.filter(b => b.toLowerCase().includes(q)).slice(0, 6);
    setRaceSugg(m); setShowRaceSugg(m.length > 0);
  }

  function resetAdvanced() {
    setFiltreRace(''); setFiltrePays(''); setFiltreRegion('');
    setFiltreDept(''); setFiltreVille('');
    setRaceSugg([]); setShowRaceSugg(false);
  }

  return (
    <div className="max-w-6xl mx-auto px-4 py-10">
      <div className="mb-8 flex items-start justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-[#1F2A2E] mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>Annonces</h1>
          <p className="text-gray-500 text-sm">
            {filtered.length} annonce{filtered.length !== 1 ? 's' : ''} · {source === 'associations' ? 'Associations & refuges' : 'Éleveurs certifiés'}
          </p>
        </div>
        <div className="flex gap-2 flex-shrink-0">
          <Link href={`/annonces/carte?${new URLSearchParams(Object.fromEntries(Object.entries({source,espece:filtreEspece,type:filtreType,race:filtreRace,pays:filtrePays,region:filtreRegion,dept:filtreDept,ville:filtreVille}).filter(([,v])=>v&&v!=='tous'))).toString()}`}
            className="flex items-center gap-2 bg-white hover:bg-gray-50 border border-gray-200 text-[#1F2A2E] text-sm font-semibold px-4 py-2.5 rounded-xl transition-colors">
            <span className="text-base">🗺️</span> Carte
          </Link>
          <Link href={`/annonces/feed?source=${source}`}
            className="flex items-center gap-2 bg-[#1F2A2E] hover:bg-[#0C5C6C] text-white text-sm font-semibold px-4 py-2.5 rounded-xl transition-colors">
            <span className="text-base">▶</span> Feed
          </Link>
        </div>
      </div>

      {/* Onglets Éleveurs / Associations */}
      <div className="flex gap-2 mb-6">
        <button onClick={() => setSource('eleveurs')}
          className={`flex items-center gap-2 px-5 py-2.5 rounded-full text-sm font-galey font-semibold border transition-all ${
            source === 'eleveurs'
              ? 'bg-[#1F2A2E] text-white border-[#1F2A2E]'
              : 'bg-white text-gray-600 border-gray-200 hover:border-[#1F2A2E]'
          }`}>
          🏠 Éleveurs
        </button>
        <button onClick={() => setSource('associations')}
          className={`flex items-center gap-2 px-5 py-2.5 rounded-full text-sm font-galey font-semibold border transition-all ${
            source === 'associations'
              ? 'bg-teal-700 text-white border-teal-700'
              : 'bg-white text-gray-600 border-gray-200 hover:border-teal-700'
          }`}>
          💚 Associations (Adoption)
        </button>
      </div>

      {/* Filtres */}
      <div className="flex flex-col gap-3 mb-8">
        {/* Search + advanced toggle */}
        <div className="flex gap-2">
          <input
            type="text"
            placeholder="Rechercher par titre, race, ville…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="flex-1 border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white"
          />
          <button
            onClick={() => setShowAdvanced(v => !v)}
            className={`relative flex items-center gap-1.5 px-4 py-2.5 rounded-xl text-sm font-semibold border transition-colors flex-shrink-0 ${
              showAdvanced || activeFilterCount > 0
                ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]'
                : 'bg-white text-gray-600 border-gray-200 hover:border-[#0C5C6C]'
            }`}>
            <svg className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" d="M3 4h18M7 8h10M11 12h2M9 16h6" />
            </svg>
            Filtres
            {activeFilterCount > 0 && (
              <span className="absolute -top-1.5 -right-1.5 w-4 h-4 bg-[#6E9E57] rounded-full text-white text-[10px] font-bold flex items-center justify-center">
                {activeFilterCount}
              </span>
            )}
          </button>
        </div>

        {/* Type chips — uniquement pour les éleveurs */}
        {source === 'eleveurs' && (
          <div className="flex gap-2 flex-wrap">
            {TYPES.map((t) => (
              <button key={t.value} onClick={() => setFiltreType(t.value)}
                className={`px-4 py-1.5 rounded-full text-sm font-medium transition-colors border ${
                  filtreType === t.value ? 'bg-[#6E9E57] text-white border-[#6E9E57]' : 'bg-white text-gray-600 border-gray-200 hover:border-[#6E9E57]'
                }`}>
                {t.label}
              </button>
            ))}
          </div>
        )}

        {/* Espèce chips */}
        <div className="flex gap-2 flex-wrap">
          {ESPECES.map((esp) => (
            <button key={esp} onClick={() => setFiltreEspece(esp)}
              className={`px-4 py-1.5 rounded-full text-sm font-medium transition-colors border ${
                filtreEspece === esp ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'bg-white text-gray-600 border-gray-200 hover:border-[#0C5C6C]'
              }`}>
              {ESPECE_LABEL[esp] ?? esp}
            </button>
          ))}
        </div>

        {/* Advanced filters panel */}
        {showAdvanced && (
          <div className="bg-white border border-gray-200 rounded-2xl p-5 flex flex-col gap-4">
            <div className="flex items-center justify-between">
              <span className="text-sm font-semibold text-[#1F2A2E]">Filtres avancés</span>
              {activeFilterCount > 0 && (
                <button onClick={resetAdvanced} className="text-xs text-gray-400 hover:text-gray-600 underline">
                  Réinitialiser
                </button>
              )}
            </div>

            {/* Race */}
            <div ref={raceRef} className="relative">
              <label className="block text-xs font-semibold text-gray-500 mb-1.5 uppercase tracking-wide">Race</label>
              <input
                type="text"
                placeholder={filtreEspece === 'tous' ? 'Ex : Labrador, Maine Coon…' : 'Rechercher une race…'}
                value={filtreRace}
                onChange={(e) => onRaceInput(e.target.value)}
                onFocus={() => raceSugg.length > 0 && setShowRaceSugg(true)}
                className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white"
              />
              {filtreRace && (
                <button onClick={() => { setFiltreRace(''); setRaceSugg([]); setShowRaceSugg(false); }}
                  className="absolute right-3 top-[2.1rem] text-gray-400 hover:text-gray-600 text-sm">✕</button>
              )}
              {showRaceSugg && raceSugg.length > 0 && (
                <div className="absolute z-20 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg overflow-hidden">
                  {raceSugg.map(b => (
                    <button key={b} onMouseDown={() => { setFiltreRace(b); setShowRaceSugg(false); }}
                      className="w-full text-left px-4 py-2.5 text-sm hover:bg-gray-50 text-[#1F2A2E]">
                      {b}
                    </button>
                  ))}
                </div>
              )}
            </div>

            {/* Pays + Région */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-1.5 uppercase tracking-wide">Pays</label>
                <select
                  value={filtrePays}
                  onChange={(e) => { setFiltrePays(e.target.value); setFiltreRegion(''); setFiltreDept(''); }}
                  className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white">
                  <option value="">Tous les pays</option>
                  {PAYS_LIST.map(p => <option key={p} value={p}>{p}</option>)}
                </select>
              </div>
              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-1.5 uppercase tracking-wide">Région</label>
                <select
                  value={filtreRegion}
                  onChange={(e) => { setFiltreRegion(e.target.value); setFiltreDept(''); }}
                  disabled={regions.length === 0}
                  className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white disabled:opacity-50">
                  <option value="">{filtrePays ? 'Toutes les régions' : 'Sélectionnez un pays'}</option>
                  {regions.map(r => <option key={r} value={r}>{r}</option>)}
                </select>
              </div>
            </div>

            {/* Département + Ville */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-1.5 uppercase tracking-wide">Département</label>
                <select
                  value={filtreDept}
                  onChange={(e) => setFiltreDept(e.target.value)}
                  disabled={departments.length === 0}
                  className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white disabled:opacity-50">
                  <option value="">{filtreRegion ? 'Tous les départements' : 'Sélectionnez une région'}</option>
                  {departments.map(d => <option key={d} value={d}>{d}</option>)}
                </select>
              </div>
              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-1.5 uppercase tracking-wide">Ville</label>
                <div className="relative">
                  <input
                    type="text"
                    placeholder="Ex : Lyon, Rennes…"
                    value={filtreVille}
                    onChange={(e) => setFiltreVille(e.target.value)}
                    className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white"
                  />
                  {filtreVille && (
                    <button onClick={() => setFiltreVille('')}
                      className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 text-sm">✕</button>
                  )}
                </div>
              </div>
            </div>

            {/* Active filter chips */}
            {activeFilterCount > 0 && (
              <div className="flex flex-wrap gap-2 pt-1">
                {filtreRace && <FilterChip label={`Race : ${filtreRace}`} onRemove={() => setFiltreRace('')} />}
                {filtrePays && <FilterChip label={`🌍 ${filtrePays}`} onRemove={() => { setFiltrePays(''); setFiltreRegion(''); setFiltreDept(''); }} />}
                {filtreRegion && <FilterChip label={`📍 ${filtreRegion}`} onRemove={() => { setFiltreRegion(''); setFiltreDept(''); }} />}
                {filtreDept && <FilterChip label={filtreDept} onRemove={() => setFiltreDept('')} />}
                {filtreVille && <FilterChip label={`🏘 ${filtreVille}`} onRemove={() => setFiltreVille('')} />}
              </div>
            )}
          </div>
        )}
      </div>

      {loading ? (
        <div className="flex justify-center py-20">
          <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
        </div>
      ) : filtreType === 'saillie' && !isEleveur ? (
        <div className="flex flex-col items-center justify-center py-20 text-center px-6">
          <div className="text-5xl mb-4">🔒</div>
          <h3 className="font-bold text-[#1F2A2E] text-lg mb-2">Réservé aux éleveurs professionnels</h3>
          <p className="text-gray-500 text-sm max-w-sm">
            La reproduction et les saillies sont réservées aux éleveurs professionnels inscrits sur PetsMatch.
            La reproduction par des particuliers n&apos;est pas conforme à notre règlement.
          </p>
        </div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-20 text-gray-400">Aucune annonce trouvée</div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-5">
          {filtered.map((a) => (
            <AnnonceCard
              key={a.id}
              annonce={a}
              verif={a.uid_eleveur ? eleveurVerifs[a.uid_eleveur] : undefined}
              likedKeys={likedKeys}
              likeCounts={likeCounts}
              onToggleLike={toggleLike}
              currentUser={user}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function FilterChip({ label, onRemove }: { label: string; onRemove: () => void }) {
  return (
    <span className="inline-flex items-center gap-1.5 bg-[#0C5C6C]/10 text-[#0C5C6C] border border-[#0C5C6C]/25 text-xs font-semibold px-3 py-1 rounded-full">
      {label}
      <button onClick={onRemove} className="hover:opacity-70">✕</button>
    </span>
  );
}

function BabyPhotoCard({
  baby: b, fallbackPhoto, annonceId, uidEleveur, annonceProfileId, bebeIndex, isLiked, likeCount, onToggleLike, currentUser,
}: {
  baby: RawBebe;
  fallbackPhoto?: string;
  annonceId: string;
  uidEleveur?: string;
  annonceProfileId?: string;
  bebeIndex: number;
  isLiked: boolean;
  likeCount: number;
  onToggleLike: (annonceId: string, bebeIndex: number | null, uidEleveur?: string, annonceProfileId?: string) => void;
  currentUser: { uid: string } | null;
}) {
  const [idx, setIdx] = useState(0);
  const photos = b.photos ?? [];
  const allPhotos = photos.length > 0 ? photos : (fallbackPhoto ? [fallbackPhoto] : []);
  const current = allPhotos[idx] ?? null;
  const total = allPhotos.length;

  function prev(e: React.MouseEvent) {
    e.preventDefault(); e.stopPropagation();
    setIdx(i => (i - 1 + total) % total);
  }
  function next(e: React.MouseEvent) {
    e.preventDefault(); e.stopPropagation();
    setIdx(i => (i + 1) % total);
  }

  return (
    <Link href={`/annonces/${annonceId}`} className="border border-gray-100 rounded-xl overflow-hidden bg-gray-50 block hover:shadow-sm transition-shadow">
      <div className="aspect-square relative bg-[#F5F5F0] group">
        {current ? (
          <img src={current} alt={b.nom ?? ''} className="w-full h-full object-cover" />
        ) : (
          <div className="w-full h-full flex items-center justify-center text-3xl">🐾</div>
        )}

        {/* Navigation flèches (si plusieurs photos) */}
        {total > 1 && (
          <>
            <button
              onClick={prev}
              className="absolute left-1 top-1/2 -translate-y-1/2 w-5 h-5 rounded-full bg-black/50 flex items-center justify-center text-white text-[10px] opacity-0 group-hover:opacity-100 transition-opacity">
              ‹
            </button>
            <button
              onClick={next}
              className="absolute right-1 top-1/2 -translate-y-1/2 w-5 h-5 rounded-full bg-black/50 flex items-center justify-center text-white text-[10px] opacity-0 group-hover:opacity-100 transition-opacity">
              ›
            </button>
            {/* Dots */}
            <div className="absolute bottom-1 left-1/2 -translate-x-1/2 flex gap-0.5">
              {allPhotos.map((_, j) => (
                <div key={j} className={`w-1 h-1 rounded-full ${j === idx ? 'bg-white' : 'bg-white/40'}`} />
              ))}
            </div>
          </>
        )}

        {b.statut === 'reserve' && (
          <div className="absolute inset-0 bg-black/40 flex items-center justify-center">
            <span className="text-white text-[10px] font-bold bg-amber-500 px-2 py-0.5 rounded-full">Réservé</span>
          </div>
        )}
        <button
          onClick={(e) => { e.preventDefault(); e.stopPropagation(); onToggleLike(annonceId, bebeIndex, uidEleveur, annonceProfileId); }}
          disabled={!currentUser}
          className="absolute top-1 right-1 w-6 h-6 rounded-full bg-black/40 flex items-center justify-center text-xs transition-transform hover:scale-110 active:scale-95 disabled:opacity-50">
          {isLiked ? '❤️' : '🤍'}
        </button>
      </div>
      <div className="p-2">
        <p className="text-xs font-bold text-[#1F2A2E] truncate">
          {b.nom ?? `Bébé ${bebeIndex + 1}`} {b.sexe === 'femelle' ? '♀' : '♂'}
        </p>
        {b.couleur && <p className="text-[10px] text-gray-400 truncate">{b.couleur}</p>}
        <div className="flex items-center justify-between mt-1">
          {b.prix != null ? <p className="text-xs font-bold text-[#0C5C6C]">{b.prix} €</p> : <span />}
          {likeCount > 0 && <p className="text-[10px] text-gray-400">❤️ {likeCount}</p>}
        </div>
      </div>
    </Link>
  );
}

function AnnonceCard({
  annonce: a, verif, likedKeys, likeCounts, onToggleLike, currentUser,
}: {
  annonce: Annonce;
  verif?: EleveurVerif;
  likedKeys: Set<string>;
  likeCounts: Record<string, number>;
  onToggleLike: (annonceId: string, bebeIndex: number | null, uidEleveur?: string, annonceProfileId?: string) => void;
  currentUser: { uid: string; profileType?: string } | null;
}) {
  const [showBabies, setShowBabies] = useState(false);
  const photos = (a.photos as unknown as string[]) ?? [];
  const photo = photos[0];
  const isSaillie = a.type_vente === 'saillie';
  const isPortee = a.type === 'portee';
  const isAsso = a.profil_source === 'association';
  const bebes = (a.animaux_portee as RawBebe[] | undefined) ?? [];

  let prix: string | null = null;
  if (isSaillie) {
    const sp = a.saillie_prix != null ? Number(a.saillie_prix) : null;
    prix = sp != null && !isNaN(sp) ? `${Math.round(sp)} €` : null;
  } else if (isPortee) {
    const parts = ([a.prix_min_portee, a.prix_max_portee] as (number | undefined)[]).filter((v): v is number => v != null);
    if (parts.length === 2 && parts[0] !== parts[1]) prix = `${parts[0]} – ${parts[1]} €`;
    else if (parts.length > 0) prix = `${parts[0]} €`;
  } else {
    prix = a.prix != null ? `${a.prix} €` : null;
  }

  const wholeKey = `${a.id}_null`;
  const isLiked = likedKeys.has(wholeKey);
  const likeCount = likeCounts[wholeKey] ?? 0;

  return (
    <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden hover:shadow-md transition-shadow">
      <div className="aspect-[4/3] bg-[#F5F5F0] relative">
        {photo ? (
          <Image src={photo} alt={a.titre ?? ''} fill className="object-contain" />
        ) : (
          <div className="w-full h-full flex items-center justify-center text-5xl">🐾</div>
        )}
        <span className={`absolute top-2 left-2 text-white text-xs font-semibold px-2 py-0.5 rounded-full ${isAsso ? 'bg-teal-600' : isSaillie ? 'bg-purple-500' : isPortee ? 'bg-amber-500' : 'bg-[#6E9E57]'}`}>
          {isAsso ? '💚 Adoption' : isSaillie ? 'Saillie' : isPortee ? 'Portée' : 'Compagnon'}
        </span>
        <button
          onClick={(e) => { e.preventDefault(); e.stopPropagation(); onToggleLike(a.id, null, a.uid_eleveur, a.profile_id); }}
          disabled={!currentUser}
          className="absolute top-2 right-2 w-8 h-8 rounded-full bg-black/40 backdrop-blur-sm flex items-center justify-center transition-transform hover:scale-110 active:scale-95 disabled:opacity-50"
          title={currentUser ? (isLiked ? 'Retirer le like' : 'Aimer') : 'Connectez-vous pour liker'}
        >
          <span className="text-base leading-none">{isLiked ? '❤️' : '🤍'}</span>
        </button>
      </div>
      <div className="p-4">
        <div className="flex items-start gap-1.5 mb-0.5">
          <h3 className="font-bold text-[#1F2A2E] text-sm truncate capitalize flex-1">
            {a.titre ?? `${a.espece ?? ''} ${a.race ?? ''}`}
          </h3>
          {verif && a.profil_source !== 'association' && <VerificationBadge level={getBadgeLevel({ statutPro: verif.statut_pro, siret: verif.siret, isPremium: verif.is_premium })} size="sm" />}
        </div>
        <p className="text-gray-500 text-xs capitalize">{a.espece}{a.race ? ` · ${a.race}` : ''}</p>
        {a.ville_eleveur && <p className="text-gray-400 text-xs mt-0.5">📍 {a.ville_eleveur}</p>}
        {prix && <p className="text-[#0C5C6C] font-bold text-sm mt-1">{prix}</p>}
        {isSaillie && a.nombre_bebes != null && (
          <p className="text-gray-400 text-xs">{a.nombre_bebes} bébé{a.nombre_bebes > 1 ? 's' : ''} disponible{a.nombre_bebes > 1 ? 's' : ''}</p>
        )}
        {likeCount > 0 && (
          <p className="text-xs text-gray-400 mt-1">❤️ {likeCount} {likeCount > 1 ? 'personnes aiment' : 'personne aime'}</p>
        )}

        {/* Portée: grille des bébés avec like par bébé */}
        {isPortee && bebes.length > 0 && (
          <div className="mt-3">
            <button
              onClick={() => setShowBabies(v => !v)}
              className="w-full text-xs text-[#0C5C6C] font-semibold py-2 border border-[#0C5C6C]/25 rounded-xl hover:bg-[#0C5C6C]/5 transition-colors">
              {showBabies ? '▲ Masquer les bébés' : `▼ Voir les ${bebes.length} bébé${bebes.length > 1 ? 's' : ''}`}
            </button>
            {showBabies && (
              <div className="grid grid-cols-2 gap-2 mt-3">
                {bebes.map((b, i) => {
                  const bKey = `${a.id}_${i}`;
                  return (
                    <BabyPhotoCard
                      key={i}
                      baby={b}
                      fallbackPhoto={photo}
                      annonceId={a.id}
                      uidEleveur={a.uid_eleveur}
                      annonceProfileId={a.profile_id}
                      bebeIndex={i}
                      isLiked={likedKeys.has(bKey)}
                      likeCount={likeCounts[bKey] ?? 0}
                      onToggleLike={onToggleLike}
                      currentUser={currentUser}
                    />
                  );
                })}
              </div>
            )}
          </div>
        )}

        <Link href={`/annonces/${a.id}`}
          className="mt-3 w-full block text-center text-sm bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-medium py-2 rounded-xl transition-colors">
          Voir l'annonce
        </Link>
      </div>
    </div>
  );
}
