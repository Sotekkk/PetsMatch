'use client';
// Galerie privée côté client (compte destinataire ou lien privé) : grille
// d'aperçus aux proportions conservées, agrandissement. Aperçus seulement
// (compressés, filigrane si activé) : les fichiers finaux ne sont jamais
// exposés ici. Sélection et livraison : étape suivante.
import { useEffect, useState } from 'react';
import type { ContenuGalerie } from '@/lib/galeries-client';

export default function GalerieVue({ charger }: { charger: () => Promise<ContenuGalerie> }) {
  const [etat, setEtat] = useState<{ ok: true; g: ContenuGalerie } | { ok: false; err: string } | null>(null);
  const [zoom, setZoom] = useState<number | null>(null);

  useEffect(() => {
    let annule = false;
    charger().then(g => { if (!annule) setEtat({ ok: true, g }); })
      .catch(e => { if (!annule) setEtat({ ok: false, err: (e as Error).message }); });
    return () => { annule = true; };
  }, [charger]);

  useEffect(() => {
    if (zoom === null || !etat?.ok) return;
    const n = etat.g.photos.length;
    const k = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setZoom(null);
      if (e.key === 'ArrowRight') setZoom(z => (z === null ? z : (z + 1) % n));
      if (e.key === 'ArrowLeft') setZoom(z => (z === null ? z : (z - 1 + n) % n));
    };
    window.addEventListener('keydown', k);
    return () => window.removeEventListener('keydown', k);
  }, [zoom, etat]);

  if (!etat) return <div className="flex justify-center py-24"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  if (!etat.ok) return (
    <div className="max-w-md mx-auto text-center py-24 px-4">
      <p className="font-bold text-[#1F2A2E]">Galerie indisponible</p>
      <p className="text-sm text-gray-500 mt-1">{etat.err}</p>
    </div>
  );
  const { album, studio, photos } = etat.g;
  const protege = (e: React.SyntheticEvent) => e.preventDefault();

  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-6xl mx-auto px-4 py-6">
        <div className="flex items-center gap-3 mb-1">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          {studio.avatar && <img src={studio.avatar} alt="" className="w-10 h-10 rounded-full object-cover" />}
          <div>
            <h1 className="text-xl font-bold text-[#1F2A2E]">{album.titre ?? 'Galerie'}</h1>
            <p className="text-sm text-gray-500">
              {[studio.nom, album.date_seance ? `séance du ${new Date(album.date_seance).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' })}` : '', `${photos.length} photo${photos.length > 1 ? 's' : ''}`].filter(Boolean).join(' · ')}
            </p>
          </div>
        </div>
        {album.description && <p className="text-sm text-gray-700 mt-2 whitespace-pre-line">{album.description}</p>}
        <p className="text-xs text-gray-400 mt-2">Aperçus en qualité réduite. Les fichiers définitifs vous seront remis par votre photographe.</p>
        {photos.length === 0 ? <p className="text-sm text-gray-400 text-center py-16">Aucune photo pour le moment.</p> : (
          <div className="mt-5 columns-2 sm:columns-3 lg:columns-4 gap-3 [column-fill:_balance]">
            {photos.map((p, i) => (
              <button key={p.id} onClick={() => setZoom(i)} className="block w-full mb-3 break-inside-avoid rounded-xl overflow-hidden bg-gray-100">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={p.url} alt="" loading="lazy" draggable={false} onContextMenu={protege}
                  className="w-full h-auto block select-none" style={p.largeur && p.hauteur ? { aspectRatio: `${p.largeur} / ${p.hauteur}` } : undefined} />
              </button>
            ))}
          </div>
        )}
      </div>
      {zoom !== null && photos[zoom] && (
        <div className="fixed inset-0 z-50 bg-black/90 flex items-center justify-center" onClick={() => setZoom(null)}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={photos[zoom].url} alt="" draggable={false} onContextMenu={protege}
            className="max-w-[94vw] max-h-[88vh] object-contain select-none" onClick={e => e.stopPropagation()} />
          {photos.length > 1 && (
            <>
              <button onClick={e => { e.stopPropagation(); setZoom((zoom - 1 + photos.length) % photos.length); }}
                className="absolute left-3 top-1/2 -translate-y-1/2 w-11 h-11 rounded-full bg-white/15 text-white text-2xl">‹</button>
              <button onClick={e => { e.stopPropagation(); setZoom((zoom + 1) % photos.length); }}
                className="absolute right-3 top-1/2 -translate-y-1/2 w-11 h-11 rounded-full bg-white/15 text-white text-2xl">›</button>
            </>
          )}
          <p className="absolute bottom-4 text-white/70 text-sm">{zoom + 1} / {photos.length}</p>
        </div>
      )}
    </div>
  );
}
