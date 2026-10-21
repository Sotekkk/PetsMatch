import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;

/// Cloisonnement des profils d'un même compte (éleveur, association,
/// pension…) dans l'agenda : un rappel ou une tâche d'un animal de l'élevage
/// ne doit jamais apparaître dans l'agenda de l'association, et inversement.
/// Miroir site : website/src/lib/cloisonnement-profils.ts.

final _supa = Supabase.instance.client;

/// Identifiants des profils du compte connecté.
Future<Set<String>> mesProfilsIds() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return {};
  try {
    final rows = await _supa.from('user_profiles_complet').select('id').eq('uid', uid);
    return {for (final r in rows as List) r['id'].toString()};
  } catch (_) {
    return {};
  }
}

/// Profil auquel rattacher un rappel lié à un animal : le profil du compte
/// qui possède l'animal (un rappel de l'élevage reste dans l'élevage même
/// créé depuis un autre profil), sinon le profil actif (animal d'un client
/// en pension, en garde…).
Future<String> profilPourAnimal(String animalId) async {
  final actif = User_Info.activeProfileId;
  try {
    final a = await _supa.from('animaux').select('profile_id').eq('id', animalId).maybeSingle();
    final pid = a?['profile_id']?.toString() ?? '';
    if (pid.isNotEmpty && pid != actif && (await mesProfilsIds()).contains(pid)) return pid;
  } catch (_) {}
  return actif;
}

/// Retire des événements d'agenda ceux dont l'animal appartient à un AUTRE
/// profil du même compte que [pid] (anciens rappels enregistrés sous le
/// mauvais profil). Les animaux de clients ou d'autres comptes restent.
Future<List<Map<String, dynamic>>> sansAnimauxAutresProfils(
    List<Map<String, dynamic>> events, String pid) async {
  if (pid.isEmpty) return events;
  final ids = {
    for (final e in events)
      if ((e['animal_id']?.toString() ?? '').isNotEmpty) e['animal_id'].toString()
  };
  if (ids.isEmpty) return events;
  try {
    final mesProfils = await mesProfilsIds();
    final rows = await _supa.from('animaux').select('id, profile_id').inFilter('id', ids.toList());
    final autres = <String>{
      for (final a in rows as List)
        if (a['profile_id'] != null && a['profile_id'].toString() != pid
            && mesProfils.contains(a['profile_id'].toString()))
          a['id'].toString()
    };
    if (autres.isEmpty) return events;
    return events.where((e) => !autres.contains(e['animal_id']?.toString())).toList();
  } catch (_) {
    return events;
  }
}

/// Animaux cités par une notification (data.animalId / data.animalIds).
Set<String> _animauxDeNotif(Map n) {
  final d = n['data'];
  if (d is! Map) return {};
  return {
    if ((d['animalId']?.toString() ?? '').isNotEmpty) d['animalId'].toString(),
    if (d['animalIds'] is List) for (final a in d['animalIds'] as List) a.toString(),
  };
}

/// Notifications SANS profil destinataire (anciens rappels automatiques) :
/// retire celles qui concernent un animal d'un AUTRE profil du compte
/// (ex. rappel de vaccin d'un chien de l'élevage affiché dans l'association).
Future<List<Map<String, dynamic>>> notifsSansAutresProfils(
    List<Map<String, dynamic>> notifs, String pid) async {
  if (pid.isEmpty) return notifs;
  final ids = <String>{
    for (final n in notifs)
      if ((n['profile_id']?.toString() ?? '').isEmpty) ..._animauxDeNotif(n)
  };
  if (ids.isEmpty) return notifs;
  try {
    final mesProfils = await mesProfilsIds();
    final rows = await _supa.from('animaux').select('id, profile_id').inFilter('id', ids.toList());
    final autres = <String>{
      for (final a in rows as List)
        if (a['profile_id'] != null && a['profile_id'].toString() != pid
            && mesProfils.contains(a['profile_id'].toString()))
          a['id'].toString()
    };
    if (autres.isEmpty) return notifs;
    return notifs.where((n) {
      if ((n['profile_id']?.toString() ?? '').isNotEmpty) return true;
      final a = _animauxDeNotif(n);
      return a.isEmpty || !a.every(autres.contains);
    }).toList();
  } catch (_) {
    return notifs;
  }
}
