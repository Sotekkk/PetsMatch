// Confirmation de suppression d'une entrée du carnet de santé, précise :
// « Supprimer ce vaccin « Nobivac » ? » plutôt que « cette entrée ».
// Miroir appli : lib/utils/sante_suppression.dart.

const LIBELLES: Record<string, string> = {
  vaccinations: 'ce vaccin',
  vermifuges: 'ce vermifuge',
  antiparasitaires: 'cet antiparasitaire',
  traitements: 'ce traitement',
  chirurgies: 'cette chirurgie / hospitalisation',
  allergies: 'cette allergie',
  poids: 'cette pesée',
  visites: 'cette visite vétérinaire',
  radios: 'cette radio / imagerie',
  tests_genetiques: 'ce test génétique',
};

/** Nom lisible d'une entrée (vaccin, produit, nom, intitulé…). */
export function nomEntreeSante(r?: Record<string, unknown> | null): string {
  if (!r) return '';
  const v = r.vaccin ?? r.produit ?? r.nom ?? r.intitule ?? r.description ?? r.motif ?? r.titre
    ?? (r.valeur != null ? `${r.valeur} kg` : '');
  return String(v ?? '').trim();
}

/** « Supprimer ce vaccin « Nobivac » ? Cette action est irréversible. » */
export function messageSuppressionSante(table: string, nom?: string | null): string {
  const quoi = LIBELLES[table] ?? 'cette entrée du carnet';
  const n = (nom ?? '').trim();
  return `Supprimer ${quoi}${n ? ` « ${n} »` : ''} ? Cette action est irréversible.`;
}
