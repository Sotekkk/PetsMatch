import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MessagingHelper {
  static final _supa = Supabase.instance.client;

  static String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

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
    final myData    = await _supa.from('users')
        .select('firstname, lastname, profile_picture_url, is_elevage, name_elevage')
        .eq('uid', myUid).maybeSingle();
    final otherData = await _supa.from('users')
        .select('firstname, lastname, profile_picture_url, is_elevage, name_elevage')
        .eq('uid', otherUid).maybeSingle();

    final myName    = _resolveName(myData);
    final otherName = _resolveName(otherData);

    final participantsInfo = <String, dynamic>{
      myUid: {
        'name': myName,
        if ((myData?['profile_picture_url'] as String?)?.isNotEmpty == true)
          'photo': myData!['profile_picture_url'],
      },
      otherUid: {
        'name': otherName,
        if ((otherData?['profile_picture_url'] as String?)?.isNotEmpty == true)
          'photo': otherData!['profile_picture_url'],
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

  static String _resolveName(Map<String, dynamic>? data) {
    if (data == null) return 'Utilisateur';
    if (data['is_elevage'] == true && (data['name_elevage'] as String?)?.isNotEmpty == true) {
      return data['name_elevage'] as String;
    }
    final full = '${data['firstname'] ?? ''} ${data['lastname'] ?? ''}'.trim();
    return full.isEmpty ? 'Utilisateur' : full;
  }
}
