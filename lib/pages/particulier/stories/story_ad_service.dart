import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'story_service.dart';

/// Story publicitaire (régie interne, pas de SDK tiers) — gérée depuis
/// /admin (table `story_ads`), injectée côté client dans le flux de stories
/// toutes les N stories cumulées vues (cf. StoryRing._openViewer).
class StoryAd {
  final String id;
  final String annonceurNom;
  final String? annonceurLogoUrl;
  final String mediaUrl;
  final String mediaType; // 'photo' | 'video'
  final int? dureeSecondes;
  final String ctaLabel;
  final String? lienUrl;

  StoryAd({
    required this.id, required this.annonceurNom, this.annonceurLogoUrl,
    required this.mediaUrl, required this.mediaType, this.dureeSecondes,
    required this.ctaLabel, this.lienUrl,
  });

  factory StoryAd.fromRow(Map<String, dynamic> r) => StoryAd(
        id: r['id'].toString(),
        annonceurNom: r['annonceur_nom']?.toString() ?? 'Sponsorisé',
        annonceurLogoUrl: r['annonceur_logo_url']?.toString(),
        mediaUrl: r['media_url']?.toString() ?? '',
        mediaType: r['media_type']?.toString() ?? 'photo',
        dureeSecondes: r['duree_secondes'] as int?,
        ctaLabel: r['cta_label']?.toString() ?? 'En savoir plus',
        lienUrl: r['lien_url']?.toString(),
      );

  /// Convertit cette pub en StoryGroup/StoryItem synthétiques, pour être
  /// injectée directement dans la liste de groupes passée à StoryViewerPage
  /// — réutilise ainsi toute la mécanique de navigation/progress bars
  /// existante sans dupliquer de code.
  StoryGroup toStoryGroup() {
    final item = StoryItem(
      id: 'ad:$id',
      authorProfileId: 'ad:$id',
      authorUid: 'ad:$id',
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      dureeSecondes: dureeSecondes,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 1)),
      isAd: true,
      adId: id,
      ctaLabel: ctaLabel,
      lienUrl: lienUrl,
    );
    return StoryGroup(
      authorProfileId: 'ad:$id',
      authorUid: 'ad:$id',
      authorProfile: {
        'firstname': annonceurNom,
        'lastname': '',
        'avatar_url': annonceurLogoUrl,
      },
      items: [item],
    );
  }
}

class StoryAdService {
  static final _supa = Supabase.instance.client;

  /// Insère une story pub toutes les N stories cumulées (façon Instagram).
  static const int adsEveryNStories = 5;

  static Future<List<StoryAd>> loadActiveAds() async {
    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final rows = await _supa.from('story_ads').select()
          .eq('actif', true)
          .lte('date_debut', nowIso)
          .or('date_fin.is.null,date_fin.gt.$nowIso');
      return (rows as List).map((r) => StoryAd.fromRow(Map<String, dynamic>.from(r))).toList();
    } catch (_) {
      return [];
    }
  }

  /// Intercale une pub (pondérée aléatoirement parmi les actives) toutes les
  /// [adsEveryNStories] stories cumulées de la liste de groupes réels.
  static List<StoryGroup> interleave(List<StoryGroup> groups, List<StoryAd> ads) {
    if (ads.isEmpty) return groups;
    final rng = Random();
    final result = <StoryGroup>[];
    var cumulative = 0;
    for (final g in groups) {
      result.add(g);
      cumulative += g.items.length;
      if (cumulative >= adsEveryNStories) {
        result.add(ads[rng.nextInt(ads.length)].toStoryGroup());
        cumulative = 0;
      }
    }
    return result;
  }

  static Future<void> registerImpression(String adId) async {
    try {
      await _supa.rpc('increment_story_ad_impressions', params: {'ad_id': adId});
    } catch (_) {
      // Fallback si la fonction RPC n'existe pas encore côté DB.
      try {
        final row = await _supa.from('story_ads').select('impressions').eq('id', adId).maybeSingle();
        if (row != null) {
          await _supa.from('story_ads').update({'impressions': (row['impressions'] as int? ?? 0) + 1}).eq('id', adId);
        }
      } catch (_) {}
    }
  }

  static Future<void> registerClick(String adId) async {
    try {
      await _supa.rpc('increment_story_ad_clics', params: {'ad_id': adId});
    } catch (_) {
      try {
        final row = await _supa.from('story_ads').select('clics').eq('id', adId).maybeSingle();
        if (row != null) {
          await _supa.from('story_ads').update({'clics': (row['clics'] as int? ?? 0) + 1}).eq('id', adId);
        }
      } catch (_) {}
    }
  }
}
