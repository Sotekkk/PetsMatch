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

export function dureeRdvLabel(min: number) {
  return min < 60 ? `${min} min` : `${Math.floor(min / 60)}h${min % 60 ? String(min % 60).padStart(2, '0') : ''}`;
}

/** « Rex — Consultation · 30 min » */
export function ligneAnimalRdv(a: AnimalRdv) {
  const suite = [a.motif ?? '', a.duree_minutes ? dureeRdvLabel(a.duree_minutes) : ''].filter(Boolean).join(' · ');
  return [a.nom, suite].filter(Boolean).join(' — ');
}
