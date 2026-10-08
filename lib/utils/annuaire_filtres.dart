// Annuaire des professionnels — filtres combinables : métier + lieu / rayon +
// animaux pris en charge (+ mot-clé). Même logique que le site :
// website/src/lib/annuaire-filtres.ts — garder les deux synchronisés.

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

// ── Métiers ──────────────────────────────────────────────────────────────────

class Metier {
  final String key;
  final String label;
  /// Groupe affiché dans le menu déroulant ('' = « Tous les métiers »)
  final String groupe;
  /// profile_type acceptés (vide = tous les pros)
  final List<String> cats;
  /// profession_pro acceptées (vide = toutes)
  final List<String> professions;
  /// Repli « promeneur » : pet-sitter qui propose des créneaux de ce type
  final List<String>? creneauTypeGarde;

  const Metier(this.key, this.label, this.groupe, this.cats,
      {this.professions = const [], this.creneauTypeGarde});
}

const kMetiers = <Metier>[
  Metier('', 'Tous les métiers', '', []),
  Metier('sante', 'Toute la santé & bien-être', 'Santé & bien-être', ['sante', 'veterinaire', 'marechal_ferrant']),
  Metier('veterinaire', 'Vétérinaire', 'Santé & bien-être', ['veterinaire']),
  Metier('osteopathe', 'Ostéopathe', 'Santé & bien-être', ['sante'], professions: ['Ostéopathe']),
  Metier('kine', 'Kinésithérapeute', 'Santé & bien-être', ['sante'], professions: ['Kinésithérapeute']),
  Metier('marechal', 'Maréchal-ferrant', 'Santé & bien-être', ['marechal_ferrant', 'sante'],
      professions: ['Maréchal-ferrant', 'Maréchal-ferrant traditionnel', 'Parage naturel']),
  Metier('education', 'Toute l\'éducation', 'Éducation & comportement', ['education']),
  Metier('educateur', 'Éducateur', 'Éducation & comportement', ['education'], professions: ['Éducateur canin', 'Dresseur']),
  Metier('comportementaliste', 'Comportementaliste', 'Éducation & comportement', ['education'], professions: ['Comportementaliste']),
  Metier('garde', 'Toute la garde & hébergement', 'Garde & hébergement', ['garde', 'pension']),
  Metier('petsitter', 'Pet-sitter', 'Garde & hébergement', ['garde'], professions: ['Pet sitter']),
  Metier('promeneur', 'Promeneur', 'Garde & hébergement', ['garde'],
      professions: ['Promeneur de chiens'], creneauTypeGarde: ['prestation']),
  Metier('pension', 'Pension', 'Garde & hébergement', ['pension']),
  Metier('toilettage', 'Toilettage', 'Autres services', ['toilettage']),
  Metier('taxi', 'Taxi animalier', 'Autres services', ['taxi_animalier']),
  Metier('photographe', 'Photographe', 'Autres services', ['photographe']),
  Metier('boutiques', 'Alimentation & boutiques', 'Autres services', ['referencement']),
  Metier('assurance', 'Assurances & juridique', 'Autres services', ['assurance', 'juridique']),
];

Metier metierByKey(String? key) =>
    kMetiers.firstWhere((m) => m.key == (key ?? ''), orElse: () => kMetiers.first);

/// Catégorie / professions d'une tuile de l'annuaire → métier équivalent.
Metier metierFromLegacy(List<String> cats, List<String>? professions) {
  String norm(Iterable<String> l) =>
      (l.map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toList()..sort()).join(',');
  final c = norm(cats), p = norm(professions ?? const []);
  if (c.isEmpty && p.isEmpty) return kMetiers.first;
  for (final m in kMetiers) {
    if (norm(m.cats) == c && norm(m.professions) == p) return m;
  }
  for (final m in kMetiers) {
    if (norm(m.cats) == c && m.professions.isEmpty) return m;
  }
  return kMetiers.first;
}

/// [creneauOk] : ids de profils garde qui proposent des créneaux du type voulu.
bool proMatchesMetier(Map<String, dynamic> p, Metier m, {Set<String> creneauOk = const {}}) {
  if (m.cats.isEmpty) return true;
  if (!m.cats.contains((p['cat_pro'] ?? '').toString())) return false;
  if (m.professions.isEmpty) return true;
  final prof = (p['profession_pro'] ?? '').toString().toLowerCase();
  if (m.professions.any((x) => x.toLowerCase() == prof)) return true;
  final pid = p['_profile_table_id']?.toString();
  return m.creneauTypeGarde != null && pid != null && creneauOk.contains(pid);
}

// ── Animaux pris en charge ───────────────────────────────────────────────────

class GroupeEspece {
  final String key;
  final String label;
  final String? detail;
  /// Valeurs de `especes_acceptees` (normalisées) rattachées au groupe
  final List<String> valeurs;
  const GroupeEspece(this.key, this.label, this.valeurs, {this.detail});
}

const kGroupesEspeces = <GroupeEspece>[
  GroupeEspece('chien', 'Chiens', ['chien', 'chiens']),
  GroupeEspece('chat', 'Chats', ['chat', 'chats']),
  GroupeEspece('cheval', 'Chevaux & ânes', ['cheval', 'chevaux', 'ane', 'anes', 'equide', 'equides', 'poney', 'poneys']),
  GroupeEspece('nac', 'NAC', ['nac', 'lapin', 'lapins', 'rongeur', 'rongeurs', 'reptile', 'reptiles', 'furet', 'furets'],
      detail: 'Lapins, rongeurs, reptiles…'),
  GroupeEspece('oiseau', 'Oiseaux', ['oiseau', 'oiseaux']),
  GroupeEspece('ferme', 'Animaux de ferme', ['animaux de la ferme', 'animaux de ferme', 'ferme', 'ovin', 'ovins',
      'caprin', 'caprins', 'porcin', 'porcins', 'bovin', 'bovins', 'volaille', 'volailles'],
      detail: 'Moutons, chèvres, porcs…'),
  GroupeEspece('autre', 'Autres', ['autre', 'autres']),
];

String _sansAccents(String s) {
  const a = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ';
  const b = 'aaaaaaceeeeiiiinooooouuuuyy';
  final low = s.toLowerCase().trim();
  final buf = StringBuffer();
  for (final ch in low.split('')) {
    final i = a.indexOf(ch);
    buf.write(i >= 0 ? b[i] : ch);
  }
  return buf.toString();
}

/// Groupes couverts par une liste `especes_acceptees` (ordre de kGroupesEspeces).
List<GroupeEspece> groupesDesEspeces(dynamic especes) {
  final vals = (especes is List ? especes : const [])
      .map((e) => _sansAccents(e.toString()))
      .toSet();
  return kGroupesEspeces.where((g) => g.valeurs.any(vals.contains)).toList();
}

/// Aucune sélection = toutes les espèces ; sinon au moins un groupe coché.
bool proMatchesEspeces(dynamic especes, List<String> selection) {
  if (selection.isEmpty) return true;
  return groupesDesEspeces(especes).any((g) => selection.contains(g.key));
}

// ── Lieu & rayon ─────────────────────────────────────────────────────────────

class LieuRecherche {
  final String label;
  final double lat;
  final double lng;
  final String? ville;
  const LieuRecherche(this.label, this.lat, this.lng, {this.ville});
}

const kRayonsKm = [10, 25, 50, 100, 200];

double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * math.pow(math.sin(dLng / 2), 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Dans la zone : à moins de [rayonKm] du lieu, ou le pro se déplace jusque-là
/// (son rayon d'intervention le couvre). Sans coordonnées : même ville.
bool proDansZone(Map<String, dynamic> p, LieuRecherche? lieu, int rayonKm) {
  if (lieu == null) return true;
  final lat = (p['lat'] as num?)?.toDouble();
  final lng = (p['lng'] as num?)?.toDouble();
  if (lat == null || lng == null || (lat == 0 && lng == 0)) {
    final v = lieu.ville;
    return v != null && _sansAccents((p['ville'] ?? '').toString()) == _sansAccents(v);
  }
  final d = haversineKm(lieu.lat, lieu.lng, lat, lng);
  if (d <= rayonKm) return true;
  final rayonPro = p['se_deplace'] == false ? 0.0 : ((p['rayon_intervention'] as num?)?.toDouble() ?? 0);
  return rayonPro > 0 && d <= rayonPro;
}

/// Communes françaises (API Adresse, data.gouv.fr).
Future<List<LieuRecherche>> chercherCommunes(String q) async {
  if (q.trim().length < 2) return [];
  try {
    final res = await http.get(Uri.https('api-adresse.data.gouv.fr', '/search/',
        {'q': q, 'type': 'municipality', 'limit': '6'}));
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return (json['features'] as List? ?? []).map((f) {
      final props = f['properties'] as Map<String, dynamic>;
      final coords = (f['geometry']['coordinates'] as List).cast<num>();
      final ville = (props['city'] ?? props['label']).toString();
      final cp = (props['postcode'] ?? '').toString();
      return LieuRecherche(cp.length >= 2 ? '$ville (${cp.substring(0, 2)})' : ville,
          coords[1].toDouble(), coords[0].toDouble(), ville: ville);
    }).toList();
  } catch (_) {
    return [];
  }
}

// ── Catégories de l'annuaire (cartes) et leurs types de service ─────────────
// Une catégorie sans type sélectionné = tout le domaine (`metier`) ; un type
// = un métier de kMetiers. Miroir site : CATEGORIES_ANNUAIRE.

class CategorieAnnuaire {
  final String key;
  final String label;
  final int color;
  /// Métier « tout le domaine »
  final String metier;
  /// Types de service (clés de kMetiers) — vide = pas de sous-type
  final List<String> types;
  const CategorieAnnuaire(this.key, this.label, this.color, this.metier, this.types);
}

const kCategoriesAnnuaire = <CategorieAnnuaire>[
  CategorieAnnuaire('sante', 'Santé & bien-être', 0xFF2E7D5E, 'sante', ['veterinaire', 'osteopathe', 'kine', 'marechal']),
  CategorieAnnuaire('education', 'Éducation & comportement', 0xFFE65100, 'education', ['educateur', 'comportementaliste']),
  CategorieAnnuaire('garde', 'Garde & hébergement', 0xFFF57C00, 'garde', ['petsitter', 'promeneur', 'pension']),
  CategorieAnnuaire('toilettage', 'Toilettage & soins', 0xFFC62828, 'toilettage', []),
  CategorieAnnuaire('transport', 'Transport', 0xFF00838F, 'taxi', ['taxi']),
  CategorieAnnuaire('photographe', 'Photographes', 0xFFAD1457, 'photographe', []),
  CategorieAnnuaire('boutiques', 'Alimentation & boutiques', 0xFF6A1B9A, 'boutiques', []),
  CategorieAnnuaire('assurance', 'Assurances & juridique', 0xFF1E3A5F, 'assurance', []),
];

CategorieAnnuaire? categorieByKey(String? key) {
  for (final c in kCategoriesAnnuaire) {
    if (c.key == key) return c;
  }
  return null;
}

/// Catégorie + type sélectionnés → métier à filtrer.
Metier metierSelectionne(String categorie, String type) {
  if (type.isNotEmpty) return metierByKey(type);
  final c = categorieByKey(categorie);
  return c != null ? metierByKey(c.metier) : kMetiers.first;
}
