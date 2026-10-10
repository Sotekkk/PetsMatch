// Couleurs des marqueurs de la carte de l'annuaire, par profile_type (miroir
// app Flutter). Source unique partagée par la carte (ServicesMap) et les
// fiches de la liste, pour que liste et carte gardent le même repère.
export const COULEUR_MARQUEUR_PRO: Record<string, string> = {
  sante:            '#2196F3',
  veterinaire:      '#2196F3',
  education:        '#FF9800',
  garde:            '#4CAF50',
  pension:          '#8BC34A',
  toilettage:       '#00BCD4',
  referencement:    '#CDDC39',
  photographe:      '#E91E63',
  marechal_ferrant: '#795548',
  taxi_animalier:   '#00838F',
};
export const COULEUR_MARQUEUR_PRO_DEFAUT = '#9C27B0'; // violet

export const couleurMarqueurPro = (cat?: string | null) =>
  COULEUR_MARQUEUR_PRO[cat ?? ''] ?? COULEUR_MARQUEUR_PRO_DEFAUT;
