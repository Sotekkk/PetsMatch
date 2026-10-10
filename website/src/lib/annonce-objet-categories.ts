// Catégories des annonces « Matériel & équipements » (matériel destiné aux
// animaux et aux activités professionnelles). Aucune catégorie ne concerne un animal vivant.
// Doit rester aligné avec `lib/data/annonce_objet_categories.dart`.

export interface AnnonceObjetCategorie {
  slug: string;
  label: string;
  exemples: string;
}

// Slugs inchangés (données existantes) ; libellés « Matériel & équipements ».
export const ANNONCE_OBJET_CATEGORIES: AnnonceObjetCategorie[] = [
  { slug: 'habitat', label: 'Couchage, habitat & parcs',
    exemples: 'Paniers, niches, grilles de chenil, parcs, cages, volières, clapiers, aquariums' },
  { slug: 'accessoires', label: 'Transport & accessoires',
    exemples: 'Caisses de transport, harnais, laisses, colliers, gamelles' },
  { slug: 'alimentation', label: 'Alimentation & fourrage',
    exemples: 'Foin, paille, granulés, litière, compléments' },
  { slug: 'entretien', label: 'Entretien & soin',
    exemples: 'Matériel de toilettage, tondeuse, pharmacie, brosses' },
  { slug: 'terrain', label: 'Terrain & pâture',
    exemples: 'Location de prairie, parcelle, pré, box en écurie, stabulation' },
  { slug: 'materiel_agricole', label: 'Équipements d’élevage & agricoles',
    exemples: 'Équipements de mise bas, couveuses, abreuvoirs, clôtures, remorque, tracteur' },
  { slug: 'autre', label: 'Autre matériel',
    exemples: 'Tout autre matériel ou équipement destiné aux animaux (jamais un animal)' },
];

export const ANNONCE_OBJET_TRANSACTIONS: Record<string, string> = {
  vente: 'Vente',
  location: 'Location',
  don: 'Don',
  recherche: 'Recherche',
};

export const ANNONCE_OBJET_ETATS: Record<string, string> = {
  neuf: 'Neuf',
  tres_bon: 'Très bon état',
  bon: 'Bon état',
  usage: "État d'usage",
};

export function categorieLabel(slug?: string | null): string {
  return ANNONCE_OBJET_CATEGORIES.find(c => c.slug === slug)?.label ?? 'Autre';
}
