// Protocoles (plan_templates) — périmètre, libellés et calcul des dates,
// partagés par la page Protocoles et la fiche PDF.
// Miroir app : lib/utils/protocoles.dart.

export interface EtapeProtocole {
  id?: string;
  type_acte: string;
  produit?: string | null;
  dosage?: string | null;
  offset_direction: 'avant' | 'apres';
  jour_offset: number;
  age_min_semaines?: number | null;
  frequence: string;
  nb_fois_semaine?: number | null;
  duree_semaines?: number | null;
  duree_jours: number;
  is_recurrent?: boolean;
  lieu?: string | null;
  description?: string | null;
  ordre: number;
  tranche_horaire?: string | null;
}

export interface ProtocoleBase {
  id: string;
  nom: string;
  type: string;
  espece?: string | null;
  description?: string | null;
  lieu?: string | null;
  cible_type: string;
  reference_event: string;
  updated_at?: string | null;
  created_at?: string | null;
  plan_template_etapes?: EtapeProtocole[];
}

// ── Périmètre : qui / quoi est concerné ─────────────────────────────────────

export type Perimetre = 'animal' | 'portee' | 'cheptel' | 'categorie' | 'locaux';

export const PERIMETRES: { value: Perimetre; label: string; aide: string }[] = [
  { value: 'animal',    label: 'Un ou plusieurs animaux', aide: 'Choisis maintenant ou au moment d’appliquer' },
  { value: 'portee',    label: 'Une portée',              aide: 'La portée est choisie au moment d’appliquer' },
  { value: 'cheptel',   label: 'Tout le cheptel',         aide: 'Tous les animaux (de l’espèce choisie)' },
  { value: 'categorie', label: 'Une catégorie d’animaux', aide: 'Mâles, femelles, femelles gestantes, jeunes…' },
  { value: 'locaux',    label: 'Locaux / matériel',       aide: 'Aucun animal : une tâche par occurrence' },
];

/** Catégories d'animaux (valeurs historiques de cible_type). */
export const CATEGORIES: { value: string; label: string }[] = [
  { value: 'males',     label: 'Mâles' },
  { value: 'femelles',  label: 'Femelles' },
  { value: 'gestantes', label: 'Femelles gestantes' },
  { value: 'bebes',     label: 'Bébés / jeunes' },
];

const TYPES_LOCAUX = ['nettoyage', 'materiel'];

/** Périmètre effectif. Les anciens protocoles de nettoyage / matériel étaient
 * enregistrés en « cheptel » (le formulaire l'imposait) alors qu'ils portent
 * sur les locaux : ils sont lus comme « locaux » (aucun animal). */
export function perimetreDe(t: Pick<ProtocoleBase, 'cible_type' | 'type'>, profilSource?: string): Perimetre {
  if (t.cible_type === 'locaux') return 'locaux';
  if (t.cible_type === 'portee') return 'portee';
  if (t.cible_type === 'individuel') return 'animal';
  if (CATEGORIES.some(c => c.value === t.cible_type)) return 'categorie';
  if (t.cible_type === 'cheptel' && TYPES_LOCAUX.includes(t.type) && profilSource !== 'garde') return 'locaux';
  return 'cheptel';
}

/** Valeur cible_type à enregistrer. */
export function cibleTypePour(p: Perimetre, categorie: string): string {
  return p === 'animal' ? 'individuel' : p === 'categorie' ? (categorie || 'femelles') : p;
}

const ESPECE_LABELS: Record<string, string> = {
  chien: 'chiens', chat: 'chats', cheval: 'chevaux', lapin: 'lapins', oiseau: 'oiseaux',
  nac: 'NAC', ovin: 'ovins', caprin: 'caprins', porcin: 'porcins',
};

/** Libellé court du périmètre (cartes, fiche PDF). */
export function perimetreLabel(t: Pick<ProtocoleBase, 'cible_type' | 'type' | 'espece' | 'lieu'>, profilSource?: string): string {
  const p = perimetreDe(t, profilSource);
  const esp = t.espece ? ` (${ESPECE_LABELS[t.espece] ?? t.espece})` : '';
  switch (p) {
    case 'locaux':    return t.lieu ? `Locaux : ${t.lieu}` : 'Locaux / matériel';
    case 'portee':    return `Portée${esp}`;
    case 'animal':    return `Animaux choisis${esp}`;
    case 'categorie': return `${CATEGORIES.find(c => c.value === t.cible_type)?.label ?? t.cible_type}${esp}`;
    default:          return `Tout le cheptel${esp}`;
  }
}

// ── Événement de référence (calcul des dates) ───────────────────────────────

export const REF_EVENTS: { value: string; label: string; aide: string }[] = [
  { value: 'manuel',       label: 'Date choisie à l’application', aide: 'Vous indiquez le jour J0' },
  { value: 'saillie',      label: 'Saillie',                      aide: 'J0 = date de la saillie' },
  { value: 'mise_bas',     label: 'Mise bas',                     aide: 'J0 = date de mise bas (prévue)' },
  { value: 'naissance',    label: 'Naissance',                    aide: 'J0 = date de naissance' },
  { value: 'age_semaines', label: 'Âge des animaux',              aide: 'Chaque étape à un âge en semaines' },
];

export function refEventLabel(v: string): string {
  return REF_EVENTS.find(r => r.value === v)?.label ?? v;
}

// ── Étapes ───────────────────────────────────────────────────────────────────

export const ACTES_SUGGERES: { value: string; label: string }[] = [
  { value: 'vermifuge',       label: 'Vermifuge' },
  { value: 'vaccination',     label: 'Vaccination' },
  { value: 'antiparasitaire', label: 'Antiparasitaire' },
  { value: 'traitement',      label: 'Traitement' },
  { value: 'visite',          label: 'Visite vétérinaire' },
  { value: 'alimentaire',     label: 'Alimentaire' },
  { value: 'toilettage',      label: 'Toilettage' },
  { value: 'nettoyage',       label: 'Désinfection' },
  { value: 'promenade',       label: 'Promenade / Socialisation' },
];

/** Libellé lisible d'une action (code connu ou texte libre saisi). */
export function acteLabel(v: string | null | undefined): string {
  if (!v) return '';
  if (v === 'socialisation') return 'Promenade / Socialisation';
  if (v === 'autre') return 'Autre';
  return ACTES_SUGGERES.find(a => a.value === v)?.label ?? v;
}

/** Saisie libre → code connu si elle correspond à une suggestion. */
export function acteDepuisSaisie(s: string): string {
  const t = s.trim();
  return ACTES_SUGGERES.find(a => a.label.toLowerCase() === t.toLowerCase() || a.value === t.toLowerCase())?.value ?? t;
}

export const TRANCHES_LABELS: Record<string, string> = {
  matin: 'Matin', midi: 'Midi', apres_midi: 'Après-midi', soir: 'Soir',
};

export function quandLabel(e: EtapeProtocole, refEvent: string): string {
  if (refEvent === 'age_semaines' || (e.age_min_semaines != null && refEvent !== 'manuel' && refEvent !== 'saillie' && refEvent !== 'mise_bas')) {
    return `À ${e.age_min_semaines ?? 0} semaine${(e.age_min_semaines ?? 0) > 1 ? 's' : ''} d’âge`;
  }
  const ref = refEvent === 'saillie' ? 'la saillie' : refEvent === 'mise_bas' ? 'la mise bas'
    : refEvent === 'naissance' ? 'la naissance' : 'la date de début';
  if (!e.jour_offset) return refEvent === 'manuel' ? 'Dès la date de début' : `Le jour de ${ref}`;
  return `${e.jour_offset} jour${e.jour_offset > 1 ? 's' : ''} ${e.offset_direction === 'avant' ? 'avant' : 'après'} ${ref}`;
}

export function frequenceLabel(e: EtapeProtocole): string {
  const sem = e.duree_semaines ?? 1;
  if (e.frequence === 'ponctuel') return e.duree_jours > 1 ? `${e.duree_jours} jours de suite` : 'Une fois';
  if (e.frequence === 'quotidien') return e.is_recurrent ? 'Chaque jour (1 an)' : `Chaque jour pendant ${sem} semaine${sem > 1 ? 's' : ''}`;
  if (e.frequence === 'hebdomadaire') return `${e.nb_fois_semaine ?? 1} fois / semaine${e.is_recurrent ? ' (1 an)' : ` pendant ${sem} semaine${sem > 1 ? 's' : ''}`}`;
  if (e.frequence === 'mensuel') return e.is_recurrent ? 'Chaque mois (1 an)' : `Chaque mois pendant ${sem} mois`;
  return e.frequence;
}
