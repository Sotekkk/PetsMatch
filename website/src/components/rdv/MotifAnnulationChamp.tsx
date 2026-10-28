'use client';

import { useState } from 'react';

// Motif obligatoire pour refuser ou annuler un RDV : liste + « Autre » à
// préciser. Miroir appli : MotifAnnulationField (lib/widgets/rdv/motif_annulation.dart).
export const MOTIFS_ANNULATION = [
  'Aucune disponibilité à ce créneau',
  'Empêchement ou urgence de ma part',
  'Fermeture exceptionnelle',
  'À la demande du client',
  'Hors de ma spécialité / espèce non prise en charge',
  'Hors de mon secteur d’intervention',
  'Autre',
];

/** [onChange] reçoit le motif complet, ou '' tant qu'il n'est pas choisi / précisé. */
export default function MotifAnnulationChamp({ onChange }: { onChange: (motif: string) => void }) {
  const [choix, setChoix] = useState('');
  const [autre, setAutre] = useState('');
  const maj = (c: string, a: string) => { setChoix(c); setAutre(a); onChange(c === 'Autre' ? a.trim() : c); };
  return (
    <div className="space-y-2" style={{ fontFamily: 'Galey, sans-serif' }}>
      <label className="text-xs font-semibold text-gray-500 block">Motif *</label>
      <select value={choix} onChange={e => maj(e.target.value, autre)}
        className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm bg-white focus:outline-none">
        <option value="">Choisir un motif…</option>
        {MOTIFS_ANNULATION.map(m => <option key={m} value={m}>{m}</option>)}
      </select>
      {choix === 'Autre' && (
        <textarea value={autre} onChange={e => maj('Autre', e.target.value)} rows={2} autoFocus placeholder="Précisez le motif…"
          className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none focus:outline-none" />
      )}
    </div>
  );
}
