'use client';

import { useEffect, useState } from 'react';
import dynamic from 'next/dynamic';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import type { ProMapItem } from '@/components/ServicesMap';

const ServicesMap = dynamic(() => import('@/components/ServicesMap'), { ssr: false });

// ─── Données géographiques ────────────────────────────────────────────────────

const REGIONS = [
  "Île-de-France", "Auvergne-Rhône-Alpes", "Bretagne", "Normandie",
  "Hauts-de-France", "Grand Est", "Pays de la Loire", "Nouvelle-Aquitaine",
  "Occitanie", "Provence-Alpes-Côte d'Azur", "Bourgogne-Franche-Comté",
  "Centre-Val de Loire", "Corse",
];

const DEPTS_BY_REGION: Record<string, string[]> = {
  "Île-de-France": ["Paris", "Seine-et-Marne", "Yvelines", "Essonne", "Hauts-de-Seine", "Seine-Saint-Denis", "Val-de-Marne", "Val-d'Oise"],
  "Auvergne-Rhône-Alpes": ["Ain", "Allier", "Ardèche", "Cantal", "Drôme", "Isère", "Loire", "Haute-Loire", "Puy-de-Dôme", "Rhône", "Savoie", "Haute-Savoie"],
  "Bretagne": ["Côtes-d'Armor", "Finistère", "Ille-et-Vilaine", "Morbihan"],
  "Normandie": ["Calvados", "Eure", "Manche", "Orne", "Seine-Maritime"],
  "Hauts-de-France": ["Aisne", "Nord", "Oise", "Pas-de-Calais", "Somme"],
  "Grand Est": ["Ardennes", "Aube", "Marne", "Haute-Marne", "Meurthe-et-Moselle", "Meuse", "Moselle", "Bas-Rhin", "Haut-Rhin", "Vosges"],
  "Pays de la Loire": ["Loire-Atlantique", "Maine-et-Loire", "Mayenne", "Sarthe", "Vendée"],
  "Nouvelle-Aquitaine": ["Charente", "Charente-Maritime", "Corrèze", "Creuse", "Dordogne", "Gironde", "Landes", "Lot-et-Garonne", "Pyrénées-Atlantiques", "Deux-Sèvres", "Vienne", "Haute-Vienne"],
  "Occitanie": ["Ariège", "Aude", "Aveyron", "Gard", "Haute-Garonne", "Gers", "Hérault", "Lot", "Lozère", "Hautes-Pyrénées", "Pyrénées-Orientales", "Tarn", "Tarn-et-Garonne"],
  "Provence-Alpes-Côte d'Azur": ["Alpes-de-Haute-Provence", "Hautes-Alpes", "Alpes-Maritimes", "Bouches-du-Rhône", "Var", "Vaucluse"],
  "Bourgogne-Franche-Comté": ["Côte-d'Or", "Doubs", "Jura", "Nièvre", "Haute-Saône", "Saône-et-Loire", "Yonne", "Territoire de Belfort"],
  "Centre-Val de Loire": ["Cher", "Eure-et-Loir", "Indre", "Indre-et-Loire", "Loir-et-Cher", "Loiret"],
  "Corse": ["Corse-du-Sud", "Haute-Corse"],
};

// ─── Config catégories ────────────────────────────────────────────────────────

const CATS = [
  { key: '',                label: 'Tous',             color: '#6B7280' },
  { key: 'veterinaire',     label: 'Vétérinaires',     color: '#2196F3' },
  { key: 'sante',           label: 'Santé',            color: '#2196F3' },
  { key: 'education',       label: 'Éducateurs',       color: '#FF9800' },
  { key: 'garde',           label: 'Pension / Garde',  color: '#4CAF50' },
  { key: 'toilettage',      label: 'Toilettage',       color: '#00BCD4' },
  { key: 'photographe',     label: 'Photographes',     color: '#E91E63' },
  { key: 'marechal_ferrant',label: 'Maréchaux',        color: '#795548' },
  { key: 'referencement',   label: 'Référencement',    color: '#CDDC39' },
];

const ESPECES = ['Chien', 'Chat', 'Lapin', 'Oiseau', 'Reptile', 'Rongeur', 'Cheval'];

// ─── Page ─────────────────────────────────────────────────────────────────────

export default function ServicesCartePage() {
  const { user, userData } = useAuth();

  const [pros, setPros] = useState<ProMapItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [catFilter, setCatFilter] = useState('');
  const [especeFilter, setEspeceFilter] = useState('');
  const [search, setSearch] = useState('');
  const [nearMe, setNearMe] = useState(false);
  const [locating, setLocating] = useState(false);
  const [userPos, setUserPos] = useState<{ lat: number; lng: number } | null>(null);
  const [filterRegion, setFilterRegion] = useState('');
  const [filterDept, setFilterDept] = useState('');

  useEffect(() => {
    loadPros();
  }, []);

  async function loadPros() {
    setLoading(true);
    try {
      // Profils primaires (users)
      const { data: primaryData } = await supabase
        .from('users')
        .select('uid, name_elevage, firstname, profile_picture_url, profession_pro, ville_elevage, ville, departement_elevage, region_elevage, cat_pro, especes_acceptees, accept_new_clients, lat, lng, rayon_intervention')
        .not('cat_pro', 'is', null)
        .neq('cat_pro', '')
        .not('lat', 'is', null)
        .not('lng', 'is', null);

      // Profils secondaires (user_profiles) — latitude/longitude OU lat/lng
      const { data: secondaryData } = await supabase
        .from('user_profiles')
        .select('id, uid, profile_type, name_elevage, avatar_url, profession_pro, ville, especes_acceptees, accept_new_clients, latitude, longitude, lat, lng, rayon_intervention')
        .not('profile_type', 'is', null);

      const items: ProMapItem[] = [];

      // Primaires
      for (const row of (primaryData ?? [])) {
        items.push({
          uid:                row.uid,
          name:               row.name_elevage || row.firstname || 'Professionnel',
          photo:              row.profile_picture_url,
          profession:         row.profession_pro,
          ville:              row.ville_elevage || row.ville,
          cat_pro:            row.cat_pro,
          especes:            Array.isArray(row.especes_acceptees) ? row.especes_acceptees : [],
          accept_new_clients: row.accept_new_clients,
          lat:                row.lat,
          lng:                row.lng,
          rayon_intervention: row.rayon_intervention,
        });
      }

      // Secondaires (on évite les doublons uid+cat_pro)
      const primaryKeys = new Set(items.map(i => `${i.uid}::${i.cat_pro}`));
      for (const row of (secondaryData ?? [])) {
        const lat = row.latitude ?? row.lat;
        const lng = row.longitude ?? row.lng;
        if (!lat || !lng) continue;
        const cat = row.profile_type ?? '';
        if (!cat) continue;
        const key = `${row.uid}::${cat}`;
        if (primaryKeys.has(key)) continue; // profil principal déjà présent
        items.push({
          uid:                row.uid,
          profileTableId:     row.id,
          name:               row.name_elevage || 'Professionnel',
          photo:              row.avatar_url,
          profession:         row.profession_pro,
          ville:              row.ville,
          cat_pro:            cat,
          especes:            Array.isArray(row.especes_acceptees) ? row.especes_acceptees : [],
          accept_new_clients: row.accept_new_clients,
          lat,
          lng,
          rayon_intervention: row.rayon_intervention,
        });
      }

      setPros(items);
    } finally {
      setLoading(false);
    }
  }

  // "Proche de moi" — lat/lng du profil Supabase, fetchés au tap
  async function toggleNearMe() {
    if (nearMe) { setNearMe(false); setUserPos(null); return; }
    if (!user) return;
    setLocating(true);
    try {
      const { data } = await supabase
        .from('users')
        .select('lat, lng')
        .eq('uid', user.uid)
        .maybeSingle();
      const lat = data?.lat as number | null;
      const lng = data?.lng as number | null;
      if (lat == null || lng == null) {
        alert('Position introuvable dans votre profil. Renseignez votre adresse dans les paramètres.');
        return;
      }
      setUserPos({ lat, lng });
      setNearMe(true);
    } catch {
      alert('Impossible de récupérer votre position.');
    } finally {
      setLocating(false);
    }
  }

  function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number) {
    const R = 6371;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLng = (lng2 - lng1) * Math.PI / 180;
    const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }

  const filtered = pros.filter(p => {
    if (catFilter && p.cat_pro !== catFilter) return false;
    if (especeFilter && !p.especes.includes(especeFilter)) return false;
    if (search) {
      const q = search.toLowerCase();
      if (!p.name.toLowerCase().includes(q) && !(p.ville ?? '').toLowerCase().includes(q)) return false;
    }
    // Filtre région/département — lit aussi les colonnes *_elevage
    if (filterRegion || filterDept) {
      const loc = [
        p.ville ?? '',
        (p as any).region_elevage ?? '',
        (p as any).departement_elevage ?? '',
      ].join(' ').toLowerCase();
      if (filterRegion) {
        const regionDepts = DEPTS_BY_REGION[filterRegion] ?? [];
        const matchesRegion = loc.includes(filterRegion.toLowerCase()) ||
          regionDepts.some((d: string) => loc.includes(d.toLowerCase()));
        if (!matchesRegion) return false;
      }
      if (filterDept && !loc.includes(filterDept.toLowerCase())) return false;
    }
    if (nearMe && userPos) {
      const rawRayon = (p as any).rayon_intervention ?? 0;
      const rayon = rawRayon > 0 ? rawRayon : 50;
      const dist = haversineKm(userPos.lat, userPos.lng, p.lat, p.lng);
      if (dist > rayon) return false;
    }
    return true;
  });

  const hasActiveFilters = nearMe || catFilter || especeFilter || filterRegion || filterDept;

  const depts = filterRegion ? (DEPTS_BY_REGION[filterRegion] ?? []) : [];

  return (
    <div className="min-h-screen bg-[#F8F8F8] flex flex-col">
      {/* Header */}
      <div className="bg-[#0C5C6C] text-white px-4 py-6">
        <div className="max-w-4xl mx-auto">
          <div className="flex items-center gap-3 mb-1">
            <a href="/services" className="text-white/70 hover:text-white text-sm">← Services</a>
          </div>
          <h1 className="text-xl font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>
            Carte des professionnels
          </h1>
          <p className="text-white/70 text-sm">{filtered.length} professionnel(s) avec localisation</p>
        </div>
      </div>

      {/* Filtres */}
      <div className="bg-white border-b border-gray-100 px-4 py-3">
        <div className="max-w-4xl mx-auto space-y-2.5">
          {/* Recherche */}
          <input
            type="text"
            placeholder="Rechercher par nom, ville…"
            value={search}
            onChange={e => setSearch(e.target.value)}
            className="w-full px-4 py-2 rounded-full border border-gray-200 text-sm outline-none focus:border-[#0C5C6C]"
            style={{ fontFamily: 'Galey, sans-serif' }}
          />

          {/* Région + Département */}
          <div className="flex gap-2">
            <select
              value={filterRegion}
              onChange={e => { setFilterRegion(e.target.value); setFilterDept(''); }}
              className="flex-1 px-3 py-1.5 rounded-full border text-xs outline-none"
              style={{
                fontFamily: 'Galey, sans-serif',
                borderColor: filterRegion ? '#0C5C6C' : '#E5E7EB',
                background: filterRegion ? '#0C5C6C11' : 'white',
                color: filterRegion ? '#0C5C6C' : '#6B7280',
              }}
            >
              <option value="">— Région</option>
              {REGIONS.map(r => <option key={r} value={r}>{r}</option>)}
            </select>
            <select
              value={filterDept}
              onChange={e => setFilterDept(e.target.value)}
              disabled={depts.length === 0}
              className="flex-1 px-3 py-1.5 rounded-full border text-xs outline-none disabled:opacity-40"
              style={{
                fontFamily: 'Galey, sans-serif',
                borderColor: filterDept ? '#0C5C6C' : '#E5E7EB',
                background: filterDept ? '#0C5C6C11' : 'white',
                color: filterDept ? '#0C5C6C' : '#6B7280',
              }}
            >
              <option value="">— Département</option>
              {depts.map(d => <option key={d} value={d}>{d}</option>)}
            </select>
          </div>

          {/* Filtre catégorie */}
          <div className="flex gap-2 flex-wrap">
            {CATS.map(c => (
              <button
                key={c.key}
                onClick={() => setCatFilter(catFilter === c.key ? '' : c.key)}
                className="px-3 py-1 rounded-full text-xs font-semibold border transition-colors"
                style={{
                  borderColor: catFilter === c.key ? c.color : '#E5E7EB',
                  background:  catFilter === c.key ? `${c.color}22` : 'white',
                  color:       catFilter === c.key ? c.color : '#6B7280',
                  fontFamily:  'Galey, sans-serif',
                }}
              >
                {c.label}
              </button>
            ))}
          </div>

          {/* Filtre espèce */}
          <div className="flex gap-2 flex-wrap">
            {ESPECES.map(e => (
              <button
                key={e}
                onClick={() => setEspeceFilter(especeFilter === e ? '' : e)}
                className="px-3 py-1 rounded-full text-xs font-medium border transition-colors"
                style={{
                  borderColor: especeFilter === e ? '#0C5C6C' : '#E5E7EB',
                  background:  especeFilter === e ? '#0C5C6C22' : 'white',
                  color:       especeFilter === e ? '#0C5C6C' : '#6B7280',
                  fontFamily:  'Galey, sans-serif',
                }}
              >
                {e}
              </button>
            ))}
          </div>

          {/* Proche de moi + reset */}
          <div className="flex items-center gap-2 flex-wrap">
            <button
              onClick={toggleNearMe}
              disabled={locating}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-semibold border transition-colors"
              style={{
                borderColor: nearMe ? '#0C5C6C' : '#E5E7EB',
                background:  nearMe ? '#0C5C6C' : 'white',
                color:       nearMe ? 'white' : '#6B7280',
                fontFamily:  'Galey, sans-serif',
                opacity:     locating ? 0.6 : 1,
              }}
            >
              {locating ? (
                <span className="w-3 h-3 border-2 border-current border-t-transparent rounded-full animate-spin inline-block" />
              ) : (
                <span>📍</span>
              )}
              Proche de moi
            </button>
            {hasActiveFilters && (
              <button
                onClick={() => {
                  setCatFilter(''); setEspeceFilter(''); setSearch('');
                  setNearMe(false); setUserPos(null);
                  setFilterRegion(''); setFilterDept('');
                }}
                className="px-3 py-1.5 rounded-full text-xs font-semibold border border-gray-200 text-gray-400 hover:bg-gray-50"
                style={{ fontFamily: 'Galey, sans-serif' }}
              >
                Réinitialiser
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Légende */}
      <div className="bg-white border-b border-gray-100 px-4 py-2">
        <div className="max-w-4xl mx-auto flex gap-4 flex-wrap">
          {[
            { color: '#2196F3', label: 'Vétérinaire / Santé' },
            { color: '#FF9800', label: 'Éducateur' },
            { color: '#4CAF50', label: 'Pension / Garde' },
            { color: '#CDDC39', label: 'Référencement' },
            { color: '#9C27B0', label: 'Autre' },
          ].map(l => (
            <div key={l.label} className="flex items-center gap-1.5">
              <div className="w-3 h-3 rounded-full flex-shrink-0" style={{ background: l.color }} />
              <span className="text-xs text-gray-500" style={{ fontFamily: 'Galey, sans-serif' }}>{l.label}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Carte */}
      <div className="flex-1 p-4">
        <div className="max-w-4xl mx-auto h-[60vh] min-h-[400px]">
          {loading ? (
            <div className="h-full flex items-center justify-center bg-gray-100 rounded-2xl">
              <div className="w-8 h-8 border-4 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
            </div>
          ) : filtered.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center bg-gray-50 rounded-2xl gap-3">
              <span className="text-4xl">🗺️</span>
              <p className="text-sm text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>
                Aucun professionnel trouvé avec ces filtres
              </p>
              <button
                onClick={() => { setCatFilter(''); setEspeceFilter(''); setSearch(''); setNearMe(false); setUserPos(null); setFilterRegion(''); setFilterDept(''); }}
                className="text-xs text-[#0C5C6C] underline"
              >
                Réinitialiser les filtres
              </button>
            </div>
          ) : (
            <ServicesMap pros={filtered} />
          )}
        </div>
      </div>
    </div>
  );
}
