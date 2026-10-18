// Poids d'un animal en kg (animaux.poids est NUMERIC) : saisie libre
// (« 8,1 », « 12 kg », vide) → nombre ou null. Miroir appli : poidsKg() dans
// lib/utils/poids.dart.
export function poidsKg(v: unknown): number | null {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  const s = String(v ?? '').trim().toLowerCase().replace(/\s*kg$/, '').replace(',', '.');
  if (!/^\d+(\.\d+)?$/.test(s)) return null;
  return Number(s);
}
