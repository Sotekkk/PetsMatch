// Protocoles (plan_templates) — périmètre, libellés et calcul des dates,
// partagés par la page Protocoles et la fiche PDF.
// Miroir app : lib/utils/protocoles.dart.

/** Statuts d'un animal qui n'est plus pris en charge par la structure
 *  (cédé / adopté / transféré / décédé) : il n'est plus proposé pour un
 *  NOUVEAU protocole. Ses fiches, anciens protocoles et historiques restent
 *  intacts et consultables. Miroir app : kStatutsHorsPriseEnCharge. */
export const STATUTS_HORS_PRISE_EN_CHARGE = ['sorti', 'adopte', 'transfere', 'decede'];

export function estHorsPriseEnCharge(a: { statut?: string | null }): boolean {
  return STATUTS_HORS_PRISE_EN_CHARGE.includes(a.statut ?? '');
}

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
/** Petits encore « de la portée » (au sein de l'élevage) : âge maximum en
 *  semaines selon l'espèce (chiot 13 sem., chaton 15, poulain 6 mois…).
 *  Miroir appli : lib/utils/protocoles.dart ageMaxPorteeSemaines. */
export function ageMaxPorteeSemaines(espece?: string | null): number {
  const e = (espece ?? '').toLowerCase();
  if (e.startsWith('chat')) return 15;
  if (e.startsWith('lapin') || e.startsWith('furet') || e.startsWith('porc')) return 12;
  if (e.startsWith('cheval') || e.startsWith('poney') || e.startsWith('âne') || e.startsWith('ane') || e.startsWith('equ') || e.startsWith('équ') || e.startsWith('bovin') || e.startsWith('vache')) return 26;
  if (e.startsWith('ovin') || e.startsWith('mouton') || e.startsWith('caprin') || e.startsWith('chèvre') || e.startsWith('chevre')) return 16;
  if (e.startsWith('volaille') || e.startsWith('oiseau') || e.startsWith('poule')) return 8;
  return 13; // chien et autres
}

/**
 * Animaux encore présents chez l'éleveur : pas sortis / adoptés / décédés, et
 * pas cédés (sa propriété est close alors qu'elle existait). Animal sans
 * aucune ligne de propriété : présent. Miroir appli : animauxPresents.
 */
export async function animauxPresents(
  sb: { from: (t: string) => any }, // eslint-disable-line @typescript-eslint/no-explicit-any
  ids: string[], uidEleveur: string,
): Promise<Set<string>> {
  const out = new Set<string>();
  if (!ids.length) return out;
  const [{ data: anims }, { data: props }] = await Promise.all([
    sb.from('animaux').select('id, statut').in('id', ids),
    sb.from('animaux_proprietes').select('animal_id, uid_proprio, date_fin').in('animal_id', ids),
  ]);
  const avecLigne = new Set<string>(), actif = new Set<string>();
  for (const p of (props ?? []) as { animal_id: string; uid_proprio: string; date_fin: string | null }[]) {
    avecLigne.add(p.animal_id);
    if (p.uid_proprio === uidEleveur && !p.date_fin) actif.add(p.animal_id);
  }
  for (const a of (anims ?? []) as { id: string; statut: string | null }[]) {
    if (estHorsPriseEnCharge(a)) continue;
    if (actif.has(a.id) || !avecLigne.has(a.id)) out.add(a.id);
  }
  return out;
}

/** « Portée de Shouka — mars 2026 » : mois et année de naissance pour
 *  distinguer deux portées de la même mère. */
export function libellePortee(membres: { nom_mere?: string | null; date_naissance?: string | null }[]): string {
  const mere = membres.map(a => a.nom_mere?.trim() ?? '').find(Boolean);
  const dates = membres.map(a => a.date_naissance).filter((d): d is string => !!d).sort();
  const mois = dates[0] ? new Date(dates[0]).toLocaleDateString('fr-FR', { month: 'long', year: 'numeric' }) : '';
  return `${mere ? `Portée de ${mere}` : 'Portée'}${mois ? ` — ${mois}` : ''}`;
}

/** Le petit a-t-il encore l'âge « portée » (date de naissance inconnue : oui) ? */
export function petitDePortee(dateNaissance?: string | null, espece?: string | null): boolean {
  if (!dateNaissance) return true;
  const n = new Date(dateNaissance).getTime();
  if (isNaN(n)) return true;
  return (Date.now() - n) / (7 * 86400000) <= ageMaxPorteeSemaines(espece);
}

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
  // Pension : appliqué tout seul à l'enregistrement de l'arrivée (lib/pension-protocoles.ts).
  { value: 'sejour',       label: 'Séjour en pension (automatique)', aide: "Appliqué tout seul à l'arrivée de chaque pensionnaire concerné ; chaque étape se place pendant son séjour" },
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
/** Pet-sitter (garde) : actions d'une visite à domicile — miroir appli kActesSuggeresGarde. */
export const ACTES_SUGGERES_GARDE: { value: string; label: string }[] = [
  { value: 'promenade',  label: 'Promenade' },
  { value: 'repas',      label: 'Repas' },
  { value: 'eau',        label: 'Eau fraîche' },
  { value: 'medicament', label: 'Donner le traitement' },
  { value: 'litiere',    label: 'Nettoyage de la litière' },
  { value: 'nettoyage',  label: 'Nettoyage des locaux' },
  { value: 'jeux',       label: 'Jeux / câlins' },
  { value: 'brossage',   label: 'Brossage' },
  { value: 'plantes',    label: 'Arrosage des plantes' },
  { value: 'courrier',   label: 'Relève du courrier' },
  { value: 'volets',     label: 'Ouverture / fermeture des volets' },
  { value: 'nouvelles',  label: 'Nouvelles au propriétaire' },
];

/** Pension : soins et entretien quotidiens — miroir appli kActesSuggeresPension. */
export const ACTES_SUGGERES_PENSION: { value: string; label: string }[] = [
  { value: 'repas', label: 'Repas' }, { value: 'eau', label: 'Eau fraîche' }, { value: 'sortie', label: 'Sortie / promenade' },
  { value: 'nettoyage_box', label: 'Nettoyage du box' }, { value: 'nettoyage', label: 'Désinfection' }, { value: 'litiere', label: 'Change de litière' },
  { value: 'medicament', label: 'Donner le traitement' }, { value: 'controle', label: "Contrôle de l'état général" }, { value: 'pesee', label: 'Pesée' },
  { value: 'brossage', label: 'Brossage / toilettage' }, { value: 'jeux', label: 'Jeux / socialisation' }, { value: 'nouvelles', label: 'Nouvelles au propriétaire' },
];

/** Actions proposées selon le profil (garde : visite à domicile ; pension). */
export function actesSuggeresPour(profilSource?: string | null) {
  return profilSource === 'garde' ? ACTES_SUGGERES_GARDE : profilSource === 'pension' ? ACTES_SUGGERES_PENSION : ACTES_SUGGERES;
}

const TOUS_ACTES = () => [...ACTES_SUGGERES, ...ACTES_SUGGERES_GARDE, ...ACTES_SUGGERES_PENSION];

export function acteLabel(v: string | null | undefined): string {
  if (!v) return '';
  if (v === 'socialisation') return 'Promenade / Socialisation';
  if (v === 'autre') return 'Autre';
  return TOUS_ACTES().find(a => a.value === v)?.label ?? v;
}

/** Saisie libre → code connu si elle correspond à une suggestion. */
export function acteDepuisSaisie(s: string): string {
  const t = s.trim();
  return TOUS_ACTES().find(a => a.label.toLowerCase() === t.toLowerCase() || a.value === t.toLowerCase())?.value ?? t;
}

export const TRANCHES_LABELS: Record<string, string> = {
  matin: 'Matin', midi: 'Midi', apres_midi: 'Après-midi', soir: 'Soir',
};

/** Créneaux d'une étape : « matin,soir » = plusieurs fois par jour. */
export function tranchesDe(v?: string | null): string[] {
  return (v ?? '').split(',').map(x => x.trim()).filter(Boolean);
}
export function trancheLabel(v?: string | null): string {
  return tranchesDe(v).map(k => TRANCHES_LABELS[k] ?? k).join(' et ');
}
/** Créneau d'une heure précise (10:00 → matin). */
export function trancheDeHeure(h: string): string {
  const n = parseInt(h.slice(0, 2), 10);
  return n < 12 ? 'matin' : n < 14 ? 'midi' : n < 18 ? 'apres_midi' : 'soir';
}

/** Réglages de l'étape sur ses tâches (migration_protocoles_heure_assigne) :
 *  heure précise (« Distribution des repas — 10:00 ») et employé attribué.
 *  Miroir appli : appliquerReglagesEtapes (lib/utils/protocoles.dart). */
export function appliquerReglagesEtapes<T>(taches: T[],
  etapes: { id?: string | null; heure?: string | null; assigne_uid?: string | null; assigne_profile_id?: string | null }[]): T[] {
  const parId = new Map(etapes.filter(e => e.id).map(e => [String(e.id), e]));
  return taches.map(t => {
    const x = t as unknown as Record<string, unknown>;
    const e = parId.get(String(x.etape_id ?? ''));
    if (!e) return t;
    const r: Record<string, unknown> = { ...x };
    if (e.assigne_uid) { r.assigned_to = e.assigne_uid; r.assigned_profile_id = e.assigne_profile_id ?? null; }
    if (e.heure) { r.heure = e.heure; r.tranche_horaire = trancheDeHeure(e.heure); r.label = `${String(x.label ?? '')} — ${e.heure}`; }
    return r as unknown as T;
  });
}

/** Une tâche par créneau (« Litière — Matin », « Litière — Soir »). Miroir
 *  appli : eclaterTranches (lib/utils/protocoles.dart). */
export function eclaterTranches<T extends { tranche_horaire?: unknown; label?: unknown }>(taches: T[]): T[] {
  return taches.flatMap(t => {
    const ts = tranchesDe(t.tranche_horaire as string | null);
    return ts.length > 1
      ? ts.map(k => ({ ...t, tranche_horaire: k, label: `${String(t.label ?? '')} — ${TRANCHES_LABELS[k] ?? k}` }))
      : [t];
  });
}

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
