'use client';

// Itinéraire vers une adresse d'intervention : choix de l'application
// (Google Maps, Waze, Plans). Miroir appli : lib/utils/itineraire.dart.

import { useEffect, useRef, useState } from 'react';

export function liensItineraire(lat: number | null, lng: number | null, adresse: string | null) {
  const coords = lat != null && lng != null;
  const dest = coords ? `${lat},${lng}` : encodeURIComponent(adresse?.trim() ?? '');
  return [
    { label: 'Google Maps', href: `https://www.google.com/maps/dir/?api=1&destination=${dest}` },
    { label: 'Waze', href: coords ? `https://waze.com/ul?ll=${dest}&navigate=yes` : `https://waze.com/ul?q=${dest}&navigate=yes` },
    { label: 'Plans (Apple)', href: `https://maps.apple.com/?daddr=${dest}` },
  ];
}

export default function ItineraireMenu({ lat, lng, adresse, className, children }: {
  lat: number | null; lng: number | null; adresse: string | null; className?: string; children: React.ReactNode;
}) {
  const [ouvert, setOuvert] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!ouvert) return;
    const fermer = (e: MouseEvent) => { if (!ref.current?.contains(e.target as Node)) setOuvert(false); };
    document.addEventListener('mousedown', fermer);
    return () => document.removeEventListener('mousedown', fermer);
  }, [ouvert]);
  return (
    <div ref={ref} className="relative inline-block">
      <button type="button" onClick={() => setOuvert(v => !v)} className={className}>{children}</button>
      {ouvert && (
        <div className="absolute right-0 top-full mt-1 w-48 bg-white rounded-xl shadow-lg border border-gray-100 z-30 overflow-hidden">
          <p className="px-3 pt-2 pb-1 text-[11px] font-bold uppercase tracking-wider text-gray-400">Ouvrir avec</p>
          {liensItineraire(lat, lng, adresse).map(l => (
            <a key={l.label} href={l.href} target="_blank" rel="noopener noreferrer" onClick={() => setOuvert(false)}
              className="block px-3 py-2 text-sm text-[#1E2025] hover:bg-gray-50">{l.label}</a>
          ))}
        </div>
      )}
    </div>
  );
}
