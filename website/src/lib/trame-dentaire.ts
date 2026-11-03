// Trame dentaire du compte rendu opératoire (détartrage, extractions) :
// dents en numérotation de Triadan (chien / chat), actes cochés ; le résultat
// est une ligne « Soins dentaires : … » des gestes réalisés, remplacée à
// chaque passage. Miroir appli : lib/utils/trame_dentaire.dart.

export type EspeceDentaire = 'chien' | 'chat';

/** Dents par quadrant (1 = maxillaire droit, 2 = maxillaire gauche, 3 = mandibule gauche, 4 = mandibule droite). */
export function dentsTriadan(espece: EspeceDentaire): Record<1 | 2 | 3 | 4, number[]> {
  const seq = (q: number, nums: number[]) => nums.map(n => q * 100 + n);
  if (espece === 'chat') {
    const haut = [1, 2, 3, 4, 6, 7, 8, 9], bas = [1, 2, 3, 4, 7, 8, 9];
    return { 1: seq(1, haut), 2: seq(2, haut), 3: seq(3, bas), 4: seq(4, bas) };
  }
  const haut = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], bas = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
  return { 1: seq(1, haut), 2: seq(2, haut), 3: seq(3, bas), 4: seq(4, bas) };
}

export const QUADRANTS: { q: 1 | 2 | 3 | 4; label: string }[] = [
  { q: 1, label: 'Maxillaire droit (100)' }, { q: 2, label: 'Maxillaire gauche (200)' },
  { q: 4, label: 'Mandibule droite (400)' }, { q: 3, label: 'Mandibule gauche (300)' },
];

export const ACTES_DENTAIRES = ['Détartrage ultrasonique', 'Polissage', 'Sondage parodontal', 'Radiographies dentaires'];

const PREFIXE = 'Soins dentaires :';

export function ligneDentaire(actes: string[], extractions: number[]): string {
  const parts: string[] = [];
  if (actes.length) parts.push(actes.map((a, i) => i === 0 ? a : a.toLowerCase()).join(', ') + '.');
  if (extractions.length) parts.push(`Extractions (numérotation de Triadan) : ${[...extractions].sort((a, b) => a - b).join(', ')}.`);
  return parts.length ? `${PREFIXE} ${parts.join(' ')}` : '';
}

/** Ligne dentaire existante dans le texte des gestes : actes et extractions. */
export function lireLigneDentaire(texte: string): { actes: string[]; extractions: number[] } {
  const l = texte.split('\n').find(x => x.trim().startsWith(PREFIXE)) ?? '';
  const ext = l.match(/Extractions[^:]*:\s*([\d,\s]+)/);
  return {
    actes: ACTES_DENTAIRES.filter(a => l.toLowerCase().includes(a.toLowerCase())),
    extractions: ext ? ext[1].split(',').map(x => Number(x.trim())).filter(Boolean) : [],
  };
}

/** Remplace (ou ajoute) la ligne dentaire dans le texte des gestes. */
export function avecLigneDentaire(texte: string, ligne: string): string {
  const autres = texte.split('\n').filter(x => !x.trim().startsWith(PREFIXE));
  return [...(ligne ? [ligne] : []), ...autres].join('\n').trim();
}
