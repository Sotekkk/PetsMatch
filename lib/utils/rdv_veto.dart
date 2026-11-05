// Élevage : RDV vétérinaire à venir (cabinet hors PetsMatch). Une tâche d'agenda
// marquée rdv_veto_cabinet ; à la validation, la base crée une visite au carnet
// par animal et la ligne du registre (migration_rdv_veto_taches.sql).
// Miroir site : website/src/lib/rdv-veto.ts.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String titreRdvVeto(String cabinet) => 'RDV vétérinaire — ${cabinet.trim()}';

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
}) async {
  final err = erreurRdvVeto(animaux: animaux, dateHeure: dateHeure, cabinet: cabinet);
  if (err != null) return err;
  final moi = FirebaseAuth.instance.currentUser?.uid;
  final employe = moi != null && moi != uid;
  final ids = [for (final a in animaux) a['id'].toString()];
  try {
    await Supabase.instance.client.from('taches_elevage').insert({
      'uid_eleveur': uid,
      'titre': titreRdvVeto(cabinet),
      'date': DateFormat('yyyy-MM-dd').format(dateHeure!),
      'heure': DateFormat('HH:mm').format(dateHeure),
      'statut': 'a_faire',
      'profil_source': 'eleveur',
      'notes': notes.trim().isEmpty ? null : notes.trim(),
      if ((profileId ?? '').isNotEmpty) 'profile_id': profileId,
      if ((profileId ?? '').isNotEmpty) 'eleveur_profile_id': profileId,
      'animaux_ids': ids,
      'animal_id': ids.length == 1 ? ids.first : null,
      'animal_nom': _noms(animaux),
      'rdv_veto_cabinet': cabinet.trim(),
      'rdv_veto_motif': motif.trim().isEmpty ? null : motif.trim(),
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
