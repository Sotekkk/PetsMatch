import 'package:flutter/material.dart';

/// Couleurs fonctionnelles des rubriques du carnet de santé : une même
/// couleur pour la rubrique, son action « Ajouter » et ses rappels / tâches
/// dans l'agenda. Miroir site : website/src/lib/sante-couleurs.ts.
class SanteCouleurs {
  static const vaccinations     = Color(0xFF2196F3);
  static const vermifuges       = Color(0xFF6E9E57);
  static const antiparasitaires = Color(0xFF5B8648);
  static const traitements      = Color(0xFF8D6E63);
  static const chirurgies       = Color(0xFFC2185B);
  static const allergies        = Color(0xFFE25C5C);
  static const poids            = Color(0xFF5F9EAA);
  static const visites          = Color(0xFF26A69A);

  /// Type d'acte (agenda / protocoles) → couleur de la rubrique, ou null.
  static Color? pourActe(String? acte) => switch (acte) {
        'vaccination'     => vaccinations,
        'vermifuge'       => vermifuges,
        'antiparasitaire' => antiparasitaires,
        'traitement'      => traitements,
        _                 => null,
      };
}
