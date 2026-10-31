import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/contrats/contrat_signature_page.dart';
import 'package:PetsMatch/services/plan_service.dart';

// Éducateur : contrat de prestation généré par PetsMatch (documents_animaux
// type contrat_education, signé en ligne) — depuis « Mes Contrats » ou le
// dossier de la séance. Formule Premium. Miroir site : lib/contrat-education.ts.

/// Ouvre le contrat PetsMatch de l'animal (le crée s'il n'existe pas).
Future<void> ouvrirContratEducation(BuildContext context, {
  required Map<String, dynamic> rdv, required String? animalId, required String clientNom, String? proProfileId,
}) async {
  final supa = Supabase.instance.client;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final messenger = ScaffoldMessenger.of(context);
  void dire(String t) => messenger.showSnackBar(SnackBar(
      content: Text(t, style: const TextStyle(fontFamily: 'Galey')), behavior: SnackBarBehavior.floating));
  try {
    String? token;
    if (animalId != null) {
      final existant = await supa.from('documents_animaux').select('token, statut')
          .eq('uid_eleveur', uid).eq('type', 'contrat_education').eq('animal_id', animalId)
          .not('statut', 'in', '(annule,refuse)').order('created_at', ascending: false).limit(1).maybeSingle();
      token = existant?['token']?.toString();
    }
    if (token == null) {
      if (await PlanService.getEducationPlanCode(uid) != 'premium') {
        dire('Le contrat PetsMatch signé en ligne est inclus dans la formule Premium. Vous pouvez charger votre propre contrat.');
        return;
      }
      final motif = rdv['motif']?.toString().trim() ?? '';
      final row = await supa.from('documents_animaux').insert({
        'animal_id': animalId,
        'uid_eleveur': uid,
        'pro_profile_id': (proProfileId ?? '').isNotEmpty ? proProfileId : null,
        'type': 'contrat_education',
        'titre': 'Contrat de prestation d\'éducation — $clientNom',
        'statut': 'brouillon',
        'metadata': {
          'acquereur_nom': clientNom,
          if ((rdv['client_email_manuel']?.toString() ?? '').isNotEmpty) 'acquereur_email': rdv['client_email_manuel'],
          'prestation': motif.isNotEmpty ? motif : 'Prestation d\'éducation canine',
          'rdv_id': rdv['id'],
        },
      }).select('token').single();
      token = row['token']?.toString();
    }
    if (token == null || !context.mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ContratSignaturePage(token: token!)));
  } catch (e) {
    dire('Contrat indisponible : $e');
  }
}
