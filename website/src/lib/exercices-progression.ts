// Exercices attribués (éducation / comportement) : durée et validation.
//  • étapes (etapes_snapshot) : validées une à une, dans l'ordre ;
//  • sinon nb_validations réussites, une par jour au plus (1 = « Marquer fait ») ;
//  • terminé (statut « fait ») au total atteint ; échéance = fin de la durée
//    (NULL = jusqu'à validation). Miroir appli : lib/utils/exercices_progression.dart.

export interface ExoValidable {
  statut: string;
  echeance?: string | null;
  etapes_snapshot?: { titre: string }[] | null;
  nb_validations?: number | null;
  validations?: string[] | null;
}

/** Durées proposées à l'attribution (jours ; null = jusqu'à validation). */
export const DUREES_EXERCICE: { label: string; jours: number | null }[] = [
  { label: '1 semaine', jours: 7 },
  { label: '2 semaines', jours: 14 },
  { label: '1 mois', jours: 30 },
  { label: "Jusqu'à validation", jours: null },
];
export const DUREE_DEFAUT_JOURS = 14;

const jourLocal = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

export function echeanceDans(jours: number | null, depuis = new Date()): string | null {
  if (jours == null) return null;
  const d = new Date(depuis);
  d.setDate(d.getDate() + jours);
  return jourLocal(d);
}

export function progression(ex: ExoValidable, maintenant = new Date()) {
  const etapes = (ex.etapes_snapshot ?? []).filter(e => e?.titre?.trim());
  const total = etapes.length || Math.max(1, ex.nb_validations ?? 1);
  const vals = ex.validations ?? [];
  const termine = ex.statut === 'fait';
  const faites = termine ? total : Math.min(total, vals.length);
  const aujourdhui = jourLocal(maintenant);
  const dejaAujourdhui = vals.includes(aujourdhui);
  const echue = !!ex.echeance && ex.echeance < aujourdhui && !termine;
  return {
    etapes, total, faites, termine, echue,
    /** Étapes : sans limite par jour ; réussites : une par jour. */
    peutValider: !termine && (etapes.length > 0 || !dejaAujourdhui),
    dejaAujourdhui: etapes.length === 0 && dejaAujourdhui,
    prochaineEtape: etapes[faites]?.titre ?? null,
  };
}

/** Mise à jour à enregistrer pour valider (étape / réussite) ou annuler la dernière. */
export function majValidation(ex: ExoValidable, action: 'valider' | 'annuler', maintenant = new Date()) {
  const p = progression(ex, maintenant);
  let vals = [...(ex.validations ?? [])];
  // Ancien « fait » sans historique : le compter comme complet pour pouvoir annuler.
  if (p.termine && vals.length < p.total) vals = Array.from({ length: p.total }, (_, i) => vals[i] ?? jourLocal(maintenant));
  if (action === 'valider') vals.push(jourLocal(maintenant));
  else vals.pop();
  const fait = vals.length >= p.total;
  return {
    validations: vals,
    statut: fait ? 'fait' : vals.length > 0 ? 'en_cours' : 'a_faire',
    termine_le: fait ? maintenant.toISOString() : null,
    updated_at: maintenant.toISOString(),
  };
}

/** Libellé de la durée : « jusqu'au 12 nov. », « durée écoulée », « jusqu'à validation ». */
export function libelleDuree(ex: ExoValidable, maintenant = new Date()) {
  const p = progression(ex, maintenant);
  if (p.termine) return null;
  if (!ex.echeance) return "Jusqu'à validation";
  if (p.echue) return 'Durée écoulée';
  return `Jusqu'au ${new Date(`${ex.echeance}T12:00:00`).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' })}`;
}
