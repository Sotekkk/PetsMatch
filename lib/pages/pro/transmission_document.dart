// Imprimer / partager / envoyer par e-mail une ordonnance ou un compte rendu
// (PDF), y compris à un propriétaire sans PetsMatch (patient créé par la
// clinique). E-mail : route du site /api/documents/envoyer-email.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:PetsMatch/config.dart';
import 'package:PetsMatch/utils/site_api.dart';

const _teal = Color(0xFF0C5C6C);

Future<void> transmettreDocument(
  BuildContext context, {
  required Future<Uint8List> Function() pdf,
  required String nomFichier,
  required String type, // 'ordonnance' | 'compte_rendu' | 'facture'
  String animalNom = '',
  String expediteur = '',
  String? emailParDefaut,
  String? destinataireNom,
}) async {
  final choix = await showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(title: Text(type == 'ordonnance' ? 'Ordonnance' : type == 'facture' ? 'Facture' : 'Compte rendu',
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
      ListTile(leading: const Icon(Icons.print_outlined, color: _teal),
          title: const Text('Imprimer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
          onTap: () => Navigator.pop(ctx, 'imprimer')),
      ListTile(leading: const Icon(Icons.share_outlined, color: _teal),
          title: const Text('Partager (WhatsApp, mail…)', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
          onTap: () => Navigator.pop(ctx, 'partager')),
      ListTile(leading: const Icon(Icons.mark_email_read_outlined, color: _teal),
          title: const Text('Envoyer au propriétaire par e-mail', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
          onTap: () => Navigator.pop(ctx, 'email')),
    ])),
  );
  if (choix == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    if (choix == 'imprimer') {
      final bytes = await pdf();
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: nomFichier);
    } else if (choix == 'partager') {
      final bytes = await pdf();
      await Printing.sharePdf(bytes: bytes, filename: nomFichier);
    } else {
      final ctrl = TextEditingController(text: emailParDefaut ?? '');
      final email = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Envoyer par e-mail', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: TextField(controller: ctrl, keyboardType: TextInputType.emailAddress, autofocus: true,
            decoration: const InputDecoration(labelText: 'E-mail du propriétaire', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Envoyer')),
        ],
      ));
      if (email == null || email.isEmpty) return;
      final bytes = await pdf();
      final res = await http.post(
        Uri.parse('$kSiteBaseUrl/api/documents/envoyer-email'),
        headers: {...await siteApiHeaders(), 'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email, 'destinataire_nom': destinataireNom, 'expediteur_nom': expediteur,
          'document_type': type, 'animal_nom': animalNom, 'fichier_nom': nomFichier,
          'pdf_base64': base64Encode(bytes),
        }),
      );
      messenger.showSnackBar(SnackBar(
        content: Text(res.statusCode == 200 ? 'Envoyé à $email.' : "L'envoi a échoué (${res.statusCode}).",
            style: const TextStyle(fontFamily: 'Galey')),
        behavior: SnackBarBehavior.floating,
      ));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Impossible : $e', style: const TextStyle(fontFamily: 'Galey')),
        behavior: SnackBarBehavior.floating));
  }
}
