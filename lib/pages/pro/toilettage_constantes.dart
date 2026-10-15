// Toilettage — listes partagées (fiche technique de prestation, fiche
// animal, compte rendu côté propriétaire). Miroir site :
// website/src/lib/toilettage.ts.

/// Travaux réalisés pendant une prestation (fiche technique).
const List<(String, String)> kTravauxToilettage = [
  ('bain', 'Bain'),
  ('shampooing', 'Shampooing'),
  ('sechage', 'Séchage'),
  ('brossage', 'Brossage'),
  ('demelage', 'Démêlage'),
  ('epilation', 'Épilation / trimming'),
  ('tonte', 'Tonte'),
  ('coupe_ciseaux', 'Coupe aux ciseaux'),
  ('griffes', 'Coupe des griffes'),
  ('oreilles', 'Nettoyage des oreilles'),
  ('yeux', 'Soin des yeux'),
  ('coussinets', 'Coussinets'),
  ('hygiene', 'Zones d\'hygiène'),
  ('glandes', 'Glandes anales'),
  ('parfum', 'Parfum / finition'),
];

String labelTravailToilettage(String k) =>
    kTravauxToilettage.firstWhere((t) => t.$1 == k, orElse: () => (k, k)).$2;

/// Coopération de l'animal pendant la prestation.
const List<(String, String)> kCooperationToilettage = [
  ('tres_cooperatif', 'Très coopératif'),
  ('cooperatif', 'Coopératif'),
  ('stresse', 'Stressé'),
  ('difficile', 'Difficile à manipuler'),
  ('agressif', 'Agressif'),
];

String labelCooperationToilettage(String? k) =>
    kCooperationToilettage.firstWhere((t) => t.$1 == k, orElse: () => ('', k ?? '')).$2;

/// Tolérance au séchoir (consignes permanentes).
const List<(String, String)> kToleranceSechoir = [
  ('bonne', 'Bonne'),
  ('moyenne', 'Moyenne'),
  ('faible', 'Faible — séchage doux'),
  ('aucune', 'Aucune — séchage serviette'),
];

String labelToleranceSechoir(String? k) =>
    kToleranceSechoir.firstWhere((t) => t.$1 == k, orElse: () => ('', k ?? '')).$2;
