'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
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
  boost_until: string | null;
  created_at: string | null;
}

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
  const [cat, setCat] = useState('tous');

  useEffect(() => {
    setLoading(true);
    let q = supabase.from('annonces_objets').select(
      'id, titre, categorie, type_transaction, prix, prix_unite, prix_negociable, photos, ville, boost_until, created_at',
    ).eq('statut', 'disponible').order('created_at', { ascending: false }).limit(120);
    if (cat !== 'tous') q = q.eq('categorie', cat);
    q.then(({ data }) => {
      const list = (data ?? []) as AnnonceObjet[];
      setRows([...list.filter(a => boostActif(a.boost_until)), ...list.filter(a => !boostActif(a.boost_until))]);
      setLoading(false);
    });
  }, [cat]);

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
      <p className="text-sm text-gray-500 mb-5">
        Cage, harnais, foin, location de prairie ou de parcelle, matériel agricole…
        Matériel lié aux animaux uniquement — jamais un animal.
      </p>

      <div className="flex gap-2 overflow-x-auto pb-3 mb-4">
        <Chip active={cat === 'tous'} onClick={() => setCat('tous')} label="🔎 Tout" />
        {ANNONCE_OBJET_CATEGORIES.map(c => (
          <Chip key={c.slug} active={cat === c.slug} onClick={() => setCat(c.slug)} label={`${c.emoji} ${c.label}`} />
        ))}
      </div>

      {loading ? (
        <div className="py-24 text-center text-gray-400">Chargement…</div>
      ) : rows.length === 0 ? (
        <div className="py-24 text-center text-gray-400">Aucune annonce dans cette catégorie.</div>
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
                {a.ville && <p className="text-gray-400 text-xs mt-0.5 truncate">📍 {a.ville}</p>}
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
