// Espèces gérées par une pension.
// `key` est stockée dans user_profiles.tarifs_pension.especes[].espece ;
// `label` correspond aux valeurs de user_profiles.especes_acceptees.

export interface PensionEspece {
  key: string;
  label: string;
  emoji: string;
}

export const PENSION_ESPECES: PensionEspece[] = [
  { key: 'chien',    label: 'Chien',     emoji: '🐕' },
  { key: 'chat',     label: 'Chat',      emoji: '🐈' },
  { key: 'cheval',   label: 'Cheval',    emoji: '🐴' },
  { key: 'ane',      label: 'Âne',       emoji: '🫏' },
  { key: 'bovin',    label: 'Bovins',    emoji: '🐄' },
  { key: 'ovin',     label: 'Ovins',     emoji: '🐑' },
  { key: 'caprin',   label: 'Caprins',   emoji: '🐐' },
  { key: 'porcin',   label: 'Porcins',   emoji: '🐖' },
  { key: 'volaille', label: 'Volailles', emoji: '🐓' },
  { key: 'lapin',    label: 'Lapin',     emoji: '🐇' },
  { key: 'nac',      label: 'NAC',       emoji: '🐹' },
  { key: 'oiseau',   label: 'Oiseaux',   emoji: '🦜' },
  { key: 'poisson',  label: 'Poissons',  emoji: '🐟' },
];

/** Ancien tarif unique « Animaux de la ferme » (avant bovins / ovins / …
 *  séparés) : encore lu tant que la pension n'a pas réenregistré ses tarifs. */
export const PENSION_ESPECE_FERME_LEGACY: PensionEspece =
  { key: 'animaux_ferme', label: 'Animaux de la ferme', emoji: '🐐' };

/** entree.espece (minuscule) OU label d'espèce acceptée -> key canonique. */
export function pensionTarifKeyForEspece(espece?: string | null): string | null {
  const s = (espece ?? '').toLowerCase().trim();
  switch (s) {
    case 'chien':
    case 'chiens':  return 'chien';
    case 'chat':
    case 'chats':   return 'chat';
    case 'cheval':
    case 'chevaux':
    case 'équidés':
    case 'equides': return 'cheval';
    case 'lapin':   return 'lapin';
    case 'ane':
    case 'âne':     return 'ane';
    case 'oiseau':
    case 'oiseaux': return 'oiseau';
    case 'nac':     return 'nac';
    case 'poisson':
    case 'poissons': return 'poisson';
    case 'bovin':
    case 'bovins':
    case 'vache':
    case 'taureau': return 'bovin';
    case 'ovin':
    case 'ovins':
    case 'mouton':
    case 'brebis':  return 'ovin';
    case 'caprin':
    case 'caprins':
    case 'chevre':
    case 'chèvre':  return 'caprin';
    case 'porcin':
    case 'porcins':
    case 'porc':
    case 'cochon':  return 'porcin';
    case 'volaille':
    case 'volailles':
    case 'poule':   return 'volaille';
    case 'animaux de la ferme': return 'animaux_ferme';
  }
  const byLabel = PENSION_ESPECES.find(p => p.label.toLowerCase() === s);
  return byLabel ? byLabel.key : null;
}

/** Rubrique large d'une key de tarif : depuis la liste commune des pros
 *  (« NAC », « Équidés »), un lapin relève des NAC et un âne des équidés. */
/** Les bovins, ovins… relèvent de l'ancien « Animaux de la ferme ». */
export function pensionGroupe(k: string): string {
  if (k === 'lapin') return 'nac';
  if (k === 'ane') return 'cheval';
  if (['bovin', 'ovin', 'caprin', 'porcin', 'volaille'].includes(k)) return 'animaux_ferme';
  return k;
}

/** Prix d'une espèce dans tarifs_pension.especes ; repli sur la rubrique
 *  large (ancien tarif « Animaux de la ferme ») si l'espèce n'a pas le sien. */
export function pensionTarifPourKey<T extends { espece: string }>(especesTarifs: T[], key: string): T | undefined {
  return especesTarifs.find(e => e.espece === key) ?? especesTarifs.find(e => e.espece === pensionGroupe(key));
}

/** La pension a-t-elle coché une espèce couvrant ce tarif ? */
export function pensionTarifAccepte(key: string, acceptees: Iterable<string>): boolean {
  for (const a of Array.from(acceptees)) {
    const k = pensionTarifKeyForEspece(a);
    if (k === key || (k != null && k === pensionGroupe(key))) return true;
  }
  return false;
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
    return k === animalKey || k === pensionGroupe(animalKey);
  });
}

/**
 * L'alimentation « pour ce séjour » (foin / granulés / compléments) est-elle
 * pertinente pour cette espèce ? Équidés + animaux de la ferme.
 */
export function pensionAlimentationSejourApplicable(espece?: string | null): boolean {
  const k = pensionTarifKeyForEspece(espece) ?? (espece ?? '').toLowerCase().trim();
  return k === 'cheval' || k === 'ane' || k === 'poney' || pensionGroupe(k) === 'animaux_ferme';
}

export interface AlimentationSejour {
  fournis_par?: 'pension' | 'proprietaire' | 'mixte';
  foin?: string;
  granules?: string;
  complements?: string;
  autres?: string;
  consignes?: string;
}

export function alimSejourFournisParLabel(v?: string | null): string {
  switch (v) {
    case 'pension': return 'Fournie par la pension';
    case 'proprietaire': return 'Fournie par le propriétaire';
    case 'mixte': return 'Alimentation partagée';
    default: return '';
  }
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
