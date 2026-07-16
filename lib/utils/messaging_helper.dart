import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MessagingHelper {
  static final _supa = Supabase.instance.client;

  static String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  static const _proTypes = {
    'veterinaire', 'sante', 'education', 'garde',
    'pension', 'toilettage', 'photographe', 'marechal_ferrant',
    'restauration', 'taxi_animalier',
  };

  /// Résout nom + photo d'affichage depuis le profil principal
  /// (`user_profiles`, `is_main=true`, toujours présent grâce au trigger
  /// de création automatique à l'inscription).
  static Future<Map<String, dynamic>> getDisplayInfo(String uid) async {
    final p = await _supa.from('user_profiles')
        .select('firstname, lastname, avatar_url, profile_type, nom')
        .eq('uid', uid).eq('is_main', true).maybeSingle();
    if (p == null) {
      return {'name': 'Utilisateur', 'photo': null, 'isElevage': false, 'isPro': false};
    }
    final type = p['profile_type'] as String?;
    final isElevage = type == 'eleveur';
    final isPro = type != null && _proTypes.contains(type);
    final name = isElevage && (p['nom'] as String?)?.isNotEmpty == true
        ? p['nom'] as String
        : '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
    return {
      'name': name.isEmpty ? 'Utilisateur' : name,
      'photo': (p['avatar_url'] as String?)?.isNotEmpty == true ? p['avatar_url'] : null,
      'isElevage': isElevage,
      'isPro': isPro,
    };
  }

  /// Trouve ou crée une conversation Supabase entre [myUid] et [otherUid].
  /// Retourne le `conversationId`.
  static Future<String> openOrCreateConversation({
    required String otherUid,
    String? categorie,
    String? alerteId,
    String? nomAnimal,
    String? myProfileId,
    String? otherProfileId,
  }) async {
    final myUid = _myUid;
    if (myUid.isEmpty) throw Exception('Non connecté');

    final sorted = ([myUid, otherUid]..sort()).join('_');

    // Chercher une conversation existante (par participant_ids)
    var q = _supa.from('conversations').select('id').eq('participant_ids', sorted);
    if (myProfileId != null) {
      q = q.or('pro_profile_id.eq.$myProfileId,consumer_profile_id.eq.$myProfileId');
    }
    final existing = await q.limit(1).maybeSingle();
    if (existing != null) return existing['id'].toString();

    // Créer une nouvelle conversation
    final myData    = await getDisplayInfo(myUid);
    final otherData = await getDisplayInfo(otherUid);

    final participantsInfo = <String, dynamic>{
      myUid: {
        'name': myData['name'],
        if (myData['photo'] != null) 'photo': myData['photo'],
      },
      otherUid: {
        'name': otherData['name'],
        if (otherData['photo'] != null) 'photo': otherData['photo'],
      },
    };

    final created = await _supa.from('conversations').insert({
      'type':              'direct',
      'participants':      [myUid, otherUid],
      'participant_ids':   sorted,
      'participants_info': participantsInfo,
      'last_message':      '',
      'unread_count':      {myUid: 0, otherUid: 0},
      'updated_at':        DateTime.now().toIso8601String(),
      if (categorie != null)    'categorie':            categorie,
      if (myProfileId != null)  'pro_profile_id':       myProfileId,
      if (otherProfileId != null) 'consumer_profile_id': otherProfileId,
    }).select('id').single();

    return created['id'].toString();
  }
}
