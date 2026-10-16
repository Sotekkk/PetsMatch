// Photographe — statuts des galeries (albums_photo.statut,
// migration_photographe_galeries_statut.sql). Miroir appli :
// lib/pages/pro/photographe_studio_dashboard.dart (styleGalerie).

export const STATUTS_GALERIE: Record<string, { label: string; fg: string; bg: string }> = {
  brouillon: { label: 'Brouillon', fg: '#4B5563', bg: '#F1F2F4' },
  partagee: { label: 'En attente de sélection', fg: '#1D4ED8', bg: '#E8F0FE' },
  selection_recue: { label: 'Sélection reçue', fg: '#D97706', bg: '#FFF4DC' },
  en_retouche: { label: 'En retouche', fg: '#7B5EA7', bg: '#F1ECF8' },
  livree: { label: 'Livrée', fg: '#2E7D5E', bg: '#E7F3EC' },
  archivee: { label: 'Archivée', fg: '#6B7280', bg: '#F3F4F6' },
};
export const styleGalerie = (s: string | null | undefined) => STATUTS_GALERIE[s ?? 'brouillon'] ?? STATUTS_GALERIE.brouillon;
/** Galeries dont la livraison finale reste à effectuer. */
export const GALERIES_A_LIVRER = new Set(['brouillon', 'partagee', 'selection_recue', 'en_retouche']);
