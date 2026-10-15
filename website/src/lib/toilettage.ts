// Toilettage — listes partagées (fiche technique, fiche animal, compte rendu
// côté propriétaire). Miroir appli : lib/pages/pro/toilettage_constantes.dart.

export const TRAVAUX_TOILETTAGE: [string, string][] = [
  ['bain', 'Bain'],
  ['shampooing', 'Shampooing'],
  ['sechage', 'Séchage'],
  ['brossage', 'Brossage'],
  ['demelage', 'Démêlage'],
  ['epilation', 'Épilation / trimming'],
  ['tonte', 'Tonte'],
  ['coupe_ciseaux', 'Coupe aux ciseaux'],
  ['griffes', 'Coupe des griffes'],
  ['oreilles', 'Nettoyage des oreilles'],
  ['yeux', 'Soin des yeux'],
  ['coussinets', 'Coussinets'],
  ['hygiene', "Zones d'hygiène"],
  ['glandes', 'Glandes anales'],
  ['parfum', 'Parfum / finition'],
];
export const labelTravail = (k: string) => TRAVAUX_TOILETTAGE.find(t => t[0] === k)?.[1] ?? k;

export const COOPERATION_TOILETTAGE: [string, string][] = [
  ['tres_cooperatif', 'Très coopératif'],
  ['cooperatif', 'Coopératif'],
  ['stresse', 'Stressé'],
  ['difficile', 'Difficile à manipuler'],
  ['agressif', 'Agressif'],
];
export const labelCooperation = (k: string | null | undefined) => COOPERATION_TOILETTAGE.find(t => t[0] === k)?.[1] ?? (k ?? '');

export const TOLERANCE_SECHOIR: [string, string][] = [
  ['bonne', 'Bonne'],
  ['moyenne', 'Moyenne'],
  ['faible', 'Faible — séchage doux'],
  ['aucune', 'Aucune — séchage serviette'],
];
export const labelTolerance = (k: string | null | undefined) => TOLERANCE_SECHOIR.find(t => t[0] === k)?.[1] ?? (k ?? '');

/** Étape d'une prestation (rdv) — miroir appli etapeToilettage. */
export type EtapeToilettage = 'aConfirmer' | 'attendu' | 'arrive' | 'enCours' | 'pret' | 'termine' | 'annule' | 'absent';
export interface RdvEtape {
  statut: string; arrivee_validee_le?: string | null; prestation_debut_le?: string | null; pret_le?: string | null;
}
export function etapeToilettage(r: RdvEtape): EtapeToilettage {
  if (r.statut === 'demande' || r.statut === 'contre_proposition') return 'aConfirmer';
  if (r.statut === 'annule' || r.statut === 'refuse') return 'annule';
  if (r.statut === 'absent') return 'absent';
  if (r.statut === 'termine') return 'termine';
  if (r.pret_le) return 'pret';
  if (r.prestation_debut_le) return 'enCours';
  if (r.arrivee_validee_le) return 'arrive';
  return 'attendu';
}
export const STYLE_ETAPE: Record<EtapeToilettage, { label: string; fg: string; bg: string }> = {
  aConfirmer: { label: 'À confirmer', fg: '#D97706', bg: '#FFF4DC' },
  attendu: { label: 'Confirmé', fg: '#1D4ED8', bg: '#E8F0FE' },
  arrive: { label: 'Animal arrivé', fg: '#7B5EA7', bg: '#F1ECF8' },
  enCours: { label: 'En cours', fg: '#0C5C6C', bg: '#E6F2F3' },
  pret: { label: 'Prêt à récupérer', fg: '#2E7D5E', bg: '#E7F3EC' },
  termine: { label: 'Terminé', fg: '#4B5563', bg: '#F1F2F4' },
  annule: { label: 'Annulé', fg: '#6B7280', bg: '#F3F4F6' },
  absent: { label: 'Non présenté', fg: '#B3261E', bg: '#FDECEA' },
};
