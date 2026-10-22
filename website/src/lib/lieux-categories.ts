// Catégories d'un lieu pet-friendly (categorie + sous_categorie, mêmes valeurs
// que les fiches des établissements), plus commerce et activité.
// Miroir appli : lib/pages/lieux/recommander_lieu_page.dart (kTypesLieu).
export const TYPES_LIEU: { value: string; categorie: string; label: string }[] = [
  { value: 'restaurant', categorie: 'restauration', label: 'Restaurant' },
  { value: 'cafe', categorie: 'restauration', label: 'Café / Salon de thé' },
  { value: 'bar', categorie: 'restauration', label: 'Bar / Brasserie' },
  { value: 'boulangerie', categorie: 'restauration', label: 'Boulangerie / Pâtisserie' },
  { value: 'hotel', categorie: 'hebergement', label: 'Hôtel' },
  { value: 'gite', categorie: 'hebergement', label: "Gîte / Chambre d'hôtes" },
  { value: 'camping', categorie: 'hebergement', label: 'Camping' },
  { value: 'villa_location', categorie: 'hebergement', label: 'Location saisonnière' },
  { value: 'hebergement_insolite', categorie: 'hebergement', label: 'Hébergement insolite' },
  { value: 'commerce', categorie: 'commerce', label: 'Commerce' },
  { value: 'activite', categorie: 'activite', label: 'Activité ou loisir' },
];

/** Mention de référencement d'un lieu (communauté / vérifié / partenaire). */
export function referencementLieu(l: { uid_pro?: string | null; plan?: string | null; verification?: string | null }): 'communaute' | 'verifie' | 'partenaire' {
  if (!l.uid_pro) return 'communaute';
  if (l.plan && l.plan !== 'decouverte') return 'partenaire';
  return 'verifie';
}
export const LIBELLE_REFERENCEMENT = {
  communaute: 'Recommandé par la communauté',
  verifie: 'Établissement vérifié',
  partenaire: 'Partenaire PetsMatch',
} as const;
