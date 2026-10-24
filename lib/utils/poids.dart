// Poids d'un animal en kg (animaux.poids est NUMERIC) : saisie libre
// (« 8,1 », « 12 kg », vide) ou valeur lue en base (nombre, ou texte pour les
// anciennes données) → nombre ou null. Miroir site : website/src/lib/poids.ts.
double? poidsKg(Object? v) {
  if (v is num) return v.toDouble();
  final s = (v?.toString() ?? '').trim().toLowerCase().replaceFirst(RegExp(r'\s*kg$'), '').replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(s)) return null;
  return double.tryParse(s);
}

/// Poids maximal plausible par espèce (kg) : au-delà, c'est presque toujours
/// une erreur d'unité (grammes saisis en kg) ou de frappe.
const kPoidsMaxEspece = <String, double>{
  'chien': 120, 'chat': 15, 'lapin': 12, 'oiseau': 20, 'nac': 250,
  'cheval': 1500, 'ane': 500, 'ovin': 200, 'caprin': 150, 'porcin': 400, 'bovin': 1500,
};

/// Message d'erreur d'une saisie de poids, ou null si elle est valide (ou vide).
/// Accepte « 8.5 », « 8,5 », « 12 kg ». `unite` 'g' : la saisie est en grammes.
/// Miroir site : erreurPoids (website/src/lib/poids.ts).
String? erreurPoids(String? saisie, {String? espece, String unite = 'kg'}) {
  final brut = (saisie ?? '').trim();
  if (brut.isEmpty) return null;
  final s = brut.toLowerCase().replaceFirst(RegExp(r'\s*(kg|g)$'), '').replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(s)) {
    return 'Poids invalide : chiffres uniquement, avec . ou , pour les décimales (ex. 8,5).';
  }
  final v = double.parse(s);
  if (v <= 0) return 'Le poids doit être supérieur à 0.';
  final kg = unite == 'g' ? v / 1000 : v;
  final max = kPoidsMaxEspece[espece];
  if (max != null && kg > max) {
    final n = kg == kg.roundToDouble() ? kg.toStringAsFixed(0) : kg.toString();
    return 'Poids incohérent pour un ${espece == 'nac' ? 'NAC' : espece} : $n kg (maximum ${max.toStringAsFixed(0)} kg). '
        'Vérifiez l\'unité (kg ou g).';
  }
  if (kg > 2000) return 'Poids incohérent (plus de 2 000 kg). Vérifiez l\'unité (kg ou g).';
  return null;
}
