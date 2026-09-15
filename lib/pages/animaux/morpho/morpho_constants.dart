import 'package:flutter/material.dart';

// ── Suivi morphologique & bien-être — constantes partagées ──────────────────
// Utilisées par morpho_silhouette.dart / morpho_timeline_tab.dart /
// morpho_form_page.dart / morpho_detail_page.dart, et par les fiches animal
// (particulier + éleveur/pro) qui embarquent ces widgets.
// Distinct de anatomie_points_page.dart (points de tension libres,
// seances_osteo/points_osteo) — coexistent, ne pas fusionner.

const kMorphoTeal = Color(0xFF0C5C6C);
const kMorphoBg = Color(0xFFF8F8F6);
const kMorphoDark = Color(0xFF1F2A2E);

/// Espèces couvertes en V1 — mêmes 3 espèces que le schéma anatomique
/// existant (anatomie_points_page.dart) : chien, chat, cheval.
String? morphoSpeciesKey(String? espece) {
  final e = (espece ?? '').toLowerCase();
  if (e.contains('chien')) return 'chien';
  if (e.contains('chat')) return 'chat';
  if (e.contains('cheval')) return 'cheval';
  return null;
}

bool morphoSpeciesSupported(String? espece) => morphoSpeciesKey(espece) != null;

const List<(String, String)> kTypesSuivi = [
  ('bilan_morphologique', 'Bilan morphologique'),
  ('bilan_posture', 'Bilan de posture'),
  ('osteopathie', 'Ostéopathie'),
  ('physiotherapie', 'Physiothérapie'),
  ('suivi_veterinaire', 'Suivi vétérinaire'),
  ('suivi_sportif', 'Suivi sportif'),
  ('suivi_post_operatoire', 'Suivi post-opératoire'),
  ('prevention', 'Prévention'),
  ('autre', 'Autre'),
];

String labelTypeSuivi(String? v) =>
    kTypesSuivi.firstWhere((t) => t.$1 == v, orElse: () => ('', 'Suivi')).$2;

const List<(String, String)> kNiveauxActivite = [
  ('faible', 'Faible'),
  ('moderee', 'Modérée'),
  ('elevee', 'Élevée'),
  ('non_evalue', 'Non évalué'),
];

const List<(String, String)> kVuesPhotos = [
  ('face', 'Face'),
  ('dos', 'Arrière / dos'),
  ('profil_g', 'Profil gauche'),
  ('profil_d', 'Profil droit'),
];

const List<(String, String, IconData)> kActivitesMouvement = [
  ('marche', 'Marche', Icons.directions_walk),
  ('trot', 'Trot', Icons.speed_outlined),
  ('course', 'Course', Icons.directions_run),
  ('assis_debout', 'Assis / debout', Icons.chair_alt_outlined),
  ('escaliers', 'Escaliers', Icons.stairs_outlined),
  ('saut', 'Saut', Icons.sports_gymnastics_outlined),
  ('sport', 'Activité sportive', Icons.sports_outlined),
  ('autre', 'Autre', Icons.more_horiz),
];

String labelActivite(String? v) =>
    kActivitesMouvement.firstWhere((a) => a.$1 == v, orElse: () => ('', 'Activité', Icons.circle)).$2;

/// Observations statiques (posture) — même vocabulaire 3-états partout,
/// seul le libellé du bouton change par catégorie.
const List<(String categorie, String label)> kCategoriesObservationStatique = [
  ('aplombs_anterieurs', 'Aplombs antérieurs'),
  ('aplombs_posterieurs', 'Aplombs postérieurs'),
  ('symetrie', 'Symétrie générale'),
  ('ligne_dos', 'Ligne du dos'),
  ('position_bassin', 'Position du bassin'),
  ('position_membres', 'Position des membres'),
];

/// {valeur_stockée: libellé} — les 3 boutons variant par catégorie
/// (ex. symétrie: Symétrique/Asymétrie observée/Non évaluée) tout en
/// gardant le même code en base (normal/a_surveiller/non_evalue).
Map<String, String> labelsValeurObservation(String categorie) {
  if (categorie == 'symetrie') {
    return {'normal': 'Symétrique', 'a_surveiller': 'Asymétrie observée', 'non_evalue': 'Non évaluée'};
  }
  return {'normal': 'Normaux', 'a_surveiller': 'À surveiller', 'non_evalue': 'Non évalué'};
}

Color colorValeurObservation(String v) => switch (v) {
      'normal' => const Color(0xFF6E9E57),
      'a_surveiller' => const Color(0xFFD97706),
      _ => Colors.grey,
    };

/// Source de la donnée — jamais présenté comme un diagnostic.
const Map<String, String> kSourceLabels = {
  'proprietaire': 'Renseigné par le propriétaire',
  'mesure': 'Mesure enregistrée',
  'professionnel': 'Réalisé par un professionnel',
};

const String kMorphoAvertissement =
    'Les informations de cette section sont destinées au suivi de l\'animal '
    'et ne remplacent pas l\'avis d\'un vétérinaire ou d\'un professionnel de '
    'santé animale.';

// ── Silhouette interactive — pointage libre (repris d'anatomie_points_page
// .dart / points_osteo à la demande explicite : on garde ce geste plutôt
// que des zones fixes, mais intégré au compte-rendu structuré). ───────────

/// Catégories de points — identiques à kCategoriesOsteo
/// (anatomie_points_page.dart), dupliquées ici (privées là-bas) pour ne pas
/// toucher ce fichier existant.
const List<(String, String, Color)> kCategoriesOsteo = [
  ('tension_cervicale', 'Tension cervicale', Color(0xFFE67E22)),
  ('tension_thoracique', 'Tension thoracique', Color(0xFFF39C12)),
  ('tension_lombaire', 'Tension lombaire', Color(0xFF3498DB)),
  ('tension_sacro_iliaque', 'Tension sacro-iliaque', Color(0xFF9B59B6)),
  ('trigger', 'Point trigger', Color(0xFF795548)),
  ('acupuncture', 'Point d\'acupuncture', Color(0xFF8BC34A)),
  ('autre', 'Autre', Color(0xFF9E9E9E)),
];

Color colorCategoriePoint(String cat) =>
    kCategoriesOsteo.firstWhere((c) => c.$1 == cat, orElse: () => kCategoriesOsteo.last).$3;

String labelCategoriePoint(String cat) =>
    kCategoriesOsteo.firstWhere((c) => c.$1 == cat, orElse: () => kCategoriesOsteo.last).$2;

/// Silhouettes réutilisées telles quelles (mêmes fichiers, même mécanisme
/// que anatomie_points_page.dart / points_osteo — voir kVuesAnatomie /
/// _speciesViewAssets dans ce fichier, non publics donc dupliqués ici plutôt
/// que touchés).
class MorphoSpeciesAsset {
  final String path;
  final double ratio; // largeur / hauteur réelle du PNG
  const MorphoSpeciesAsset(this.path, this.ratio);
}

// Nouveau design (ivoire/bleu), plus sobre que l'ancienne planche
// arc-en-ciel — les 3 espèces ont maintenant leurs 4 vues.
const Map<String, Map<String, MorphoSpeciesAsset>> kMorphoSilhouetteAssets = {
  'chien': {
    'face': MorphoSpeciesAsset('assets/anatomie/chien2_face.png', 1024 / 1536),
    'profil_g': MorphoSpeciesAsset('assets/anatomie/chien2_profil_gauche.png', 1536 / 1024),
    'profil_d': MorphoSpeciesAsset('assets/anatomie/chien2_profil_droit.png', 1536 / 1024),
    'dos': MorphoSpeciesAsset('assets/anatomie/chien2_dos.png', 1024 / 1536),
  },
  'chat': {
    'face': MorphoSpeciesAsset('assets/anatomie/chat2_face.png', 1024 / 1536),
    'profil_g': MorphoSpeciesAsset('assets/anatomie/chat2_profil_gauche.png', 1536 / 1024),
    'profil_d': MorphoSpeciesAsset('assets/anatomie/chat2_profil_droit.png', 1536 / 1024),
    'dos': MorphoSpeciesAsset('assets/anatomie/chat2_dos.png', 1024 / 1536),
  },
  'cheval': {
    'face': MorphoSpeciesAsset('assets/anatomie/cheval2_face.png', 1024 / 1536),
    'profil_g': MorphoSpeciesAsset('assets/anatomie/cheval2_profil_gauche.png', 1536 / 1024),
    'profil_d': MorphoSpeciesAsset('assets/anatomie/cheval2_profil_droit.png', 1536 / 1024),
    'dos': MorphoSpeciesAsset('assets/anatomie/cheval2_dos.png', 1024 / 1536),
  },
};

/// Ordre d'affichage des vues + libellé — seules celles ayant un asset pour
/// l'espèce donnée sont proposées (chat/cheval : profils uniquement pour
/// l'instant, chien : les 4 vues).
const List<(String, String)> _kVueOrder = [
  ('face', 'Face'),
  ('profil_g', 'Profil gauche'),
  ('profil_d', 'Profil droit'),
  ('dos', 'Dos'),
];

List<(String key, String label)> vuesDisponibles(String espece) {
  final assets = kMorphoSilhouetteAssets[espece] ?? kMorphoSilhouetteAssets['chien']!;
  return [for (final v in _kVueOrder) if (assets.containsKey(v.$1)) v];
}
