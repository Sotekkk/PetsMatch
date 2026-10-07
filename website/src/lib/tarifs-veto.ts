// Grille de tarifs du vétérinaire (user_profiles.tarifs_veto) — miroir de
// lib/utils/tarifs_veto.dart (appli). Stérilisations chien par tranche de
// poids : le tarif dépend du gabarit.
export const TARIFS_VETO_GROUPES: { groupe: string; items: { key: string; label: string }[] }[] = [
  { groupe: 'Consultations', items: [
    { key: 'consultation', label: 'Consultation' },
    { key: 'consultation_urgence', label: "Consultation d'urgence" },
    { key: 'visite_domicile', label: 'Visite à domicile' },
  ] },
  { groupe: 'Vaccins & identification', items: [
    { key: 'vaccin_chien', label: 'Vaccin chien' },
    { key: 'vaccin_chat', label: 'Vaccin chat' },
    { key: 'identification', label: 'Identification (puce)' },
  ] },
  { groupe: 'Stérilisation chat', items: [
    { key: 'castration_chat', label: 'Castration chat' },
    { key: 'sterilisation_chatte', label: 'Stérilisation chatte' },
  ] },
  { groupe: 'Castration chien (selon le poids)', items: [
    { key: 'castration_chien_10', label: 'Moins de 10 kg' },
    { key: 'castration_chien_25', label: '10 à 25 kg' },
    { key: 'castration_chien_45', label: '25 à 45 kg' },
    { key: 'castration_chien_45p', label: 'Plus de 45 kg' },
  ] },
  { groupe: 'Stérilisation chienne (selon le poids)', items: [
    { key: 'sterilisation_chienne_10', label: 'Moins de 10 kg' },
    { key: 'sterilisation_chienne_25', label: '10 à 25 kg' },
    { key: 'sterilisation_chienne_45', label: '25 à 45 kg' },
    { key: 'sterilisation_chienne_45p', label: 'Plus de 45 kg' },
  ] },
];

/** Libellé complet (« Castration chien — 10 à 25 kg »). */
export function libelleTarifVeto(groupe: string, label: string): string {
  return groupe.includes('(selon le poids)') ? `${groupe.replace(' (selon le poids)', '')} — ${label}` : label;
}
