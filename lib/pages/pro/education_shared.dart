import 'package:flutter/material.dart';

/// Constantes partagées du module de suivi éducateur (objectifs, exercices…).

const kEduCategories = <String, String>{
  'rappel': 'Rappel',
  'laisse': 'Marche en laisse',
  'proprete': 'Propreté',
  'aboiements': 'Aboiements',
  'destruction': 'Destruction',
  'socialisation_chien': 'Socialisation chiens',
  'socialisation_humain': 'Socialisation humains',
  'manipulation': 'Manipulation / soins',
  'solitude': 'Solitude',
  'agressivite': 'Agressivité',
  'peurs': 'Peurs',
  'autre': 'Autre',
};

const kEduObjectifStatuts = ['a_travailler', 'en_cours', 'acquis'];
const kEduObjectifStatutLabels = <String, String>{
  'a_travailler': 'À travailler',
  'en_cours': 'En cours',
  'acquis': 'Acquis',
};
Color eduObjectifStatutColor(String s) => switch (s) {
      'acquis' => const Color(0xFF6E9E57),
      'en_cours' => const Color(0xFFEFA100),
      _ => const Color(0xFFD5573B),
    };

const kEduExerciceStatutLabels = <String, String>{
  'a_faire': 'À faire',
  'en_cours': 'En cours',
  'fait': 'Fait',
  'abandonne': 'Abandonné',
};

const kEduOrange = Color(0xFFEF6C00);
