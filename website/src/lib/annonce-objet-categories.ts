// Catégories des petites annonces « objets & matériel » liées aux animaux
// (profil particulier). Aucune catégorie ne concerne un animal vivant.
// Doit rester aligné avec `lib/data/annonce_objet_categories.dart`.

export interface AnnonceObjetCategorie {
  slug: string;
  label: string;
  emoji: string;
  exemples: string;
}

export const ANNONCE_OBJET_CATEGORIES: AnnonceObjetCategorie[] = [
  { slug: 'habitat', label: 'Habitat & cage', emoji: '🏠',
    exemples: 'Cage, clapier, volière, aquarium, terrarium, niche, box, abri' },
  { slug: 'accessoires', label: 'Accessoires', emoji: '🦮',
    exemples: 'Harnais, laisse, collier, gamelle, sac de transport, jouets, couchage' },
  { slug: 'alimentation', label: 'Alimentation & fourrage', emoji: '🌾',
    exemples: 'Foin, paille, granulés, litière, compléments' },
  { slug: 'entretien', label: 'Entretien & soin', emoji: '✂️',
    exemples: 'Matériel de toilettage, tondeuse, pharmacie, brosses' },
  { slug: 'terrain', label: 'Terrain & pâture', emoji: '🌳',
    exemples: 'Location de prairie, parcelle, pré, box en écurie, stabulation, pension' },
  { slug: 'materiel_agricole', label: 'Matériel agricole', emoji: '🚜',
    exemples: "Tracteur, remorque, clôture, abreuvoir, matériel d'élevage" },
  { slug: 'autre', label: 'Autre (lié aux animaux)', emoji: '📦',
    exemples: 'Tout autre objet ou service lié aux animaux (pas un animal)' },
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

export function categorieEmoji(slug?: string | null): string {
  return ANNONCE_OBJET_CATEGORIES.find(c => c.slug === slug)?.emoji ?? '📦';
}
