'use client';

import { useEffect, useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import dynamic from 'next/dynamic';
import { supabase } from '@/lib/supabase';
import type { EleveurMapItem } from '@/components/ElevagesMap';

const ElevagesMap = dynamic(() => import('@/components/ElevagesMap'), {
  ssr: false,
  loading: () => (
    <div className="flex items-center justify-center h-full bg-gray-100 rounded-2xl">
      <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
    </div>
  ),
});

interface Eleveur {
  uid: string;
  firstname?: string;
  lastname?: string;
  name_elevage?: string;
  profile_picture_url?: string;
  profile_picture_url_elevage?: string;
  banner_url?: string;
  ville_elevage?: string;
  ville?: string;
  especes_elevees?: { espece: string; races?: string[] }[];
  is_dog?: boolean;
  is_cat?: boolean;
  dog_breeds?: string[];
  cat_breeds?: string[];
  desc_entreprise?: string;
  lat?: number;
  lng?: number;
}

const ESPECES = ['tous', 'chien', 'chat', 'cheval', 'lapin', 'oiseau', 'nac', 'ovin', 'autre'];
const ESPECE_LABEL: Record<string, string> = {
  tous: 'Tous', chien: 'Chien', chat: 'Chat', cheval: 'Cheval',
  lapin: 'Lapin', oiseau: 'Oiseau', nac: 'NAC', ovin: 'Ovin', autre: 'Autre',
};

function especesOf(e: Eleveur): string[] {
  if (e.especes_elevees && e.especes_elevees.length > 0)
    return e.especes_elevees.map(x => x.espece.toLowerCase());
  const list: string[] = [];
  if (e.is_dog) list.push('chien');
  if (e.is_cat) list.push('chat');
  return list;
}

export default function ElevagesPage() {
  const [eleveurs, setEleveurs] = useState<Eleveur[]>([]);
  const [loading, setLoading] = useState(true);
  const [filtre, setFiltre] = useState('tous');
  const [search, setSearch] = useState('');
  const [view, setView] = useState<'liste' | 'carte'>('liste');

  useEffect(() => {
    supabase
      .from('users')
      .select('uid, firstname, lastname, name_elevage, profile_picture_url, profile_picture_url_elevage, banner_url, ville_elevage, ville, especes_elevees, is_dog, is_cat, dog_breeds, cat_breeds, desc_entreprise, lat, lng')
      .eq('is_elevage', true)
      .then(({ data }) => {
        setEleveurs((data ?? []) as Eleveur[]);
        setLoading(false);
      });
  }, []);

  const filtered = eleveurs.filter(e => {
    const esps = especesOf(e);
    if (filtre !== 'tous' && !esps.includes(filtre)) return false;
    const name = e.name_elevage ?? `${e.firstname ?? ''} ${e.lastname ?? ''}`.trim();
    const ville = e.ville_elevage ?? e.ville ?? '';
    const races = [
      ...((e.dog_breeds ?? []) as string[]),
      ...((e.cat_breeds ?? []) as string[]),
      ...(e.especes_elevees?.flatMap(x => x.races ?? []) ?? []),
    ];
    if (search && !`${name} ${ville} ${races.join(' ')}`.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  });

  const withCoords: EleveurMapItem[] = filtered
    .filter(e => e.lat != null && e.lng != null)
    .map(e => ({
      id: e.uid,
      name: (e.name_elevage ?? `${e.firstname ?? ''} ${e.lastname ?? ''}`.trim()) || 'Élevage',
      photo: e.profile_picture_url_elevage ?? e.profile_picture_url,
      ville: e.ville_elevage ?? e.ville,
      especes: especesOf(e),
      lat: e.lat!,
      lng: e.lng!,
    }));

  return (
    <div className="max-w-6xl mx-auto px-4 py-10">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-3xl font-bold text-[#1F2A2E] mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>
            Élevages certifiés
          </h1>
          <p className="text-gray-500 text-sm">
            {filtered.length} élevage{filtered.length !== 1 ? 's' : ''}
            {view === 'carte' && withCoords.length < filtered.length
              ? ` · ${withCoords.length} sur la carte`
              : ''}
          </p>
        </div>
        <div className="flex bg-gray-100 rounded-xl p-1">
          <button onClick={() => setView('liste')}
            className={`flex items-center gap-1.5 px-4 py-2 rounded-lg text-sm font-medium transition-colors ${view === 'liste' ? 'bg-white text-[#1F2A2E] shadow-sm' : 'text-gray-500 hover:text-gray-700'}`}>
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 10h16M4 14h16M4 18h16"/>
            </svg>
            Liste
          </button>
          <button onClick={() => setView('carte')}
            className={`flex items-center gap-1.5 px-4 py-2 rounded-lg text-sm font-medium transition-colors ${view === 'carte' ? 'bg-white text-[#1F2A2E] shadow-sm' : 'text-gray-500 hover:text-gray-700'}`}>
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7"/>
            </svg>
            Carte
          </button>
        </div>
      </div>

      <div className="flex flex-col sm:flex-row gap-3 mb-6">
        <input
          type="text"
          placeholder="Rechercher par nom, race, ville…"
          value={search}
          onChange={e => setSearch(e.target.value)}
          className="flex-1 border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white"
        />
        <div className="flex gap-2 flex-wrap">
          {ESPECES.map(esp => (
            <button key={esp} onClick={() => setFiltre(esp)}
              className={`px-3 py-2 rounded-full text-xs font-medium transition-colors border ${
                filtre === esp
                  ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]'
                  : 'bg-white text-gray-600 border-gray-200 hover:border-[#0C5C6C]'
              }`}>
              {ESPECE_LABEL[esp] ?? esp}
            </button>
          ))}
        </div>
      </div>

      {loading ? (
        <div className="flex justify-center py-20">
          <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
        </div>
      ) : view === 'carte' ? (
        <div className="rounded-2xl overflow-hidden border border-gray-200 shadow-sm" style={{ height: '65vh' }}>
          <ElevagesMap eleveurs={withCoords} />
        </div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-20 text-gray-400">Aucun élevage trouvé</div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
          {filtered.map(e => <EleveurCard key={e.uid} eleveur={e} />)}
        </div>
      )}

      {view === 'carte' && (
        <div className="mt-4 flex flex-wrap gap-2 justify-center">
          {[
            { esp: 'chien', color: '#2196F3', emoji: '🐕' },
            { esp: 'chat', color: '#FF9800', emoji: '🐈' },
            { esp: 'cheval', color: '#4CAF50', emoji: '🐴' },
            { esp: 'lapin', color: '#9C27B0', emoji: '🐇' },
            { esp: 'oiseau', color: '#00BCD4', emoji: '🦜' },
            { esp: 'nac', color: '#CDDC39', emoji: '🦎' },
            { esp: 'autre', color: '#E91E8C', emoji: '🏡' },
          ].map(({ esp, color, emoji }) => (
            <span key={esp} className="flex items-center gap-1 text-xs text-gray-600 bg-white border border-gray-100 px-2.5 py-1 rounded-full shadow-sm">
              <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ backgroundColor: color }} />
              {emoji} {ESPECE_LABEL[esp] ?? esp}
            </span>
          ))}
        </div>
      )}
    </div>
  );
}

function EleveurCard({ eleveur: e }: { eleveur: Eleveur }) {
  const name = (e.name_elevage ?? `${e.firstname ?? ''} ${e.lastname ?? ''}`.trim()) || 'Élevage';
  const photo = e.profile_picture_url_elevage ?? e.profile_picture_url;
  const banner = e.banner_url;
  const ville = e.ville_elevage ?? e.ville;
  const esps = especesOf(e);

  return (
    <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden hover:shadow-md transition-shadow">
      <div className="relative h-36 bg-[#EEF5EA]">
        {banner ? (
          <>
            <Image src={banner} alt={name} fill className="object-cover" />
            {photo && (
              <div className="absolute bottom-2 left-3 w-10 h-10 rounded-full border-2 border-white overflow-hidden shadow-sm bg-[#EEF5EA]">
                <Image src={photo} alt={name} fill className="object-cover" />
              </div>
            )}
          </>
        ) : photo ? (
          <Image src={photo} alt={name} fill className="object-cover" />
        ) : (
          <span className="absolute inset-0 flex items-center justify-center text-5xl">🏡</span>
        )}
      </div>
      <div className="p-4">
        <h3 className="font-bold text-[#1F2A2E] text-base truncate">{name}</h3>
        {ville && <p className="text-gray-400 text-sm">📍 {ville}</p>}
        {esps.length > 0 && (
          <div className="flex gap-1 flex-wrap mt-2">
            {esps.slice(0, 3).map(esp => (
              <span key={esp} className="text-xs bg-[#EEF5EA] text-[#0C5C6C] px-2 py-0.5 rounded-full font-medium capitalize">
                {ESPECE_LABEL[esp] ?? esp}
              </span>
            ))}
          </div>
        )}
        {e.desc_entreprise && (
          <p className="text-gray-500 text-xs mt-2 line-clamp-2">{e.desc_entreprise}</p>
        )}
        <Link href={`/elevages/${e.uid}`}
          className="mt-3 w-full block text-center text-sm bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-medium py-2 rounded-xl transition-colors">
          Voir le profil
        </Link>
      </div>
    </div>
  );
}
