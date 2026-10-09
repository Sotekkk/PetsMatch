'use client';

// Champ compact « Sélectionner un étalon / une reproductrice » :
// liste déroulante avec recherche, sélection unique (lib/reproducteurs).

import { useEffect, useRef, useState } from 'react';
import type { Reproducteur } from '@/lib/reproducteurs';

const GROUPES: Record<Reproducteur['source'], string> = {
  elevage: 'Mon élevage',
  historique: 'Déjà utilisés dans vos saillies',
  reseau: 'Réseau PetsMatch',
};

export default function ReproducteurSelect({ label, options, valeur, detail, vide, onSelect }: {
  label: string;
  options: Reproducteur[];
  valeur?: string | null;
  detail?: string | null;
  vide: string;
  onSelect: (r: Reproducteur) => void;
}) {
  const [ouvert, setOuvert] = useState(false);
  const [q, setQ] = useState('');
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!ouvert) return;
    const fermer = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setOuvert(false); };
    document.addEventListener('mousedown', fermer);
    return () => document.removeEventListener('mousedown', fermer);
  }, [ouvert]);

  const t = q.trim().toLowerCase();
  const liste = options.filter(r => !t || [r.nom, r.race, r.identification].some(v => (v ?? '').toLowerCase().includes(t)));
  const plusieursGroupes = new Set(options.map(r => r.source)).size > 1;

  return (
    <div ref={ref} className="relative">
      <button type="button" onClick={() => setOuvert(o => !o)} aria-haspopup="listbox" aria-expanded={ouvert}
        className="w-full min-h-[44px] flex items-center justify-between gap-2 border border-gray-300 rounded-lg px-3 py-2 text-left bg-white hover:border-gray-400 focus:outline-none focus:border-[#0C5C6C] focus:ring-2 focus:ring-[#0C5C6C]/10">
        <span className="min-w-0">
          {valeur ? (
            <>
              <span className="block text-sm font-semibold text-[#1F2A2E] truncate">{valeur}</span>
              {detail && <span className="block text-xs text-gray-500 truncate">{detail}</span>}
            </>
          ) : <span className="text-sm text-gray-400">{label}</span>}
        </span>
        <svg className={`w-4 h-4 text-gray-400 flex-shrink-0 transition-transform ${ouvert ? 'rotate-180' : ''}`} fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden>
          <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
        </svg>
      </button>
      {ouvert && (
        <div className="absolute z-30 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-lg shadow-lg">
          <div className="p-2 border-b border-gray-100">
            <input type="search" autoFocus value={q} onChange={e => setQ(e.target.value)}
              placeholder="Rechercher par nom, race ou identification"
              className="w-full h-9 border border-gray-200 rounded-md px-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
          </div>
          <ul role="listbox" className="max-h-64 overflow-y-auto py-1">
            {liste.length === 0 ? (
              <li className="px-3 py-4 text-sm text-gray-500 text-center">{options.length === 0 ? vide : 'Aucun résultat.'}</li>
            ) : liste.map((r, i) => (
              <li key={`${r.source}-${r.id ?? r.nom}-${i}`}>
                {plusieursGroupes && (i === 0 || liste[i - 1].source !== r.source) && (
                  <p className="px-3 pt-2 pb-1 text-[11px] font-bold uppercase tracking-wide text-gray-400">{GROUPES[r.source]}</p>
                )}
                <button type="button" role="option" aria-selected={valeur === r.nom}
                  onClick={() => { onSelect(r); setOuvert(false); setQ(''); }}
                  className="w-full text-left px-3 py-2 hover:bg-[#E8F4F6]">
                  <span className="block text-sm font-semibold text-[#1F2A2E]">{r.nom}</span>
                  {(r.race || r.identification) && (
                    <span className="block text-xs text-gray-500">{[r.race, r.identification].filter(Boolean).join(' · ')}</span>
                  )}
                </button>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
