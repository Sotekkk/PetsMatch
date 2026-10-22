'use client';
// Bloc « Souhaitez-vous booster votre annonce ? », juste avant de publier.
// « Publier sans boost » est sélectionné par défaut ; offres et prix réels
// (produits_ponctuels). Utilisé pour le matériel & équipements ; le même bloc
// figure dans la création d'une annonce d'animal (app/annonces/creer).

import { useEffect, useState } from 'react';
import { chargerOffresBoost, dureeOffre, prixOffre, type OffreBoost } from '@/lib/boost-offres';

export function useOffresBoost() {
  const [offres, setOffres] = useState<OffreBoost[]>([]);
  useEffect(() => { chargerOffresBoost().then(setOffres); }, []);
  return offres;
}

export default function ChoixBoost({ offres, choix, onChoix, paiementAnnule }: {
  offres: OffreBoost[]; choix: string; onChoix: (code: string) => void; paiementAnnule?: boolean;
}) {
  if (offres.length === 0) return null;
  const options: OffreBoost[] = [
    { code: '', label: 'Publier sans boost', prix: 0, duree_heures: null,
      description: 'Votre annonce est publiée normalement. Vous pourrez la booster plus tard depuis « Mes annonces ».' },
    ...offres,
  ];
  return (
    <div className="space-y-2">
      {paiementAnnule && (
        <p role="status" className="rounded-xl px-3.5 py-2.5 text-sm text-[#92400E] bg-[#FFFBEB] border border-[#FDE68A]">
          Paiement annulé : votre annonce est conservée avec toutes ses informations et photos, sans être publiée. Vous pouvez réessayer ou publier sans boost.
        </p>
      )}
      {options.map(o => {
        const actif = choix === o.code;
        return (
          <label key={o.code || 'sans'} className={`flex items-start gap-3 rounded-xl border p-3.5 cursor-pointer transition-colors ${actif ? 'border-[#0C5C6C] bg-[#E8F4F6]' : 'border-[#E5E8E6] bg-white hover:border-gray-300'}`}>
            <input type="radio" name="choix-boost" value={o.code} checked={actif} onChange={() => onChoix(o.code)} className="mt-1 accent-[#0C5C6C]" />
            <span className="flex-1 min-w-0">
              <span className="flex items-baseline justify-between gap-3">
                <span className="text-[15px] font-semibold text-[#1E2025]">{o.label}</span>
                {o.code && <span className="text-[15px] font-bold text-[#1E2025] tabular-nums whitespace-nowrap">{prixOffre(o.prix)}</span>}
              </span>
              {o.code && <span className="block text-xs text-gray-600">{dureeOffre(o.duree_heures)} de mise en avant · prix total, paiement unique</span>}
              {o.description && <span className="block text-xs text-gray-500 mt-0.5">{o.description}</span>}
            </span>
          </label>
        );
      })}
    </div>
  );
}
