// Couleurs fonctionnelles des rubriques du carnet de santé : une même
// couleur pour la rubrique, son action « Ajouter » et ses rappels / tâches
// dans l'agenda. Valeurs historiques du carnet (fiche animal) — ne pas
// remplacer. Miroir app : lib/utils/sante_couleurs.dart.
export const SANTE_COULEURS = {
  vaccinations:     '#2196F3',
  vermifuges:       '#6E9E57',
  antiparasitaires: '#5B8648',
  traitements:      '#8D6E63',
  chirurgies:       '#C2185B',
  allergies:        '#E25C5C',
  poids:            '#5F9EAA',
} as const;

/** Type d'acte (agenda / protocoles) → couleur de la rubrique santé. */
export const SANTE_COULEUR_ACTE: Record<string, string> = {
  vaccination:     SANTE_COULEURS.vaccinations,
  vermifuge:       SANTE_COULEURS.vermifuges,
  antiparasitaire: SANTE_COULEURS.antiparasitaires,
  traitement:      SANTE_COULEURS.traitements,
};
