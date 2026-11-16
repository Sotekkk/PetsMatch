// Photographe — « Facturer la sélection » depuis la galerie (16/11/2026) :
// facture préremplie d'après la séance (forfait de la prestation + photos
// supplémentaires choisies au-delà des photos incluses − acompte déjà réglé),
// coordonnées du client reprises de son profil. La facture est envoyée au
// client par e-mail (PDF) à sa création (CreerFacturePage). Même calcul que
// le dossier de la séance (_facturer, photographe_dossier_seance.dart).
// Miroir site : website/src/lib/facture-seance-photo.ts.
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:PetsMatch/config.dart' show kSiteBaseUrl;
import 'package:PetsMatch/utils/site_api.dart' show siteApiHeaders;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/eleveur/admin/facturation.dart' show CreerFacturePage, FacturePrefillLigne, facturePdfDepuisLigne;

/// Page de création de la facture de la séance liée à la galerie, ou null si
/// la galerie n'est pas rattachée à un rendez-vous.
Future<Widget?> pageFactureSelectionPhoto(String albumId) async {
  final supa = Supabase.instance.client;
  final album = await supa.from('albums_photo').select('id, rdv_id, nb_photos_incluses, prix_photo_supp, client_email').eq('id', albumId).maybeSingle();
  final rdvId = album?['rdv_id']?.toString() ?? '';
  if (album == null || rdvId.isEmpty) return null;
  final r = await supa.from('rdv')
      .select('id, date_heure, prestation_id, motif, animal_id, animal_nom_manuel, client_uid, client_profile_id, client_nom_manuel, client_telephone_manuel, client_email_manuel, lieu_type, adresse_depart')
      .eq('id', rdvId).maybeSingle();
  if (r == null) return null;

  String premier(List<dynamic> v) => v.map((x) => (x ?? '').toString().trim()).firstWhere((x) => x.isNotEmpty, orElse: () => '');
  final cp = r['client_profile_id']?.toString() ?? '';
  Map<String, dynamic>? prof;
  if (cp.isNotEmpty) {
    try {
      prof = await supa.from('user_profiles_complet')
          .select('firstname, lastname, nom, phone_number, phone, email_contact, rue, code_postal, ville, rue_pro, code_postal_pro, ville_pro')
          .eq('id', cp).maybeSingle();
    } catch (_) {}
  }
  var rue = premier([prof?['rue'], prof?['rue_pro']]);
  if (rue.isEmpty && r['lieu_type'] == 'domicile') rue = (r['adresse_depart']?.toString() ?? '').trim();

  Map<String, dynamic>? presta;
  if (r['prestation_id'] != null) {
    try { presta = await supa.from('prestations_photographe').select('nom, prix').eq('id', r['prestation_id']).maybeSingle(); } catch (_) {}
  }
  final prix = (presta?['prix'] as num?)?.toDouble() ?? 0;
  final animaux = (r['animal_nom_manuel']?.toString() ?? '').split('+').map((x) => x.trim()).where((x) => x.isNotEmpty).join(', ');
  final nomPresta = premier([presta?['nom'], r['motif'], 'Séance photo']);
  final debut = DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal() ?? DateTime.now();
  final designation = '${[nomPresta, if (animaux.isNotEmpty) animaux].join(' — ')} — séance du ${DateFormat('EEE d MMM', 'fr_FR').format(debut)}';

  // Photos choisies au-delà des photos incluses.
  final ph = await supa.from('album_photos').select('selectionnee').eq('album_id', albumId);
  final nbChoisies = (ph as List).where((p) => p['selectionnee'] == true).length;
  final incluses = (album['nb_photos_incluses'] as num?)?.toInt();
  final prixSupp = (album['prix_photo_supp'] as num?)?.toDouble();
  final supp = incluses == null ? 0 : (nbChoisies - incluses).clamp(0, 9999);

  // Acompte déjà réglé : déduit (facture de solde).
  final deductions = <FacturePrefillLigne>[];
  try {
    final acomptes = await supa.from('factures').select('total_ttc, numero_affichage, numero_facture')
        .eq('source_rdv_id', rdvId).eq('type_facture', 'acompte').eq('statut', 'payee');
    for (final a in acomptes as List) {
      final m = (a['total_ttc'] as num?)?.toDouble() ?? 0;
      if (m > 0) {
        deductions.add(FacturePrefillLigne(
            designation: 'Acompte déjà réglé (facture n° ${a['numero_affichage'] ?? a['numero_facture'] ?? ''})',
            prixTTC: -m, quantite: 1, tauxTVA: 20));
      }
    }
  } catch (_) {}

  final nom = premier([prof?['lastname'], r['client_nom_manuel'], prof?['nom']]);
  final prenom = premier([prof?['firstname']]);
  // Client sans compte : adresse saisie sur le RDV ou celle de l'envoi de la galerie.
  final email = premier([prof?['email_contact'], r['client_email_manuel'], album['client_email']]);
  final tel = premier([prof?['phone_number'], prof?['phone'], r['client_telephone_manuel']]);
  final cpPostal = premier([prof?['code_postal'], prof?['code_postal_pro']]);
  final ville = premier([prof?['ville'], prof?['ville_pro']]);
  // Tarifs affichés TTC : le HT est déduit selon le régime de TVA du pro.
  return CreerFacturePage(
    clientNom: nom.isNotEmpty ? nom : null,
    clientPrenom: prenom.isNotEmpty ? prenom : null,
    clientEmail: email.isNotEmpty ? email : null,
    clientTel: tel.isNotEmpty ? tel : null,
    clientRue: rue.isNotEmpty ? rue : null,
    clientCp: cpPostal.isNotEmpty ? cpPostal : null,
    clientVille: ville.isNotEmpty ? ville : null,
    lignesPrefill: [
      FacturePrefillLigne(designation: designation, prixTTC: prix, quantite: 1, tauxTVA: 20),
      if (supp > 0 && prixSupp != null && prixSupp > 0)
        FacturePrefillLigne(designation: 'Photos supplémentaires', prixTTC: prixSupp, quantite: supp.toDouble(), tauxTVA: 20),
      ...deductions,
    ],
    sourceRdvId: rdvId,
    sourceAnimalId: r['animal_id']?.toString(),
    clientUid: r['client_uid']?.toString(),
    clientProfileId: cp.isNotEmpty ? cp : null,
  );
}

/// Facture marquée payée : PDF acquitté envoyé au client par e-mail (avec ou
/// sans compte PetsMatch), à l'adresse de la facture. Renvoie le message à
/// afficher. Miroir site : envoyerFactureAcquittee (facture-seance-photo.ts).
Future<String> envoyerFactureAcquitteePhoto(String factureId) async {
  const echec = "Paiement enregistré, mais l'envoi de la facture acquittée a échoué : renvoyez-la depuis la Facturation.";
  try {
    final row = await Supabase.instance.client.from('factures').select().eq('id', factureId).maybeSingle();
    if (row == null) return 'Paiement enregistré.';
    final f = Map<String, dynamic>.from(row)..['statut'] = 'payee';
    final email = (f['email_client']?.toString() ?? '').trim();
    if (email.isEmpty) return "Paiement enregistré. Pas d'adresse e-mail sur la facture : la facture acquittée n'a pas été envoyée.";
    final n = f['numero_affichage'] ?? f['numero_facture'] ?? '';
    final nom = '${f['prenom_client'] ?? ''} ${f['nom_client'] ?? ''}'.trim();
    final res = await http.post(Uri.parse('$kSiteBaseUrl/api/documents/envoyer-email'),
        headers: await siteApiHeaders(),
        body: jsonEncode({
          'email': email, 'contexte': 'photo', 'document_type': 'facture', 'fichier_nom': 'Facture-$n-acquittee.pdf',
          if (nom.isNotEmpty) 'destinataire_nom': nom,
          if ((f['nom_emetteur']?.toString() ?? '').trim().isNotEmpty) 'expediteur_nom': f['nom_emetteur'].toString().trim(),
          'pdf_base64': base64Encode(await facturePdfDepuisLigne(f)),
        }));
    return res.statusCode == 200 ? 'Paiement enregistré : facture acquittée envoyée à $email.' : echec;
  } catch (_) {
    return echec;
  }
}
