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

  /// Envoie (ou renvoie) une demande d'accès au propriétaire principal actuel.
  static Future<void> demander(String animalId, {String? animalNom}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final pid = User_Info.activeProfileId;
    if (uid == null || pid.isEmpty) throw Exception('Profil professionnel introuvable');

    final props = await _supa.from('animaux_proprietes')
        .select('uid_proprio, profile_id_proprio, role_proprio')
        .eq('animal_id', animalId).isFilter('date_fin', null);
    final liste = List<Map<String, dynamic>>.from(props as List);
    if (liste.isEmpty) throw Exception('Propriétaire introuvable');
    final principal = liste.firstWhere((p) => p['role_proprio'] == 'principal', orElse: () => liste.first);
    final ownerUid = principal['uid_proprio'] as String;
    final ownerPid = principal['profile_id_proprio'] as String?;

    await _supa.from('animal_access').upsert({
      'animal_id':             animalId,
      'pro_profile_id':        pid,
      if (ownerPid != null) 'granted_by_profile_id': ownerPid,
      'permissions':           ['read_basic', 'read_health', 'write_health'],
      'statut':                'pending',
    }, onConflict: 'animal_id,pro_profile_id');

    // Nom affiché : le profil pro ACTIF (jamais is_main).
    String proNom = '';
    bool isClinic = false;
    try {
      final p = await _supa.from('user_profiles_complet')
          .select('nom, firstname, lastname').eq('id', pid).maybeSingle();
      final nom = (p?['nom'] ?? '').toString().trim();
      if (nom.isNotEmpty) {
        proNom = nom;
        isClinic = true;
      } else {
        proNom = '${p?['firstname'] ?? ''} ${p?['lastname'] ?? ''}'.trim();
      }
    } catch (_) {}
    final affiche = proNom.isNotEmpty ? proNom : 'Un professionnel';
    final nomAnimal = animalNom ?? 'votre animal';

    await _supa.from('notifications').insert({
      'uid':   ownerUid,
      'type':  'vet_access_demande',
      'title': 'Demande d\'accès — $affiche',
      'body':  '$affiche demande l\'accès au dossier de santé de $nomAnimal.',
      if (ownerPid != null) 'profile_id': ownerPid,
      'data':  <String, dynamic>{
        'animal_id':  animalId,
        'vet_id':     uid,
        'vet_nom':    proNom,
        'is_clinic':  isClinic,
        'animal_nom': nomAnimal,
        'pro_profile_id': pid, // la réponse ne touche que CETTE demande
      },
      'read':  false,
    });
  }
}
