// Types de logement d'une pension (`enclos_chenil.type`, texte libre).
// Miroir de `kPensionLogementTypes` dans `lib/pages/pro/pension_tarifs_page.dart`.
// Box / Pré / Paddock d'abord (trio équin), puis les logements classiques.

export const PENSION_LOGEMENT_TYPES: { value: string; label: string }[] = [
  { value: 'box', label: 'Box' },
  { value: 'pre', label: 'Pré' },
  { value: 'paddock', label: 'Paddock' },
  { value: 'enclos', label: 'Enclos' },
  { value: 'parc', label: 'Parc' },
  { value: 'chatterie', label: 'Chatterie' },
  { value: 'cage', label: 'Cage' },
];

export const LOGEMENT_TYPE_LABEL: Record<string, string> =
  Object.fromEntries(PENSION_LOGEMENT_TYPES.map(t => [t.value, t.label]));

export function pensionLogementTypeLabel(type?: string | null): string {
  return LOGEMENT_TYPE_LABEL[(type ?? '').toLowerCase().trim()] ?? (type ?? '');
}
