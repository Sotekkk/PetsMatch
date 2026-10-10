/// Catégories des annonces « Matériel & équipements » (matériel destiné aux
/// animaux et aux activités professionnelles). Aucune catégorie ne concerne
/// un animal vivant. Slugs inchangés (données existantes).
///
/// Doit rester aligné avec `website/src/lib/annonce-objet-categories.ts`.
class AnnonceObjetCategorie {
  final String slug;
  final String label;
  final String exemples;
  const AnnonceObjetCategorie(this.slug, this.label, this.exemples);
}

const kAnnonceObjetCategories = <AnnonceObjetCategorie>[
  AnnonceObjetCategorie('habitat', 'Couchage, habitat & parcs',
      'Paniers, niches, grilles de chenil, parcs, cages, volières, clapiers, aquariums'),
  AnnonceObjetCategorie('accessoires', 'Transport & accessoires',
      'Caisses de transport, harnais, laisses, colliers, gamelles'),
  AnnonceObjetCategorie('alimentation', 'Alimentation & fourrage',
      'Foin, paille, granulés, litière, compléments'),
  AnnonceObjetCategorie('entretien', 'Entretien & soin',
      'Matériel de toilettage, tondeuse, pharmacie, brosses'),
  AnnonceObjetCategorie('terrain', 'Terrain & pâture',
      'Location de prairie, parcelle, pré, box en écurie, stabulation'),
  AnnonceObjetCategorie('materiel_agricole', 'Équipements d\'élevage & agricoles',
      'Équipements de mise bas, couveuses, abreuvoirs, clôtures, remorque, tracteur'),
  AnnonceObjetCategorie('autre', 'Autre matériel',
      'Tout autre matériel ou équipement destiné aux animaux (jamais un animal)'),
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
