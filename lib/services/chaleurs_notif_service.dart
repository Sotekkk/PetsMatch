import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart';

class ChaleursNotifService {
  static const _channelId   = 'chaleurs_channel';
  static const _channelName = 'Chaleurs animaux';

  static int _intervalChaleurs(String espece) {
    switch (espece.toLowerCase()) {
      case 'chien':  return 182;
      case 'chat':   return 21;
      case 'lapin':  return 14;
      case 'ovin':   return 17;
      case 'caprin': return 21;
      case 'porcin': return 21;
      case 'cheval': return 21;
      default:       return 0;
    }
  }

  static String _emoji(String espece) {
    switch (espece.toLowerCase()) {
      case 'chien':  return '🐕';
      case 'chat':   return '🐈';
      case 'cheval': return '🐴';
      case 'lapin':  return '🐰';
      case 'ovin':   return '🐑';
      case 'caprin': return '🐐';
      case 'porcin': return '🐷';
      default:       return '🐾';
    }
  }

  /// À appeler à l'ouverture de MesAnimauxPage (éleveur).
  /// Envoie une notification locale pour chaque femelle en chaleurs
  /// aujourd'hui, demain ou en retard — avec nom, race et espèce.
  static Future<void> checkAndNotify() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final supa = Supabase.instance.client;

    final List<dynamic> animaux;
    try {
      animaux = await supa
          .from('animaux')
          .select('id, nom, race, espece, intervalle_chaleurs_jours')
          .eq('uid_eleveur', uid)
          .eq('sexe', 'femelle')
          .not('statut', 'in', '("sorti","decede")');
    } catch (_) { return; }

    if (animaux.isEmpty) return;
    final femIds = animaux.map((a) => (a as Map)['id'] as String).toList();

    final List<dynamic> chaleurs;
    try {
      chaleurs = await supa
          .from('chaleurs')
          .select('animal_id, date')
          .inFilter('animal_id', femIds)
          .order('date', ascending: false);
    } catch (_) { return; }

    final Map<String, DateTime> lastChaleur = {};
    for (final c in chaleurs) {
      final aid = (c as Map)['animal_id'] as String? ?? '';
      if (lastChaleur.containsKey(aid)) continue;
      final d = DateTime.tryParse(c['date'] as String? ?? '');
      if (d != null) lastChaleur[aid] = d;
    }

    final now = DateTime.now();
    int notifId = 2000;

    const notifDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Alertes chaleurs femelles',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_notification',
      ),
    );

    for (final raw in animaux) {
      final a = raw as Map;
      final id      = a['id'] as String? ?? '';
      final nom     = a['nom'] as String? ?? 'Animal';
      final race    = a['race'] as String?;
      final espece  = a['espece'] as String? ?? '';
      final custom  = a['intervalle_chaleurs_jours'] as int?;
      final interval = custom ?? _intervalChaleurs(espece);
      if (interval == 0) continue;

      final last = lastChaleur[id];
      if (last == null) continue;

      final nextHeat = last.add(Duration(days: interval));
      final diff = nextHeat.difference(now).inDays;

      // Notifie uniquement si chaleurs dans 7j, aujourd'hui ou en retard
      if (diff > 7) continue;

      final subtitle = [if (race != null && race.isNotEmpty) race, espece]
          .where((s) => s.isNotEmpty).join(' · ');
      final emoji = _emoji(espece);

      final String title, body;
      if (diff < 0) {
        title = '🌸 Chaleurs probables — $nom';
        body  = '$emoji $nom ($subtitle) est probablement en chaleurs (${-diff} j de retard).';
      } else if (diff == 0) {
        title = '🌸 Chaleurs aujourd\'hui — $nom';
        body  = '$emoji $nom ($subtitle) est attendue en chaleurs aujourd\'hui.';
      } else if (diff == 1) {
        title = '🌸 Chaleurs demain — $nom';
        body  = '$emoji $nom ($subtitle) sera en chaleurs demain.';
      } else {
        title = '🌸 Chaleurs dans $diff jours — $nom';
        body  = '$emoji $nom ($subtitle) sera en chaleurs dans $diff jours.';
      }

      try {
        await flutterLocalNotificationsPlugin.show(
          id: notifId++,
          title: title,
          body: body,
          notificationDetails: notifDetails,
        );
      } catch (_) {}
    }
  }
}
