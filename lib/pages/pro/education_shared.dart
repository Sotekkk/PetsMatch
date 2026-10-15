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

// Statut d'un objectif : renseigné par le professionnel (aucun pourcentage
// de réussite calculé). migration_education_fiche.sql.
const kEduObjectifStatuts = ['a_travailler', 'en_cours', 'en_progression', 'acquis', 'a_reevaluer'];
const kEduObjectifStatutLabels = <String, String>{
  'a_travailler': 'À travailler',
  'en_cours': 'En cours',
  'en_progression': 'En progression',
  'acquis': 'Acquis selon évaluation',
  'a_reevaluer': 'À réévaluer',
};
Color eduObjectifStatutColor(String s) => switch (s) {
      'acquis' => const Color(0xFF6E9E57),
      'en_progression' => const Color(0xFF2E7D8C),
      'en_cours' => const Color(0xFFEFA100),
      'a_reevaluer' => const Color(0xFF7B5EA7),
      _ => const Color(0xFFD5573B),
    };

/// Types de séance (education_progression.type_seance).
const kEduTypesSeance = <String, String>{
  'bilan': 'Bilan initial',
  'individuelle': 'Séance individuelle',
  'collective': 'Séance collective',
  'domicile': 'Séance à domicile',
  'exterieur': 'Séance en extérieur',
  'suivi': 'Suivi comportemental',
};

const kEduExerciceStatutLabels = <String, String>{
  'a_faire': 'À faire',
  'en_cours': 'En cours',
  'fait': 'Fait',
  'abandonne': 'Abandonné',
};

const kEduOrange = Color(0xFFEF6C00);
