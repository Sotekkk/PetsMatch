'use client';
// Validation d'une tâche de protocole : à la DERNIÈRE prise (vermifuge,
// antiparasitaire, vaccin), date du prochain rappel, posée sur le soin du
// carnet (date_rappel → rappels habituels). Rien pour les autres prises.
// Miroir appli : champRappelDernierePrise (planning_service.dart).
import { useEffect, useState } from 'react';
import { dernieresDuProtocole } from '@/lib/carnet-depuis-tache';

export default function RappelDernierePrise({ tacheIds, value, onChange }: {
  tacheIds: string[]; value: string; onChange: (v: string) => void;
}) {
  const [derniere, setDerniere] = useState(false);
  const cle = tacheIds.join(',');
  useEffect(() => {
    let annule = false;
    dernieresDuProtocole(cle ? cle.split(',') : []).then(s => { if (!annule) setDerniere(s.size > 0); });
    return () => { annule = true; };
  }, [cle]);
  if (!derniere) return null;
  return (
    <label className="block border border-[#0C5C6C]/30 bg-[#0C5C6C]/5 rounded-xl p-3">
      <span className="block text-sm font-semibold text-[#0C5C6C]">Dernière prise du protocole : prochain rappel</span>
      <span className="block text-xs text-gray-500 mb-2">Facultatif. Le rappel est posé sur le soin du carnet (et dans l&apos;agenda).</span>
      <input type="date" value={value} onChange={e => onChange(e.target.value)}
        className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white" />
    </label>
  );
}
