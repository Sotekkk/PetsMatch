'use client';

// Mon profil (vétérinaire) : consignes avant une intervention, une par
// sous-type (détartrage, stérilisation…). Reprises à la prise d'un RDV
// « Intervention » (modifiables pour ce RDV), envoyées au propriétaire et
// rappelées la veille. Miroir appli : section du profil vétérinaire.
import { useEffect, useState } from 'react';
import { SOUS_TYPES_INTERVENTION, consignesPreopDefaut, enregistrerConsignesPreop } from '@/lib/intervention';

export default function ConsignesPreopCard({ profileId }: { profileId: string }) {
  const [textes, setTextes] = useState<Record<string, string>>({});
  const [ouvert, setOuvert] = useState<string>('detartrage');
  const [etat, setEtat] = useState<'' | 'enregistrement' | 'ok' | 'erreur'>('');

  useEffect(() => { consignesPreopDefaut(profileId).then(setTextes).catch(() => {}); }, [profileId]);

  async function enregistrer() {
    setEtat('enregistrement');
    setEtat(await enregistrerConsignesPreop(profileId, textes) ? 'ok' : 'erreur');
  }

  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-5 mb-4">
      <h2 className="font-bold text-[#1F2A2E] text-sm mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>Consignes avant une intervention</h2>
      <p className="text-xs text-gray-400 mb-3">Envoyées au propriétaire à la prise d&apos;un RDV « Intervention » et rappelées la veille. Modifiables pour chaque RDV.</p>
      <div className="flex flex-wrap gap-1.5 mb-3">
        {SOUS_TYPES_INTERVENTION.map(t => (
          <button key={t.key} type="button" onClick={() => setOuvert(t.key)}
            className="px-3 py-1.5 rounded-full text-xs font-semibold border"
            style={ouvert === t.key ? { background: '#0C5C6C', borderColor: '#0C5C6C', color: 'white' } : { borderColor: '#D1D5DB', color: '#374151' }}>
            {t.label}
          </button>
        ))}
      </div>
      <textarea value={textes[ouvert] ?? ''} rows={5}
        onChange={e => { setTextes(prev => ({ ...prev, [ouvert]: e.target.value })); setEtat(''); }}
        className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
      <div className="flex items-center gap-3 mt-2">
        <button type="button" onClick={enregistrer} disabled={etat === 'enregistrement'}
          className="px-4 py-2 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ background: '#0C5C6C' }}>
          {etat === 'enregistrement' ? 'Enregistrement…' : 'Enregistrer les consignes'}
        </button>
        {etat === 'ok' && <span className="text-xs font-semibold text-[#2E7D5E]">Enregistré</span>}
        {etat === 'erreur' && <span className="text-xs font-semibold text-red-500">Non enregistré, réessayez</span>}
      </div>
    </div>
  );
}
