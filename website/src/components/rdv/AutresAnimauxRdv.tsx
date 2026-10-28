'use client';

import { AnimalMultiPickerField, type PickableAnimal } from '@/components/AnimalPickerField';

// Autres animaux sur le même RDV (vétérinaire, ostéo, toiletteur, éducateur) :
// chacun avec son motif et sa durée ; le créneau couvre la somme des durées
// (rdv.animaux_ids + rdv.animaux_detail). « Toute la portée » dans le
// sélecteur pour un éleveur. Miroir appli : _buildAutresAnimaux
// (lib/pages/pro/rdv_booking_page.dart).

export interface OptionMotifAnimal { key: string; label: string; duree: number }

export function fmtDureeRdv(min: number) {
  return min < 60 ? `${min} min` : `${Math.floor(min / 60)}h${min % 60 ? String(min % 60).padStart(2, '0') : ''}`;
}

export default function AutresAnimauxRdv({ animaux, principalId, selectedIds, onChange, options, motifDe, onMotif, dureeTotale, accentColor }: {
  animaux: PickableAnimal[];
  principalId: number | string;
  selectedIds: (number | string)[];
  onChange: (ids: (number | string)[]) => void;
  options: OptionMotifAnimal[];
  /** Motif retenu pour l'animal (celui de l'animal principal par défaut). */
  motifDe: (id: number | string) => OptionMotifAnimal | undefined;
  onMotif: (id: number | string, key: string) => void;
  dureeTotale: number;
  accentColor: string;
}) {
  const autres = animaux.filter(a => a.id !== principalId);
  if (autres.length === 0) return null;
  const enPlus = selectedIds.filter(id => id !== principalId);
  return (
    <div className="mt-2.5 space-y-2" style={{ fontFamily: 'Galey, sans-serif' }}>
      {enPlus.map(id => {
        const a = animaux.find(x => x.id === id);
        if (!a) return null;
        const o = motifDe(id);
        return (
          <div key={id} className="flex items-center gap-2.5 rounded-xl border border-[#E4E7E2] bg-white pl-3 pr-1 py-1.5">
            <span className="flex-1 min-w-0">
              <span className="block text-[13.5px] font-bold text-[#1E2025] truncate">{a.nom}</span>
              {options.length > 0 && (
                <select value={o?.key ?? ''} onChange={e => onMotif(id, e.target.value)} aria-label={`Motif pour ${a.nom}`}
                  className="w-full text-[12.5px] font-semibold bg-transparent focus:outline-none" style={{ color: accentColor }}>
                  {options.map(op => <option key={op.key} value={op.key}>{op.label} · {fmtDureeRdv(op.duree)}</option>)}
                </select>
              )}
            </span>
            <button type="button" onClick={() => onChange(selectedIds.filter(x => x !== id))}
              className="px-2 py-1 text-gray-400 hover:text-gray-600" aria-label={`Retirer ${a.nom}`}>✕</button>
          </div>
        );
      })}
      <AnimalMultiPickerField animaux={autres} selectedIds={enPlus} onChange={onChange} accentColor={accentColor}
        placeholder="Ajouter un autre animal (même rendez-vous)" />
      {enPlus.length > 0 && (
        <p className="text-xs font-semibold" style={{ color: accentColor }}>
          {enPlus.length + 1} animaux · durée totale {fmtDureeRdv(dureeTotale)}
        </p>
      )}
    </div>
  );
}
