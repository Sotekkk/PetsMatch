'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { REGIONS_BY_PAYS, departmentsInRegion, fromPostalCode } from '@/lib/french-geo';
import {
  ANNONCE_OBJET_CATEGORIES, ANNONCE_OBJET_TRANSACTIONS, categorieEmoji,
} from '@/lib/annonce-objet-categories';

interface AnnonceObjet {
  id: string;
  titre: string;
  categorie: string;
  type_transaction: string;
  prix: number | null;
  prix_unite: string | null;
  prix_negociable: boolean | null;
  photos: string[] | null;
  ville: string | null;
  departement: string | null;
  region: string | null;
  boost_until: string | null;
  created_at: string | null;
}

const TRIS = [
  { k: 'recent', label: 'Plus récentes' },
  { k: 'prix_asc', label: 'Prix croissant' },
  { k: 'prix_desc', label: 'Prix décroissant' },
];

function prixLabel(a: AnnonceObjet): string {
  if (a.type_transaction === 'don') return 'Don';
  if (a.type_transaction === 'recherche') return 'Recherche';
  if (a.prix == null) return 'Prix à convenir';
  return `${Math.round(a.prix)} €${a.prix_unite ?? ''}${a.prix_negociable ? ' (négociable)' : ''}`;
}
const boostActif = (s: string | null) => !!s && new Date(s) > new Date();

export default function AnnoncesObjetsFeedPage() {
  const [rows, setRows] = useState<AnnonceObjet[]>([]);
  const [loading, setLoading] = useState(true);

  const [kw, setKw] = useState('');
  const [kwInput, setKwInput] = useState('');
  const [cat, setCat] = useState('tous');
  const [region, setRegion] = useState('');
  const [dept, setDept] = useState('');
  const [ville, setVille] = useState('');
  const [cp, setCp] = useState('');
  const [communes, setCommunes] = useState<string[]>([]);
  const [tri, setTri] = useState('recent');
  const [locating, setLocating] = useState(false);

  // Debounce mot-clé
  useEffect(() => {
    const t = setTimeout(() => setKw(kwInput.trim()), 400);
    return () => clearTimeout(t);
  }, [kwInput]);

  // Code postal → communes + région/département
  useEffect(() => {
    if (cp.length !== 5) { setCommunes([]); return; }
    const geo = fromPostalCode(cp);
    if (geo) { setRegion(geo.region); setDept(geo.departement); }
    fetch(`https://geo.api.gouv.fr/communes?codePostal=${cp}&fields=nom&format=json`)
      .then(r => r.json())
      .then((list: { nom: string }[]) => {
        const names = [...new Set((list ?? []).map(c => c.nom))].sort();
        setCommunes(names);
        setVille(v => (names.includes(v) ? v : names.length === 1 ? names[0] : ''));
      })
      .catch(() => setCommunes([]));
  }, [cp]);

  const depts = useMemo(() => (region ? departmentsInRegion(region) : []), [region]);
  const activeFilters = (region ? 1 : 0) + (dept ? 1 : 0) + (ville ? 1 : 0) + (cp ? 1 : 0) + (tri !== 'recent' ? 1 : 0);

  useEffect(() => {
    setLoading(true);
    let q = supabase.from('annonces_objets').select(
      'id, titre, categorie, type_transaction, prix, prix_unite, prix_negociable, photos, ville, departement, region, boost_until, created_at',
    ).eq('statut', 'disponible');
    if (cat !== 'tous') q = q.eq('categorie', cat);
    if (kw) {
      const safe = kw.replace(/[%,]/g, ' ');
      q = q.or(`titre.ilike.%${safe}%,description.ilike.%${safe}%`);
    }
    if (region) q = q.eq('region', region);
    if (dept) q = q.eq('departement', dept);
    if (cp.length === 5) q = q.eq('code_postal', cp);
    if (ville) q = q.ilike('ville', `%${ville}%`);
    q = tri === 'prix_asc'
      ? q.order('prix', { ascending: true, nullsFirst: false })
      : tri === 'prix_desc'
        ? q.order('prix', { ascending: false, nullsFirst: false })
        : q.order('created_at', { ascending: false });
    q.limit(200).then(({ data }) => {
      const list = (data ?? []) as AnnonceObjet[];
      setRows(tri === 'recent'
        ? [...list.filter(a => boostActif(a.boost_until)), ...list.filter(a => !boostActif(a.boost_until))]
        : list);
      setLoading(false);
    });
  }, [cat, kw, region, dept, cp, ville, tri]);

  function autourDeMoi() {
    if (!navigator.geolocation) return;
    setLocating(true);
    navigator.geolocation.getCurrentPosition(async (pos) => {
      try {
        // Reverse via l'API adresse.gouv.fr (open data, sans clé)
        const r = await fetch(
          `https://api-adresse.data.gouv.fr/reverse/?lon=${pos.coords.longitude}&lat=${pos.coords.latitude}`,
        );
        const j = await r.json();
        const cp = j?.features?.[0]?.properties?.postcode as string | undefined;
        const geo = cp ? fromPostalCode(cp) : null;
        if (geo) { setRegion(geo.region); setDept(geo.departement); }
      } catch { /* ignore */ }
      setLocating(false);
    }, () => setLocating(false), { enableHighAccuracy: false, timeout: 8000 });
  }

  return (
    <div className="max-w-5xl mx-auto px-4 py-8">
      <div className="flex items-center justify-between flex-wrap gap-3 mb-2">
        <h1 className="text-2xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
          Petites annonces — matériel
        </h1>
        <Link href="/annonces/creer-objet"
          className="text-sm font-semibold bg-[#0C5C6C] text-white px-4 py-2 rounded-xl hover:bg-[#094F5D] transition-colors">
          + Publier
        </Link>
      </div>
      <p className="text-sm text-gray-500 mb-4">
        Cage, harnais, foin, location de prairie ou de parcelle, matériel agricole…
        Matériel lié aux animaux uniquement — jamais un animal.
      </p>

      {/* Recherche */}
      <div className="relative mb-3">
        <input value={kwInput} onChange={e => setKwInput(e.target.value)}
          placeholder="Rechercher (cage, foin, harnais, tracteur…)"
          className="w-full border border-gray-200 rounded-full pl-11 pr-10 py-2.5 text-sm bg-[#F1F3F2] focus:outline-none focus:border-[#0C5C6C] focus:bg-white" />
        <span className="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400">🔎</span>
        {kwInput && (
          <button onClick={() => setKwInput('')} className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm">✕</button>
        )}
      </div>

      {/* Catégories */}
      <div className="flex gap-2 overflow-x-auto pb-3">
        <Chip active={cat === 'tous'} onClick={() => setCat('tous')} label="🔎 Tout" />
        {ANNONCE_OBJET_CATEGORIES.map(c => (
          <Chip key={c.slug} active={cat === c.slug} onClick={() => setCat(c.slug)} label={`${c.emoji} ${c.label}`} />
        ))}
      </div>

      {/* Filtres : code postal → commune */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-2 mb-2">
        <input value={cp} onChange={e => setCp(e.target.value.replace(/\D/g, '').slice(0, 5))}
          inputMode="numeric" placeholder="Code postal"
          className="border border-gray-200 rounded-xl px-2.5 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
        {communes.length > 0 ? (
          <select value={ville} onChange={e => setVille(e.target.value)}
            className="border border-gray-200 rounded-xl px-2.5 py-2 text-sm bg-white focus:outline-none focus:border-[#0C5C6C]">
            <option value="">Toutes les communes</option>
            {communes.map(c => <option key={c} value={c}>{c}</option>)}
          </select>
        ) : (
          <input value={ville} onChange={e => setVille(e.target.value)} placeholder="Commune"
            className="border border-gray-200 rounded-xl px-2.5 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
        )}
        <select value={tri} onChange={e => setTri(e.target.value)}
          className="border border-gray-200 rounded-xl px-2.5 py-2 text-sm bg-white focus:outline-none focus:border-[#0C5C6C]">
          {TRIS.map(t => <option key={t.k} value={t.k}>{t.label}</option>)}
        </select>
      </div>
      <div className="grid grid-cols-2 gap-2 mb-2">
        <select value={region} onChange={e => { setRegion(e.target.value); setDept(''); }}
          className="border border-gray-200 rounded-xl px-2.5 py-2 text-sm bg-white focus:outline-none focus:border-[#0C5C6C]">
          <option value="">Ou : toutes régions</option>
          {REGIONS_BY_PAYS.France.map(r => <option key={r} value={r}>{r}</option>)}
        </select>
        <select value={dept} onChange={e => setDept(e.target.value)} disabled={!region}
          className="border border-gray-200 rounded-xl px-2.5 py-2 text-sm bg-white disabled:bg-gray-50 disabled:text-gray-400 focus:outline-none focus:border-[#0C5C6C]">
          <option value="">Tous départements</option>
          {depts.map(d => <option key={d} value={d}>{d}</option>)}
        </select>
      </div>
      <div className="flex items-center gap-3 mb-5 text-sm">
        <button onClick={autourDeMoi} disabled={locating}
          className="inline-flex items-center gap-1.5 border border-[#0C5C6C] text-[#0C5C6C] px-3 py-1.5 rounded-full hover:bg-[#E8F4F6] transition-colors disabled:opacity-60">
          📍 {locating ? 'Localisation…' : 'Autour de moi'}
        </button>
        {activeFilters > 0 && (
          <button onClick={() => { setRegion(''); setDept(''); setVille(''); setCp(''); setCommunes([]); setTri('recent'); }}
            className="text-gray-400 hover:text-gray-600">Réinitialiser les filtres</button>
        )}
      </div>

      {loading ? (
        <div className="py-24 text-center text-gray-400">Chargement…</div>
      ) : rows.length === 0 ? (
        <div className="py-24 text-center text-gray-400">Aucune annonce ne correspond à votre recherche.</div>
      ) : (
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-4">
          {rows.map(a => (
            <Link key={a.id} href={`/annonces/objets/${a.id}`}
              className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden hover:shadow-md transition-shadow">
              <div className="aspect-square bg-[#EEF3F0] relative">
                {a.photos?.[0]
                  ? <img src={a.photos[0]} alt={a.titre} className="w-full h-full object-cover" />
                  : <div className="w-full h-full flex items-center justify-center text-4xl">📦</div>}
                {boostActif(a.boost_until) && (
                  <span className="absolute top-2 left-2 bg-[#FF8A00] text-white text-[11px] font-bold px-2 py-0.5 rounded-full">⚡ Boostée</span>
                )}
                <span className="absolute bottom-2 left-2 bg-black/55 text-white text-[11px] px-2 py-0.5 rounded-full">
                  {categorieEmoji(a.categorie)} {ANNONCE_OBJET_TRANSACTIONS[a.type_transaction] ?? 'Vente'}
                </span>
              </div>
              <div className="p-3">
                <p className="font-bold text-[#1F2A2E] text-sm line-clamp-2" style={{ fontFamily: 'Galey, sans-serif' }}>{a.titre}</p>
                <p className="text-[#0C5C6C] font-bold text-sm mt-1">{prixLabel(a)}</p>
                {(a.ville || a.departement) && (
                  <p className="text-gray-400 text-xs mt-0.5 truncate">
                    📍 {[a.ville, a.departement].filter(Boolean).join(', ')}
                  </p>
                )}
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}

function Chip({ active, onClick, label }: { active: boolean; onClick: () => void; label: string }) {
  return (
    <button onClick={onClick}
      className={`whitespace-nowrap px-3 py-1.5 rounded-full text-xs font-semibold border transition-colors ${active ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'border-gray-200 text-gray-600 hover:border-[#0C5C6C]'}`}>
      {label}
    </button>
  );
}
