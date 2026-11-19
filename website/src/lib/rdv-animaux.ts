// RDV à plusieurs animaux (vétérinaire, ostéo, toiletteur, éducateur) :
// rdv.animaux_detail = [{ id, nom, motif, motif_cle, duree_minutes, prestation_id?, prix? }]
// (migration_rdv_animaux_detail.sql). rdv.animal_id = le premier animal,
// rdv.duree_minutes = la somme des durées. Miroir appli : lib/utils/rdv_animaux.dart.

export interface AnimalRdv {
  id: string; nom: string; motif?: string | null; motif_cle?: string | null;
  duree_minutes?: number | null; prestation_id?: string | null; prix?: number | null;
}

/** Détail par animal — vide pour un RDV à un seul animal. */
export function animauxDetailRdv(rdv: { animaux_detail?: unknown }): AnimalRdv[] {
  const d = rdv.animaux_detail;
  if (!Array.isArray(d) || d.length < 2) return [];
  return d.filter((x): x is AnimalRdv => !!x && typeof x === 'object').map(x => ({ ...x, id: String(x.id) }));
}

/** Animaux dont on peut ouvrir la fiche : détail du RDV, sinon animaux_ids
 *  (visite de pension, garde : noms repris de « Azur + Loup Gris »). Vide pour un seul animal.
 *  Miroir appli : animauxFichesRdv (rdv_animaux.dart). */
export function animauxFichesRdv(rdv: { animaux_detail?: unknown; animaux_ids?: unknown; animal_nom_manuel?: string | null }): { id: string; nom: string; motif?: string | null }[] {
  const d = animauxDetailRdv(rdv);
  if (d.length) return d.map(a => ({ id: a.id, nom: a.nom ?? 'Animal', motif: a.motif ?? null }));
  const ids = Array.isArray(rdv.animaux_ids) ? [...new Set(rdv.animaux_ids.filter(Boolean).map(String))] : [];
  if (ids.length < 2) return [];
  const noms = (rdv.animal_nom_manuel ?? '').split(' + ').map(n => n.trim()).filter(Boolean);
  return ids.map((id, i) => ({ id, nom: noms.length === ids.length ? noms[i] : `Animal ${i + 1}` }));
}

export function dureeRdvLabel(min: number) {
  return min < 60 ? `${min} min` : `${Math.floor(min / 60)}h${min % 60 ? String(min % 60).padStart(2, '0') : ''}`;
}

/** « Rex — Consultation · 30 min » */
export function ligneAnimalRdv(a: AnimalRdv) {
  const suite = [a.motif ?? '', a.duree_minutes ? dureeRdvLabel(a.duree_minutes) : ''].filter(Boolean).join(' · ');
  return [a.nom, suite].filter(Boolean).join(' — ');
}
