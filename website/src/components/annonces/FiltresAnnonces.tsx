'use client';
// Filtres compacts de « Mes annonces » : type (Toutes / Animaux / Matériel &
// équipements) et statut, en listes déroulantes (pas de rangées d'étiquettes).
import { FILTRES_TYPE, type TypeAnnonceFiltre } from '@/lib/annonces-droits';

const cls = 'border border-[#E5E8E6] rounded-xl pl-3 pr-8 py-2 text-sm bg-white text-[#1E2025] focus:outline-none focus:border-[#0C5C6C]';

export default function FiltresAnnonces({ type, onType, statut, onStatut, statuts }: {
  type: TypeAnnonceFiltre; onType: (t: TypeAnnonceFiltre) => void;
  statut: string; onStatut: (s: string) => void; statuts: { k: string; label: string }[];
}) {
  return (
    <div className="flex flex-col sm:flex-row gap-2 sm:items-center mb-5">
      <label className="flex items-center gap-2 text-sm text-gray-600">
        <span className="w-14 sm:w-auto">Type</span>
        <select value={type} onChange={e => onType(e.target.value as TypeAnnonceFiltre)} className={`${cls} flex-1 sm:flex-none`}>
          {FILTRES_TYPE.map(f => <option key={f.k} value={f.k}>{f.label}</option>)}
        </select>
      </label>
      <label className="flex items-center gap-2 text-sm text-gray-600 sm:ml-2">
        <span className="w-14 sm:w-auto">Statut</span>
        <select value={statut} onChange={e => onStatut(e.target.value)} className={`${cls} flex-1 sm:flex-none`}>
          {statuts.map(s => <option key={s.k} value={s.k}>{s.label}</option>)}
        </select>
      </label>
    </div>
  );
}
