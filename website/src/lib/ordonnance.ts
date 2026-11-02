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
  const lignes = c.lignes.filter(l => Object.values(l).some(v => String(v ?? '').trim()));
  if (!lignes.length) bloquants.push('Au moins un médicament');
  const rente = especeDeRente(espece);
  lignes.forEach((l, i) => {
    const n = `Ligne ${i + 1}${l.medicament.trim() ? ` (${l.medicament.trim()})` : ''}`;
    if (!l.medicament.trim()) bloquants.push(`${n} : médicament`);
    if (!l.posologie.trim()) bloquants.push(`${n} : posologie (dose, prises, fréquence)`);
    if (!l.duree.trim()) bloquants.push(`${n} : durée du traitement`);
    if (!l.voie.trim()) avertissements.push(`${n} : voie d'administration non précisée`);
    if (!l.quantite.trim()) avertissements.push(`${n} : quantité à délivrer non précisée`);
    if (rente && !l.mentions.trim()) avertissements.push(`${n} : espèce pouvant être destinée à la consommation — indiquez le temps d'attente ou l'exclusion dans les mentions réglementaires`);
  });
  return { bloquants, avertissements };
}

/** Contenu nettoyé (lignes vides retirées, espaces superflus). */
export function nettoyerOrdo(c: ContenuOrdo): ContenuOrdo {
  return {
    lignes: c.lignes
      .map(l => Object.fromEntries(Object.entries(l).map(([k, v]) => [k, String(v ?? '').trim()])) as unknown as LigneOrdo)
      .filter(l => Object.values(l).some(Boolean)),
    ...(c.poids?.trim() ? { poids: c.poids.trim() } : {}),
    ...(c.remarques?.trim() ? { remarques: c.remarques.trim() } : {}),
  };
}

/** Résumé court (colonne notes, listes). */
export const resumeOrdo = (c: ContenuOrdo) => c.lignes.map(l => l.medicament).filter(Boolean).join(', ');
