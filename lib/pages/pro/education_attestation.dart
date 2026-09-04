import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;

const _kOrange = PdfColor(239 / 255, 108 / 255, 0);

/// Génère l'attestation de fin de programme (PDF), l'archive dans le bucket
/// `media`, écrit une ligne `education_attestations` et notifie la famille.
/// Retourne l'URL du PDF, ou null en cas d'échec.
Future<String?> genererAttestationEducation({
  required String animalId,
  required String animalNom,
  required String? ownerUid,
  required String? ownerProfileId,
  required List<Map<String, dynamic>> objectifs,
  required List<Map<String, dynamic>> seances,
}) async {
  final supa = Supabase.instance.client;
  final proUid = FirebaseAuth.instance.currentUser?.uid;
  if (proUid == null) return null;

  final proNom = User_Info.nameElevage.isNotEmpty
      ? User_Info.nameElevage
      : '${User_Info.firstname} ${User_Info.lastname}'.trim();
  final profession = User_Info.professionPro.isNotEmpty ? User_Info.professionPro : 'Éducateur canin';

  final acquis = objectifs.where((o) => o['statut'] == 'acquis').toList();
  final autres = objectifs.where((o) => o['statut'] != 'acquis').toList();
  final dates = seances
      .map((s) => DateTime.tryParse(s['date_seance']?.toString() ?? ''))
      .whereType<DateTime>()
      .toList()
    ..sort();
  final debut = dates.isNotEmpty ? dates.first : null;
  final fin = dates.isNotEmpty ? dates.last : DateTime.now();
  String fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(40),
    build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(16),
        decoration: const pw.BoxDecoration(
          color: _kOrange,
          borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Attestation de fin de programme',
              style: pw.TextStyle(fontSize: 18, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          pw.Text('Suivi comportemental — $animalNom',
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.white)),
        ]),
      ),
      pw.SizedBox(height: 20),
      pw.Text('Je soussigné(e) ${proNom.isNotEmpty ? proNom : profession}, $profession, atteste avoir '
          'accompagné $animalNom dans un programme d\'éducation'
          '${debut != null ? ' du ${fmt(debut)} au ${fmt(fin)}' : ''}, '
          'à raison de ${seances.length} séance${seances.length > 1 ? 's' : ''}.',
          style: const pw.TextStyle(fontSize: 11, lineSpacing: 3)),
      pw.SizedBox(height: 16),
      if (acquis.isNotEmpty) ...[
        pw.Text('Objectifs atteints',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _kOrange)),
        pw.SizedBox(height: 4),
        ...acquis.map((o) => pw.Bullet(text: o['libelle']?.toString() ?? '', style: const pw.TextStyle(fontSize: 10))),
        pw.SizedBox(height: 12),
      ],
      if (autres.isNotEmpty) ...[
        pw.Text('Axes de travail à poursuivre',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
        pw.SizedBox(height: 4),
        ...autres.map((o) => pw.Bullet(text: o['libelle']?.toString() ?? '', style: const pw.TextStyle(fontSize: 10))),
        pw.SizedBox(height: 12),
      ],
      pw.Spacer(),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Fait le ${fmt(DateTime.now())}', style: const pw.TextStyle(fontSize: 10)),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text(proNom.isNotEmpty ? proNom : profession,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          if (User_Info.siret.isNotEmpty)
            pw.Text('SIRET ${User_Info.siret}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ]),
      ]),
      pw.SizedBox(height: 8),
      pw.Text('Document généré via PetsMatch', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
    ]),
  ));

  try {
    final bytes = await doc.save();
    final path = 'attestations/$proUid/${animalId}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await supa.storage.from('media').uploadBinary(
      path, bytes,
      fileOptions: const FileOptions(contentType: 'application/pdf', upsert: true),
    );
    final url = supa.storage.from('media').getPublicUrl(path);

    await supa.from('education_attestations').insert({
      'animal_id': animalId,
      'pro_uid': proUid,
      if (User_Info.activeProfileId.isNotEmpty) 'pro_profile_id': User_Info.activeProfileId,
      'owner_uid': ownerUid,
      if (ownerProfileId != null) 'owner_profile_id': ownerProfileId,
      'pdf_url': url,
      'contenu': {
        'objectifs_atteints': acquis.map((o) => o['libelle']).toList(),
        'nb_seances': seances.length,
      },
    });

    if (ownerUid != null && ownerUid.isNotEmpty) {
      try {
        await supa.from('notifications').insert({
          'uid': ownerUid,
          'type': 'education_attestation',
          'title': 'Attestation de fin de programme — $animalNom',
          'body': '${proNom.isNotEmpty ? proNom : 'Votre éducateur'} vous a remis l\'attestation.',
          if (ownerProfileId != null) 'profile_id': ownerProfileId,
          'data': {
            'animalId': animalId,
            'url': '/mes-animaux/$animalId?tab=education',
          },
          'read': false,
        });
      } catch (_) {}
    }
    return url;
  } catch (_) {
    return null;
  }
}
