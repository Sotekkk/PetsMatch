// Espèces gérées par une pension.
// `key` est stockée dans user_profiles.tarifs_pension.especes[].espece ;
// `label` correspond aux valeurs de user_profiles.especes_acceptees.

export interface PensionEspece {
  key: string;
  label: string;
  emoji: string;
}

export const PENSION_ESPECES: PensionEspece[] = [
  { key: 'chien',         label: 'Chien',                emoji: '🐕' },
  { key: 'chat',          label: 'Chat',                 emoji: '🐈' },
  { key: 'cheval',        label: 'Cheval',               emoji: '🐴' },
  { key: 'animaux_ferme', label: 'Animaux de la ferme',  emoji: '🐐' },
  { key: 'lapin',         label: 'Lapin',                emoji: '🐇' },
  { key: 'ane',           label: 'Âne',                  emoji: '🫏' },
  { key: 'nac',           label: 'NAC',                  emoji: '🐹' },
  { key: 'oiseau',        label: 'Oiseaux',              emoji: '🦜' },
];

/** entree.espece (minuscule) OU label d'espèce acceptée -> key canonique. */
export function pensionTarifKeyForEspece(espece?: string | null): string | null {
  const s = (espece ?? '').toLowerCase().trim();
  switch (s) {
    case 'chien':   return 'chien';
    case 'chat':    return 'chat';
    case 'cheval':  return 'cheval';
    case 'lapin':   return 'lapin';
    case 'ane':
    case 'âne':     return 'ane';
    case 'oiseau':
    case 'oiseaux': return 'oiseau';
    case 'nac':     return 'nac';
    case 'animaux de la ferme': return 'animaux_ferme';
    case 'ovin':
    case 'caprin':
    case 'porcin':
    case 'mouton':
    case 'chevre':
    case 'chèvre':
    case 'cochon':  return 'animaux_ferme';
  }
  const byLabel = PENSION_ESPECES.find(p => p.label.toLowerCase() === s);
  return byLabel ? byLabel.key : null;
}

/**
 * Un logement (enclos_chenil.especes) accepte-t-il cette espèce d'animal ?
 * Un logement sans espèce configurée accepte tout.
 */
export function especeMatchesLogement(
  animalEspece: string | null | undefined,
  logementEspeces: string[] | null | undefined,
): boolean {
  if (!logementEspeces || logementEspeces.length === 0) return true;
  const animalKey = pensionTarifKeyForEspece(animalEspece) ?? (animalEspece ?? '').toLowerCase().trim();
  if (!animalKey) return true;
  return logementEspeces.some(e => {
    const k = pensionTarifKeyForEspece(e) ?? (e ?? '').toLowerCase().trim();
    return k === animalKey;
  });
}

export interface EspeceTarif {
  espece: string;
  prix_seul: number;
  prix_partage: number;
}

export interface TarifsPension {
  especes?: EspeceTarif[];
  // Ancien modèle, encore lu en fallback.
  tranches_poids?: { poids_max: number | null; prix_seul: number; prix_partage: number }[];
  reductions_long_sejour?: { min_nuits: number; pourcentage: number }[];
}
