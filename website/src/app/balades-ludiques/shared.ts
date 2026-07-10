export const ESPECES = [
  { value: 'tous', label: 'Toutes espèces', emoji: '🐾' },
  { value: 'chien', label: 'Chien', emoji: '🐕' },
  { value: 'chat', label: 'Chat', emoji: '🐈' },
  { value: 'cheval', label: 'Cheval', emoji: '🐴' },
];

export const DIFFICULTES = [
  { value: 'facile', label: 'Facile', color: '#6E9E57' },
  { value: 'modere', label: 'Modéré', color: '#F59E0B' },
  { value: 'difficile', label: 'Difficile', color: '#DC2626' },
];

export const TYPES_DEFI = [
  { value: 'photo', label: 'Photo', icon: '📷' },
  { value: 'question', label: 'Question', icon: '❓' },
  { value: 'objet_nature', label: 'Objet / élément naturel', icon: '🌿' },
  { value: 'action_animal', label: 'Action avec son animal', icon: '🐾' },
  { value: 'qr_code', label: 'QR code', icon: '📱' },
  { value: 'gps_seul', label: 'Localisation GPS', icon: '📍' },
];

export function especeLabel(v?: string) {
  return ESPECES.find(e => e.value === v)?.label ?? v ?? '';
}
export function especeEmoji(v?: string) {
  return ESPECES.find(e => e.value === v)?.emoji ?? '🐾';
}
export function difficulteLabel(v?: string) {
  return DIFFICULTES.find(d => d.value === v)?.label ?? v ?? '';
}
export function difficulteColor(v?: string) {
  return DIFFICULTES.find(d => d.value === v)?.color ?? '#0C5C6C';
}
export function typeDefiLabel(v?: string) {
  return TYPES_DEFI.find(t => t.value === v)?.label ?? v ?? '';
}
export function typeDefiIcon(v?: string) {
  return TYPES_DEFI.find(t => t.value === v)?.icon ?? '🚩';
}
export function dureeLabel(min?: number | null) {
  if (min == null) return '';
  if (min < 60) return `${min} min`;
  const h = Math.floor(min / 60);
  const r = min % 60;
  return r === 0 ? `${h}h` : `${h}h${String(r).padStart(2, '0')}`;
}
