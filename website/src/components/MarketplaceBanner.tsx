'use client';

import { useEffect, useState, useRef, useCallback } from 'react';
import { supabase } from '@/lib/supabase';

const VET_PLACEHOLDER =
  'https://images.unsplash.com/photo-1628009368231-7bb7cfcb0def?w=800&q=70&fit=crop';

type Partner = {
  id: string;
  nom: string;
  description?: string;
  logo_url?: string;
  site_url?: string;
  categorie?: string;
};

function accentColor(categorie?: string) {
  if (categorie === 'assurance') return '#0C5C6C';
  if (categorie === 'sante' || categorie === 'veterinaire') return '#2E86AB';
  return '#6E9E57';
}

function heroImage(p: Partner): string | undefined {
  if (p.logo_url) return p.logo_url;
  if (p.categorie === 'sante' || p.categorie === 'veterinaire') return VET_PLACEHOLDER;
  return undefined;
}

export default function MarketplaceBanner() {
  const [partners, setPartners] = useState<Partner[]>([]);
  const [current, setCurrent] = useState(0);
  const slideTimer = useRef<ReturnType<typeof setInterval> | null>(null);
  const reloadTimer = useRef<ReturnType<typeof setInterval> | null>(null);

  const loadPartners = useCallback(async () => {
    const { data } = await supabase
      .from('marketplace_partners')
      .select('id, nom, description, logo_url, site_url, categorie')
      .eq('statut', 'actif')
      .limit(20);
    if (!data || data.length === 0) return;
    const shuffled = [...data].sort(() => Math.random() - 0.5).slice(0, 5) as Partner[];
    setCurrent(0);
    setPartners(shuffled);
  }, []);

  const startTimers = useCallback((count: number) => {
    if (slideTimer.current) clearInterval(slideTimer.current);
    if (reloadTimer.current) clearInterval(reloadTimer.current);

    if (count > 1) {
      slideTimer.current = setInterval(() => {
        setCurrent((c) => (c + 1) % count);
      }, 8000);
    }

    reloadTimer.current = setInterval(() => {
      if (slideTimer.current) clearInterval(slideTimer.current);
      loadPartners();
    }, 40000);
  }, [loadPartners]);

  useEffect(() => {
    loadPartners();
    return () => {
      if (slideTimer.current) clearInterval(slideTimer.current);
      if (reloadTimer.current) clearInterval(reloadTimer.current);
    };
  }, [loadPartners]);

  useEffect(() => {
    if (partners.length > 0) startTimers(partners.length);
  }, [partners, startTimers]);

  if (partners.length === 0) return null;

  const p = partners[current];
  const color = accentColor(p.categorie);
  const img = heroImage(p);

  const handleClick = () => {
    if (p.site_url) window.open(p.site_url, '_blank', 'noopener,noreferrer');
  };

  return (
    <div className="w-full">
      {/* Carte */}
      <div
        onClick={handleClick}
        className={`relative rounded-2xl overflow-hidden shadow-md cursor-pointer select-none transition-transform hover:scale-[1.01] active:scale-[0.99]`}
        style={{ height: 130 }}
      >
        {/* Hero image / gradient */}
        {img ? (
          <img
            key={p.id}
            src={img}
            alt={p.nom}
            className="absolute inset-0 w-full h-full object-cover transition-opacity duration-500"
          />
        ) : (
          <div
            className="absolute inset-0"
            style={{
              background: `linear-gradient(135deg, ${color}, ${color}BB)`,
            }}
          />
        )}

        {/* Vignette bas */}
        <div className="absolute inset-0 bg-gradient-to-t from-black/70 via-black/20 to-transparent" />

        {/* Badge pub */}
        <span className="absolute top-3 left-3 text-[10px] text-white bg-black/40 px-2 py-0.5 rounded">
          Publicité
        </span>

        {/* Nom + description */}
        <div className="absolute bottom-0 left-0 right-0 p-4">
          <p className="text-white font-extrabold text-xl leading-tight drop-shadow"
            style={{ fontFamily: 'Galey, sans-serif' }}>
            {p.nom}
          </p>
          {p.description && (
            <p className="text-white/80 text-sm mt-1 line-clamp-1"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              {p.description}
            </p>
          )}
        </div>
      </div>

      {/* Dots */}
      {partners.length > 1 && (
        <div className="flex justify-center gap-1.5 mt-2.5">
          {partners.map((partner, i) => {
            const c = accentColor(partner.categorie);
            return (
              <button
                key={partner.id}
                onClick={() => {
                  setCurrent(i);
                  startTimers(partners.length);
                }}
                className="h-[7px] rounded-full transition-all duration-300"
                style={{
                  width: i === current ? 22 : 7,
                  backgroundColor: i === current ? c : '#D1D5DB',
                }}
              />
            );
          })}
        </div>
      )}
    </div>
  );
}
