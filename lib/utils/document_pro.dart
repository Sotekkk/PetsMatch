// Documents faits par le professionnel lui-même (tous les métiers) :
//  • compte rendu chargé (PDF, ou photo convertie en PDF) — rangé dans
//    documents_animaux (type « compte_rendu_pro »), envoyé au client à la
//    place du compte rendu généré ;
//  • contrat chargé (type « contrat_document_pro ») — signé en ligne comme
//    les contrats générés ; le PDF signé = le document du pro + une page de
//    signatures ajoutée à la fin.
// Stockage privé `documents` (documents-pro/<uid>/…), ouvert via lienDocument.
// Miroir site : website/src/lib/document-pro.ts + components/pro/DocumentProModal.tsx.
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:PetsMatch/pages/pro/toilettage_dossier_seance.dart'
    show coordonneesClientRdv, envoyerContratParEmail, signerContratAvecSignaturePro;
import 'package:PetsMatch/pages/pro/transmission_document.dart' show envoyerDocumentsParEmail;
import 'package:PetsMatch/services/plan_service.dart' show PlanService;
import 'package:PetsMatch/utils/document_prive.dart' show lienDocument;
import 'package:PetsMatch/utils/storage_helper.dart' show uploadDocumentBytes;

const kTypeCrPro = 'compte_rendu_pro';
const kTypeContratPro = 'contrat_document_pro';
const _teal = Color(0xFF0C5C6C);

/// Photo (JPEG) → PDF A4, image ajustée à la page.
Future<Uint8List> imageEnPdf(Uint8List jpeg) async {
  final doc = pw.Document();
  final img = pw.MemoryImage(jpeg);
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(18),
    build: (_) => pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain)),
  ));
  return doc.save();
}

Future<Uint8List> _photoEnPdf(Uint8List octets) async {
  final jpeg = await FlutterImageCompress.compressWithList(octets,
      minWidth: 1600, minHeight: 1600, quality: 85, format: CompressFormat.jpeg);
  return imageEnPdf(jpeg);
}

/// Photo (appareil ou galerie) ou fichier (PDF / image) → PDF. null si annulé.
Future<Uint8List?> choisirDocumentPdf(BuildContext context) async {
  final source = await showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.photo_camera_outlined, color: _teal), title: const Text('Prendre en photo', style: TextStyle(fontFamily: 'Galey')),
          onTap: () => Navigator.pop(ctx, 'camera')),
      ListTile(leading: const Icon(Icons.photo_library_outlined, color: _teal), title: const Text('Choisir une photo', style: TextStyle(fontFamily: 'Galey')),
          onTap: () => Navigator.pop(ctx, 'galerie')),
      ListTile(leading: const Icon(Icons.picture_as_pdf_outlined, color: _teal), title: const Text('Choisir un fichier (PDF)', style: TextStyle(fontFamily: 'Galey')),
          onTap: () => Navigator.pop(ctx, 'fichier')),
    ])),
  );
  if (source == null) return null;
  if (source == 'fichier') {
    final res = await FilePicker.pickFiles(type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'], withData: true);
    final f = res?.files.single;
    final octets = f?.bytes;
    if (f == null || octets == null) return null;
    if ((f.extension ?? '').toLowerCase() == 'pdf') return octets;
    return _photoEnPdf(octets);
  }
  final x = await ImagePicker().pickImage(source: source == 'camera' ? ImageSource.camera : ImageSource.gallery);
  if (x == null) return null;
  return _photoEnPdf(await x.readAsBytes());
}

Future<String> _deposer(Uint8List pdf) async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  return uploadDocumentBytes(pdf, 'documents-pro/$uid/${DateTime.now().microsecondsSinceEpoch}.pdf');
}

/// Compte rendu chargé par le pro, rattaché au RDV (et à l'animal s'il a une fiche). Renvoie son id.
Future<String> chargerCompteRenduPro(Uint8List pdf, {required Map<String, dynamic> rdv, String? proProfileId, required String titre}) async {
  final url = await _deposer(pdf);
  final row = await Supabase.instance.client.from('documents_animaux').insert({
    'uid_eleveur': FirebaseAuth.instance.currentUser?.uid,
    if ((proProfileId ?? '').isNotEmpty) 'pro_profile_id': proProfileId,
    'animal_id': rdv['animal_id']?.toString(), 'rdv_id': rdv['id'].toString(),
    'type': kTypeCrPro, 'titre': titre, 'url': url, 'statut': 'envoye',
    'metadata': {'client_uid': rdv['client_uid'], 'client_profile_id': rdv['client_profile_id']},
  }).select('id').single();
  return row['id'].toString();
}

/// Comptes rendus chargés pour un RDV (id, titre, url, created_at).
Future<List<Map<String, dynamic>>> comptesRendusProDuRdv(String rdvId) async {
  try {
    final rows = await Supabase.instance.client.from('documents_animaux').select('id, titre, url, created_at')
        .eq('rdv_id', rdvId).eq('type', kTypeCrPro).order('created_at');
    return [for (final r in rows as List) Map<String, dynamic>.from(r as Map)];
  } catch (_) {
    return [];
  }
}

/// Fin de séance : « Joindre mon compte rendu » (photo / PDF) au RDV [rdvId].
/// Renvoie la ligne créée (id, titre, url) ou null si annulé.
Future<Map<String, dynamic>?> joindreCompteRenduProAuRdv(BuildContext context, String rdvId, {String titre = 'Compte rendu'}) async {
  final pdf = await choisirDocumentPdf(context);
  if (pdf == null) return null;
  final r = await Supabase.instance.client.from('rdv')
      .select('id, animal_id, pro_profile_id, client_uid, client_profile_id').eq('id', rdvId).maybeSingle();
  if (r == null) return null;
  final id = await chargerCompteRenduPro(pdf, rdv: r, proProfileId: r['pro_profile_id']?.toString(), titre: titre);
  return {'id': id, 'titre': titre, 'url': ''};
}

/// Octets d'un compte rendu chargé (pour l'e-mail de fin de séance).
Future<Uint8List?> octetsDocumentPro(String documentId) async {
  try {
    final row = await Supabase.instance.client.from('documents_animaux').select('url').eq('id', documentId).maybeSingle();
    final url = row?['url']?.toString() ?? '';
    if (url.isEmpty) return null;
    final res = await http.get(Uri.parse(await lienDocument(url)));
    return res.statusCode == 200 ? res.bodyBytes : null;
  } catch (_) {
    return null;
  }
}

/// Fenêtres de fin de séance (véto, ostéo, toiletteur) : mes comptes rendus
/// chargés (cochés) + « Joindre mon compte rendu ». Un document joint décoche
/// les comptes rendus générés ([estGenere]) : c'est lui qui part au client.
List<Widget> lignesCrsPro(BuildContext ctx, void Function(void Function()) setM, {
  required String rdvId, required List<Map<String, dynamic>> crsPro, required Map<String, bool> coches,
  required Widget Function(String cle, String titre, [String? sous]) ligne, required bool Function(String cle) estGenere,
}) => [
      for (final d in crsPro) ligne('pro:${d['id']}', d['titre']?.toString() ?? 'Compte rendu', 'Mon document'),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(
        onPressed: () async {
          final d = await joindreCompteRenduProAuRdv(ctx, rdvId);
          if (d == null) return;
          setM(() {
            crsPro.add(d);
            for (final k in coches.keys.toList()) {
              if (estGenere(k)) coches[k] = false;
            }
            coches['pro:${d['id']}'] = true;
          });
        },
        icon: const Icon(Icons.upload_file_outlined, size: 18),
        label: const Text('Joindre mon compte rendu (photo / PDF)', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
        style: TextButton.styleFrom(foregroundColor: _teal, padding: EdgeInsets.zero),
      )),
    ];

/// Ajoute aux pièces de l'e-mail mes comptes rendus chargés et cochés.
Future<void> ajouterPiecesCrsPro(List<({String type, String nomFichier, Uint8List bytes})> pieces,
    List<Map<String, dynamic>> crsPro, Map<String, bool> coches) async {
  for (final d in crsPro) {
    if (coches['pro:${d['id']}'] != true) continue;
    final octets = await octetsDocumentPro(d['id'].toString());
    if (octets == null) continue;
    final nom = (d['titre']?.toString() ?? 'Compte rendu').replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
    pieces.add((type: 'compte_rendu', nomFichier: '$nom.pdf', bytes: octets));
  }
}

/// Contrat chargé par le pro : à signer en ligne par le client.
Future<({String id, String token})> creerContratPro(Uint8List pdf, {
  required Map<String, dynamic> rdv, String? proProfileId, required String titre, required String clientNom, String? clientEmail,
}) async {
  final url = await _deposer(pdf);
  final row = await Supabase.instance.client.from('documents_animaux').insert({
    'uid_eleveur': FirebaseAuth.instance.currentUser?.uid,
    if ((proProfileId ?? '').isNotEmpty) 'pro_profile_id': proProfileId,
    'animal_id': rdv['animal_id']?.toString(), 'rdv_id': rdv['id'].toString(),
    'type': kTypeContratPro, 'titre': titre, 'statut': 'en_attente', 'url': url, 'pdf_original_url': url,
    // client_uid / client_profile_id / client_email : le contrat remonte dans « Mes contrats » du client.
    'metadata': {'document_pro': true, 'client_nom': clientNom, 'client_uid': rdv['client_uid'],
        'client_profile_id': rdv['client_profile_id'], 'client_email': clientEmail},
  }).select('id, token').single();
  return (id: row['id'].toString(), token: row['token'].toString());
}

Uint8List? _octetsSignature(String? dataUrl) {
  if (dataUrl == null || !dataUrl.startsWith('data:image/')) return null;
  try { return base64Decode(dataUrl.split(',').last); } catch (_) { return null; }
}

/// PDF du contrat chargé + une page de signatures à la fin (pages d'origine
/// reprises en image : le paquet pdf ne fusionne pas les PDF).
Future<Uint8List> contratProSigne(Uint8List original, {
  required String titre, required String proNom, required String clientNom,
  String? sigPro, String? sigClient, String? signeLePro, String? signeLeClient,
}) async {
  final doc = pw.Document();
  await for (final page in Printing.raster(original, dpi: 130)) {
    final png = await page.toPng();
    doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: pw.EdgeInsets.zero,
        build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain))));
  }
  String le(String? iso, String? sig) {
    final d = DateTime.tryParse(iso ?? '');
    return d != null ? 'Signé le ${DateFormat('dd/MM/yyyy').format(d.toLocal())}' : (sig != null ? 'Signé' : 'Non signé');
  }
  pw.Widget colonne(String role, String nom, String? sig, String? iso) {
    final img = _octetsSignature(sig);
    return pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(role, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0C5C6C))),
      pw.Text(nom.isEmpty ? '-' : nom),
      pw.SizedBox(height: 8),
      pw.Container(height: 80, alignment: pw.Alignment.bottomLeft,
          child: img != null ? pw.Image(pw.MemoryImage(img), fit: pw.BoxFit.contain) : pw.SizedBox()),
      pw.Divider(thickness: 0.5),
      pw.Text(le(iso, sig), style: const pw.TextStyle(fontSize: 9)),
      pw.Text('« Lu et approuvé »', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ]));
  }
  doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(48), build: (_) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Signatures', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0C5C6C))),
      pw.SizedBox(height: 6),
      pw.Text(titre),
      pw.SizedBox(height: 30),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        colonne('Le Prestataire', proNom, sigPro, signeLePro),
        pw.SizedBox(width: 40),
        colonne('Le Client', clientNom, sigClient, signeLeClient),
      ]),
      pw.Spacer(),
      pw.Text('Signatures électroniques recueillies sur PetsMatch.', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ],
  )));
  return doc.save();
}

/// Depuis un RDV (tous les pros) : charger mon compte rendu ou mon contrat.
/// [mode] 'compte_rendu' | 'contrat'. Renvoie true si un document a été créé.
/// Miroir site : DocumentProModal.
/// [catPro] : métier (abonnements.profil_type) — contrat = formule payante, comme le contrat PetsMatch.
Future<bool> showDocumentProSheet(BuildContext context, {
  required Map<String, dynamic> rdv, required String mode, required String clientNom, String animalNom = '', String proNom = '',
  required String catPro,
}) async {
  final cr = mode == 'compte_rendu';
  final messenger = ScaffoldMessenger.of(context);
  if (!cr && await PlanService.getPlanCode(FirebaseAuth.instance.currentUser?.uid ?? '', profilType: catPro) == 'free') {
    messenger.showSnackBar(const SnackBar(content: Text('La signature électronique des contrats est disponible avec les formules payantes.',
        style: TextStyle(fontFamily: 'Galey')), behavior: SnackBarBehavior.floating));
    return false;
  }
  if (!context.mounted) return false;
  final titreCtrl = TextEditingController(text: cr ? 'Compte rendu${animalNom.isNotEmpty ? ' — $animalNom' : ''}' : 'Contrat — $clientNom');
  Uint8List? pdf;
  var envoyer = true;
  var enCours = false;
  final ok = await showModalBottomSheet<bool>(
    context: context, isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setM) => Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(cr ? 'Charger mon compte rendu' : 'Charger mon contrat',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(cr
            ? 'Votre propre document (photo ou PDF) : c’est lui qui est envoyé au client et rangé avec le rendez-vous.'
            : 'Votre propre contrat (photo ou PDF) : le client le lit et le signe en ligne, comme un contrat PetsMatch.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade600)),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: enCours ? null : () async {
            final p = await choisirDocumentPdf(ctx);
            if (p != null) setM(() => pdf = p);
          },
          icon: Icon(pdf == null ? Icons.upload_file_outlined : Icons.check_circle_outline, size: 18),
          label: Text(pdf == null ? 'Photo ou fichier' : 'Document prêt — changer', style: const TextStyle(fontFamily: 'Galey')),
          style: OutlinedButton.styleFrom(foregroundColor: _teal, minimumSize: const Size(double.infinity, 46)),
        ),
        const SizedBox(height: 12),
        TextField(controller: titreCtrl, style: const TextStyle(fontFamily: 'Galey'),
            decoration: const InputDecoration(labelText: 'Titre', border: OutlineInputBorder(), isDense: true)),
        if (cr)
          CheckboxListTile(
            value: envoyer, onChanged: (v) => setM(() => envoyer = v ?? true),
            contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, activeColor: _teal,
            title: Text('Envoyer au client maintenant (e-mail${rdv['client_uid'] != null ? ' et notification' : ''})',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
          ),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: enCours || pdf == null ? null : () async {
            setM(() => enCours = true);
            try {
              final titre = titreCtrl.text.trim().isEmpty ? (cr ? 'Compte rendu' : 'Contrat') : titreCtrl.text.trim();
              final pid = rdv['pro_profile_id']?.toString();
              final email = (await coordonneesClientRdv(rdv))['email'];
              final supa = Supabase.instance.client;
              Future<void> notifier(String type, String title, String body, Map<String, dynamic> data) async {
                if (rdv['client_uid'] == null) return;
                await supa.from('notifications').insert({'uid': rdv['client_uid'], 'type': type, 'title': title, 'body': body,
                    if (rdv['client_profile_id'] != null) 'profile_id': rdv['client_profile_id'], 'data': data, 'read': false});
              }
              final qui = proNom.isEmpty ? 'Votre professionnel' : proNom;
              if (cr) {
                final id = await chargerCompteRenduPro(pdf!, rdv: rdv, proProfileId: pid, titre: titre);
                if (envoyer) {
                  await notifier('compte_rendu_pro', 'Nouveau compte rendu',
                      '$qui vous a transmis un compte rendu${animalNom.isNotEmpty ? ' pour $animalNom' : ''}.',
                      {'rdv_id': rdv['id'].toString(), if (rdv['animal_id'] != null) 'animal_id': rdv['animal_id'].toString(), 'document_id': id});
                  if (ctx.mounted) {
                    await envoyerDocumentsParEmail(ctx, pieces: [(type: 'compte_rendu', nomFichier: '${titre.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')}.pdf', bytes: pdf!)],
                        emailParDefaut: (email ?? '').isEmpty ? null : email, destinataireNom: clientNom, expediteur: proNom,
                        animalNom: animalNom, animalId: rdv['animal_id']?.toString());
                  }
                }
              } else {
                final c = await creerContratPro(pdf!, rdv: rdv, proProfileId: pid, titre: titre, clientNom: clientNom,
                    clientEmail: (email ?? '').isEmpty ? null : email);
                // Ma signature apposée d'office ; à défaut je la dessine (enregistrée pour les suivants).
                if (ctx.mounted) await signerContratAvecSignaturePro(ctx, c.id);
                if (rdv['client_uid'] != null) {
                  await notifier('contrat_invite', 'Contrat à signer', '$qui vous envoie un contrat — vérifiez et signez',
                      {'token': c.token, 'url': '/signer-contrat/${c.token}'});
                } else {
                  await envoyerContratParEmail(rdv, c.token, titre: titre, nomClient: clientNom);
                }
              }
              if (ctx.mounted) Navigator.pop(ctx, true);
            } catch (e) {
              setM(() => enCours = false);
              messenger.showSnackBar(SnackBar(content: Text('Impossible : $e', style: const TextStyle(fontFamily: 'Galey')),
                  behavior: SnackBarBehavior.floating));
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white, minimumSize: const Size(0, 46)),
          child: Text(enCours ? '…' : cr ? (envoyer ? 'Enregistrer et envoyer' : 'Enregistrer') : 'Envoyer le contrat à signer',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        )),
      ]),
    )),
  );
  if (ok == true) {
    messenger.showSnackBar(SnackBar(content: Text(cr ? 'Compte rendu enregistré.' : 'Contrat envoyé au client pour signature.',
        style: const TextStyle(fontFamily: 'Galey')), behavior: SnackBarBehavior.floating));
  }
  return ok == true;
}
