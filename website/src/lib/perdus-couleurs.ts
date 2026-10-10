// Couleurs des marqueurs de la carte « Animaux perdus / trouvés » (site).
// Source unique partagée par la carte (AnimauxPerdusMap) et sa légende :
// valeurs reprises telles quelles de la carte, aucune réattribution.
// Perdu : couleur selon l'espèce (rouge par défaut) ; Trouvé : vert.

export const MARQUEUR_ESPECE: Record<string, string> = {
  chien:  '#3B82F6',
  chat:   '#EC4899',
  cheval: '#F59E0B',
  lapin:  '#10B981',
  oiseau: '#8B5CF6',
  nac:    '#EF4444',
  ovin:   '#22C55E',
  caprin: '#F97316',
  porcin: '#D946EF',
};
export const MARQUEUR_PERDU_DEFAUT = '#EF4444';
export const MARQUEUR_TROUVE = '#16A34A';

export function couleurMarqueur(espece: string | undefined, type: 'perdu' | 'trouve'): string {
  if (type === 'trouve') return MARQUEUR_TROUVE;
  return MARQUEUR_ESPECE[espece ?? ''] ?? MARQUEUR_PERDU_DEFAUT;
}
