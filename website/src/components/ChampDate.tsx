'use client';

// Date saisie au clavier au format JJ/MM/AAAA (barres ajoutées toutes seules)
// ou choisie au calendrier. Le champ <input type="date"> du navigateur
// laissait des états intermédiaires (date vidée aux flèches, année sur
// 2 chiffres) qui faisaient planter les calculs de rappel.
// value / onChange : AAAA-MM-JJ quand la date est complète et réelle ;
// sinon le texte tel que tapé (refusé à l'enregistrement par erreursDatesSante).

import { useRef, useState } from 'react';
import { dateValide } from '@/lib/controle-dates';

const versTexte = (iso: string) => (dateValide(iso) ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}` : iso);

/** « 12032026 » ou « 12/03/2026 » → « 12/03/2026 » (au fil de la frappe). */
function masque(saisie: string): string {
  const c = saisie.replace(/\D/g, '').slice(0, 8);
  return [c.slice(0, 2), c.slice(2, 4), c.slice(4, 8)].filter(Boolean).join('/');
}

function versIso(texte: string): string {
  const m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(texte);
  if (!m) return texte;
  const iso = `${m[3]}-${m[2]}-${m[1]}`;
  return dateValide(iso) ? iso : texte;
}

export default function ChampDate({ label, value, onChange, required, min, max, aide }: {
  label: string; value: string; onChange: (v: string) => void; required?: boolean;
  min?: string; max?: string;
  /** Petite ligne sous le champ (ex. « calculée d'après la fréquence »). */
  aide?: string;
}) {
  const [texte, setTexte] = useState(versTexte(value));
  const calendrier = useRef<HTMLInputElement>(null);

  // Valeur changée de l'extérieur (rappel recalculé, calendrier) : on l'affiche.
  const [vue, setVue] = useState(value);
  if (vue !== value) {
    setVue(value);
    if (versIso(texte) !== value) setTexte(versTexte(value));
  }

  const saisir = (brut: string) => {
    const t = masque(brut);
    setTexte(t);
    onChange(t ? versIso(t) : '');
  };

  const ouvrirCalendrier = () => {
    const el = calendrier.current;
    if (!el) return;
    try { el.showPicker(); } catch { el.focus(); el.click(); }
  };

  return (
    <div>
      <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">
        {label}{required && <span className="text-red-400 ml-0.5">*</span>}
      </label>
      <div className="relative">
        <input value={texte} onChange={e => saisir(e.target.value)} inputMode="numeric" placeholder="JJ/MM/AAAA" maxLength={10}
          className="w-full border border-gray-200 rounded-xl pl-3 pr-10 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30" />
        <button type="button" onClick={ouvrirCalendrier} aria-label="Choisir dans le calendrier"
          className="absolute right-1 top-1/2 -translate-y-1/2 w-8 h-8 flex items-center justify-center rounded-lg text-gray-400 hover:text-[#0C5C6C] hover:bg-gray-50">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <rect x="3" y="4" width="18" height="18" rx="2" /><path d="M16 2v4M8 2v4M3 10h18" />
          </svg>
        </button>
        <input ref={calendrier} type="date" tabIndex={-1} aria-hidden="true" min={min} max={max}
          value={dateValide(value) ? value : ''}
          onChange={e => { if (dateValide(e.target.value)) { setTexte(versTexte(e.target.value)); onChange(e.target.value); } }}
          className="absolute right-0 bottom-0 w-0 h-0 opacity-0 pointer-events-none" />
      </div>
      {aide && <p className="text-[11px] text-gray-400 mt-1">{aide}</p>}
    </div>
  );
}
