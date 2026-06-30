import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:PetsMatch/main.dart' show flutterLocalNotificationsPlugin;

const _kChannel = AndroidNotificationChannel(
  'promenades_reminders',
  'Rappels Promenades',
  description: 'Rappels avant les promenades auxquelles vous participez',
  importance: Importance.high,
);

const _kDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'promenades_reminders',
    'Rappels Promenades',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  ),
);

bool _tzInitialized = false;

Future<void> _initTz() async {
  if (_tzInitialized) return;
  tz.initializeTimeZones();
  final name = await FlutterTimezone.getLocalTimezone();
  try {
    tz.setLocalLocation(tz.getLocation(name));
  } catch (_) {}
  _tzInitialized = true;
}

/// Notification IDs stables basés sur le hash du promenadeId.
int _idJ1(String promenadeId) => (promenadeId.hashCode.abs() % 499999) * 2;
int _idH1(String promenadeId) => (promenadeId.hashCode.abs() % 499999) * 2 + 1;

String _prefKey(String promenadeId) => 'prom_notif_$promenadeId';

/// Crée le canal Android (à appeler une fois au démarrage).
Future<void> setupPromenadeNotificationChannel() async {
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_kChannel);
}

/// Programme les rappels J-1 et H-1 pour une promenade acceptée.
/// Ne fait rien si déjà programmés ou si la date est passée.
Future<void> schedulePromenadeReminders({
  required String promenadeId,
  required String titre,
  required DateTime dateHeure,
}) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_prefKey(promenadeId)) == true) return;

  await _initTz();

  final now = DateTime.now();
  final j1  = dateHeure.subtract(const Duration(hours: 24));
  final h1  = dateHeure.subtract(const Duration(hours: 1));

  try {
    if (j1.isAfter(now)) {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        _idJ1(promenadeId),
        'Promenade demain !',
        '$titre — rendez-vous demain à ${_fmtHeure(dateHeure)}',
        tz.TZDateTime.from(j1, tz.local),
        _kDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
    if (h1.isAfter(now)) {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        _idH1(promenadeId),
        'Promenade dans 1 heure !',
        '$titre — départ à ${_fmtHeure(dateHeure)}',
        tz.TZDateTime.from(h1, tz.local),
        _kDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
    await prefs.setBool(_prefKey(promenadeId), true);
  } catch (e) {
    debugPrint('PromenadeNotificationService.schedule error: $e');
  }
}

/// Annule les rappels d'une promenade (désinscription ou annulation).
Future<void> cancelPromenadeReminders(String promenadeId) async {
  await flutterLocalNotificationsPlugin.cancel(_idJ1(promenadeId));
  await flutterLocalNotificationsPlugin.cancel(_idH1(promenadeId));
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_prefKey(promenadeId));
}

String _fmtHeure(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}h${dt.minute.toString().padLeft(2, '0')}';
