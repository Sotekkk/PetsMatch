import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:PetsMatch/pages/particulier/social_feed_page.dart' show socialProfileName;

/// Fonds proposés pour une story "texte" (sans photo/vidéo) — partagé entre
/// la création et le visionnage pour rendre exactement le même dégradé.
const kStoryFonds = <(String, List<Color>)>[
  ('grad_sunset', [Color(0xFFFF6B6B), Color(0xFFFFD166)]),
  ('grad_ocean',  [Color(0xFF0C5C6C), Color(0xFF4ECDC4)]),
  ('grad_forest', [Color(0xFF2E7D5E), Color(0xFF6E9E57)]),
  ('grad_purple', [Color(0xFF6A4C93), Color(0xFFB185DB)]),
  ('grad_night',  [Color(0xFF0D1F22), Color(0xFF1F2A2E)]),
  ('grad_pink',   [Color(0xFFFF8FA3), Color(0xFFFFC6D9)]),
  ('solid_black', [Colors.black, Colors.black]),
  ('solid_white', [Colors.white, Colors.white]),
];

List<Color> storyFondColors(String? fondId) {
  final f = kStoryFonds.where((f) => f.$1 == fondId).firstOrNull;
  return f?.$2 ?? kStoryFonds.first.$2;
}

/// Modèle + accès données pour les Stories Pets Social (éphémères 24h,
/// musique piochée dans la bibliothèque maison — jamais d'import libre côté
/// utilisateur, cf. supabase/migration_stories.sql).

class StoryMusicTrack {
  final String id;
  final String titre;
  final String? artiste;
  final String urlAudio;
  final int? dureeSecondes;

  StoryMusicTrack({required this.id, required this.titre, this.artiste, required this.urlAudio, this.dureeSecondes});

  factory StoryMusicTrack.fromRow(Map<String, dynamic> r) => StoryMusicTrack(
        id: r['id'].toString(),
        titre: r['titre']?.toString() ?? '',
        artiste: r['artiste']?.toString(),
        urlAudio: r['url_audio']?.toString() ?? '',
        dureeSecondes: r['duree_secondes'] as int?,
      );
}

class StoryItem {
  final String id;
  final String authorProfileId;
  final String authorUid;
  final String mediaUrl;
  final String mediaType; // 'photo' | 'video' | 'texte'
  final String? fond; // fond choisi, uniquement pour mediaType == 'texte'
  final int? dureeSecondes;
  final String? legende; // balisage @[Nom](profileId), comme Pets Social/Forum/Groupes
  final String legendeCouleur;
  final String legendeTaille; // 's' | 'm' | 'l'
  final bool legendeGras;
  final double legendeX; // 0..1, position libre sur le média (glisser-déposer)
  final double legendeY;
  final DateTime createdAt;
  final DateTime expiresAt;
  final StoryMusicTrack? music;
  bool vue;

  StoryItem({
    required this.id, required this.authorProfileId, required this.authorUid,
    required this.mediaUrl, required this.mediaType, this.fond, this.dureeSecondes, this.legende,
    this.legendeCouleur = '#FFFFFF', this.legendeTaille = 'm', this.legendeGras = false,
    this.legendeX = 0.5, this.legendeY = 0.85,
    required this.createdAt, required this.expiresAt, this.music, this.vue = false,
  });

  factory StoryItem.fromRow(Map<String, dynamic> r) {
    final musicRow = r['story_music_tracks'] as Map<String, dynamic>?;
    return StoryItem(
      id: r['id'].toString(),
      authorProfileId: r['author_profile_id'].toString(),
      authorUid: r['uid'].toString(),
      mediaUrl: r['media_url']?.toString() ?? '',
      mediaType: r['media_type']?.toString() ?? 'photo',
      fond: r['fond']?.toString(),
      dureeSecondes: r['duree_secondes'] as int?,
      legende: r['legende']?.toString(),
      legendeCouleur: r['legende_couleur']?.toString() ?? '#FFFFFF',
      legendeTaille: r['legende_taille']?.toString() ?? 'm',
      legendeGras: r['legende_gras'] as bool? ?? false,
      legendeX: (r['legende_x'] as num?)?.toDouble() ?? 0.5,
      legendeY: (r['legende_y'] as num?)?.toDouble() ?? 0.85,
      createdAt: DateTime.parse(r['created_at'].toString()),
      expiresAt: DateTime.parse(r['expires_at'].toString()),
      music: musicRow != null ? StoryMusicTrack.fromRow(musicRow) : null,
    );
  }
}

class StoryGroup {
  final String authorProfileId;
  final String authorUid;
  final Map<String, dynamic>? authorProfile;
  final List<StoryItem> items;
  StoryGroup({required this.authorProfileId, required this.authorUid, this.authorProfile, required this.items});
  bool get allSeen => items.every((s) => s.vue);
}

const _kStoryCols = 'id, uid, author_profile_id, media_url, media_type, fond, duree_secondes, legende, '
    'legende_couleur, legende_taille, legende_gras, legende_x, legende_y, '
    'created_at, expires_at, story_music_tracks(id, titre, artiste, url_audio, duree_secondes)';

class StoryService {
  static final _supa = Supabase.instance.client;

  /// Groupes de stories actives (non expirées) DES PROFILS QUE JE SUIS (+
  /// les miennes) — mêmes règles de visibilité que « Mon feed », pas les
  /// stories de n'importe qui : si Natacha me suit, elle a bien MON profil
  /// dans sa liste de « suivis » et voit donc mes stories ; ce n'est PAS
  /// réciproque (je ne vois pas forcément les siennes si je ne la suis pas).
  /// Triées : moi d'abord, puis non-vues avant vues, puis plus récent d'abord.
  static Future<List<StoryGroup>> loadActiveGroups({required String myUid, String? myProfileId}) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    var q = _supa.from('stories').select(_kStoryCols).gt('expires_at', nowIso);
    if (myProfileId != null && myProfileId.isNotEmpty) {
      final follows = await _supa.from('follows').select('following_profile_id')
          .eq('follower_profile_id', myProfileId);
      final followedIds = (follows as List)
          .map((f) => f['following_profile_id']?.toString())
          .whereType<String>()
          .toSet()
        ..add(myProfileId);
      q = q.inFilter('author_profile_id', followedIds.toList());
    }
    final rows = await q.order('created_at', ascending: true);
    final items = (rows as List).map((r) => StoryItem.fromRow(Map<String, dynamic>.from(r))).toList();
    if (items.isEmpty) return [];

    // Vues par MOI (profil actif) — marque chaque item.
    if (myProfileId != null && myProfileId.isNotEmpty) {
      final storyIds = items.map((s) => s.id).toList();
      final views = await _supa.from('story_views').select('story_id')
          .inFilter('story_id', storyIds).eq('viewer_profile_id', myProfileId);
      final seenIds = (views as List).map((v) => v['story_id'].toString()).toSet();
      for (final s in items) { s.vue = seenIds.contains(s.id); }
    }

    // Profils auteurs (mêmes colonnes que Pets Social pour un rendu cohérent).
    final authorIds = items.map((s) => s.authorProfileId).toSet().toList();
    final profRows = await _supa.from('user_profiles')
        .select('id, uid, firstname, lastname, avatar_url, profile_picture_url_pro, profile_type, nom, is_influencer, social_pseudo')
        .inFilter('id', authorIds);
    final profByI = {for (final p in (profRows as List)) p['id'].toString(): Map<String, dynamic>.from(p)};

    final grouped = <String, List<StoryItem>>{};
    for (final s in items) {
      grouped.putIfAbsent(s.authorProfileId, () => []).add(s);
    }
    final groups = grouped.entries.map((e) => StoryGroup(
          authorProfileId: e.key,
          authorUid: e.value.first.authorUid,
          authorProfile: profByI[e.key],
          items: e.value,
        )).toList();

    groups.sort((a, b) {
      final aMine = a.authorProfileId == myProfileId;
      final bMine = b.authorProfileId == myProfileId;
      if (aMine != bMine) return aMine ? -1 : 1;
      if (a.allSeen != b.allSeen) return a.allSeen ? 1 : -1;
      return b.items.last.createdAt.compareTo(a.items.last.createdAt);
    });
    return groups;
  }

  static Future<List<StoryMusicTrack>> loadMusicLibrary() async {
    final rows = await _supa.from('story_music_tracks').select('id, titre, artiste, url_audio, duree_secondes')
        .eq('actif', true).order('titre');
    return (rows as List).map((r) => StoryMusicTrack.fromRow(Map<String, dynamic>.from(r))).toList();
  }

  static Future<void> markViewed(String storyId, {required String viewerUid, String? viewerProfileId}) async {
    try {
      await _supa.from('story_views').upsert({
        'story_id': storyId,
        'viewer_uid': viewerUid,
        if (viewerProfileId != null) 'viewer_profile_id': viewerProfileId,
      }, onConflict: 'story_id,viewer_profile_id');
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> viewers(String storyId) async {
    final rows = await _supa.from('story_views').select('viewer_profile_id, viewed_at')
        .eq('story_id', storyId).order('viewed_at', ascending: false);
    final ids = (rows as List).map((r) => r['viewer_profile_id']?.toString()).whereType<String>().toList();
    if (ids.isEmpty) return [];
    final profRows = await _supa.from('user_profiles')
        .select('id, firstname, lastname, avatar_url, profile_picture_url_pro, profile_type, nom, social_pseudo')
        .inFilter('id', ids);
    final profByI = {for (final p in (profRows as List)) p['id'].toString(): Map<String, dynamic>.from(p)};
    return rows.map((r) {
      final pid = r['viewer_profile_id']?.toString();
      return {'viewed_at': r['viewed_at'], 'profile': pid != null ? profByI[pid] : null};
    }).toList();
  }

  static Future<bool> isLiked(String storyId, String? profileId) async {
    if (profileId == null || profileId.isEmpty) return false;
    final row = await _supa.from('story_likes').select('id')
        .eq('story_id', storyId).eq('liker_profile_id', profileId).maybeSingle();
    return row != null;
  }

  static Future<int> likesCount(String storyId) async {
    final rows = await _supa.from('story_likes').select('id').eq('story_id', storyId);
    return (rows as List).length;
  }

  /// Bascule le like et renvoie le nouvel état. Notifie l'auteur uniquement
  /// au moment où le like est posé (pas au retrait), en évitant les
  /// doublons si l'utilisateur tape plusieurs fois d'affilée.
  static Future<bool> toggleLike(
    String storyId, {
    required String uid, required String? profileId,
    required String authorUid, required String authorProfileId,
  }) async {
    if (profileId == null || profileId.isEmpty) return false;
    final existing = await _supa.from('story_likes').select('id')
        .eq('story_id', storyId).eq('liker_profile_id', profileId).maybeSingle();
    if (existing != null) {
      await _supa.from('story_likes').delete().eq('id', existing['id']);
      return false;
    }
    await _supa.from('story_likes').insert({'story_id': storyId, 'uid': uid, 'liker_profile_id': profileId});
    if (authorUid != uid) {
      try {
        final since = DateTime.now().toUtc().subtract(const Duration(minutes: 1)).toIso8601String();
        final dup = await _supa.from('notifications').select('id')
            .eq('uid', authorUid).eq('type', 'story_like').eq('profile_id', authorProfileId)
            .contains('data', {'story_id': storyId, 'liker_profile_id': profileId})
            .gte('created_at', since).limit(1).maybeSingle();
        if (dup == null) {
          final me = await _supa.from('user_profiles').select('firstname, lastname, nom, social_pseudo, profile_type')
              .eq('id', profileId).maybeSingle();
          final nom = me != null ? socialProfileName(me) : 'Quelqu\'un';
          await _supa.from('notifications').insert({
            'uid': authorUid,
            'type': 'story_like',
            'profile_id': authorProfileId,
            'title': '$nom a aimé ta story',
            'body': '❤️',
            'data': {'story_id': storyId, 'liker_profile_id': profileId},
            'read': false,
          });
        }
      } catch (_) {}
    }
    return true;
  }

  static Future<String> createStory({
    required String uid, required String authorProfileId,
    String? mediaUrl, required String mediaType, String? fond,
    int? dureeSecondes, String? musicTrackId, String? legende,
    String legendeCouleur = '#FFFFFF', String legendeTaille = 'm', bool legendeGras = false,
    double legendeX = 0.5, double legendeY = 0.85,
  }) async {
    final res = await _supa.from('stories').insert({
      'uid': uid,
      'author_profile_id': authorProfileId,
      if (mediaUrl != null) 'media_url': mediaUrl,
      'media_type': mediaType,
      if (fond != null) 'fond': fond,
      if (dureeSecondes != null) 'duree_secondes': dureeSecondes,
      if (musicTrackId != null) 'music_track_id': musicTrackId,
      if (legende != null && legende.isNotEmpty) ...{
        'legende': legende,
        'legende_couleur': legendeCouleur,
        'legende_taille': legendeTaille,
        'legende_gras': legendeGras,
        'legende_x': legendeX,
        'legende_y': legendeY,
      },
    }).select('id').single();
    return res['id'].toString();
  }

  static Future<void> deleteStory(String storyId, {String? mediaUrl}) async {
    await _supa.from('stories').delete().eq('id', storyId);
    if (mediaUrl == null || mediaUrl.isEmpty) return;
    try {
      final path = Uri.parse(mediaUrl).pathSegments;
      final idx = path.indexOf('stories');
      if (idx != -1 && idx + 1 < path.length) {
        await _supa.storage.from('stories').remove([path.sublist(idx + 1).join('/')]);
      }
    } catch (_) {}
  }
}
