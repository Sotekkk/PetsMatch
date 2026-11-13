'use client';
// Image / vidéo d'un document qui peut être privé (stockage `documents`) :
// le lien temporaire est demandé à lien-document avant l'affichage.
import { useEffect, useState } from 'react';
import type { ImgHTMLAttributes, VideoHTMLAttributes } from 'react';
import { estDocumentPrive, lienDocument } from '@/lib/document-prive';

/** Lien utilisable de [url] (null pendant la résolution ou si refusé). */
export function useLienDocument(url?: string | null, lienSecret?: string): string | null {
  const prive = estDocumentPrive(url);
  const [lien, setLien] = useState<string | null>(prive ? null : (url ?? null));
  useEffect(() => {
    if (!url) { setLien(null); return; }
    if (!estDocumentPrive(url)) { setLien(url); return; }
    let actif = true;
    setLien(null);
    lienDocument(url, lienSecret).then((l) => { if (actif) setLien(l); }, () => { if (actif) setLien(null); });
    return () => { actif = false; };
  }, [url, lienSecret]);
  return lien;
}

type ImgProps = Omit<ImgHTMLAttributes<HTMLImageElement>, 'src'> & { src?: string | null; lienSecret?: string };
export default function ImagePrivee({ src, lienSecret, alt = '', ...rest }: ImgProps) {
  const lien = useLienDocument(src, lienSecret);
  if (!lien) return <span className={`block bg-gray-100 ${rest.className ?? ''}`} style={rest.style} />;
  // eslint-disable-next-line @next/next/no-img-element
  return <img src={lien} alt={alt} {...rest} />;
}

type VideoProps = Omit<VideoHTMLAttributes<HTMLVideoElement>, 'src'> & { src?: string | null; lienSecret?: string };
export function VideoPrivee({ src, lienSecret, ...rest }: VideoProps) {
  const lien = useLienDocument(src, lienSecret);
  if (!lien) return <span className={`block bg-black ${rest.className ?? ''}`} style={rest.style} />;
  return <video src={lien} {...rest} />;
}

/** Photo d'un journal (pension, garde) : entière sur fond flouté (jamais
 *  rognée), plein écran au clic avec « Télécharger ». Miroir appli :
 *  lib/widgets/photo_journal.dart. */
export function PhotoJournal({ src, hauteur = 'h-60' }: { src?: string | null; hauteur?: string }) {
  const lien = useLienDocument(src);
  const [plein, setPlein] = useState(false);
  if (!lien) return <span className={`block bg-gray-100 w-full ${hauteur}`} />;
  const telecharger = async () => {
    try {
      const blob = await (await fetch(lien)).blob();
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = `photo-${Date.now()}.${blob.type.includes('png') ? 'png' : 'jpg'}`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 2000);
    } catch { window.open(lien, '_blank', 'noopener'); }
  };
  return (
    <>
      <button type="button" onClick={() => setPlein(true)} className={`relative block w-full overflow-hidden ${hauteur}`} aria-label="Agrandir la photo">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={lien} alt="" aria-hidden className="absolute inset-0 w-full h-full object-cover blur-xl scale-110 opacity-70" />
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={lien} alt="" className="relative w-full h-full object-contain" />
      </button>
      {plein && (
        <div className="fixed inset-0 z-[80] bg-black/95 flex flex-col" onClick={() => setPlein(false)}>
          <div className="flex justify-end gap-2 p-3" onClick={e => e.stopPropagation()}>
            <button type="button" onClick={telecharger} className="px-3 py-1.5 rounded-lg text-sm font-semibold text-white border border-white/40">Télécharger</button>
            <button type="button" onClick={() => setPlein(false)} className="px-3 py-1.5 rounded-lg text-sm font-semibold text-white border border-white/40">Fermer</button>
          </div>
          <div className="flex-1 flex items-center justify-center p-3 min-h-0">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={lien} alt="" className="max-w-full max-h-full object-contain" onClick={e => e.stopPropagation()} />
          </div>
        </div>
      )}
    </>
  );
}
