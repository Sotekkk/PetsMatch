// Devis rattachés à un RDV (créés depuis le dossier de la consultation /
// séance) : enregistrés sans être envoyés, puis envoyés au client à la fin
// avec le reste des documents (« Terminer et envoyer ») — lien de signature
// par e-mail + notification s'il a un compte. Miroir site : website/src/lib/devis-rdv.ts.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:PetsMatch/config.dart' show kSiteBaseUrl;
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/signature_pro.dart' show maSignaturePro;
import 'package:PetsMatch/utils/site_api.dart';

/// Devis modifiable : pas encore signé par le client (ni refusé / expiré).
bool devisModifiable(dynamic statut) => statut == 'brouillon' || statut == 'envoye';

/// Signature du pro sur le devis envoyé (sa signature enregistrée, comme sur
/// les ordonnances), s'il ne l'a pas déjà signé. Faux si aucune signature.
/// Miroir site : signerDevisPro (website/src/lib/devis-rdv.ts).
Future<bool> signerDevisPro(String devisId, {String? signature}) async {
  final supa = Supabase.instance.client;
  try {
    final doc = await supa.from('documents_animaux').select('id, statut, metadata')
        .contains('metadata', {'devis_id': devisId}).limit(1).maybeSingle();
    if (doc == null) return false;
    final m = (doc['metadata'] as Map?) ?? const {};
    if ((m['signature_eleveur']?.toString() ?? '').trim().isNotEmpty) return true;
    if (const ['brouillon', 'signe', 'annule', 'refuse', 'expire'].contains(doc['statut'])) return false;
    final sig = signature ?? await maSignaturePro();
    if (sig == null) return false;
    final r = await http.post(Uri.parse('$kSiteBaseUrl/api/contracts/${doc['id']}/sign'),
        headers: {...await siteApiHeaders(), 'Content-Type': 'application/json'},
        body: jsonEncode({'role': 'eleveur', 'signature': sig, 'actorUid': User_Info.uid,
            'actorNom': '${User_Info.firstname} ${User_Info.lastname}'.trim()}));
    return r.statusCode == 200;
  } catch (_) {
    return false;
  }
}

/// Devis du RDV pas encore acceptés / refusés (brouillon ou déjà envoyé),
/// avec l'id et le jeton de leur document signable (`_doc_id`, `_doc_token`).
Future<List<Map<String, dynamic>>> devisDuRdv(String rdvId) async {
  final supa = Supabase.instance.client;
  try {
    final rows = List<Map<String, dynamic>>.from(await supa.from('devis')
        .select('id, statut, total_ttc, email_client, nom_client, prenom_client, client_uid, client_profile_id, token_acceptation')
        .eq('rdv_id', rdvId).inFilter('statut', ['brouillon', 'envoye']).order('created_at'));
    for (final d in rows) {
      final doc = await supa.from('documents_animaux').select('id, token')
          .contains('metadata', {'devis_id': d['id']}).limit(1).maybeSingle();
      d['_doc_id'] = doc?['id'];
      d['_doc_token'] = doc?['token'];
    }
    return rows;
  } catch (_) {
    return [];
  }
}

/// Libellé d'un devis du RDV dans la liste de fin de consultation.
String titreDevisRdv(Map<String, dynamic> d) =>
    'Devis — ${((d['total_ttc'] as num?) ?? 0).toStringAsFixed(2)} € TTC';
String sousTitreDevisRdv(Map<String, dynamic> d) => d['statut'] == 'brouillon'
    ? 'À signer en ligne par le client (lien par e-mail)'
    : 'Déjà envoyé — renvoyer le lien de signature';

/// Envoie le devis : statut « envoyé », document à signer, notification,
/// e-mail. Renvoie false si aucun e-mail n'est parti.
Future<bool> envoyerDevisRdv(Map<String, dynamic> d, {required String proNom, String? emailSecours}) async {
  final supa = Supabase.instance.client;
  final total = ((d['total_ttc'] as num?) ?? 0).toDouble();
  if (d['statut'] == 'brouillon') {
    await supa.from('devis').update({'statut': 'envoye', 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', d['id']);
  }
  final docToken = d['_doc_token']?.toString();
  if (d['_doc_id'] != null) {
    await supa.from('documents_animaux').update({'statut': 'en_attente'}).eq('id', d['_doc_id']).eq('statut', 'brouillon');
  }
  await signerDevisPro(d['id'].toString());
  final chemin = docToken != null ? '/signer-contrat/$docToken' : '/devis/${d['token_acceptation']}';
  if (d['client_uid'] != null) {
    await supa.from('notifications').insert({
      'uid': d['client_uid'], 'type': 'devis_recu', 'title': 'Vous avez reçu un devis',
      'body': 'Un devis de ${total.toStringAsFixed(2)} € vous a été envoyé.',
      if (d['client_profile_id'] != null) 'profile_id': d['client_profile_id'],
      'data': {'devis_id': d['id'], 'token': docToken ?? d['token_acceptation'], 'url': chemin},
      'read': false,
    });
  }
  final email = ((d['email_client'] ?? '').toString().trim().isNotEmpty ? d['email_client'].toString() : (emailSecours ?? '')).trim();
  if (email.isEmpty) return false;
  try {
    final r = await http.post(Uri.parse('$kSiteBaseUrl/api/devis/notify-email'), headers: await siteApiHeaders(), body: jsonEncode({
      'email': email,
      'client_nom': '${d['prenom_client'] ?? ''} ${d['nom_client'] ?? ''}'.trim().isEmpty
          ? 'Client' : '${d['prenom_client'] ?? ''} ${d['nom_client'] ?? ''}'.trim(),
      'pro_nom': proNom.isEmpty ? 'Votre professionnel' : proNom,
      'total_ttc': total,
      'devis_url': '$kSiteBaseUrl$chemin',
    }));
    return r.statusCode == 200;
  } catch (_) {
    return false;
  }
}

/// Envoie les devis cochés (clé `dev:<id>`) ; renvoie le nombre d'e-mails
/// non partis pour des clients sans compte (à signaler).
Future<int> envoyerDevisCoches(List<Map<String, dynamic>> devis, Map<String, bool> coches,
    {required String rdvId, required String proNom, String? emailSecours}) async {
  var echecs = 0;
  final aEnvoyer = devis.where((d) => coches['dev:${d['id']}'] == true).toList();
  if (aEnvoyer.isEmpty) return 0;
  var secours = emailSecours;
  try {
    final cc = await Supabase.instance.client.rpc('pm_contact_client_rdv', params: {'p_rdv_id': rdvId});
    final e = (cc is Map ? cc['email'] : null)?.toString() ?? '';
    if (e.isNotEmpty) secours = e;
  } catch (_) {}
  for (final d in aEnvoyer) {
    final ok = await envoyerDevisRdv(d, proNom: proNom, emailSecours: secours);
    if (!ok && d['client_uid'] == null) echecs++;
  }
  return echecs;
}
