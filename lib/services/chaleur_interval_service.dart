import 'package:supabase_flutter/supabase_flutter.dart';

/// Une ligne de protocole race telle que stockée dans protocoles_chaleur_race.
class RaceIntervalEntry {
  final String espece;
  final String race;
  final int jours;
  const RaceIntervalEntry({required this.espece, required this.race, required this.jours});
}

/// Résolution de l'intervalle de chaleurs : override par animal > protocole
/// race (configuré par l'éleveur, cf. ProtocoleChaleurPage) > défaut espèce.
///
/// La correspondance race est volontairement souple (sous-chaîne dans les
/// deux sens, insensible à la casse) : le nom de race stocké sur l'animal
/// vient souvent du sélecteur officiel (ex. "Spitz Allemand", "Berger
/// Blanc Suisse") alors que l'éleveur tape un raccourci plus court dans le
/// protocole (ex. "Spitz") — une correspondance exacte les manquerait tous.
class ChaleurIntervalService {
  ChaleurIntervalService._();

  static const Map<String, int> especeDefaults = {
    'chien': 182, 'chat': 21, 'lapin': 14,
    'ovin': 17, 'caprin': 21, 'porcin': 21, 'cheval': 21,
  };

  /// Charge tous les protocoles race d'un éleveur.
  static Future<List<RaceIntervalEntry>> loadRaceIntervals(String uidEleveur) async {
    if (uidEleveur.isEmpty) return [];
    try {
      final rows = await Supabase.instance.client
          .from('protocoles_chaleur_race')
          .select('espece, race, intervalle_jours')
          .eq('uid_eleveur', uidEleveur);
      final list = <RaceIntervalEntry>[];
      for (final r in (rows as List)) {
        final m = r as Map;
        final espece = m['espece'] as String? ?? '';
        final race = m['race'] as String? ?? '';
        final jours = (m['intervalle_jours'] as num?)?.toInt();
        if (espece.isNotEmpty && race.isNotEmpty && jours != null) {
          list.add(RaceIntervalEntry(espece: espece, race: race, jours: jours));
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  static bool _racesMatch(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    return a.contains(b) || b.contains(a);
  }

  /// Intervalle défini par un protocole race (sans repli), pour affichage :
  /// permet de distinguer "vient d'un protocole race" de "moyenne espèce".
  static int? raceIntervalFor({
    required List<RaceIntervalEntry> raceIntervals,
    required String espece,
    String? race,
  }) {
    if (race == null || race.trim().isEmpty) return null;
    final e = espece.toLowerCase().trim();
    final r = race.toLowerCase().trim();
    for (final entry in raceIntervals) {
      if (entry.espece.toLowerCase().trim() != e) continue;
      if (_racesMatch(entry.race.toLowerCase().trim(), r)) return entry.jours;
    }
    return null;
  }

  /// Intervalle effectif (en jours) pour un animal donné.
  static int resolve({
    required List<RaceIntervalEntry> raceIntervals,
    required String espece,
    String? race,
    int? animalOverride,
  }) {
    if (animalOverride != null && animalOverride > 0) return animalOverride;
    final v = raceIntervalFor(raceIntervals: raceIntervals, espece: espece, race: race);
    if (v != null) return v;
    return especeDefaults[espece.toLowerCase()] ?? 0;
  }
}
