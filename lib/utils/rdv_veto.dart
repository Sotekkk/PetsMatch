// Élevage : RDV vétérinaire à venir (cabinet hors PetsMatch). Une tâche d'agenda
// marquée rdv_veto_cabinet ; à la validation, la base crée une visite au carnet
// par animal et la ligne du registre (migration_rdv_veto_taches.sql).
// Miroir site : website/src/lib/rdv-veto.ts.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:PetsMatch/utils/protocoles.dart' show estHorsPriseEnCharge;

/// Praticien du RDV : 'veterinaire' ou 'osteopathe' (acte de soin, au registre
/// sanitaire comme une visite).
String titreRdvVeto(String cabinet, [String praticien = 'veterinaire']) =>
    'RDV ${praticien == 'osteopathe' ? 'ostéopathe' : 'vétérinaire'} — ${cabinet.trim()}';

/// Animaux présents de CE profil élevage : propriété en cours (animaux_proprietes), ou fiche
/// de ce profil sans propriété close ; ni adopté / cédé / décédé / sorti, ni fiche client d'un
/// pro, ni animal d'un autre profil du compte (association…). Miroir site : lib/rdv-veto.ts.
Future<List<Map<String, dynamic>>> animauxPresentsElevage(String? profileId) async {
  if ((profileId ?? '').isEmpty) return [];
  final supa = Supabase.instance.client;
  const cols = 'id, nom, espece, race, portee_id, nom_mere, statut, uid_eleveur, date_naissance';
  final props = await supa.from('animaux_proprietes').select('animal_id, date_fin, statut').eq('profile_id_proprio', profileId!) as List;
  final ouverts = {for (final p in props) if (p['date_fin'] == null && p['statut'] == 'actif') p['animal_id'].toString()};
  final clos = {for (final p in props) if (p['date_fin'] != null) p['animal_id'].toString()};
  final liste = <String, Map<String, dynamic>>{};
  for (final a in await supa.from('animaux').select(cols).eq('profile_id', profileId) as List) {
    final id = a['id'].toString();
    if (ouverts.contains(id) || !clos.contains(id)) liste[id] = Map<String, dynamic>.from(a as Map);
  }
  final manquants = ouverts.where((id) => !liste.containsKey(id)).toList();
  if (manquants.isNotEmpty) {
    for (final a in await supa.from('animaux').select(cols).inFilter('id', manquants) as List) {
      liste[a['id'].toString()] = Map<String, dynamic>.from(a as Map);
    }
  }
  return liste.values.where((a) => !estHorsPriseEnCharge(a) && a['statut'] != 'patient_clinique').toList()
    ..sort((a, b) => (a['nom'] ?? '').toString().toLowerCase().compareTo((b['nom'] ?? '').toString().toLowerCase()));
}

/// Message d'erreur, ou null si tout est prêt.
String? erreurRdvVeto({required List<Map<String, dynamic>> animaux, required DateTime? dateHeure, required String cabinet}) {
  if (cabinet.trim().isEmpty) return 'Indiquez le nom du cabinet vétérinaire.';
  if (animaux.isEmpty) return 'Sélectionnez au moins un animal.';
  if (dateHeure == null) return 'Indiquez la date et l’heure du RDV.';
  if (!dateHeure.isAfter(DateTime.now())) {
    return 'Le RDV doit être dans le futur. Pour une visite déjà faite, utilisez « Visite vétérinaire ».';
  }
  return null;
}

String? _noms(List<Map<String, dynamic>> animaux) {
  final n = [for (final a in animaux) if ((a['nom']?.toString() ?? '').isNotEmpty) a['nom'].toString()].join(', ');
  return n.isEmpty ? null : n;
}

/// [uid] : propriétaire de l'élevage (employé ou cogérant : pas la personne connectée).
/// Renvoie un message d'erreur, ou null.
Future<String?> creerRdvVeto({
  required String uid, required String? profileId, required List<Map<String, dynamic>> animaux,
  required DateTime? dateHeure, required String cabinet, String motif = '', String notes = '',
  String praticien = 'veterinaire', String profilSource = 'eleveur',
}) async {
  final err = erreurRdvVeto(animaux: animaux, dateHeure: dateHeure, cabinet: cabinet);
  if (err != null) return err;
  final moi = FirebaseAuth.instance.currentUser?.uid;
  final employe = moi != null && moi != uid;
  final ids = [for (final a in animaux) a['id'].toString()];
  try {
    await Supabase.instance.client.from('taches_elevage').insert({
      'uid_eleveur': uid,
      'titre': titreRdvVeto(cabinet, praticien),
      'date': DateFormat('yyyy-MM-dd').format(dateHeure!),
      'heure': DateFormat('HH:mm').format(dateHeure),
      'statut': 'a_faire',
      'profil_source': profilSource,
      'notes': notes.trim().isEmpty ? null : notes.trim(),
      if ((profileId ?? '').isNotEmpty) 'profile_id': profileId,
      if ((profileId ?? '').isNotEmpty) 'eleveur_profile_id': profileId,
      'animaux_ids': ids,
      'animal_id': ids.length == 1 ? ids.first : null,
      'animal_nom': _noms(animaux),
      'rdv_veto_cabinet': cabinet.trim(),
      // Ostéopathe : « Ostéopathie — motif » au carnet et au registre sanitaire.
      'rdv_veto_motif': praticien == 'osteopathe'
          ? ['Ostéopathie', if (motif.trim().isNotEmpty) motif.trim()].join(' — ')
          : (motif.trim().isEmpty ? null : motif.trim()),
      // Employé : la tâche lui est attribuée, il peut la voir et la valider.
      if (employe) 'assigne_a': moi,
      if (employe) 'assignes_a': [moi],
    });
    return null;
  } catch (e) {
    return 'Enregistrement impossible : $e';
  }
}

/// Valide le RDV : date réelle et animaux réellement vus ; la base écrit carnet et registre.
Future<String?> validerRdvVeto(Map<String, dynamic> tache, DateTime date, List<Map<String, dynamic>> animaux, {String? profilActif}) async {
  if (animaux.isEmpty) return 'Cochez au moins un animal.';
  final ids = [for (final a in animaux) a['id'].toString()];
  try {
    await Supabase.instance.client.from('taches_elevage').update({
      'statut': 'fait',
      'date': DateFormat('yyyy-MM-dd').format(date),
      'animaux_ids': ids,
      'animal_id': ids.length == 1 ? ids.first : null,
      'animal_nom': _noms(animaux),
      'fait_par': FirebaseAuth.instance.currentUser?.uid,
      if ((profilActif ?? '').isNotEmpty) 'fait_par_profile_id': profilActif,
      'fait_a': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', tache['id']);
    return null;
  } catch (e) {
    return 'Validation impossible : $e';
  }
}

/// Animaux qu'on peut associer à un événement d'agenda, selon le profil actif :
/// élevage / association → présents de ce profil ; pension → pensionnaires
/// présents ; particulier → ses animaux ; autre pro → animaux de ses clients.
/// Miroir site : animauxPourAgenda (lib/rdv-veto.ts).
Future<List<Map<String, dynamic>>> animauxPourAgenda(String source, String? profileId, String uid) async {
  final supa = Supabase.instance.client;
  try {
    if (source == 'eleveur' || source == 'association') return await animauxPresentsElevage(profileId);
    if (source == 'pension') {
      var q = supa.from('pension_entrees').select('animal_id, animal_nom, espece').eq('statut', 'en_pension').not('animal_id', 'is', null);
      q = (profileId ?? '').isNotEmpty ? q.eq('pro_profile_id', profileId!) : q.eq('pro_uid', uid);
      final vus = <String, Map<String, dynamic>>{};
      for (final e in await q) {
        vus[e['animal_id'].toString()] = {'id': e['animal_id'].toString(), 'nom': e['animal_nom'] ?? 'Pensionnaire', 'espece': e['espece']};
      }
      return vus.values.toList()..sort((a, b) => a['nom'].toString().compareTo(b['nom'].toString()));
    }
    if ((profileId ?? '').isEmpty) return [];
    if (source == 'particulier') {
      final props = await supa.from('animaux_proprietes').select('animal_id')
          .eq('profile_id_proprio', profileId!).eq('statut', 'actif').isFilter('date_fin', null);
      final ids = {for (final p in props) p['animal_id'].toString()}.toList();
      if (ids.isEmpty) return [];
      final rows = await supa.from('animaux').select('id, nom, espece, statut').inFilter('id', ids);
      return [for (final a in rows) if (!estHorsPriseEnCharge(Map<String, dynamic>.from(a))) Map<String, dynamic>.from(a)]
        ..sort((a, b) => (a['nom'] ?? '').toString().compareTo((b['nom'] ?? '').toString()));
    }
    final rows = await supa.rpc('pm_mes_clients', params: {'p_profile': profileId}) as List;
    final vus = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final id = r['animal_id']?.toString() ?? '';
      if (id.isNotEmpty) vus.putIfAbsent(id, () => {'id': id, 'nom': r['animal_nom'] ?? 'Animal', 'espece': r['espece']});
    }
    return vus.values.toList()..sort((a, b) => a['nom'].toString().compareTo(b['nom'].toString()));
  } catch (_) {
    return [];
  }
}
