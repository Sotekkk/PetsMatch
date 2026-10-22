/// Composition en pourcentages (BARF, ration mixte…) qui doit toujours faire
/// 100 % : la part modifiée prend la valeur choisie, les autres se partagent le
/// reste au prorata de leurs valeurs actuelles (à parts égales si elles sont
/// toutes à 0). Miroir site : website/src/lib/repartition.ts.
Map<String, double> repartir100(Map<String, double> parts, String cle, double valeur) {
  final v = valeur.clamp(0, 100).toDouble();
  final autres = parts.keys.where((k) => k != cle).toList();
  final reste = 100 - v;
  final somme = autres.fold<double>(0, (s, k) => s + parts[k]!);
  final res = <String, double>{cle: v};
  for (final k in autres) {
    res[k] = somme <= 0 ? reste / autres.length : parts[k]! / somme * reste;
  }
  // Arrondi à l'unité en gardant un total exact de 100.
  final arrondis = {for (final e in res.entries) e.key: e.value.roundToDouble()};
  final ecart = 100 - arrondis.values.fold<double>(0, (s, x) => s + x);
  if (ecart != 0) {
    final k = autres.isEmpty ? cle : autres.reduce((a, b) => arrondis[a]! >= arrondis[b]! ? a : b);
    arrondis[k] = arrondis[k]! + ecart;
  }
  return arrondis;
}
