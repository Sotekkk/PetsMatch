import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;

/// Compte pro sur lequel on travaille. Par défaut le pro connecté (profil
/// actif). Un employé de clinique (« Mes Employeurs ») l'ouvre AU NOM de la
/// clinique : uid du gérant + profil clinique — scopé à CE profil
/// (multi-profil) ; l'accès est contrôlé en base (pm_acces_compte,
/// migration_clinique_equipe.sql).
class AgendaContexte {
  static String? _uid, _profileId, _catPro;
  static Set<String>? _droits;
  static String? _monProfilEmploye;

  /// uid du COMPTE pro (gérant) — pas forcément l'utilisateur connecté.
  static String? get uid => _uid ?? FirebaseAuth.instance.currentUser?.uid;
  static String get profileId => _profileId ?? User_Info.activeProfileId;
  static String get catPro => _catPro ?? User_Info.catPro;
  /// Ouvert pour le compte d'un employeur (et non le sien).
  static bool get pourEmployeur => _uid != null;
  /// Utilisateur réellement connecté (rédacteur, prescripteur…).
  static String? get moi => FirebaseAuth.instance.currentUser?.uid;

  static void ouvrir({required String uid, required String profileId, required String catPro}) {
    _uid = uid; _profileId = profileId; _catPro = catPro;
    _droits = null; _monProfilEmploye = null;
  }

  static void fermer() {
    _uid = null; _profileId = null; _catPro = null;
    _droits = null; _monProfilEmploye = null;
  }

  /// Droits de l'utilisateur dans ce contexte. Titulaire / cogérant (contexte
  /// non employé) : tous. Employé : employe_permissions de CE profil.
  static Future<Set<String>> droits() async {
    if (!pourEmployeur) return const {'*'};
    if (_droits != null) return _droits!;
    final supa = Supabase.instance.client;
    try {
      final e = await supa.from('employes').select('employe_profile_id')
          .eq('eleveur_profile_id', profileId).eq('uid_employe', moi ?? '')
          .eq('actif', true).maybeSingle();
      _monProfilEmploye = e?['employe_profile_id'] as String?;
      if (_monProfilEmploye == null) return _droits = <String>{};
      final rows = await supa.from('employe_permissions').select('permission')
          .eq('eleveur_profile_id', profileId).eq('employe_profile_id', _monProfilEmploye!);
      return _droits = {for (final r in rows as List) r['permission'] as String};
    } catch (_) {
      return <String>{};
    }
  }

  /// Profil (particulier) de l'employé dans ce contexte ; pour le titulaire :
  /// le profil pro lui-même.
  static Future<String?> monProfil() async {
    if (!pourEmployeur) return profileId.isNotEmpty ? profileId : null;
    await droits();
    return _monProfilEmploye;
  }

  static Future<bool> peut(String droit) async {
    final d = await droits();
    return d.contains('*') || d.contains(droit);
  }
}
