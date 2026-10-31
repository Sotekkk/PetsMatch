'use client';

// Panneau latéral (plein écran sur mobile) qui affiche une page du site par-
// dessus la page courante : la page du dessous garde son onglet, ses filtres,
// sa position et l'élément sélectionné. La page affichée referme le panneau
// d'elle-même après son action (lib/panneau.ts allerOuFermer).

import { useEffect, useState } from 'react';
import { MSG_PANNEAU_FERMER, MSG_PANNEAU_PRET } from '@/lib/panneau';

export default function PanneauPage({ url, titre, onClose }: { url: string; titre: string; onClose: () => void }) {
  const [pret, setPret] = useState(false);

  useEffect(() => {
    const onMsg = (e: MessageEvent) => {
      if (e.origin !== window.location.origin) return;
      const type = (e.data as { type?: string } | null)?.type;
      if (type === MSG_PANNEAU_FERMER) onClose();
      if (type === MSG_PANNEAU_PRET) setPret(true);
    };
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('message', onMsg);
    window.addEventListener('keydown', onKey);
    return () => { window.removeEventListener('message', onMsg); window.removeEventListener('keydown', onKey); };
  }, [onClose]);

  return (
    <div className="fixed inset-0 z-[70] flex justify-end bg-black/40" onClick={onClose}>
      <div className="relative h-full w-full md:w-[min(920px,92vw)] bg-[#F8F8F6] shadow-2xl flex flex-col"
        onClick={e => e.stopPropagation()} role="dialog" aria-label={titre}>
        <div className="flex items-center gap-3 px-4 py-3 bg-[#0C5C6C] text-white shrink-0">
          <p className="flex-1 min-w-0 truncate text-sm font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>{titre}</p>
          <button type="button" onClick={onClose}
            className="text-sm font-semibold px-3 py-1.5 rounded-lg bg-white/15 hover:bg-white/25">Fermer</button>
        </div>
        <div className="relative flex-1 min-h-0">
          {!pret && (
            <div className="absolute inset-0 flex items-center justify-center bg-[#F8F8F6]">
              <div className="w-8 h-8 border-4 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
            </div>
          )}
          {/* Page sans en-tête : SiteShell détecte l'iframe et prévient (MSG_PANNEAU_PRET). */}
          <iframe src={url} title={titre} className="w-full h-full border-0"
            onLoad={() => setTimeout(() => setPret(true), 1500)} />
        </div>
      </div>
    </div>
  );
}
