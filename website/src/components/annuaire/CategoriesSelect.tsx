'use client';

// Sélecteur compact « Catégories » de l'annuaire (remplace la grille de
// tuiles). Sélection unique comme avant : une catégorie (re-cliquer la
// désélectionne), puis éventuellement un type de service de cette catégorie.
// Repère coloré = couleur de la catégorie (CATEGORIES_ANNUAIRE.color).

import { useEffect, useRef, useState } from 'react';
import { CATEGORIES_ANNUAIRE, categorieByKey, metierByKey } from '@/lib/annuaire-filtres';

interface Props {
  categorie: string;
  type: string;
  onCategorie: (k: string) => void;
  onType: (k: string) => void;
}

function Radio({ actif }: { actif: boolean }) {
  return (
    <span className={`w-4 h-4 rounded-full border flex items-center justify-center flex-shrink-0 ${actif ? 'border-[#0C5C6C]' : 'border-gray-300'}`} aria-hidden>
      {actif && <span className="w-2 h-2 rounded-full bg-[#0C5C6C]" />}
    </span>
  );
}

export default function CategoriesSelect({ categorie, type, onCategorie, onType }: Props) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const cat = categorieByKey(categorie);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false); };
    document.addEventListener('mousedown', onDown);
    return () => document.removeEventListener('mousedown', onDown);
  }, [open]);

  const resume = !cat ? 'Catégories' : type ? metierByKey(type).label : cat.label;

  return (
    <div className="relative" ref={ref}>
      <button type="button" onClick={() => setOpen(o => !o)} aria-expanded={open}
        className={`w-full h-11 flex items-center gap-2 px-3 rounded-xl border text-sm bg-white transition-colors ${open || cat ? 'border-[#0C5C6C]' : 'border-[#E5E8E6] hover:border-gray-300'}`}>
        {cat && <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ background: cat.color }} />}
        <span className={`flex-1 text-left truncate ${cat ? 'text-[#0C5C6C] font-semibold' : 'text-[#1E2025]'}`}>{resume}</span>
        <svg className={`w-4 h-4 text-gray-400 flex-shrink-0 transition-transform ${open ? 'rotate-180' : ''}`} fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden><path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" /></svg>
      </button>

      {open && (
        <div className="absolute z-30 left-0 mt-1 w-[19rem] max-w-[calc(100vw-2rem)] bg-white border border-[#E5E8E6] rounded-2xl shadow-lg py-1.5 max-h-[60vh] overflow-y-auto" role="listbox">
          <button type="button" onClick={() => { onCategorie(''); setOpen(false); }}
            className="w-full flex items-center gap-3 px-4 py-2.5 text-sm text-left hover:bg-gray-50" role="option" aria-selected={!cat}>
            <Radio actif={!cat} />
            <span className="w-2.5 h-2.5 rounded-full flex-shrink-0 border border-gray-300" />
            <span className="flex-1 text-[#1E2025]">Toutes les catégories</span>
          </button>
          {CATEGORIES_ANNUAIRE.map(c => {
            const actif = c.key === categorie;
            return (
              <div key={c.key} className="border-t border-[#F1F2F1]">
                <button type="button" onClick={() => { onCategorie(c.key); if (actif || c.types.length === 0) setOpen(false); }}
                  className="w-full flex items-center gap-3 px-4 py-2.5 text-sm text-left hover:bg-gray-50" role="option" aria-selected={actif}>
                  <Radio actif={actif} />
                  <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ background: c.color }} />
                  <span className={`flex-1 ${actif ? 'font-semibold text-[#0C5C6C]' : 'text-[#1E2025]'}`}>{c.label}</span>
                </button>
                {/* Types de service de la catégorie choisie */}
                {actif && c.types.length > 0 && (
                  <div className="pb-1.5">
                    {[{ key: '', label: 'Tous les services' }, ...c.types.map(t => ({ key: t, label: metierByKey(t).label }))].map(t => (
                      <button key={t.key || 'tous'} type="button" onClick={() => { onType(t.key); setOpen(false); }}
                        className="w-full flex items-center gap-3 pl-11 pr-4 py-2 text-[13px] text-left hover:bg-gray-50">
                        <Radio actif={t.key === type} />
                        <span className={t.key === type ? 'font-semibold text-[#0C5C6C]' : 'text-[#374151]'}>{t.label}</span>
                      </button>
                    ))}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
