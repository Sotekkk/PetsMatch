'use client';

// En-tête commun de « Trouver un animal » : onglets Animaux / Élevages /
// Associations et modes d'affichage disponibles pour l'onglet (Liste / Fil /
// Carte). Les filtres compatibles passent d'une vue à l'autre par l'URL.
// Miroir appli : TrouverAnimalPage + SelecteurModes (trouver_animal_page.dart).

import Link from 'next/link';
import { Icone } from '@/components/dashboard/kit';
import { paramsAnimaux, type FiltresAnimaux } from '@/lib/trouver-animal';

type Onglet = 'animaux' | 'elevages' | 'associations';
type Mode = 'liste' | 'fil' | 'carte';

export default function TrouverAnimalNav({ onglet, mode, filtres, compteur, onMode }: {
  onglet: Onglet;
  mode: Mode;
  /** Onglet Animaux : filtres en cours, repris par Fil et Carte. */
  filtres?: FiltresAnimaux;
  compteur?: string;
  /** Élevages / Associations : Liste / Carte basculent sur la même page. */
  onMode?: (m: Mode) => void;
}) {
  const qs = filtres ? paramsAnimaux(filtres) : '';
  const onglets: { v: Onglet; l: string; href: string }[] = [
    { v: 'animaux', l: 'Animaux', href: `/annonces${qs ? `?${qs}` : ''}` },
    { v: 'elevages', l: 'Élevages', href: '/elevages' },
    { v: 'associations', l: 'Associations', href: '/associations' },
  ];
  const modes: { v: Mode; l: string; icone: string; href?: string }[] =
    onglet === 'animaux' ? [
      { v: 'liste', l: 'Liste', icone: 'document', href: `/annonces?${qs}` },
      { v: 'fil', l: 'Fil', icone: 'lecture', href: `/annonces/feed?${qs}&demarrer=1` },
      { v: 'carte', l: 'Carte', icone: 'pin', href: `/annonces/carte?${qs}` },
    ]
    : [
      { v: 'liste', l: 'Liste', icone: 'document' },
      { v: 'carte', l: 'Carte', icone: 'pin' },
    ];

  const classeMode = (actif: boolean) =>
    `inline-flex items-center gap-1.5 h-9 px-3.5 rounded-lg text-sm font-semibold transition-colors ${
      actif ? 'bg-[#0C5C6C] text-white' : 'text-gray-600 hover:text-[#1F2A2E]'}`;

  return (
    <div className="mb-6">
      <div className="flex flex-wrap items-end justify-between gap-3 mb-4">
        <div>
          <h1 className="text-2xl sm:text-3xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Trouver un animal</h1>
          {compteur && <p className="text-gray-500 text-sm mt-0.5">{compteur}</p>}
        </div>
        {modes.length > 1 && (
          <div role="group" aria-label="Affichage" className="inline-flex p-1 bg-white border border-gray-200 rounded-xl">
            {modes.map(m => m.href && !onMode
              ? <Link key={m.v} href={m.href} aria-current={mode === m.v ? 'page' : undefined} className={classeMode(mode === m.v)}>
                  <Icone nom={m.icone} taille={16} /> {m.l}
                </Link>
              : <button key={m.v} type="button" onClick={() => onMode?.(m.v)} aria-pressed={mode === m.v} className={classeMode(mode === m.v)}>
                  <Icone nom={m.icone} taille={16} /> {m.l}
                </button>)}
          </div>
        )}
      </div>
      <nav aria-label="Rubriques" className="flex gap-1 border-b border-gray-200 overflow-x-auto">
        {onglets.map(o => (
          <Link key={o.v} href={o.href} aria-current={onglet === o.v ? 'page' : undefined}
            className={`-mb-px px-4 sm:px-6 py-3 text-[15px] whitespace-nowrap border-b-2 transition-colors ${
              onglet === o.v ? 'border-[#0C5C6C] text-[#0C5C6C] font-semibold' : 'border-transparent text-gray-600 hover:text-[#1F2A2E]'}`}>
            {o.l}
          </Link>
        ))}
      </nav>
    </div>
  );
}
