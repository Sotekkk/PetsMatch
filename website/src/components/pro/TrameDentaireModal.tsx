'use client';

// Trame dentaire (CR opératoire) : actes cochés et dents extraites (Triadan).
import { useState } from 'react';
import { ACTES_DENTAIRES, QUADRANTS, dentsTriadan, ligneDentaire, lireLigneDentaire, type EspeceDentaire } from '@/lib/trame-dentaire';

const TEAL = '#0C5C6C';

export default function TrameDentaireModal({ especeInitiale, gestes, onValider, onClose }: {
  especeInitiale: EspeceDentaire; gestes: string;
  onValider: (ligne: string) => void; onClose: () => void;
}) {
  const depart = lireLigneDentaire(gestes);
  const [espece, setEspece] = useState<EspeceDentaire>(especeInitiale);
  const [actes, setActes] = useState<string[]>(depart.actes.length || depart.extractions.length ? depart.actes : ['Détartrage ultrasonique', 'Polissage']);
  const [ext, setExt] = useState<number[]>(depart.extractions);
  const dents = dentsTriadan(espece);
  const basculer = <T,>(l: T[], v: T) => l.includes(v) ? l.filter(x => x !== v) : [...l, v];
  const apercu = ligneDentaire(actes, ext.filter(n => Object.values(dents).flat().includes(n)));

  return (
    <div className="fixed inset-0 z-[80] flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-2xl sm:rounded-2xl w-full max-w-xl max-h-[90vh] overflow-y-auto p-5 space-y-4" onClick={e => e.stopPropagation()}
        style={{ fontFamily: 'Galey, sans-serif' }}>
        <div className="flex items-center gap-2">
          <h3 className="flex-1 font-bold text-lg text-[#1F2A2E]">Schéma dentaire</h3>
          {(['chien', 'chat'] as EspeceDentaire[]).map(e => (
            <button key={e} type="button" onClick={() => setEspece(e)} className="px-3 py-1 rounded-full text-xs font-semibold border"
              style={espece === e ? { background: TEAL, borderColor: TEAL, color: 'white' } : { borderColor: '#D1D5DB', color: '#374151' }}>
              {e === 'chien' ? 'Chien' : 'Chat'}
            </button>
          ))}
        </div>
        <div>
          <p className="text-xs font-semibold text-gray-500 mb-1.5">Actes</p>
          <div className="flex flex-wrap gap-1.5">
            {ACTES_DENTAIRES.map(a => (
              <label key={a} className="flex items-center gap-1.5 text-sm px-2.5 py-1.5 rounded-lg border border-gray-200 cursor-pointer">
                <input type="checkbox" checked={actes.includes(a)} onChange={() => setActes(l => basculer(l, a))} style={{ accentColor: TEAL }} />{a}
              </label>
            ))}
          </div>
        </div>
        <div>
          <p className="text-xs font-semibold text-gray-500 mb-1.5">Dents extraites (touchez une dent)</p>
          <div className="grid sm:grid-cols-2 gap-3">
            {QUADRANTS.map(({ q, label }) => (
              <div key={q}>
                <p className="text-[11px] text-gray-500 mb-1">{label}</p>
                <div className="flex flex-wrap gap-1">
                  {dents[q].map(n => {
                    const x = ext.includes(n);
                    return (
                      <button key={n} type="button" onClick={() => setExt(l => basculer(l, n))}
                        className="w-10 py-1 rounded-md text-xs font-semibold border"
                        style={x ? { background: '#B91C1C', borderColor: '#B91C1C', color: 'white' } : { borderColor: '#D1D5DB', color: '#1F2A2E' }}>
                        {n}
                      </button>
                    );
                  })}
                </div>
              </div>
            ))}
          </div>
        </div>
        <p className="text-xs rounded-lg bg-[#F1F7F8] px-3 py-2 text-[#1F2A2E]">{apercu || 'Aucun soin dentaire sélectionné.'}</p>
        <div className="flex gap-2 justify-end">
          <button type="button" onClick={onClose} className="px-4 py-2 rounded-xl border text-sm font-semibold text-gray-600 border-gray-200">Annuler</button>
          <button type="button" onClick={() => onValider(apercu)} className="px-4 py-2 rounded-xl text-sm font-semibold text-white" style={{ background: TEAL }}>
            Reporter dans les gestes réalisés
          </button>
        </div>
      </div>
    </div>
  );
}
