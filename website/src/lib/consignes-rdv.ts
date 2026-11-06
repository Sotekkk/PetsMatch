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

// ── RDV à plusieurs animaux : consignes par animal ──────────────────────────
// rdv.consignes garde sa forme simple { cle: valeur } pour un RDV à un animal ;
// à plusieurs animaux (rdv.animaux_detail, lib/rdv-animaux.ts) :
// { par_animal: { "<id animal>": { cle: valeur } } }. Une ancienne saisie
// simple sur un RDV à plusieurs animaux vaut pour tous ses animaux.
// Miroir appli : lib/utils/consignes_rdv.dart.
export type Reponses = Record<string, string>;
export interface AnimalConsignes { id: string; nom: string; reponses: Reponses | null; prefill?: Reponses | null }

export function estParAnimal(c: unknown): c is { par_animal: Record<string, Reponses> } {
  return !!c && typeof c === 'object' && !Array.isArray(c) && typeof (c as { par_animal?: unknown }).par_animal === 'object'
    && (c as { par_animal?: unknown }).par_animal !== null;
}

/** Réponses d'un animal dans les consignes d'un RDV (forme simple ou par animal). */
export function reponsesAnimal(c: unknown, animalId: string): Reponses | null {
  if (!c || typeof c !== 'object' || Array.isArray(c)) return null;
  if (estParAnimal(c)) return c.par_animal[animalId] ?? null;
  // Forme simple : celle d'un RDV à un animal, ou commune à tous (ancienne saisie).
  return c as Reponses;
}

/** Consignes d'un RDV, animal par animal, pour l'affichage côté professionnel. */
export function consignesParAnimal(metier: string | null | undefined, c: unknown, animaux: { id: string; nom: string }[]) {
  if (!c || typeof c !== 'object') return [] as { id: string; nom: string; lignes: { label: string; valeur: string }[] }[];
  if (!estParAnimal(c) || animaux.length < 2) {
    return [{ id: animaux[0]?.id ?? '', nom: animaux.length > 1 ? 'Tous les animaux' : (animaux[0]?.nom ?? ''), lignes: reponsesAffichables(metier, (estParAnimal(c) ? Object.values(c.par_animal)[0] : c) as Reponses) }];
  }
  return animaux.map(a => ({ id: a.id, nom: a.nom, lignes: reponsesAffichables(metier, c.par_animal[a.id]) }));
}
