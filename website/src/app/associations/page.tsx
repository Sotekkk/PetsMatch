'use client';

import { useEffect, useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import dynamic from 'next/dynamic';
import { supabase } from '@/lib/supabase';
import type { AssoMapItem } from '@/components/AssociationsMap';

const AssociationsMap = dynamic(() => import('@/components/AssociationsMap'), {
  ssr: false,
  loading: () => (
    <div className="flex items-center justify-center h-full bg-gray-100 rounded-2xl">
      <div className="w-8 h-8 border-2 border-teal-700 border-t-transparent rounded-full animate-spin" />
    </div>
  ),
});

interface Asso {
  uid: string;
  name: string;
  avatar?: string;
  banner?: string;
  ville?: string;
  description?: string;
  lat?: number;
  lng?: number;
}

export default function AssociationsPage() {
  const [assos, setAssos]   = useState<Asso[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch]   = useState('');
  const [view, setView]       = useState<'liste' | 'carte'>('liste');

  useEffect(() => {
    Promise.all([
      supabase.from('user_profiles')
        .select('uid, name_elevage, profile_label, avatar_url, banner_url, ville, description, latitude, longitude')
        .eq('profile_type', 'association')
        .order('name_elevage'),
      supabase.from('users')
        .select('uid, name_elevage, firstname, lastname, photo_profil_elevage, photo_url, banner_url, ville_elevage, ville, description_elevage, latitude, longitude')
        .eq('is_association', true)
        .then(r => r), // primary accounts
    ]).then(([{ data: profiles }, { data: primary }]) => {
      const list: Asso[] = [];
      const seenUids = new Set<string>();

      for (const p of (profiles ?? []) as Record<string, unknown>[]) {
        const uid = p['uid'] as string ?? '';
        seenUids.add(uid);
        const nameEl = (p['name_elevage'] as string | undefined)?.trim() ?? '';
        const label  = (p['profile_label'] as string | undefined)?.trim() ?? '';
        list.push({
          uid,
          name:        nameEl || label || 'Association',
          avatar:      (p['avatar_url'] as string | undefined) ?? undefined,
          banner:      (p['banner_url'] as string | undefined) ?? undefined,
          ville:       (p['ville'] as string | undefined)?.trim() ?? undefined,
          description: (p['description'] as string | undefined)?.trim() ?? undefined,
          lat:         (p['latitude'] as number | undefined) ?? undefined,
          lng:         (p['longitude'] as number | undefined) ?? undefined,
        });
      }

      for (const u of (primary ?? []) as Record<string, unknown>[]) {
        const uid = u['uid'] as string ?? '';
        if (seenUids.has(uid)) continue;
        const name = (u['name_elevage'] as string | undefined)?.trim()
          || `${u['firstname'] ?? ''} ${u['lastname'] ?? ''}`.trim()
          || 'Association';
        const ville = ((u['ville_elevage'] as string | undefined)?.trim() || (u['ville'] as string | undefined)?.trim()) ?? undefined;
        const avatar = ((u['photo_profil_elevage'] as string | undefined) || (u['photo_url'] as string | undefined)) ?? undefined;
        const banner = (u['banner_url'] as string | undefined) ?? undefined;
        list.push({
          uid, name, avatar, banner, ville,
          description: (u['description_elevage'] as string | undefined)?.trim() ?? undefined,
          lat: (u['latitude'] as number | undefined) ?? undefined,
          lng: (u['longitude'] as number | undefined) ?? undefined,
        });
      }

      setAssos(list);
      setLoading(false);
    });
  }, []);

  const filtered = assos.filter(a => {
    if (!search) return true;
    const q = search.toLowerCase();
    return a.name.toLowerCase().includes(q) || (a.ville ?? '').toLowerCase().includes(q);
  });

  const withCoords: AssoMapItem[] = filtered
    .filter(a => a.lat != null && a.lng != null)
    .map(a => ({ id: a.uid, name: a.name, avatar: a.avatar, ville: a.ville, lat: a.lat!, lng: a.lng! }));

  return (
    <div className="max-w-6xl mx-auto px-4 py-10">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-3xl font-bold text-[#1F2A2E] font-galey mb-1">
            Associations & Refuges
          </h1>
          <p className="text-gray-500 text-sm font-galey">
            {filtered.length} association{filtered.length !== 1 ? 's' : ''}
            {view === 'carte' && withCoords.length < filtered.length
              ? ` · ${withCoords.length} sur la carte` : ''}
          </p>
        </div>
        {/* Toggle liste / carte */}
        <div className="flex bg-gray-100 rounded-xl p-1">
          {(['liste', 'carte'] as const).map(v => (
            <button key={v} onClick={() => setView(v)}
              className={`flex items-center gap-1.5 px-4 py-2 rounded-lg text-sm font-medium transition-colors font-galey ${
                view === v ? 'bg-white text-[#1F2A2E] shadow-sm' : 'text-gray-500 hover:text-gray-700'
              }`}>
              {v === 'liste' ? (
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 10h16M4 14h16M4 18h16"/>
                </svg>
              ) : (
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7"/>
                </svg>
              )}
              {v === 'liste' ? 'Liste' : 'Carte'}
            </button>
          ))}
        </div>
      </div>

      {/* Recherche */}
      <input
        type="text"
        placeholder="Rechercher par nom, ville…"
        value={search}
        onChange={e => setSearch(e.target.value)}
        className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-teal-600 bg-white mb-6 font-galey"
      />

      {loading ? (
        <div className="flex justify-center py-20">
          <div className="w-8 h-8 border-2 border-teal-700 border-t-transparent rounded-full animate-spin" />
        </div>
      ) : view === 'carte' ? (
        <div className="rounded-2xl overflow-hidden border border-gray-200 shadow-sm" style={{ height: '65vh' }}>
          <AssociationsMap assos={withCoords} />
        </div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-20 text-gray-400 font-galey">
          <p className="text-5xl mb-4">🏠</p>
          <p>Aucune association trouvée</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
          {filtered.map(a => <AssoCard key={a.uid} asso={a} />)}
        </div>
      )}
    </div>
  );
}

function AssoCard({ asso: a }: { asso: Asso }) {
  return (
    <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden hover:shadow-md transition-shadow">
      <div className="relative h-36 bg-[#EEF5EA]">
        {a.banner ? (
          <>
            <Image src={a.banner} alt={a.name} fill className="object-cover" unoptimized />
            {a.avatar && (
              <div className="absolute bottom-2 left-3 w-10 h-10 rounded-full border-2 border-white overflow-hidden shadow-sm bg-[#EEF5EA]">
                <Image src={a.avatar} alt={a.name} fill className="object-cover" unoptimized />
              </div>
            )}
          </>
        ) : a.avatar ? (
          <Image src={a.avatar} alt={a.name} fill className="object-cover" unoptimized />
        ) : (
          <span className="absolute inset-0 flex items-center justify-center text-5xl">🏠</span>
        )}
      </div>
      <div className="p-4">
        <div className="flex items-start gap-2 mb-0.5">
          <h3 className="font-bold text-[#1F2A2E] text-base truncate flex-1 font-galey">{a.name}</h3>
          <span className="text-xs bg-teal-50 text-teal-700 px-2 py-0.5 rounded-full font-galey font-medium flex-shrink-0">Asso</span>
        </div>
        {a.ville && <p className="text-gray-400 text-sm font-galey">📍 {a.ville}</p>}
        {a.description && (
          <p className="text-gray-500 text-xs mt-2 line-clamp-2 font-galey">{a.description}</p>
        )}
        <Link href={`/associations/${a.uid}`}
          className="mt-3 w-full block text-center text-sm bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-medium py-2 rounded-xl transition-colors font-galey">
          Voir le profil
        </Link>
      </div>
    </div>
  );
}
