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
