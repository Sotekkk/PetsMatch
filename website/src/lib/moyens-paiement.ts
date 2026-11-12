// Moyens de paiement acceptés par un pro (user_profiles.moyens_paiement),
// cochés dans son profil ; affichés sur sa fiche, à la prise de RDV et dans le
// RDV du client (avec le RIB si virement — RPC pm_rib_pro).
// Miroir appli : lib/utils/moyens_paiement.dart.
export const MOYENS_PAIEMENT = [
  { value: 'especes', label: 'Espèces' },
  { value: 'cheque', label: 'Chèque' },
  { value: 'cb', label: 'Carte bancaire' },
  { value: 'virement', label: 'Virement' },
] as const;

export function moyensPaiement(v: unknown): string[] {
  return Array.isArray(v) ? v.map(String).filter(x => MOYENS_PAIEMENT.some(m => m.value === x)) : [];
}

export function libelleMoyens(v: unknown): string {
  const l = moyensPaiement(v);
  return MOYENS_PAIEMENT.filter(m => l.includes(m.value)).map(m => m.label).join(', ');
}
