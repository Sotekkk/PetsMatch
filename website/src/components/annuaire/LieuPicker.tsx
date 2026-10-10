'use client';

// Champ « Lieu » de l'annuaire : commune française (autocomplétion API
// Adresse) ou « Autour de moi » (position du profil). Vide = toute la France.

import { useEffect, useRef, useState } from 'react';
import { chercherCommunes, type LieuRecherche } from '@/lib/annuaire-filtres';

interface Props {
  value: LieuRecherche | null;
  onChange: (l: LieuRecherche | null) => void;
  /** Position du profil connecté, pour « Autour de moi » (null = indisponible) */
  maPosition: LieuRecherche | null;
}

export default function LieuPicker({ value, onChange, maPosition }: Props) {
  const [text, setText] = useState(value?.label ?? '');
  const [open, setOpen] = useState(false);
  const [suggestions, setSuggestions] = useState<LieuRecherche[]>([]);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => { setText(value?.label ?? ''); }, [value]);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) { setOpen(false); setText(value?.label ?? ''); }
    };
    document.addEventListener('mousedown', onDown);
    return () => document.removeEventListener('mousedown', onDown);
  }, [open, value]);

  function onType(v: string) {
    setText(v);
    setOpen(true);
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(async () => setSuggestions(await chercherCommunes(v)), 250);
  }

  function choisir(l: LieuRecherche | null) {
    onChange(l);
    setText(l?.label ?? '');
    setSuggestions([]);
    setOpen(false);
  }

  return (
    <div className="relative" ref={ref}>
      <div className={`h-11 flex items-center gap-2 px-3 rounded-xl border bg-white ${open || value ? 'border-[#0C5C6C]' : 'border-[#E5E8E6]'}`}>
        <svg className="w-4 h-4 text-gray-400 flex-shrink-0" fill="none" stroke="currentColor" strokeWidth={1.8} viewBox="0 0 24 24" aria-hidden><path strokeLinecap="round" strokeLinejoin="round" d="M12 21s7-6.2 7-12a7 7 0 10-14 0c0 5.8 7 12 7 12z" /><circle cx="12" cy="9" r="2.5" /></svg>
        <input type="text" value={text} placeholder="Ville ou code postal" title="Ville ou code postal"
          onChange={e => onType(e.target.value)} onFocus={() => setOpen(true)}
          className="flex-1 min-w-0 text-[13px] sm:text-sm outline-none bg-transparent placeholder:text-gray-500" style={{ fontFamily: 'Galey, sans-serif' }} />
        {value && (
          <button type="button" onClick={() => choisir(null)} aria-label="Effacer le lieu"
            className="text-gray-400 hover:text-gray-600 text-lg leading-none px-1">×</button>
        )}
      </div>
      {open && (
        <div className="absolute z-30 left-0 right-0 min-w-[16rem] mt-1 bg-white border border-[#E5E8E6] rounded-xl shadow-lg overflow-hidden max-h-64 overflow-y-auto">
          {maPosition && (
            <button type="button" onClick={() => choisir(maPosition)}
              className="w-full text-left px-4 py-2.5 text-sm hover:bg-gray-50 text-[#0C5C6C] font-semibold border-b border-gray-50">
              Autour de moi{maPosition.ville ? ` (${maPosition.ville})` : ''}
            </button>
          )}
          <button type="button" onClick={() => choisir(null)}
            className="w-full text-left px-4 py-2.5 text-sm hover:bg-gray-50 text-gray-600 border-b border-gray-50">
            Toute la France
          </button>
          {suggestions.map(s => (
            <button key={`${s.label}-${s.lat}`} type="button" onClick={() => choisir(s)}
              className="w-full text-left px-4 py-2.5 text-sm hover:bg-gray-50 text-[#1F2A2E]">
              {s.label}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
