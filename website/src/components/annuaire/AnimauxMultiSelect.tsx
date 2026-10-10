'use client';

// Menu déroulant « Animaux pris en charge » : cases à cocher (plusieurs choix),
// liste défilante, boutons Réinitialiser / Appliquer. La sélection n'est prise
// en compte qu'à « Appliquer ». Miroir app : AnimauxMultiSelectField
// (lib/widgets/annuaire_filtres_widgets.dart).

import { useEffect, useRef, useState } from 'react';
import { GROUPES_ESPECES } from '@/lib/annuaire-filtres';

interface Props {
  value: string[];
  onApply: (keys: string[]) => void;
}

export default function AnimauxMultiSelect({ value, onApply }: Props) {
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState<string[]>(value);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => { if (open) setDraft(value); }, [open, value]);

  // Fermer au clic extérieur (sans appliquer)
  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false); };
    document.addEventListener('mousedown', onDown);
    return () => document.removeEventListener('mousedown', onDown);
  }, [open]);

  const toggle = (k: string) => setDraft(d => d.includes(k) ? d.filter(x => x !== k) : [...d, k]);
  const resume = value.length === 0
    ? 'Toutes les espèces'
    : value.length === 1
      ? GROUPES_ESPECES.find(g => g.key === value[0])?.label ?? '1 sélectionnée'
      : `${value.length} sélectionnés`;

  return (
    <div className="relative" ref={ref}>
      <button type="button" onClick={() => setOpen(o => !o)}
        className={`w-full h-11 flex items-center justify-between gap-2 px-3 rounded-xl border text-sm bg-white transition-colors ${open || value.length ? 'border-[#0C5C6C]' : 'border-[#E5E8E6] hover:border-gray-300'}`}
        style={{ fontFamily: 'Galey, sans-serif' }} aria-expanded={open}>
        <span className="truncate text-left">
          {value.length
            ? <strong className="text-[#0C5C6C] font-semibold">{resume}</strong>
            : <span className="text-[#1E2025]"><span className="md:hidden">Animaux</span><span className="hidden md:inline">Animaux : toutes les espèces</span></span>}
        </span>
        <svg className={`w-4 h-4 text-gray-400 flex-shrink-0 transition-transform ${open ? 'rotate-180' : ''}`} fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden><path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" /></svg>
      </button>

      {open && (
        <div className="absolute z-30 left-0 sm:left-auto sm:right-auto min-w-full w-72 max-w-[calc(100vw-2rem)] mt-1 bg-white border border-[#E5E8E6] rounded-2xl shadow-lg overflow-hidden">
          <div className="px-4 pt-3 pb-1">
            <p className="text-sm font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Animaux pris en charge</p>
            <p className="text-[11px] text-gray-400">Plusieurs choix possibles</p>
          </div>
          <div className="max-h-56 overflow-y-auto px-2 py-1">
            {GROUPES_ESPECES.map(g => (
              <label key={g.key} className="flex items-center gap-3 px-2 py-2 rounded-lg hover:bg-gray-50 cursor-pointer">
                <input type="checkbox" checked={draft.includes(g.key)} onChange={() => toggle(g.key)}
                  className="w-4 h-4 accent-[#0C5C6C] flex-shrink-0" />
                <span className="text-sm text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
                  {g.label}
                  {g.detail && <span className="block text-[11px] text-gray-400">{g.detail}</span>}
                </span>
              </label>
            ))}
          </div>
          <div className="flex gap-2 p-3 border-t border-gray-100">
            <button type="button" onClick={() => setDraft([])}
              className="flex-1 border border-gray-200 text-gray-600 rounded-xl py-2 text-sm font-semibold hover:bg-gray-50"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              Réinitialiser
            </button>
            <button type="button" onClick={() => { onApply(draft); setOpen(false); }}
              className="flex-1 bg-[#0C5C6C] hover:bg-[#0a4d5b] text-white rounded-xl py-2 text-sm font-semibold"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              Appliquer
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
