'use client';

import { useState } from 'react';

// Espèces proposées au particulier (espèces possédées et projet d'adoption) —
// codes enregistrés dans user_profiles.especes_possedees / especes_projet.
// Miroir appli : lib/widgets/choix_especes_pastilles.dart.
export const ESPECES_PARTICULIER: [string, string][] = [
  ['chien', 'Chien'], ['chat', 'Chat'], ['lapin', 'Lapin'], ['cheval', 'Cheval'],
  ['oiseau', 'Oiseau'], ['nac', 'NAC'], ['reptile', 'Reptile'], ['autre', 'Autre'],
];

/** Choix d'espèces à cocher : une fois validé, le champ n'affiche plus que les
 *  espèces retenues (pastilles) ; un clic rouvre la liste (« Tout cocher » en
 *  tête) à valider. */
export default function ChoixEspecesPastilles({ selection, onChange, titre = 'Choisir les espèces', especes = ESPECES_PARTICULIER }: {
  selection: string[];
  onChange: (v: string[]) => void;
  titre?: string;
  especes?: [string, string][];
}) {
  const [ouvert, setOuvert] = useState(false);
  const [choix, setChoix] = useState<string[]>([]);
  const retenues = especes.filter(([k]) => selection.includes(k));
  const tout = especes.every(([k]) => choix.includes(k));

  function ouvrir() { setChoix(selection); setOuvert(true); }
  function valider() { onChange(especes.map(([k]) => k).filter(k => choix.includes(k))); setOuvert(false); }

  if (ouvert) {
    return (
      <div className="border border-gray-200 rounded-xl bg-white">
        <p className="px-3 pt-2.5 pb-1 text-sm font-bold text-[#1F2A2E]">{titre}</p>
        <label className="flex items-center gap-3 px-3 py-2 text-sm font-semibold cursor-pointer hover:bg-gray-50">
          <input type="checkbox" className="w-4 h-4 accent-[#6E9E57]" checked={tout}
            onChange={e => setChoix(e.target.checked ? especes.map(([k]) => k) : [])} />
          Tout cocher
        </label>
        <div className="border-t border-gray-100 my-1" />
        {especes.map(([k, l]) => (
          <label key={k} className="flex items-center gap-3 px-3 py-2 text-sm cursor-pointer hover:bg-gray-50">
            <input type="checkbox" className="w-4 h-4 accent-[#6E9E57]" checked={choix.includes(k)}
              onChange={() => setChoix(c => c.includes(k) ? c.filter(x => x !== k) : [...c, k])} />
            {l}
          </label>
        ))}
        <div className="p-3 pt-2">
          <button type="button" onClick={valider}
            className="w-full py-2.5 rounded-xl bg-[#0C5C6C] text-white text-sm font-semibold hover:bg-[#094F5D]">Valider</button>
        </div>
      </div>
    );
  }

  return (
    <button type="button" onClick={ouvrir}
      className="w-full flex items-center gap-2 border border-gray-200 rounded-xl bg-white px-3 py-2.5 text-left">
      <span className="flex-1 flex flex-wrap gap-1.5">
        {retenues.length === 0
          ? <span className="text-sm text-gray-400">{titre}</span>
          : retenues.map(([k, l]) => (
              <span key={k} className="text-xs font-semibold text-[#0C5C6C] bg-[#0C5C6C]/10 rounded-full px-2.5 py-1">{l}</span>
            ))}
      </span>
      {retenues.length > 0 && <span className="text-xs font-semibold text-[#0C5C6C]">Modifier</span>}
      <svg className="w-4 h-4 text-gray-400 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden>
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
      </svg>
    </button>
  );
}
