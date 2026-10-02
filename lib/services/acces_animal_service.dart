import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;

/// Accès d'un pro (profil ACTIF) à l'animal d'un client : lecture du statut
/// et demande d'accès au propriétaire (notification `vet_access_demande`,
/// que le propriétaire accepte / refuse depuis ses notifications).
class AccesAnimalService {
  static final _supa = Supabase.instance.client;

  /// 'proprietaire' (le pro est propriétaire / co-propriétaire de l'animal),
  /// 'active' | 'active_write' | 'write_requested' | 'pending', ou null
  /// (aucun accès, ou accès révoqué).
  static Future<String?> statut(String animalId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final pid = User_Info.activeProfileId;
    if (uid == null) return null;
    final proprio = await _supa.from('animaux_proprietes').select('id')
        .eq('animal_id', animalId).eq('uid_proprio', uid).isFilter('date_fin', null).limit(1);
    if ((proprio as List).isNotEmpty) return 'proprietaire';
    if (pid.isEmpty) return null;
    final row = await _supa.from('animal_access').select('statut')
        .eq('animal_id', animalId).eq('pro_profile_id', pid).neq('statut', 'revoked')
        .limit(1).maybeSingle();
    return row?['statut'] as String?;
  }

  /// Envoie une demande d'accès au propriétaire principal actuel — côté
  /// serveur (pm_demander_acces_animal) : un pro sans accès ne peut pas lire
  /// les propriétaires de l'animal (RLS). Retourne le statut de l'accès.
  static Future<String> demander(String animalId) async {
    final pid = User_Info.activeProfileId;
    if (pid.isEmpty) throw Exception('Profil professionnel introuvable');
    final r = await _supa.rpc('pm_demander_acces_animal',
        params: {'p_animal_id': animalId, 'p_pro_profile_id': pid});
    return r?.toString() ?? 'envoyee';
  }
}
