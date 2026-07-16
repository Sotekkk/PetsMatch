'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';

interface AlbumPartageRow {
  album_id: string;
  expire_at: string;
  actif: boolean;
}

interface Album {
  id: string;
  titre: string;
}

interface Photo {
  id: string;
  photo_url: string;
  favori: boolean;
}

type State =
  | { status: 'loading' }
  | { status: 'expired' }
  | { status: 'invalid' }
  | { status: 'ok'; album: Album; photos: Photo[] };

export default function AlbumPartagePage() {
  const { token } = useParams<{ token: string }>();
  const [state, setState] = useState<State>({ status: 'loading' });

  useEffect(() => {
    if (!token) { setState({ status: 'invalid' }); return; }
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token]);

  async function load() {
    try {
      const { data: partage, error } = await supabase
        .from('album_partage')
        .select('album_id, expire_at, actif')
        .eq('token', token)
        .single();

      if (error || !partage) { setState({ status: 'invalid' }); return; }

      const row = partage as AlbumPartageRow;
      if (!row.actif || new Date(row.expire_at) < new Date()) {
        setState({ status: 'expired' }); return;
      }

      const [{ data: album, error: aErr }, { data: photos }] = await Promise.all([
        supabase.from('albums_photo').select('id, titre').eq('id', row.album_id).single(),
        supabase.from('album_photos').select('id, photo_url, favori').eq('album_id', row.album_id).order('created_at', { ascending: false }),
      ]);

      if (aErr || !album) { setState({ status: 'invalid' }); return; }

      setState({ status: 'ok', album: album as Album, photos: (photos ?? []) as Photo[] });
    } catch {
      setState({ status: 'invalid' });
    }
  }

  if (state.status === 'loading') {
    return <div className="flex justify-center py-32"><div className="w-8 h-8 border-2 border-[#90A4AE] border-t-transparent rounded-full animate-spin" /></div>;
  }

  if (state.status === 'expired') {
    return (
      <div className="max-w-md mx-auto px-4 py-24 text-center">
        <p className="text-5xl mb-4">⏳</p>
        <h1 className="font-['Galey'] font-bold text-xl text-[#1F2A2E] mb-2">Ce lien a expiré</h1>
        <p className="text-gray-500 text-sm">Demandez un nouveau lien à votre photographe.</p>
      </div>
    );
  }

  if (state.status === 'invalid') {
    return (
      <div className="max-w-md mx-auto px-4 py-24 text-center">
        <p className="text-5xl mb-4">🔍</p>
        <h1 className="font-['Galey'] font-bold text-xl text-[#1F2A2E] mb-2">Lien introuvable</h1>
        <p className="text-gray-500 text-sm">Vérifiez le lien reçu.</p>
      </div>
    );
  }

  const { album, photos } = state;

  return (
    <div className="max-w-4xl mx-auto px-4 py-10">
      <div className="text-center mb-8">
        <p className="text-4xl mb-2">📸</p>
        <h1 className="font-['Galey'] font-bold text-2xl text-[#1F2A2E]">{album.titre}</h1>
        <p className="text-gray-500 text-sm mt-1">{photos.length} photo{photos.length > 1 ? 's' : ''}</p>
      </div>

      {photos.length === 0 ? (
        <p className="text-center text-gray-400 py-16">Aucune photo pour l&apos;instant.</p>
      ) : (
        <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
          {photos.map(p => (
            <a key={p.id} href={p.photo_url} download target="_blank" rel="noreferrer"
              className="relative aspect-square rounded-xl overflow-hidden bg-gray-100 group">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={p.photo_url} alt="" className="w-full h-full object-cover" />
              {p.favori && (
                <span className="absolute top-2 right-2 text-red-500 text-lg drop-shadow">❤️</span>
              )}
              <div className="absolute inset-0 bg-black/0 group-hover:bg-black/30 transition-colors flex items-center justify-center opacity-0 group-hover:opacity-100">
                <span className="text-white text-xs font-semibold">Télécharger</span>
              </div>
            </a>
          ))}
        </div>
      )}

      <p className="text-center text-xs text-gray-400 mt-10">Galerie livrée via PetsMatch</p>
    </div>
  );
}
