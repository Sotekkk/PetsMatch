// Ce que comprend la formule gratuite de chaque métier, affiché en tête de la
// carte « Gratuit » sur /tarifs et sur chaque page d'abonnement
// (app/<métier>/abonnement, app/abonnement pour l'éleveur). Éleveur : pas de
// prise de RDV, donc pas d'agenda des rendez-vous.

export const estFormuleGratuite = (planCode: string) => planCode === 'free' || planCode === 'decouverte';

export function inclusFormuleGratuite(metier: string): string[] {
  return metier === 'eleveur'
    ? ['Profil dans l’annuaire']
    : ['Profil dans l’annuaire', 'Agenda des rendez-vous'];
}

/** Libellés d'une formule : ceux de la formule gratuite d'abord, sans doublon. */
export function avecInclusGratuit(metier: string, planCode: string, libelles: string[]): string[] {
  if (!estFormuleGratuite(planCode)) return libelles;
  const inclus = inclusFormuleGratuite(metier);
  return [...inclus, ...libelles.filter(l => !inclus.includes(l))];
}
