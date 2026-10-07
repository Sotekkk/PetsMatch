// Types de salle et motifs de RDV vétérinaire — miroir de l'appli
// (salles_clinique_page.dart : kTypesSalle, kMotifsVeto) et du contrôle en
// base (pm_rdv_controle_clinique, migration_clinique_rdv.sql).
export const TYPES_SALLE = [
  { key: 'consultation', label: 'Consultation' },
  { key: 'chirurgie', label: 'Bloc opératoire' },
  { key: 'imagerie', label: 'Imagerie / radiologie' },
  { key: 'soins', label: 'Soins / hospitalisation' },
];

export const MOTIFS_VETO = [
  { key: 'consultation', label: 'Consultation' },
  { key: 'vaccination', label: 'Vaccination' },
  { key: 'bilan', label: 'Bilan annuel' },
  { key: 'urgence', label: 'Urgence' },
  { key: 'chirurgie', label: 'Chirurgie' },
  { key: 'autre', label: 'Autre' },
];

export function libelleTypeSalle(t: string): string {
  return TYPES_SALLE.find(x => x.key === t)?.label ?? t;
}

/** Clé de motif à partir du libellé saisi — même règle que pm_cle_motif (SQL). */
export function cleMotif(motif?: string | null): string {
  const m = (motif ?? '').toLowerCase();
  if (!m) return 'autre';
  if (m.includes('chirurg')) return 'chirurgie';
  if (m.includes('vaccin')) return 'vaccination';
  if (m.includes('urgen')) return 'urgence';
  if (m.includes('bilan')) return 'bilan';
  if (m.includes('domicile')) return 'visite_domicile';
  if (m.includes('consult')) return 'consultation';
  return 'autre';
}
