'use client';

// Chiffre d'affaires du mois et de l'année, en tête de la page Facturation
// (tous les pros qui ont la facturation). Miroir appli :
// lib/widgets/chiffre_affaires_card.dart.
import { useMemo, useState } from 'react';
import { resumeCA, MOIS_COURTS, euros, type FactureCA } from '@/lib/chiffre-affaires';

export default function ChiffreAffaires({ factures }: { factures: FactureCA[] }) {
  const maintenant = new Date();
  const [an, setAn] = useState(maintenant.getFullYear());
  const [detail, setDetail] = useState(false);
  const r = useMemo(() => resumeCA(factures, an), [factures, an]);
  const anCourant = an === maintenant.getFullYear();
  const moisCourant = anCourant ? r.mois[maintenant.getMonth()] : null;
  const max = Math.max(1, ...r.mois.map(x => Math.max(x.ttc, x.encaisse)));
  const evolution = r.ttcAnneePrec > 0 ? Math.round(((r.ttc - r.ttcAnneePrec) / r.ttcAnneePrec) * 100) : null;

  const tuile = (titre: string, valeur: string, sous?: string) => (
    <div className="bg-[#F7FAF8] rounded-xl px-3 py-2.5 min-w-0">
      <p className="text-[11px] font-semibold text-gray-500 uppercase tracking-wide">{titre}</p>
      <p className="text-lg font-extrabold text-[#1F2A2E] truncate">{valeur}</p>
      {sous && <p className="text-[11px] text-gray-500 truncate">{sous}</p>}
    </div>
  );

  return (
    <section className="bg-white rounded-2xl border border-gray-100 shadow-sm p-4 mb-6" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="flex items-center justify-between gap-2 mb-3">
        <h2 className="font-extrabold text-[#0C5C6C]">Chiffre d&apos;affaires</h2>
        <div className="flex items-center gap-1 text-sm">
          <button onClick={() => setAn(a => a - 1)} className="px-2 py-1 rounded-lg hover:bg-gray-100 text-gray-600" aria-label="Année précédente">‹</button>
          <span className="font-bold text-[#1F2A2E] w-12 text-center">{an}</span>
          <button onClick={() => setAn(a => a + 1)} disabled={anCourant} className="px-2 py-1 rounded-lg hover:bg-gray-100 text-gray-600 disabled:opacity-30" aria-label="Année suivante">›</button>
        </div>
      </div>
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
        {tuile(moisCourant ? `${MOIS_COURTS[maintenant.getMonth()]} (mois)` : 'Mois en cours',
          moisCourant ? euros(moisCourant.ttc) : '—', moisCourant ? `${euros(moisCourant.ht)} HT · ${moisCourant.nb} facture${moisCourant.nb > 1 ? 's' : ''}` : undefined)}
        {tuile(`Année ${an}`, euros(r.ttc),
          `${euros(r.ht)} HT${evolution != null ? ` · ${evolution >= 0 ? '+' : ''}${evolution} % vs ${an - 1}` : ''}`)}
        {tuile('Encaissé', euros(r.encaisse), `en ${an}`)}
        {tuile('À encaisser', euros(r.aEncaisser), 'factures émises non payées')}
      </div>
      <button onClick={() => setDetail(d => !d)} className="mt-3 text-sm font-semibold text-[#0C5C6C] hover:underline">
        {detail ? 'Masquer le détail par mois' : 'Voir le détail par mois'}
      </button>
      {detail && (
        <div className="mt-2 space-y-1.5">
          <div className="flex items-center gap-3 text-[11px] text-gray-500">
            <span className="flex items-center gap-1"><span className="w-3 h-2 rounded-sm bg-[#0C5C6C] inline-block" /> Facturé TTC</span>
            <span className="flex items-center gap-1"><span className="w-3 h-2 rounded-sm bg-[#6E9E57] inline-block" /> Encaissé</span>
          </div>
          {r.mois.map((x, i) => (
            <div key={i} className="grid grid-cols-[3rem_1fr_6.5rem] items-center gap-2 text-sm">
              <span className="text-gray-600">{MOIS_COURTS[i]}</span>
              <div className="space-y-0.5">
                <div className="h-2 rounded-full bg-[#0C5C6C]" style={{ width: `${Math.max(0, (x.ttc / max) * 100)}%` }} />
                <div className="h-2 rounded-full bg-[#6E9E57]" style={{ width: `${Math.max(0, (x.encaisse / max) * 100)}%` }} />
              </div>
              <span className="text-right tabular-nums">
                <span className="font-semibold text-[#1F2A2E]">{euros(x.ttc)}</span>
                <span className="block text-[11px] text-gray-500">{euros(x.encaisse)} encaissé</span>
              </span>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}
