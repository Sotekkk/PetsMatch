// Composition en pourcentages (BARF…) qui doit toujours faire 100 % : la part
// modifiée prend la valeur choisie, les autres se partagent le reste au prorata
// de leurs valeurs actuelles (à parts égales si toutes à 0).
// Miroir appli : lib/utils/repartition.dart.
export function repartir100<K extends string>(parts: Record<K, number>, cle: K, valeur: number): Record<K, number> {
  const v = Math.min(100, Math.max(0, valeur));
  const autres = (Object.keys(parts) as K[]).filter(k => k !== cle);
  const reste = 100 - v;
  const somme = autres.reduce((s, k) => s + (parts[k] ?? 0), 0);
  const res = { ...parts, [cle]: v } as Record<K, number>;
  for (const k of autres) res[k] = somme <= 0 ? reste / autres.length : (parts[k] / somme) * reste;
  for (const k of Object.keys(res) as K[]) res[k] = Math.round(res[k]);
  const ecart = 100 - (Object.values(res) as number[]).reduce((s, x) => s + x, 0);
  if (ecart && autres.length) {
    const k = autres.reduce((a, b) => (res[a] >= res[b] ? a : b));
    res[k] += ecart;
  }
  return res;
}
