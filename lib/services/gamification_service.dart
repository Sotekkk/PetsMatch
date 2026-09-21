import 'package:supabase_flutter/supabase_flutter.dart';

/// Boucle centrale de gamification — Phase 1.
/// Activité réelle (balade) → XP animal + palier → flamme → carte de feed.
class BaladeResult {
  final int xpEarned;
  final int totalXp;
  final String previousTier;
  final String newTier;
  final bool tierEvolved;
  final int streakCount;
  final bool streakIncremented;

  const BaladeResult({
    required this.xpEarned,
    required this.totalXp,
    required this.previousTier,
    required this.newTier,
    required this.tierEvolved,
    required this.streakCount,
    required this.streakIncremented,
  });
}

class GamificationService {
  GamificationService._();
  static final GamificationService instance = GamificationService._();

  static const List<String> tierOrder = [
    'decouverte', 'bronze', 'argent', 'or', 'legendaire',
  ];

  static String tierLabel(String tier) => switch (tier) {
    'decouverte' => 'Découverte',
    'bronze' => 'Bronze',
    'argent' => 'Argent',
    'or' => 'Or',
    'legendaire' => 'Légendaire',
    _ => tier,
  };

  SupabaseClient get _supa => Supabase.instance.client;

  /// XP gagné pour une balade : basé sur la distance si connue (10 XP/km),
  /// sinon sur la durée (1 XP/min). Cf. spec 3.2 : "calculé selon distance
  /// ou durée" — pas de formule imposée, valeurs à ajuster après retours.
  int computeXp({double? distanceKm, int? dureeMinutes}) {
    if (distanceKm != null && distanceKm > 0) {
      return (distanceKm * 10).round().clamp(1, 500);
    }
    if (dureeMinutes != null && dureeMinutes > 0) {
      return dureeMinutes.clamp(1, 500);
    }
    return 0;
  }

  /// Enregistre une balade : crée l'activity_log, met à jour l'XP/palier de
  /// l'animal, la flamme du profil, et publie les cartes de feed +
  /// notification d'évolution le cas échéant.
  Future<BaladeResult> recordBalade({
    required String uid,
    String? profileId,
    required String animalId,
    required String espece,
    double? distanceKm,
    int? dureeMinutes,
  }) async {
    final xpEarned = computeXp(distanceKm: distanceKm, dureeMinutes: dureeMinutes);
    // Normalise l'espèce en minuscule pour correspondre à species_object_tiers
    final especeKey = espece.trim().toLowerCase();

    // Résout le profil actif — si absent, prend le profil principal (is_main)
    // pour garantir que la flamme est toujours mise à jour (cf. note Angel :
    // user_id seul ne suffit pas, il faut le profile_id pour éviter les doublons).
    String? pid = (profileId != null && profileId.isNotEmpty) ? profileId : null;
    if (pid == null && uid.isNotEmpty) {
      final mainRow = await _supa
          .from('user_profiles')
          .select('id')
          .eq('uid', uid)
          .eq('is_main', true)
          .maybeSingle();
      pid = mainRow?['id']?.toString();
    }

    await _supa.from('activity_log').insert({
      'uid': uid,
      if (pid != null) 'profile_id': pid,
      'animal_id': animalId,
      'activity_type': 'balade',
      'xp_earned': xpEarned,
      'counts_for_streak': true,
      if (distanceKm != null) 'distance_km': distanceKm,
      if (dureeMinutes != null) 'duree_minutes': dureeMinutes,
    });

    final animalRow = await _supa
        .from('animaux')
        .select('xp, object_tier, nom')
        .eq('id', animalId)
        .single();
    final previousTier = (animalRow['object_tier'] as String?) ?? 'decouverte';
    final animalNom = (animalRow['nom'] as String?)?.trim().isNotEmpty == true
        ? animalRow['nom'] as String
        : 'Votre animal';
    final newTotalXp = ((animalRow['xp'] as num?)?.toInt() ?? 0) + xpEarned;

    final tiersRaw = await _supa
        .from('species_object_tiers')
        .select('tier, xp_threshold')
        .eq('species', especeKey)
        .order('xp_threshold');
    var newTier = previousTier;
    for (final t in (tiersRaw as List)) {
      final threshold = ((t as Map)['xp_threshold'] as num).toInt();
      if (newTotalXp >= threshold) newTier = t['tier'] as String;
    }
    final tierEvolved = newTier != previousTier &&
        tierOrder.indexOf(newTier) > tierOrder.indexOf(previousTier);

    await _supa.from('animaux').update({
      'xp': newTotalXp,
      if (tierEvolved) 'object_tier': newTier,
    }).eq('id', animalId);

    var streakCount = 0;
    var streakIncremented = false;
    if (pid != null) {
      final result = await _applyStreak(pid);
      streakCount = result.$1;
      streakIncremented = result.$2;
    }

    await _publishFeedAndNotif(
      uid: uid,
      profileId: pid,
      animalId: animalId,
      animalNom: animalNom,
      xpEarned: xpEarned,
      distanceKm: distanceKm,
      dureeMinutes: dureeMinutes,
      tierEvolved: tierEvolved,
      newTier: newTier,
    );

    return BaladeResult(
      xpEarned: xpEarned,
      totalXp: newTotalXp,
      previousTier: previousTier,
      newTier: newTier,
      tierEvolved: tierEvolved,
      streakCount: streakCount,
      streakIncremented: streakIncremented,
    );
  }

  /// Met à jour la flamme du profil et retourne (nouveau compteur, incrémenté ?).
  /// Rupture de série = perte sèche, avec 1 jour de retard toléré par semaine.
  Future<(int, bool)> _applyStreak(String profileId) async {
    final profRow = await _supa
        .from('user_profiles')
        .select('streak_count, streak_last_activity_date, streak_grace_used_this_week')
        .eq('id', profileId)
        .maybeSingle();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentStreak = (profRow?['streak_count'] as num?)?.toInt() ?? 0;
    var graceUsed = profRow?['streak_grace_used_this_week'] as bool? ?? false;
    DateTime? lastDate;
    final rawLast = profRow?['streak_last_activity_date'];
    if (rawLast != null) lastDate = DateTime.tryParse(rawLast.toString());

    int newStreak;
    bool incremented;
    if (lastDate == null) {
      newStreak = 1;
      incremented = true;
    } else {
      final lastDay = DateTime(lastDate.year, lastDate.month, lastDate.day);
      final diffDays = today.difference(lastDay).inDays;
      if (diffDays <= 0) {
        newStreak = currentStreak == 0 ? 1 : currentStreak;
        incremented = false;
      } else if (diffDays == 1) {
        newStreak = currentStreak + 1;
        incremented = true;
      } else if (diffDays == 2 && !graceUsed) {
        // Garde-fou léger : 1 jour de retard toléré par semaine.
        newStreak = currentStreak + 1;
        incremented = true;
        graceUsed = true;
      } else {
        newStreak = 1;
        incremented = true;
        graceUsed = false;
      }
    }

    await _supa.from('user_profiles').update({
      'streak_count': newStreak,
      'streak_last_activity_date':
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
      'streak_grace_used_this_week': graceUsed,
    }).eq('id', profileId);

    return (newStreak, incremented);
  }

  Future<void> _publishFeedAndNotif({
    required String uid,
    String? profileId,
    required String animalId,
    required String animalNom,
    required int xpEarned,
    double? distanceKm,
    int? dureeMinutes,
    required bool tierEvolved,
    required String newTier,
  }) async {
    try {
      final parts = <String>[];
      if (distanceKm != null && distanceKm > 0) parts.add('${distanceKm.toStringAsFixed(1)} km');
      if (dureeMinutes != null && dureeMinutes > 0) parts.add('$dureeMinutes min');
      final detail = parts.isEmpty ? '' : ' (${parts.join(' · ')})';
      await _supa.from('posts_socialmedia').insert({
        'uid': uid,
        if (profileId != null) 'author_profile_id': profileId,
        'texte': '🚶 Balade avec $animalNom$detail — +$xpEarned XP',
        'tagged_animal_ids': [animalId],
        'visibilite': 'public',
        'post_type': 'balade_terminee',
        'data': {
          'animal_id': animalId,
          'xp_earned': xpEarned,
          if (distanceKm != null) 'distance_km': distanceKm,
          if (dureeMinutes != null) 'duree_minutes': dureeMinutes,
        },
      });

      if (tierEvolved) {
        await _supa.from('posts_socialmedia').insert({
          'uid': uid,
          if (profileId != null) 'author_profile_id': profileId,
          'texte': '✨ $animalNom passe au palier ${tierLabel(newTier)} !',
          'tagged_animal_ids': [animalId],
          'visibilite': 'public',
          'post_type': 'evolution',
          'data': {'animal_id': animalId, 'tier': newTier},
        });
        await _supa.from('notifications').insert({
          'uid': uid,
          'type': 'animal_evolution',
          if (profileId != null) 'profile_id': profileId,
          'title': '$animalNom a évolué !',
          'body': 'Nouveau palier : ${tierLabel(newTier)}',
          'data': {'animal_id': animalId, 'tier': newTier},
          'read': false,
        });
      }
    } catch (_) {
      // Le feed/la notif sont accessoires : une balade doit rester
      // enregistrée (XP + flamme) même si cette étape échoue.
    }
  }
}
