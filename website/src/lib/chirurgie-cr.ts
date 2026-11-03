// Comptes rendus préopératoire et opératoire d'une intervention
// (migration_chirurgies_cr.sql) : champs, préremplissage depuis la fiche
// chirurgie, contrôles, texte du PDF. Seuls les champs saisis apparaissent :
// rien n'est affirmé par défaut (pas de « aucune complication » d'office).
// Miroir appli : lib/utils/chirurgie_cr.dart.

export type TypeCrChir = 'preop' | 'operatoire';

/** [clé, libellé, texte long]. */
export const CHAMPS_CR_CHIR: Record<TypeCrChir, [string, string, boolean][]> = {
  preop: [
    ['intervention', 'Intervention prévue', false],
    ['date_prevue', 'Date prévue de l’opération', false],
    ['antecedents', 'Antécédents pertinents', true],
    ['examen_clinique', 'Examen clinique', true],
    ['poids', 'Poids (kg)', false],
    ['evaluation_anesthesique', 'Évaluation préanesthésique', true],
    ['examens', 'Examens réalisés', true],
    ['risques', 'Risques identifiés', true],
    ['protocole', 'Protocole préopératoire', true],
    ['observations', 'Observations', true],
    ['decision', 'Décision et recommandations', true],
  ],
  operatoire: [
    ['intervention', "Nature de l'intervention", false],
    ['indication', 'Indication', true],
    ['anesthesie', "Type d'anesthésie", false],
    ['description', "Description de l'acte", true],
    ['gestes', 'Gestes chirurgicaux réalisés', true],
    ['observations', 'Observations', true],
    ['complications', 'Complications', true],
    ['soins', 'Soins administrés', true],
    ['etat_fin', "État de l'animal en fin d'intervention", true],
    ['surveillance', 'Surveillance postopératoire', true],
    ['traitements', 'Traitements prescrits', true],
    ['controles', 'Contrôles recommandés', true],
    ['prochain_rdv', 'Prochain rendez-vous', false],
  ],
};

export const TITRE_CR_CHIR: Record<TypeCrChir, string> = {
  preop: 'Compte rendu préopératoire', operatoire: 'Compte rendu opératoire',
};

export interface DocCrChir { statut?: 'brouillon' | 'valide'; valide_le?: string; valide_par_uid?: string; version?: number; [k: string]: unknown }

export interface ChirurgieCr {
  id: string; date: string; intitule: string; type: string | null;
  protocole_preop: string | null; protocole_postop: string | null;
  preop?: DocCrChir | null; operatoire?: DocCrChir | null;
  preop_doc_url?: string | null; operatoire_doc_url?: string | null;
  /** Consignes postopératoires (migration_consignes_postop.sql). */
  consignes?: (DocCrChir & { sections?: { titre: string; texte: string }[] }) | null;
  consignes_doc_url?: string | null;
  pro_uid?: string | null; pro_profile_id?: string | null;
}

export const valeur = (d: DocCrChir | null | undefined, k: string) => String(d?.[k] ?? '').trim();

/** Champs de départ : saisie existante, sinon données déjà enregistrées. */
export function prerempli(type: TypeCrChir, c: ChirurgieCr, poidsFiche?: number | string | null): Record<string, string> {
  const d = c[type];
  const out: Record<string, string> = {};
  for (const [k] of CHAMPS_CR_CHIR[type]) out[k] = valeur(d, k);
  if (!out.intervention) out.intervention = c.intitule ?? '';
  if (type === 'preop' && !out.date_prevue && c.date) out.date_prevue = c.date.slice(0, 10);
  if (type === 'preop' && !out.protocole) out.protocole = c.protocole_preop ?? '';
  if (type === 'preop' && !out.poids && poidsFiche != null && String(poidsFiche).trim()) out.poids = String(poidsFiche);
  if (type === 'operatoire' && !out.surveillance) out.surveillance = c.protocole_postop ?? '';
  return out;
}

export function controlerCrChir(type: TypeCrChir, champs: Record<string, string>): { bloquants: string[]; avertissements: string[] } {
  const bloquants: string[] = [], avertissements: string[] = [];
  const rempli = (k: string) => !!champs[k]?.trim();
  if (!rempli('intervention')) bloquants.push(type === 'preop' ? 'Intervention prévue' : "Nature de l'intervention");
  if (type === 'preop') {
    if (!CHAMPS_CR_CHIR.preop.some(([k]) => k !== 'intervention' && rempli(k))) bloquants.push('Au moins une information clinique');
    if (!rempli('decision')) avertissements.push('Décision et recommandations non renseignées');
  } else {
    if (!rempli('description')) bloquants.push("Description de l'acte");
    if (!rempli('anesthesie')) avertissements.push("Type d'anesthésie non renseigné");
    if (!rempli('complications')) avertissements.push('Complications non renseignées : le document n’indiquera rien à ce sujet (il n’affirme pas leur absence)');
    if (!rempli('etat_fin')) avertissements.push("État de l'animal en fin d'intervention non renseigné");
  }
  return { bloquants, avertissements };
}

/** Texte du PDF (« Libellé : valeur » par paragraphe, champs vides omis). */
export function texteCrChir(type: TypeCrChir, champs: Record<string, string>, dateIntervention?: string | null): string {
  const lignes: string[] = [];
  // Pré-op : la date figure dans « Date prévue de l'opération ».
  if (dateIntervention && !(type === 'preop' && champs.date_prevue?.trim())) lignes.push(`Date de l'intervention : ${new Date(`${dateIntervention.slice(0, 10)}T12:00:00`).toLocaleDateString('fr-FR')}`);
  for (const [k, l] of CHAMPS_CR_CHIR[type]) {
    const v = champs[k]?.trim();
    if (!v) continue;
    const val = k === 'poids' ? `${v.replace('.', ',')} kg`
      : k === 'date_prevue' && /^\d{4}-\d{2}-\d{2}/.test(v) ? new Date(`${v.slice(0, 10)}T12:00:00`).toLocaleDateString('fr-FR') : v;
    lignes.push(`${l.replace(/\s*\(kg\)$/, '')} : ${val}`);
  }
  if (type === 'preop') lignes.push("Ce compte rendu ne vaut pas consentement du propriétaire à l'intervention.");
  return lignes.join('\n\n');
}
