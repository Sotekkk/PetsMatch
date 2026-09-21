import 'package:supabase_flutter/supabase_flutter.dart';

/// Résolution de l'intervalle de chaleurs : override par animal > protocole
/// race (configuré par l'éleveur, cf. ProtocoleChaleurPage) > défaut espèce.
class ChaleurIntervalService {
  ChaleurIntervalService._();

  static const Map<String, int> especeDefaults = {
    'chien': 182, 'chat': 21, 'lapin': 14,
    'ovin': 17, 'caprin': 21, 'porcin': 21, 'cheval': 21,
  };

  static String _key(String espece, String race) =>
      '${espece.toLowerCase().trim()}|${race.toLowerCase().trim()}';

  /// Charge tous les protocoles race d'un éleveur : "espece|race" → jours.
  static Future<Map<String, int>> loadRaceIntervals(String uidEleveur) async {
    if (uidEleveur.isEmpty) return {};
    try {
      final rows = await Supabase.instance.client
          .from('protocoles_chaleur_race')
          .select('espece, race, intervalle_jours')
          .eq('uid_eleveur', uidEleveur);
      final map = <String, int>{};
      for (final r in (rows as List)) {
        final m = r as Map;
        final espece = m['espece'] as String? ?? '';
        final race = m['race'] as String? ?? '';
        final jours = (m['intervalle_jours'] as num?)?.toInt();
        if (espece.isNotEmpty && race.isNotEmpty && jours != null) {
          map[_key(espece, race)] = jours;
        }
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  /// Intervalle défini par un protocole race (sans repli), pour affichage :
  /// permet de distinguer "vient d'un protocole race" de "moyenne espèce".
  static int? raceIntervalFor({
    required Map<String, int> raceIntervals,
    required String espece,
    String? race,
  }) {
    if (race == null || race.trim().isEmpty) return null;
    return raceIntervals[_key(espece, race)];
  }

  /// Intervalle effectif (en jours) pour un animal donné.
  static int resolve({
    required Map<String, int> raceIntervals,
    required String espece,
    String? race,
    int? animalOverride,
  }) {
    if (animalOverride != null && animalOverride > 0) return animalOverride;
    if (race != null && race.trim().isNotEmpty) {
      final v = raceIntervals[_key(espece, race)];
      if (v != null) return v;
    }
    return especeDefaults[espece.toLowerCase()] ?? 0;
  }
}
