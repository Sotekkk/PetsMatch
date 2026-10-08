'use client';

// Espèces prises en charge par un pro (`especes_acceptees`) : menu déroulant
// avec « Toutes les espèces », cases à cocher et saisie libre d'une autre
// espèce. Même liste que le filtre de l'annuaire (ESPECES_PRO,
// lib/annuaire-filtres.ts). Miroir app : lib/widgets/especes_pro_selector.dart.

import { useEffect, useRef, useState } from 'react';
import { ESPECES_PRO } from '@/lib/annuaire-filtres';

interface Props {
  value: string[];
  onChange: (especes: string[]) => void;
}

const estListee = (s: string) => ESPECES_PRO.some(e => e.label === s);

export default function EspecesProSelect({ value, onChange }: Props) {
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState<string[]>(value);
  const [autres, setAutres] = useState<string[]>([]);
  const [saisie, setSaisie] = useState('');
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    setDraft(value);
    setAutres(value.filter(v => !estListee(v)));
    setSaisie('');
  }, [open, value]);

  // Fermer au clic extérieur (sans enregistrer)
  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false); };
    document.addEventListener('mousedown', onDown);
    return () => document.removeEventListener('mousedown', onDown);
  }, [open]);

  const toggle = (s: string) => setDraft(d => d.includes(s) ? d.filter(x => x !== s) : [...d, s]);
  const nbListees = ESPECES_PRO.filter(e => draft.includes(e.label)).length;
  const toutes = nbListees === ESPECES_PRO.length;

  const toggleToutes = () => setDraft(d => toutes
    ? d.filter(x => !estListee(x))
    : [...ESPECES_PRO.map(e => e.label), ...d.filter(x => !estListee(x))]);

  const ajouterAutre = () => {
    const v = saisie.trim();
    if (!v) return;
    const listee = ESPECES_PRO.find(e => e.label.toLowerCase() === v.toLowerCase());
    const cible = listee?.label ?? autres.find(a => a.toLowerCase() === v.toLowerCase()) ?? v;
    if (!listee && !autres.includes(cible)) setAutres(a => [...a, cible]);
    setDraft(d => d.includes(cible) ? d : [...d, cible]);
    setSaisie('');
  };

  const valider = () => {
    onChange([
      ...ESPECES_PRO.map(e => e.label).filter(l => draft.includes(l)),
      ...autres.filter(a => draft.includes(a)),
    ]);
    setOpen(false);
  };

  const autresChoisies = value.filter(v => !estListee(v));
  const resume = value.length === 0
    ? 'Choisir les espèces'
    : ESPECES_PRO.every(e => value.includes(e.label))
      ? ['Toutes les espèces', ...autresChoisies].join(' + ')
      : value.join(', ');

  return (
    <div className="relative" ref={ref}>
      <button type="button" onClick={() => setOpen(o => !o)}
        className={`w-full flex items-center justify-between px-3 py-2.5 rounded-xl border text-sm bg-white transition-colors ${open ? 'border-[#0C5C6C]' : 'border-gray-200 hover:border-gray-300'}`}
        style={{ fontFamily: 'Galey, sans-serif' }}>
        <span className={`truncate text-left ${value.length ? 'text-[#1F2A2E]' : 'text-gray-400'}`}>🐾 {resume}</span>
        <span className={`text-gray-400 text-xs transition-transform flex-shrink-0 ml-2 ${open ? 'rotate-180' : ''}`}>▼</span>
      </button>

      {open && (
        <div className="absolute z-30 left-0 w-full min-w-[18rem] mt-1 bg-white border border-gray-200 rounded-2xl shadow-lg overflow-hidden">
          <div className="max-h-72 overflow-y-auto px-2 py-2">
            <label className="flex items-center gap-3 px-2 py-2 rounded-lg hover:bg-gray-50 cursor-pointer border-b border-gray-100 mb-1">
              <input type="checkbox" checked={toutes}
                ref={el => { if (el) el.indeterminate = nbListees > 0 && !toutes; }}
                onChange={toggleToutes} className="w-4 h-4 accent-[#0C5C6C] flex-shrink-0" />
              <span className="text-sm font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Toutes les espèces</span>
            </label>
            {[...ESPECES_PRO.map(e => ({ label: e.label, detail: e.detail })), ...autres.map(a => ({ label: a, detail: 'Autre espèce' }))].map(e => (
              <label key={e.label} className="flex items-center gap-3 px-2 py-2 rounded-lg hover:bg-gray-50 cursor-pointer">
                <input type="checkbox" checked={draft.includes(e.label)} onChange={() => toggle(e.label)}
                  className="w-4 h-4 accent-[#0C5C6C] flex-shrink-0" />
                <span className="text-sm text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
                  {e.label}
                  {e.detail && <span className="block text-[11px] text-gray-400">{e.detail}</span>}
                </span>
              </label>
            ))}
          </div>
          <div className="flex gap-2 px-3 pb-2">
            <input value={saisie} onChange={e => setSaisie(e.target.value)}
              onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); ajouterAutre(); } }}
              placeholder="Autre espèce (ex : Alpagas)"
              className="flex-1 min-w-0 px-3 py-2 rounded-xl border border-gray-200 text-sm focus:outline-none focus:border-[#0C5C6C]" />
            <button type="button" onClick={ajouterAutre}
              className="px-3 py-2 rounded-xl text-sm font-semibold text-[#0C5C6C] hover:bg-gray-50">
              Ajouter
            </button>
          </div>
          <div className="p-3 border-t border-gray-100">
            <button type="button" onClick={valider}
              className="w-full bg-[#0C5C6C] hover:bg-[#0a4d5b] text-white rounded-xl py-2 text-sm font-semibold"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              Valider
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
