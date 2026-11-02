// Ordonnance structurée (migration_ordonnances_v2.sql) : contenu jsonb des
// lignes, contrôles avant validation, statuts. Le PDF est produit à partir de
// ce contenu (ordonnance-pdf.ts). Miroir appli : lib/utils/ordonnance.dart.
//
// Règle : rien n'est déduit ni inventé — un champ vide reste vide et bloque
// (médicament, posologie, durée) ou est signalé (voie, quantité, mentions).

export interface LigneOrdo {
  medicament: string;
  principeActif: string;
  /** Présentation et concentration (ex. comprimé 50 mg). */
  presentation: string;
  /** Dose, nombre de prises, fréquence. */
  posologie: string;
  voie: string;
  duree: string;
  /** Quantité à délivrer. */
  quantite: string;
  /** Renouvellement autorisé (ex. « 1 fois », vide = non renouvelable). */
  renouvellement: string;
  instructions: string;
  /** Mentions réglementaires (temps d'attente, catégorie…) saisies par le vétérinaire. */
  mentions: string;
  /** Quantité suggérée par le calcul (posologie × durée ÷ contenance) : tant
   *  que quantite lui est égale, elle est signalée « à vérifier ». */
  quantiteCalculee?: string;
  /** Médicament de la pharmacie marqué stupéfiant. */
  stupefiant?: boolean;
}

/** Article de la pharmacie (migration_pharmacie_ordonnance.sql). */
export interface ArticleOrdo {
  nom: string; presentation?: string | null; principe_actif?: string | null;
  contenance?: number | null; contenance_unite?: string | null; voie?: string | null;
  instructions?: string | null; mentions?: string | null; stupefiant?: boolean | null;
}

export const COLONNES_ARTICLE_ORDO = 'nom, presentation, principe_actif, contenance, contenance_unite, voie, instructions, mentions, stupefiant';

/** Article de même nom (sans tenir compte de la casse ni des accents). */
export function articleDe(nom: string, articles: ArticleOrdo[]): ArticleOrdo | null {
  const n = sansAccent(nom);
  return n ? articles.find(a => sansAccent(a.nom) === n) ?? null : null;
}

/** Champs vides de la ligne complétés par l'article (rien n'est écrasé). */
export function completerDepuisArticle(l: LigneOrdo, a: ArticleOrdo | null): LigneOrdo {
  if (!a) return l;
  const garde = (actuel: string, val?: string | null) => actuel.trim() ? actuel : String(val ?? '').trim();
  return {
    ...l,
    presentation: garde(l.presentation, a.presentation),
    principeActif: garde(l.principeActif, a.principe_actif),
    voie: garde(l.voie, a.voie),
    instructions: garde(l.instructions, a.instructions),
    mentions: garde(l.mentions, a.mentions),
    ...(a.stupefiant ? { stupefiant: true } : {}),
  };
}

function sansAccent(x: string) { return x.normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim().toLowerCase(); }

/** Unité de prise ramenée à une forme commune (cp, comprimés → comprime). */
function uniteCommune(u: string): string {
  const x = sansAccent(u).replace(/\.$/, '');
  if (/^(cp|cps|comp|comprime|comprimes)$/.test(x)) return 'comprime';
  if (/^(gel|gelule|gelules)$/.test(x)) return 'gelule';
  if (/^(ml|millilitre|millilitres)$/.test(x)) return 'ml';
  return x.replace(/s$/, '');
}

/** « 1 cp », « ½ cp », « 1,5 mL », « 1/2 comprimé » → { n, unite } ; null si incertain. */
function doseNumerique(d: string): { n: number; unite: string } | null {
  const m = /^\s*(\d+(?:[.,]\d+)?)?\s*(½|¼|¾|1\/2|1\/4|3\/4)?\s*([a-zA-ZÀ-ÿ.]+)\s*$/.exec(d);
  if (!m || (!m[1] && !m[2])) return null;
  const frac: Record<string, number> = { '½': 0.5, '¼': 0.25, '¾': 0.75, '1/2': 0.5, '1/4': 0.25, '3/4': 0.75 };
  const n = (m[1] ? parseFloat(m[1].replace(',', '.')) : 0) + (m[2] ? frac[m[2]] : 0);
  return n > 0 ? { n, unite: uniteCommune(m[3]) } : null;
}

/** Phase de traitement saisie dans le compte rendu. */
export interface PhasePosologie { dose: string; prises: string[]; frequenceJours: number; dureeJours: number | null; doses?: Record<string, string> }

/** Quantité à délivrer SUGGÉRÉE : seulement si toutes les doses sont des
 *  nombres dans l'unité de la boîte et que la durée est connue ; sinon ''. */
export function quantiteSuggeree(phases: PhasePosologie[], a: ArticleOrdo | null): string {
  if (!a?.contenance || !a.contenance_unite || !phases.length) return '';
  const unite = uniteCommune(a.contenance_unite);
  let total = 0;
  for (const p of phases) {
    if (!p.dureeJours || !p.prises.length) return '';
    const jours = Math.ceil(p.dureeJours / Math.max(1, p.frequenceJours));
    const doses = p.doses && p.prises.length > 1 ? p.prises.map(k => p.doses?.[k]?.trim() || p.dose) : p.prises.map(() => p.dose);
    for (const d of doses) {
      const x = doseNumerique(d);
      if (!x || x.unite !== unite) return '';
      total += x.n * jours;
    }
  }
  const boites = Math.ceil(total / a.contenance);
  const fmt = (n: number) => String(Math.round(n * 100) / 100).replace('.', ',');
  return `${boites} conditionnement${boites > 1 ? 's' : ''} de ${fmt(a.contenance)} ${a.contenance_unite} (${fmt(total)} ${a.contenance_unite} pour le traitement)`;
}

export interface ContenuOrdo { lignes: LigneOrdo[]; poids?: string; remarques?: string }

export type StatutOrdo = 'brouillon' | 'validee' | 'signee' | 'remplacee';

export interface OrdonnanceRow {
  id: string; date_emit: string | null; doc_url: string | null; notes: string | null; created_at?: string | null;
  pro_uid?: string | null; pro_profile_id?: string | null; animal_id?: string | null;
  owner_uid?: string | null; owner_profile_id?: string | null; rdv_id?: string | null;
  praticien_uid?: string | null; praticien_profile_id?: string | null;
  statut?: StatutOrdo | null; numero?: string | null; contenu?: ContenuOrdo | null; version?: number | null;
  remplace_id?: string | null; remplacee_par?: string | null; valide_le?: string | null;
  redige_par_uid?: string | null;
}

export const ligneVide = (): LigneOrdo => ({
  medicament: '', principeActif: '', presentation: '', posologie: '', voie: '', duree: '',
  quantite: '', renouvellement: '', instructions: '', mentions: '',
});

/** Lignes d'un contenu enregistré (champs manquants complétés à vide). */
export function lignesDe(c: ContenuOrdo | null | undefined): LigneOrdo[] {
  return (c?.lignes ?? []).map(l => ({ ...ligneVide(), ...l }));
}

export const VOIES = ['Orale', 'Cutanée', 'Auriculaire', 'Oculaire', 'Sous-cutanée', 'Intramusculaire', 'Intraveineuse', 'Rectale', 'Nasale'];

export const LIBELLE_STATUT: Record<StatutOrdo, string> = {
  brouillon: 'Brouillon', validee: 'Validée', signee: 'Signée', remplacee: 'Remplacée',
};

/** Espèces pouvant être destinées à la consommation humaine : le vétérinaire
 *  doit indiquer le temps d'attente ou l'exclusion. Les règles exactes
 *  (catégories, délais) restent à faire valider par un vétérinaire. */
const RENTE = ['bovin', 'vache', 'veau', 'taureau', 'ovin', 'mouton', 'brebis', 'agneau', 'caprin', 'chèvre', 'chevre',
  'porc', 'porcin', 'cochon', 'volaille', 'poule', 'coq', 'canard', 'oie', 'dinde', 'caille', 'pintade', 'lapin',
  'cheval', 'jument', 'poney', 'âne', 'ane', 'équidé', 'equide', 'mule', 'abeille', 'poisson'];
export function especeDeRente(espece?: string | null): boolean {
  const e = (espece ?? '').toLowerCase();
  return !!e && RENTE.some(r => e.includes(r));
}

/** Contrôles avant aperçu / validation. */
export function controlerOrdo(c: ContenuOrdo, espece?: string | null): { bloquants: string[]; avertissements: string[] } {
  const bloquants: string[] = [];
  const avertissements: string[] = [];
  const lignes = c.lignes.filter(l => Object.entries(l).some(([k, v]) => k !== 'stupefiant' && k !== 'quantiteCalculee' && String(v ?? '').trim()));
  if (!lignes.length) bloquants.push('Au moins un médicament');
  const rente = especeDeRente(espece);
  lignes.forEach((l, i) => {
    const n = `Ligne ${i + 1}${l.medicament.trim() ? ` (${l.medicament.trim()})` : ''}`;
    if (!l.medicament.trim()) bloquants.push(`${n} : médicament`);
    if (!l.posologie.trim()) bloquants.push(`${n} : posologie (dose, prises, fréquence)`);
    if (!l.duree.trim()) bloquants.push(`${n} : durée du traitement`);
    if (!l.voie.trim()) avertissements.push(`${n} : voie d'administration non précisée`);
    if (!l.quantite.trim()) avertissements.push(`${n} : quantité à délivrer non précisée`);
    else if (l.quantiteCalculee && l.quantite.trim() === l.quantiteCalculee) avertissements.push(`${n} : quantité calculée d'après la posologie et le conditionnement — à vérifier`);
    if (l.stupefiant) avertissements.push(`${n} : médicament classé stupéfiant — vérifiez les règles de prescription particulières`);
    if (rente && !l.mentions.trim()) avertissements.push(`${n} : espèce pouvant être destinée à la consommation — indiquez le temps d'attente ou l'exclusion dans les mentions réglementaires`);
  });
  return { bloquants, avertissements };
}

/** Contenu nettoyé (lignes vides retirées, espaces superflus). */
export function nettoyerOrdo(c: ContenuOrdo): ContenuOrdo {
  return {
    lignes: c.lignes
      .map(l => Object.fromEntries(Object.entries(l).map(([k, v]) => [k, typeof v === 'boolean' ? v : String(v ?? '').trim()])) as unknown as LigneOrdo)
      .filter(l => Object.entries(l).some(([k, v]) => k !== 'stupefiant' && k !== 'quantiteCalculee' && !!v)),
    ...(c.poids?.trim() ? { poids: c.poids.trim() } : {}),
    ...(c.remarques?.trim() ? { remarques: c.remarques.trim() } : {}),
  };
}

/** Résumé court (colonne notes, listes). */
export const resumeOrdo = (c: ContenuOrdo) => c.lignes.map(l => l.medicament).filter(Boolean).join(', ');
