/// Catégories des petites annonces « objets & matériel » liées aux animaux
/// (profil particulier). Aucune catégorie ne concerne un animal vivant.
///
/// Doit rester aligné avec `website/src/lib/annonce-objet-categories.ts`.
class AnnonceObjetCategorie {
  final String slug;
  final String label;
  final String emoji;
  final String exemples;
  const AnnonceObjetCategorie(this.slug, this.label, this.emoji, this.exemples);
}

const kAnnonceObjetCategories = <AnnonceObjetCategorie>[
  AnnonceObjetCategorie('habitat', 'Habitat & cage', '🏠',
      'Cage, clapier, volière, aquarium, terrarium, niche, box, abri'),
  AnnonceObjetCategorie('accessoires', 'Accessoires', '🦮',
      'Harnais, laisse, collier, gamelle, sac de transport, jouets, couchage'),
  AnnonceObjetCategorie('alimentation', 'Alimentation & fourrage', '🌾',
      'Foin, paille, granulés, litière, compléments'),
  AnnonceObjetCategorie('entretien', 'Entretien & soin', '✂️',
      'Matériel de toilettage, tondeuse, pharmacie, brosses'),
  AnnonceObjetCategorie('terrain', 'Terrain & pâture', '🌳',
      'Location de prairie, parcelle, pré, box en écurie, stabulation, pension'),
  AnnonceObjetCategorie('materiel_agricole', 'Matériel agricole', '🚜',
      "Tracteur, remorque, clôture, abreuvoir, matériel d'élevage"),
  AnnonceObjetCategorie('autre', 'Autre (lié aux animaux)', '📦',
      'Tout autre objet ou service lié aux animaux (pas un animal)'),
];

const kAnnonceObjetTransactions = <String, String>{
  'vente': 'Vente',
  'location': 'Location',
  'don': 'Don',
  'recherche': 'Recherche',
};

const kAnnonceObjetEtats = <String, String>{
  'neuf': 'Neuf',
  'tres_bon': 'Très bon état',
  'bon': 'Bon état',
  'usage': 'État d\'usage',
};

String annonceObjetCategorieLabel(String? slug) {
  for (final c in kAnnonceObjetCategories) {
    if (c.slug == slug) return c.label;
  }
  return 'Autre';
}

String annonceObjetCategorieEmoji(String? slug) {
  for (final c in kAnnonceObjetCategories) {
    if (c.slug == slug) return c.emoji;
  }
  return '📦';
}

/// Libellé de prix affichable pour une ligne `annonces_objets`.
String annonceObjetPrixLabel(Map<String, dynamic> r) {
  final t = (r['type_transaction'] ?? 'vente').toString();
  if (t == 'don') return 'Don';
  if (t == 'recherche') return 'Recherche';
  final p = r['prix'];
  if (p == null) return 'Prix à convenir';
  final unite = (r['prix_unite'] ?? '').toString();
  final neg = r['prix_negociable'] == true ? ' (négociable)' : '';
  return '${(p as num).toStringAsFixed(0)} €$unite$neg';
}

/// Le boost d'une annonce objet est-il encore actif ?
bool annonceObjetBoostActif(dynamic boostUntil) {
  final s = boostUntil?.toString();
  if (s == null || s.isEmpty) return false;
  final d = DateTime.tryParse(s);
  return d != null && d.isAfter(DateTime.now());
}
