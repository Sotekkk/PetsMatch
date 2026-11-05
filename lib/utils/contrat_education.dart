import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/contrats/contrat_signature_page.dart';
import 'package:PetsMatch/services/plan_service.dart';
import 'package:PetsMatch/utils/fin_seance_education.dart' show clientDuRdv;
import 'package:PetsMatch/utils/prestations_education.dart' show tarifSeanceRdv;
import 'package:PetsMatch/utils/rdv_animaux.dart' show animauxDetailRdv;
import 'package:PetsMatch/config.dart' show kSiteBaseUrl;
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/pro/toilettage_dossier_seance.dart' show envoyerContratParEmail;
import 'package:PetsMatch/utils/signature_pro.dart' show maSignaturePro;
import 'package:PetsMatch/utils/site_api.dart';

// Éducateur : contrat de prestation généré par PetsMatch (documents_animaux
// type contrat_education, signé en ligne) — depuis « Mes Contrats » ou le
// dossier de la séance. Formule Premium. Miroir site : lib/contrat-education.ts.

/// Ma signature enregistrée apposée d'office, sans prévenir le client. Faux si aucune / échec.
Future<bool> _apposerMaSignature(String docId) async {
  final sig = await maSignaturePro();
  if (sig == null) return false;
  try {
    final r = await http.post(Uri.parse('$kSiteBaseUrl/api/contracts/$docId/sign'),
        headers: {...await siteApiHeaders(), 'Content-Type': 'application/json'},
        body: jsonEncode({'role': 'eleveur', 'signature': sig, 'actorUid': User_Info.uid,
            'actorNom': '${User_Info.firstname} ${User_Info.lastname}'.trim(), 'sansNotification': true}));
    return r.statusCode == 200;
  } catch (_) {
    return false;
  }
}

/// Ouvre le contrat PetsMatch de l'animal (le crée s'il n'existe pas).
Future<void> ouvrirContratEducation(BuildContext context, {
  required Map<String, dynamic> rdv, required String? animalId, required String clientNom, String? proProfileId,
  /// Forfait en cours : contrat du forfait au prix de la formule complète.
  Map<String, dynamic>? forfait,
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
          // Un devis envoyé est aussi un document à signer : ce n'est pas le contrat.
          .isFilter('metadata->>devis_id', null)
          .not('statut', 'in', '(annule,refuse)').order('created_at', ascending: false).limit(1).maybeSingle();
      token = existant?['token']?.toString();
      // Contrat commun d'une séance à plusieurs chiens : rattaché à un seul, valable pour tous.
      if (token == null) {
        final commun = await supa.from('documents_animaux').select('token')
            .eq('uid_eleveur', uid).eq('type', 'contrat_education')
            .contains('metadata', {'animaux_ids': [animalId]}).isFilter('metadata->>devis_id', null)
            .not('statut', 'in', '(annule,refuse)').order('created_at', ascending: false).limit(1).maybeSingle();
        token = commun?['token']?.toString();
      }
    }
    if (token == null) {
      // Devis en cours sur ce RDV : le contrat attend la réponse du client (miroir site).
      final devis = await supa.from('devis').select('statut, total_ttc').eq('rdv_id', rdv['id'].toString())
          .order('created_at', ascending: false).limit(1).maybeSingle();
      final statutDevis = devis?['statut']?.toString();
      if (statutDevis != null && statutDevis != 'accepte' && statutDevis != 'refuse') {
        dire('Contrat à générer une fois le devis accepté. Vous pouvez aussi charger votre propre contrat.');
        return;
      }
      if (await PlanService.getEducationPlanCode(uid) != 'premium') {
        dire('Le contrat PetsMatch signé en ligne est inclus dans la formule Premium. Vous pouvez charger votre propre contrat.');
        return;
      }
      final motif = rdv['motif']?.toString().trim() ?? '';
      // Intitulé et montant, modifiables : forfait (formule complète) ou séance.
      final nbF = (forfait?['nb_seances_total'] as num?)?.toInt() ?? 0;
      final libelleBase = forfait != null
          ? '${forfait['nom_snapshot'] ?? 'Forfait'} ($nbF séance${nbF > 1 ? 's' : ''})'
          : (motif.isNotEmpty ? motif : 'Séance d\'éducation');
      // Séance à plusieurs, devis accepté : un seul contrat pour tous les chiens, au total du devis.
      final chiens = animauxDetailRdv(rdv);
      final tousLesChiens = chiens.length > 1 && statutDevis == 'accepte';
      final nomsChiens = chiens.map((a) => a['nom']?.toString() ?? '').where((n) => n.isNotEmpty).join(', ');
      final libelleCtrl = TextEditingController(text: tousLesChiens ? '$libelleBase — $nomsChiens' : libelleBase);
      // Devis accepté sans forfait : le montant accepté par le client.
      final totalDevis = statutDevis == 'accepte' ? (devis?['total_ttc'] as num?)?.toDouble() ?? 0 : 0.0;
      final prixDefaut = tousLesChiens && totalDevis > 0 ? totalDevis
          : forfait != null ? ((forfait['prix_snapshot'] as num?)?.toDouble() ?? 0)
          : totalDevis > 0 ? totalDevis : await tarifSeanceRdv(rdv);
      final montantCtrl = TextEditingController(text: prixDefaut > 0 ? prixDefaut.toStringAsFixed(prixDefaut == prixDefaut.roundToDouble() ? 0 : 2) : '');
      if (!context.mounted) return;
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Contrat de prestation', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: libelleCtrl, decoration: InputDecoration(labelText: forfait != null ? 'Forfait' : 'Prestation')),
          TextField(controller: montantCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: forfait != null ? 'Montant de la formule complète (€ TTC)' : 'Montant (€ TTC)')),
          const SizedBox(height: 8),
          Text('Vos coordonnées (adresse, téléphone, SIRET) et celles du client sont reprises automatiquement.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Créer le contrat')),
        ],
      ));
      final libelle = libelleCtrl.text.trim();
      final montant = double.tryParse(montantCtrl.text.trim().replaceAll(',', '.'));
      libelleCtrl.dispose(); montantCtrl.dispose();
      if (ok != true) return;
      final c = await clientDuRdv(rdv);
      final adresse = [c['rue'] ?? '', '${c['cp'] ?? ''} ${c['ville'] ?? ''}'.trim()].where((x) => x.isNotEmpty).join(', ');
      final nomClient = [c['prenom'] ?? '', c['nom'] ?? ''].where((x) => x.isNotEmpty).join(' ');
      final row = await supa.from('documents_animaux').insert({
        'animal_id': animalId,
        'uid_eleveur': uid,
        'pro_profile_id': (proProfileId ?? '').isNotEmpty ? proProfileId : null,
        'type': 'contrat_education',
        'titre': 'Contrat de prestation d\'éducation — ${nomClient.isNotEmpty ? nomClient : clientNom}',
        'statut': 'brouillon',
        'metadata': {
          'acquereur_nom': nomClient.isNotEmpty ? nomClient : clientNom,
          if ((c['email'] ?? '').isNotEmpty) 'acquereur_email': c['email'],
          if ((c['tel'] ?? '').isNotEmpty) 'acquereur_tel': c['tel'],
          if (adresse.isNotEmpty) 'acquereur_adresse': adresse,
          'prestation': libelle.isNotEmpty ? libelle : 'Prestation d\'éducation canine',
          if (forfait != null) 'forfait': libelle,
          if (montant != null && montant > 0) 'lignes': [
            {'description': libelle, 'quantite': 1, 'prix_unitaire': montant, 'total': montant},
          ],
          if (montant != null && montant > 0) 'total_ttc': montant,
          'rdv_id': rdv['id'],
          if (chiens.length > 1) 'animaux_ids': [for (final a in chiens) a['id']],
        },
      }).select('id, token').single();
      token = row['token']?.toString();
      // Ma signature apposée d'office ; sans signature enregistrée : page de signature, comme avant.
      if (token != null && await _apposerMaSignature(row['id'].toString())) {
        if (!context.mounted) return;
        final nomContrat = nomClient.isNotEmpty ? nomClient : clientNom;
        final envoyer = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Contrat signé de votre côté', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          content: Text("L'envoyer à $nomContrat maintenant ? Sinon, il partira avec « Terminer et envoyer au client ».",
              style: const TextStyle(fontFamily: 'Galey')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Plus tard')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Envoyer')),
          ],
        ));
        if (envoyer != true) return;
        final clientUid = rdv['client_uid']?.toString() ?? '';
        if (clientUid.isNotEmpty) {
          await supa.from('notifications').insert({
            'uid': clientUid, 'type': 'contrat_invite', 'title': 'Contrat de prestation à signer',
            'body': '${User_Info.nameElevage.isNotEmpty ? User_Info.nameElevage : 'Votre professionnel'} vous envoie le contrat — vérifiez et signez',
            if (rdv['client_profile_id'] != null) 'profile_id': rdv['client_profile_id'],
            'data': {'token': token, 'url': '/signer-contrat/$token'}, 'read': false,
          });
        }
        final parEmail = await envoyerContratParEmail(rdv, token, nomClient: nomContrat);
        dire(parEmail || clientUid.isNotEmpty ? 'Contrat envoyé à $nomContrat.'
            : 'Contrat non envoyé : aucune adresse e-mail pour ce client.');
        return;
      }
    }
    if (token == null || !context.mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ContratSignaturePage(token: token!)));
  } catch (e) {
    dire('Contrat indisponible : $e');
  }
}
