import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Vitesse moyenne lisible (« 4,2 km/h »), ou « – » tant que la mesure n'a
/// pas de sens (tout début de balade, quasi aucune distance).
String baladeVitesseLabel(double distanceM, int dureeSecondes) {
  if (dureeSecondes < 30 || distanceM < 20) return '–';
  final kmh = (distanceM / 1000) / (dureeSecondes / 3600);
  return '${kmh.toStringAsFixed(1).replaceAll('.', ',')} km/h';
}

/// Balade lancée par erreur, pas encore terminée : rien n'a été compté
/// (XP / flamme sont créés au récap de fin) → on efface simplement la
/// ligne « en cours ».
Future<void> abandonnerBalade(String? baladeId) async {
  if (baladeId == null) return;
  try {
    await Supabase.instance.client.from('balades_perso').delete()
        .eq('id', baladeId).eq('statut', 'en_cours');
  } catch (_) {}
}

/// Supprime une balade TERMINÉE et défait ce qu'elle a produit :
/// - l'XP gagnée par l'animal (xp_earned retiré de animaux.xp, jamais < 0) ;
/// - la ligne activity_log créée par GamificationService.recordBalade, et le
///   post automatique « 🚶 Balade avec … » des balades antérieures au
///   29/09/2026 (publié sans demander, supprimé depuis) — retrouvés par animal
///   + XP + fenêtre de temps autour de la fin de balade, faute d'identifiant ;
/// - les photos de la balade (bucket social) ;
/// - la balade elle-même.
/// Volontairement NON défait : la flamme du jour (impossible de savoir sans
/// risque si une autre activité l'aurait aussi entretenue) et les posts /
/// stories partagés explicitement par l'utilisateur.
Future<bool> supprimerBalade(String baladeId) async {
  final supa = Supabase.instance.client;
  final b = await supa.from('balades_perso').select().eq('id', baladeId).maybeSingle();
  if (b == null) return false;
  final uid = b['uid']?.toString() ?? '';
  final animalId = b['animal_id']?.toString() ?? '';
  final xp = (b['xp_earned'] as num?)?.toInt() ?? 0;
  final ended = DateTime.tryParse(b['ended_at']?.toString() ?? '');

  if (xp > 0 && animalId.isNotEmpty) {
    try {
      final a = await supa.from('animaux').select('xp').eq('id', animalId).maybeSingle();
      if (a != null) {
        final cur = (a['xp'] as num?)?.toInt() ?? 0;
        await supa.from('animaux').update({'xp': math.max(0, cur - xp)}).eq('id', animalId);
      }
    } catch (_) {}
  }

  if (ended != null && xp > 0) {
    // recordBalade tourne à l'ouverture du récap, quelques secondes après la
    // fin. ⚠️ Les balades enregistrées avant le 29/09/2026 ont un ended_at en
    // heure LOCALE étiquetée UTC (décalé de +1/+2 h) : on cherche donc dans une
    // fenêtre large et on garde la ligne la plus proche de l'une des deux
    // heures de fin possibles (vraie UTC, ou locale reconvertie).
    final endLocalFix = DateTime(ended.year, ended.month, ended.day, ended.hour,
        ended.minute, ended.second).toUtc();
    final from = ended.subtract(const Duration(hours: 3)).toUtc().toIso8601String();
    final to = ended.add(const Duration(minutes: 15)).toUtc().toIso8601String();
    int distance(Object? createdAt) {
      final c = DateTime.tryParse(createdAt?.toString() ?? '');
      if (c == null) return 1 << 30;
      return math.min(c.difference(ended).inSeconds.abs(), c.difference(endLocalFix).inSeconds.abs());
    }
    Map? closest(List rows, bool Function(Map) keep) {
      Map? best;
      for (final r in rows) {
        final m = r as Map;
        if (!keep(m)) continue;
        if (best == null || distance(m['created_at']) < distance(best['created_at'])) best = m;
      }
      // Au-delà de 15 min de l'heure de fin corrigée, ce n'est pas cette balade.
      return (best != null && distance(best['created_at']) <= 900) ? best : null;
    }
    try {
      final posts = await supa.from('posts_socialmedia').select('id, data, created_at')
          .eq('uid', uid).eq('post_type', 'balade_terminee')
          .gte('created_at', from).lte('created_at', to).limit(20);
      final p = closest(posts as List, (m) {
        final d = m['data'] as Map?;
        return d?['animal_id']?.toString() == animalId && (d?['xp_earned'] as num?)?.toInt() == xp;
      });
      if (p != null) await supa.from('posts_socialmedia').delete().eq('id', p['id']);
    } catch (_) {}
    try {
      final logs = await supa.from('activity_log').select('id, created_at')
          .eq('uid', uid).eq('animal_id', animalId).eq('activity_type', 'balade').eq('xp_earned', xp)
          .gte('created_at', from).lte('created_at', to).limit(20);
      final l = closest(logs as List, (_) => true);
      if (l != null) await supa.from('activity_log').delete().eq('id', l['id']);
    } catch (_) {}
  }

  final photos = (b['photos'] as List?)?.cast<String>() ?? const <String>[];
  final paths = <String>[
    for (final url in photos)
      if (url.contains('/object/public/social/')) Uri.decodeComponent(url.split('/object/public/social/').last),
  ];
  if (paths.isNotEmpty) {
    try { await supa.storage.from('social').remove(paths); } catch (_) {}
  }

  await supa.from('balades_perso').delete().eq('id', baladeId);
  return true;
}
