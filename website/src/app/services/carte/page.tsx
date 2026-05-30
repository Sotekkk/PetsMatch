'use client';

import { useEffect, useState } from 'react';
import dynamic from 'next/dynamic';
import { supabase } from '@/lib/supabase';
import type { ProMapItem } from '@/components/ServicesMap';

const ServicesMap = dynamic(() => import('@/components/ServicesMap'), { ssr: false });

// ─── Config catégories ────────────────────────────────────────────────────────

const CATS = [
  { key: '',             label: 'Tous',                  color: '#6B7280' },
  { key: 'veterinaire',  label: 'Vétérinaires',          color: '#2196F3' },
  { key: 'sante',        label: 'Santé',                 color: '#2196F3' },
  { key: 'education',    label: 'Éducateurs',            color: '#FF9800' },
  { key: 'garde',        label: 'Pension / Garde',       color: '#4CAF50' },
  { key: 'referencement',label: 'Référencement',         color: '#CDDC39' },
];

const ESPECES = ['Chien', 'Chat', 'Lapin', 'Oiseau', 'Reptile', 'Rongeur', 'Cheval'];

// ─── Page ─────────────────────────────────────────────────────────────────────

export default function ServicesCartePage() {
  const [pros, setPros] = useState<ProMapItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [catFilter, setCatFilter] = useState('');
  const [especeFilter, setEspeceFilter] = useState('');
  const [search, setSearch] = useState('');

  useEffect(() => {
    loadPros();
  }, []);

  async function loadPros() {
    setLoading(true);
    try {
      const { data } = await supabase
        .from('users')
        .select('uid, name_elevage, firstname, profile_picture_url, profession_pro, ville_elevage, ville, cat_pro, especes_acceptees, accept_new_clients, lat, lng')
        .eq('is_pro', true)
        .not('lat', 'is', null)
        .not('lng', 'is', null);

      const items: ProMapItem[] = (data ?? []).map(row => ({
        uid:               row.uid,
        name:              row.name_elevage || row.firstname || 'Professionnel',
        photo:             row.profile_picture_url,
        profession:        row.profession_pro,
        ville:             row.ville_elevage || row.ville,
        cat_pro:           row.cat_pro,
        especes:           Array.isArray(row.especes_acceptees) ? row.especes_acceptees : [],
        accept_new_clients: row.accept_new_clients,
        lat:               row.lat,
        lng:               row.lng,
      }));
      setPros(items);
    } finally {
      setLoading(false);
    }
  }

  const filtered = pros.filter(p => {
    if (catFilter && p.cat_pro !== catFilter) return false;
    if (especeFilter && !p.especes.includes(especeFilter)) return false;
    if (search) {
      const q = search.toLowerCase();
      if (!p.name.toLowerCase().includes(q) && !(p.ville ?? '').toLowerCase().includes(q)) return false;
    }
    return true;
  });

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
        <div className="max-w-4xl mx-auto space-y-2">
          {/* Recherche */}
          <input
            type="text"
            placeholder="Rechercher par nom, ville…"
            value={search}
            onChange={e => setSearch(e.target.value)}
            className="w-full px-4 py-2 rounded-full border border-gray-200 text-sm outline-none focus:border-[#0C5C6C]"
            style={{ fontFamily: 'Galey, sans-serif' }}
          />
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
          ) : (
            <ServicesMap pros={filtered} />
          )}
        </div>
      </div>
    </div>
  );
}
