import 'package:supabase_flutter/supabase_flutter.dart';

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
  final String mediaType; // 'photo' | 'video'
  final int? dureeSecondes;
  final String? legende;
  final DateTime createdAt;
  final DateTime expiresAt;
  final StoryMusicTrack? music;
  bool vue;

  StoryItem({
    required this.id, required this.authorProfileId, required this.authorUid,
    required this.mediaUrl, required this.mediaType, this.dureeSecondes, this.legende,
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
      dureeSecondes: r['duree_secondes'] as int?,
      legende: r['legende']?.toString(),
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

const _kStoryCols = 'id, uid, author_profile_id, media_url, media_type, duree_secondes, legende, '
    'created_at, expires_at, story_music_tracks(id, titre, artiste, url_audio, duree_secondes)';

class StoryService {
  static final _supa = Supabase.instance.client;

  /// Groupes de stories actives (non expirées), triées : moi d'abord, puis
  /// non-vues avant vues, puis plus récent d'abord.
  static Future<List<StoryGroup>> loadActiveGroups({required String myUid, String? myProfileId}) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final rows = await _supa.from('stories').select(_kStoryCols)
        .gt('expires_at', nowIso).order('created_at', ascending: true);
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

  static Future<String> createStory({
    required String uid, required String authorProfileId,
    required String mediaUrl, required String mediaType,
    int? dureeSecondes, String? musicTrackId, String? legende,
  }) async {
    final res = await _supa.from('stories').insert({
      'uid': uid,
      'author_profile_id': authorProfileId,
      'media_url': mediaUrl,
      'media_type': mediaType,
      if (dureeSecondes != null) 'duree_secondes': dureeSecondes,
      if (musicTrackId != null) 'music_track_id': musicTrackId,
      if (legende != null && legende.isNotEmpty) 'legende': legende,
    }).select('id').single();
    return res['id'].toString();
  }

  static Future<void> deleteStory(String storyId, {required String mediaUrl}) async {
    await _supa.from('stories').delete().eq('id', storyId);
    try {
      final path = Uri.parse(mediaUrl).pathSegments;
      final idx = path.indexOf('stories');
      if (idx != -1 && idx + 1 < path.length) {
        await _supa.storage.from('stories').remove([path.sublist(idx + 1).join('/')]);
      }
    } catch (_) {}
  }
}
