'use client';

// Rubrique du carnet de santé : une ligne sobre (pastille de couleur, nom,
// nombre d'enregistrements, « + Ajouter » de la même couleur, chevron).
// À placer dans un HealthPanel (panneau blanc unique, lignes séparées par
// des traits fins). La couleur est fonctionnelle (cf. lib/sante-couleurs).

import { useState, ReactNode } from 'react';

interface Props {
  title: string;
  /** Conservé pour compatibilité ; plus affiché (présentation sans emojis). */
  icon?: string;
  color: string;
  count: number;
  children: ReactNode;
  onAdd?: () => void;
  addForm?: ReactNode;
  addFormOpen?: boolean;
  id?: string;
  defaultOpen?: boolean;
}

/** Panneau blanc unique regroupant les rubriques. */
export function HealthPanel({ children }: { children: ReactNode }) {
  return (
    <div className="bg-white border border-gray-200 rounded-xl divide-y divide-gray-200 overflow-hidden">
      {children}
    </div>
  );
}

export default function HealthSection({ title, color, count, children, onAdd, addForm, addFormOpen, id, defaultOpen }: Props) {
  const [open, setOpen] = useState(!!defaultOpen);

  return (
    <section id={id} className={defaultOpen ? 'bg-gray-50/60' : undefined}>
      <div className="flex items-center gap-3 pl-4 pr-2 min-h-[64px]">
        <button type="button" onClick={() => setOpen(!open)} aria-expanded={open}
          className="flex-1 min-w-0 flex items-center gap-3 py-3 text-left">
          <span className="w-3 h-3 rounded-full flex-shrink-0" style={{ backgroundColor: color }} aria-hidden />
          <span className="min-w-0">
            <span className="block font-semibold text-[#1F2A2E] text-[15px] truncate" style={{ fontFamily: 'Galey, sans-serif' }}>{title}</span>
            <span className="block text-xs text-gray-500">{count} enregistrement{count > 1 ? 's' : ''}</span>
          </span>
        </button>
        {onAdd && (
          <button type="button"
            onClick={(e) => { e.stopPropagation(); onAdd(); }}
            className="h-10 px-3 rounded-lg text-sm font-semibold whitespace-nowrap hover:bg-gray-50 transition-colors"
            style={{ color }}>
            + Ajouter
          </button>
        )}
        <button type="button" onClick={() => setOpen(!open)} aria-label={open ? 'Replier' : 'Déplier'}
          className="w-10 h-10 flex items-center justify-center rounded-lg text-gray-400 hover:bg-gray-50">
          <svg className={`w-4 h-4 transition-transform ${open ? 'rotate-180' : ''}`} fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
          </svg>
        </button>
      </div>

      {/* « + Ajouter » affiche le formulaire sans déplier la liste */}
      {addFormOpen && addForm && (
        <div className="px-4 py-4 border-t border-gray-100 bg-gray-50">{addForm}</div>
      )}
      {open && (
        <div className="border-t border-gray-100 divide-y divide-gray-100">{children}</div>
      )}
    </section>
  );
}
