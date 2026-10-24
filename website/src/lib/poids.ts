// Poids d'un animal en kg (animaux.poids est NUMERIC) : saisie libre
// (« 8,1 », « 12 kg », vide) → nombre ou null. Miroir appli : poidsKg() dans
// lib/utils/poids.dart.
export function poidsKg(v: unknown): number | null {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  const s = String(v ?? '').trim().toLowerCase().replace(/\s*kg$/, '').replace(',', '.');
  if (!/^\d+(\.\d+)?$/.test(s)) return null;
  return Number(s);
}

/** Poids maximal plausible par espèce (kg) : au-delà, c'est presque toujours
 *  une erreur d'unité (grammes saisis en kg) ou de frappe. */
export const POIDS_MAX_ESPECE: Record<string, number> = {
  chien: 120, chat: 15, lapin: 12, oiseau: 20, nac: 250,
  cheval: 1500, ane: 500, ovin: 200, caprin: 150, porcin: 400, bovin: 1500,
};

/** Message d'erreur d'une saisie de poids, ou null si elle est valide (ou
 *  vide). Accepte « 8.5 », « 8,5 », « 12 kg ». Miroir appli : erreurPoids
 *  (lib/utils/poids.dart). */
export function erreurPoids(saisie: unknown, espece?: string | null, unite: 'kg' | 'g' = 'kg'): string | null {
  if (typeof saisie === 'number') saisie = String(saisie);
  const brut = String(saisie ?? '').trim();
  if (!brut) return null;
  const s = brut.toLowerCase().replace(/\s*(kg|g)$/, '').replace(',', '.');
  if (!/^\d+(\.\d{1,3})?$/.test(s)) return 'Poids invalide : chiffres uniquement, avec . ou , pour les décimales (ex. 8,5).';
  const v = Number(s);
  if (v <= 0) return 'Le poids doit être supérieur à 0.';
  const kg = unite === 'g' ? v / 1000 : v;
  const max = espece ? POIDS_MAX_ESPECE[espece] : undefined;
  if (max !== undefined && kg > max) {
    return `Poids incohérent pour un ${espece === 'nac' ? 'NAC' : espece} : ${kg} kg (maximum ${max} kg). Vérifiez l’unité (kg ou g).`;
  }
  if (kg > 2000) return 'Poids incohérent (plus de 2 000 kg). Vérifiez l’unité (kg ou g).';
  return null;
}
