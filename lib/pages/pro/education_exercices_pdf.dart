import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/widgets/rich_text_view.dart';

const _kOrange = PdfColor.fromInt(0xFFEF6C00);

/// Génère un PDF listant les exercices attribués à un animal (déroulé en
/// texte brut — pas de mise en forme HTML dans le PDF) et l'héberge sur le
/// bucket `media`. Pensé pour les familles sans compte PetsMatch : le lien
/// peut être envoyé par email/SMS/WhatsApp (cf. `Share.share`).
Future<String?> genererExercicesPdf({
  required String animalId,
  required String animalNom,
  required List<Map<String, dynamic>> exercices, // exercices_attribues (snapshots)
}) async {
  final proUid = FirebaseAuth.instance.currentUser?.uid;
  if (proUid == null) return null;

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (ctx) => [
        pw.Text('Programme d\'éducation',
            style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600)),
        pw.Text(animalNom,
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: _kOrange)),
        pw.SizedBox(height: 4),
        pw.Text('Édité le ${_today()}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
        pw.Divider(height: 24),
        if (exercices.isEmpty)
          pw.Text('Aucun exercice attribué pour le moment.', style: const pw.TextStyle(fontSize: 12))
        else
          ...exercices.map((e) => pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 16),
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(e['titre_snapshot']?.toString() ?? '',
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  if ((e['cadence']?.toString() ?? '').isNotEmpty)
                    pw.Text('Fréquence : ${e['cadence']}',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                  if (e['echeance'] != null)
                    pw.Text('À faire avant le : ${e['echeance']}',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                  if ((e['description_snapshot']?.toString() ?? '').isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    pw.Text(
                      richTextToPlain(e['description_snapshot']?.toString()),
                      style: const pw.TextStyle(fontSize: 11, lineSpacing: 2),
                    ),
                  ],
                ]),
              )),
        pw.SizedBox(height: 20),
        pw.Text('Programme édité depuis PetsMatch.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey400)),
      ],
    ),
  );

  final bytes = await doc.save();
  final supa = Supabase.instance.client;
  final path = 'exercices_pdf/$proUid/${animalId}_${DateTime.now().millisecondsSinceEpoch}.pdf';
  await supa.storage.from('media').uploadBinary(
        path, bytes,
        fileOptions: const FileOptions(contentType: 'application/pdf', upsert: true),
      );
  return supa.storage.from('media').getPublicUrl(path);
}

String _today() {
  final now = DateTime.now();
  return '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
}
