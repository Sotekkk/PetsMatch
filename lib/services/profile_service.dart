import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  static final _supa = Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> loadProfiles(String uid) async {
    final rows = await _supa
        .from('user_profiles')
        .select()
        .eq('uid', uid)
        .order('is_main', ascending: false)
        .order('created_at', ascending: true);
    final owned = List<Map<String, dynamic>>.from(rows as List);
    final cogeres = await _loadCogerances(uid);
    return [...owned, ...cogeres];
  }

  /// Élevages cogérés activement (elevage_cogerants) : le profil élevage du
  /// gérant principal, "emprunté" tel quel — même id, même profile_id utilisé
  /// partout dans le reste de l'appli. Marqué `_is_cogerance` pour l'affichage
  /// (badge, pas de suppression possible) — champ synthétique, pas en base.
  static Future<List<Map<String, dynamic>>> _loadCogerances(String uid) async {
    try {
      final links = await _supa
          .from('elevage_cogerants')
          .select('elevage_profile_id')
          .eq('uid_cogerant', uid)
          .eq('statut', 'actif')
          .isFilter('date_fin', null);
      final ids = (links as List)
          .map((l) => l['elevage_profile_id']?.toString())
          .whereType<String>()
          .toList();
      if (ids.isEmpty) return [];
      final profs = await _supa.from('user_profiles').select().inFilter('id', ids);
      return List<Map<String, dynamic>>.from(profs as List)
          .map((p) => {...p, '_is_cogerance': true})
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> upsertProfile(Map<String, dynamic> data) async {
    await _supa
        .from('user_profiles')
        .upsert(data, onConflict: 'uid,profile_type');
  }

  static Future<void> deleteProfile(String id) async {
    await _supa.from('user_profiles').delete().eq('id', id);
  }
}
