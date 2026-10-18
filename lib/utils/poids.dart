// Poids d'un animal en kg (animaux.poids est NUMERIC) : saisie libre
// (« 8,1 », « 12 kg », vide) ou valeur lue en base (nombre, ou texte pour les
// anciennes données) → nombre ou null. Miroir site : website/src/lib/poids.ts.
double? poidsKg(Object? v) {
  if (v is num) return v.toDouble();
  final s = (v?.toString() ?? '').trim().toLowerCase().replaceFirst(RegExp(r'\s*kg$'), '').replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(s)) return null;
  return double.tryParse(s);
}
