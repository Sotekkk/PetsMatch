// Questionnaire de consignes avant un rendez-vous (toiletteur ; structure par
// métier pour pouvoir l'étendre). Le client les
// remplit (appli, site ou lien personnel reçu par e-mail) ; le professionnel
// les lit dans son agenda / dossier de séance. Miroir appli :
// lib/utils/consignes_rdv.dart (garder les mêmes clés).

export interface QuestionConsigne {
  cle: string;
  label: string;
  aide?: string;
  /** Réponses proposées (choix unique) ; sinon texte libre. */
  choix?: string[];
}

const COMPORTEMENT: QuestionConsigne = {
  cle: 'comportement', label: 'Comportement à la manipulation',
  aide: 'Peur, agressivité, muselière nécessaire, ce qui l\'apaise…',
};

export const QUESTIONNAIRES: Record<string, QuestionConsigne[]> = {
  toilettage: [
    { cle: 'demande', label: 'Coupe ou soin souhaité', aide: 'Longueur, style, zones à ne pas couper…' },
    { cle: 'zones_sensibles', label: 'Zones sensibles', aide: 'Oreilles, pattes, queue, peau irritée…' },
    { cle: 'tolerance_sechoir', label: 'Tolérance au séchoir', choix: ['Bonne', 'Moyenne', 'Difficile', 'Je ne sais pas'] },
    COMPORTEMENT,
    { cle: 'produits_a_eviter', label: 'Allergies ou produits à éviter' },
    { cle: 'autre', label: 'Autre chose à signaler' },
  ],
};

/** Métiers concernés (profile_type / cat_pro du profil professionnel). */
export const METIERS_CONSIGNES = Object.keys(QUESTIONNAIRES);

export function questionnaire(metier: string | null | undefined): QuestionConsigne[] {
  return QUESTIONNAIRES[metier ?? ''] ?? [{ cle: 'autre', label: 'Consignes pour le professionnel' }];
}

/** Libellé d'une réponse enregistrée, pour l'affichage côté professionnel. */
export function reponsesAffichables(metier: string | null | undefined, reponses: Record<string, string> | null | undefined) {
  if (!reponses) return [] as { label: string; valeur: string }[];
  return questionnaire(metier).map(q => ({ label: q.label, valeur: (reponses[q.cle] ?? '').trim() })).filter(x => x.valeur);
}
