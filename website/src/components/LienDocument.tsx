'use client';
// <a> vers un document : si le document est privé (stockage `documents` /
// `contrats`), le clic demande un lien temporaire à lien-document.
import type { AnchorHTMLAttributes, MouseEvent } from 'react';
import { estDocumentPrive, ouvrirDocument } from '@/lib/document-prive';

type Props = AnchorHTMLAttributes<HTMLAnchorElement> & { href?: string | null; lienSecret?: string };

export default function LienDocument({ href, lienSecret, onClick, ...rest }: Props) {
  const url = href ?? '';
  if (!estDocumentPrive(url)) return <a href={url || undefined} onClick={onClick} {...rest} />;
  return (
    <a
      href={url}
      {...rest}
      download={undefined}
      onClick={(e: MouseEvent<HTMLAnchorElement>) => {
        onClick?.(e);
        e.preventDefault();
        void ouvrirDocument(url, lienSecret);
      }}
    />
  );
}
