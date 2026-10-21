import 'package:PetsMatch/main.dart' show User_Info;
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

  /// Résout nom + photo d'affichage : le profil précis de la conversation
  /// ([profileId], ex. la pension contactée), sinon le profil principal.
  static Future<Map<String, dynamic>> getDisplayInfo(String uid, {String? profileId}) async {
    Map<String, dynamic>? p;
    if (profileId != null && profileId.isNotEmpty) {
      p = await _supa.from('user_profiles_complet')
          .select('firstname, lastname, avatar_url, profile_type, nom').eq('id', profileId).maybeSingle();
    }
    p ??= await _supa.from('user_profiles_complet')
        .select('firstname, lastname, avatar_url, profile_type, nom')
        .eq('uid', uid).eq('is_main', true).maybeSingle();
    if (p == null) {
      return {'name': 'Utilisateur', 'photo': null, 'isElevage': false, 'isPro': false};
    }
    final type = p['profile_type'] as String?;
    final isElevage = type == 'eleveur';
    final isPro = type != null && _proTypes.contains(type);
    // Profil pro / élevage / association : son nom de structure (comme une page).
    final name = (isElevage || isPro || type == 'association') && (p['nom'] as String?)?.isNotEmpty == true
        ? p['nom'] as String
        : '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
    return {
      'name': name.isEmpty ? 'Utilisateur' : name,
      'photo': (p['avatar_url'] as String?)?.isNotEmpty == true ? p['avatar_url'] : null,
      'isElevage': isElevage,
      'isPro': isPro,
    };
  }

  /// Profil principal du compte connecté (is_main, sinon le premier).
  static String get _profilPrincipal {
    final ps = User_Info.availableProfiles.where((p) => (p['uid']?.toString() ?? _myUid) == _myUid).toList();
    if (ps.isEmpty) return '';
    return (ps.firstWhere((p) => p['is_main'] == true, orElse: () => ps.first)['id'] ?? '').toString();
  }

  /// Messagerie multi-profil : la conversation s'affiche-t-elle dans la
  /// messagerie du profil actif ? Chaque côté est marqué par un profil
  /// (pro_profile_id = celui qui l'a ouverte, consumer_profile_id = le
  /// destinataire) ; un côté non marqué revient au profil PRINCIPAL de ce
  /// participant. Même règle pour la liste et la bulle de non-lus.
  /// Miroir site : website/src/lib/conversations-profil.ts.
  static bool visiblePourProfilActif(Map conv) {
    if (conv['type']?.toString() == 'groupe') return true;
    // Seuls MES profils comptent pour savoir de quel côté je suis : la liste
    // des profils contient aussi ceux auxquels j'ai accès (cogérance,
    // employeur) — un message envoyé depuis l'élevage de ma mère n'est pas
    // « de moi » côté élevage, il m'est adressé côté pension.
    final monUid = _myUid;
    final miens = User_Info.availableProfiles
        .where((p) => (p['uid']?.toString() ?? monUid) == monUid)
        .map((p) => p['id']?.toString() ?? '').where((x) => x.isNotEmpty).toSet();
    if (miens.isEmpty) return true;
    final pro = conv['pro_profile_id']?.toString() ?? '';
    final con = conv['consumer_profile_id']?.toString() ?? '';
    final actif = User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : _profilPrincipal;
    final mien = miens.contains(pro) ? pro
        : miens.contains(con) ? con
        // Profil partagé actif (cogérance) présent dans la conversation.
        : (actif == pro || actif == con) ? actif
        : _profilPrincipal;
    return mien == actif;
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

    // Une conversation relie DEUX profils précis (comme une page Facebook) :
    // mon profil actif (sinon principal) et le profil contacté (sinon son
    // profil principal). Écrire à la pension de quelqu'un ou à la personne
    // elle-même donne deux conversations distinctes, chacune dans la bonne
    // messagerie.
    myProfileId ??= _profilPrincipal.isEmpty ? null : _profilPrincipal;
    if (otherProfileId == null) {
      try {
        final p = await _supa.from('user_profiles').select('id').eq('uid', otherUid).eq('is_main', true).maybeSingle();
        otherProfileId = p?['id']?.toString();
      } catch (_) {}
    }

    // Conversation existante entre ces deux profils.
    var q = _supa.from('conversations').select('id').eq('participant_ids', sorted).eq('type', 'direct');
    if (myProfileId != null && otherProfileId != null) {
      q = q.or('and(pro_profile_id.eq.$myProfileId,consumer_profile_id.eq.$otherProfileId),'
          'and(pro_profile_id.eq.$otherProfileId,consumer_profile_id.eq.$myProfileId)');
    } else if (myProfileId != null) {
      q = q.or('pro_profile_id.eq.$myProfileId,consumer_profile_id.eq.$myProfileId');
    }
    final existing = await q.limit(1).maybeSingle();
    if (existing != null) return existing['id'].toString();

    // Créer une nouvelle conversation
    final myData    = await getDisplayInfo(myUid, profileId: myProfileId);
    final otherData = await getDisplayInfo(otherUid, profileId: otherProfileId);

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
      'updated_at':        DateTime.now().toUtc().toIso8601String(),
      if (categorie != null)    'categorie':            categorie,
      if (myProfileId != null)  'pro_profile_id':       myProfileId,
      if (otherProfileId != null) 'consumer_profile_id': otherProfileId,
    }).select('id').single();

    return created['id'].toString();
  }
}
