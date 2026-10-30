import 'package:PetsMatch/utils/ecriture_sure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  static final _supa = Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> loadProfiles(String uid) async {
    final rows = await _supa
        .from('user_profiles_complet')
        .select()
        .eq('uid', uid)
        .order('is_main', ascending: false)
        .order('created_at', ascending: true);
    final owned = List<Map<String, dynamic>>.from(rows as List);
    final cogeres = await _loadCogerances(uid);
    final dejaLa = {for (final p in [...owned, ...cogeres]) p['id']?.toString()};
    final cliniques = (await _loadEmploisCliniques(uid)).where((p) => !dejaLa.contains(p['id']?.toString())).toList();
    return [...owned, ...cogeres, ...cliniques];
  }

  /// Cliniques vétérinaires où l'on est employé (employes actif) : leur
  /// profil s'ouvre comme un profil à soi (espace employé), scopé à ses RDV /
  /// patients et limité par ses autorisations (AgendaContexte). Marqué
  /// `_is_employe_clinique` (+ `_employeur_uid`) — champs synthétiques. Nom,
  /// prénom et téléphone vidés : ce sont ceux de la clinique, pas les siens.
  static Future<List<Map<String, dynamic>>> _loadEmploisCliniques(String uid) async {
    try {
      final liens = await _supa.from('employes')
          .select('uid_eleveur, eleveur_profile_id, role_pro')
          .eq('uid_employe', uid).eq('actif', true)
          .not('eleveur_profile_id', 'is', null);
      final parId = <String, Map<String, dynamic>>{
        for (final l in liens as List)
          if (l['uid_eleveur'] != uid) l['eleveur_profile_id'].toString(): Map<String, dynamic>.from(l as Map),
      };
      if (parId.isEmpty) return [];
      final profs = await _supa.from('user_profiles_complet').select().inFilter('id', parId.keys.toList());
      return [
        for (final p in profs as List)
          if (p['profile_type'] == 'veterinaire')
            {
              ...Map<String, dynamic>.from(p as Map),
              'firstname': '', 'lastname': '', 'phone': '', 'is_main': false,
              '_is_employe_clinique': true,
              '_employeur_uid': parId[p['id'].toString()]?['uid_eleveur'],
              '_role_pro': parId[p['id'].toString()]?['role_pro'],
            },
      ];
    } catch (_) {
      return [];
    }
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
      final profs = await _supa.from('user_profiles_complet').select().inFilter('id', ids);
      return List<Map<String, dynamic>>.from(profs as List)
          .map((p) => {...p, '_is_cogerance': true})
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> upsertProfile(Map<String, dynamic> data) async {
    // Pas d'upsert : colonnes privées non lisibles (phase 2 données perso).
    await ecrireLigne('user_profiles', data,
        {'uid': data['uid'] as Object, 'profile_type': data['profile_type'] as Object}, colRetour: 'id');
  }

  static Future<void> deleteProfile(String id) async {
    await _supa.from('user_profiles').delete().eq('id', id);
  }
}
