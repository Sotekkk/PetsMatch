// Ordonnance vétérinaire générée depuis le compte rendu (compte_rendu_page.dart) :
// en-tête de la clinique (n° d'Ordre), patient, propriétaire, médicaments
// (posologie, durée), prescripteur. Même police que les contrats
// (contrat_pdf.dart, NotoSans : accents).

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _teal = PdfColor.fromInt(0xFF0C5C6C);
const _dark = PdfColor.fromInt(0xFF1E2025);
const _grey = PdfColor.fromInt(0xFF6F767B);
const _line = PdfColor.fromInt(0xFFDDE2DC);

class LigneOrdonnance {
  final String medicament;
  final String posologie;
  final int? dureeJours;
  final String? notes;
  const LigneOrdonnance({required this.medicament, required this.posologie, this.dureeJours, this.notes});
}

pw.ThemeData? _theme;
Future<pw.ThemeData> _chargerTheme() async {
  if (_theme != null) return _theme!;
  Future<pw.Font> load(String p) async => pw.Font.ttf(await rootBundle.load('assets/font/$p'));
  return _theme = pw.ThemeData.withFont(
    base: await load('NotoSans-Regular.ttf'),
    bold: await load('NotoSans-Bold.ttf'),
    italic: await load('NotoSans-Italic.ttf'),
  );
}

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Âge de l'animal (« 5 mois », « 3 ans ») d'après sa date de naissance,
/// sinon l'âge estimé saisi. Miroir site : ageAnimal (lib/ordonnance-pdf.ts).
String ageAnimal(dynamic naissance, dynamic estime) {
  final d = DateTime.tryParse(naissance?.toString() ?? '');
  if (d != null) {
    final n = DateTime.now();
    final mois = (n.year - d.year) * 12 + n.month - d.month - (n.day < d.day ? 1 : 0);
    if (mois < 0) return '';
    if (mois < 12) return '$mois mois';
    final ans = mois ~/ 12;
    return '$ans an${ans > 1 ? 's' : ''}';
  }
  final e = estime?.toString().trim() ?? '';
  final n = int.tryParse(e);
  if (n != null) return '$n an${n > 1 ? 's' : ''} (estimé)';
  return e;
}

/// « Femelle » / « Mâle » quel que soit le codage (F, femelle, female…).
String sexeAnimal(dynamic sexe) {
  final s = sexe?.toString().trim().toLowerCase() ?? '';
  if (s.isEmpty) return '';
  if (s.startsWith('f')) return 'Femelle';
  if (s.startsWith('m')) return 'Mâle';
  return sexe.toString();
}

/// Paragraphes du compte rendu : titre en gras (« Motif : », « Poids : »,
/// « Actes réalisés : », « Recommandations »…), suite en texte normal.
final _titreParagraphe = RegExp(r'^([A-ZÀ-Ý][^:\n.]{0,40}?)\s*:\s*(.*)$', dotAll: true);
final _titreSeul = RegExp(r'^(recommandations?|conclusion|conseils?|diagnostic|examen clinique|observations?|traitement)\s*:?\s*$', caseSensitive: false);
List<pw.Widget> _paragraphesCr(String contenu) => [
  for (final l in contenu.split('\n'))
    if (l.trim().isEmpty)
      pw.SizedBox(height: 6)
    else if (_titreSeul.hasMatch(l.trim()))
      pw.Padding(padding: const pw.EdgeInsets.only(top: 2, bottom: 1),
          child: pw.Text(l.trim(), style: pw.TextStyle(fontSize: 10.5, color: _dark, fontWeight: pw.FontWeight.bold)))
    else if (_titreParagraphe.firstMatch(l.trim()) case final m?)
      pw.RichText(text: pw.TextSpan(style: const pw.TextStyle(fontSize: 10.5, color: _dark, lineSpacing: 2), children: [
        pw.TextSpan(text: '${m.group(1)} : ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.TextSpan(text: m.group(2)),
      ]))
    else
      pw.Text(l, style: const pw.TextStyle(fontSize: 10.5, color: _dark, lineSpacing: 2)),
];

Future<Uint8List> ordonnancePdfBytes({
  required String cliniqueNom,
  String cliniqueAdresse = '',
  String cliniqueTel = '',
  String numeroOrdre = '',
  required String prescripteur,
  required String animalNom,
  String animalEspeceRace = '',
  String animalSexe = '',
  String animalAge = '',
  String animalIdentification = '',
  String animalPoids = '',
  String proprietaire = '',
  required List<LigneOrdonnance> lignes,
  String? remarques,
  DateTime? date,
  /// Signature manuscrite du prescripteur (PNG), apposée au-dessus du trait.
  Uint8List? signature,
}) async {
  final doc = pw.Document(theme: await _chargerTheme());
  final jour = date ?? DateTime.now();
  pw.Widget info(String label, String valeur) => valeur.trim().isEmpty
      ? pw.SizedBox()
      : pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.RichText(text: pw.TextSpan(children: [
            pw.TextSpan(text: '$label : ', style: const pw.TextStyle(fontSize: 9, color: _grey)),
            pw.TextSpan(text: valeur, style: const pw.TextStyle(fontSize: 9, color: _dark)),
          ])),
        );

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      // En-tête clinique
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(cliniqueNom, style: pw.TextStyle(fontSize: 15, color: _teal, fontWeight: pw.FontWeight.bold)),
          if (cliniqueAdresse.isNotEmpty) pw.Text(cliniqueAdresse, style: const pw.TextStyle(fontSize: 9, color: _dark)),
          if (cliniqueTel.isNotEmpty) pw.Text('Tél. $cliniqueTel', style: const pw.TextStyle(fontSize: 9, color: _dark)),
          if (numeroOrdre.isNotEmpty) pw.Text("N° d'inscription à l'Ordre : $numeroOrdre", style: const pw.TextStyle(fontSize: 9, color: _dark)),
        ])),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('ORDONNANCE', style: pw.TextStyle(fontSize: 13, color: _teal, fontWeight: pw.FontWeight.bold, letterSpacing: 1)),
          pw.SizedBox(height: 2),
          pw.Text('Le ${_date(jour)}', style: const pw.TextStyle(fontSize: 9, color: _dark)),
        ]),
      ]),
      pw.SizedBox(height: 14),
      pw.Divider(color: _line, thickness: 1),
      pw.SizedBox(height: 10),

      // Patient / propriétaire
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFF4F7F6), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Patient', style: pw.TextStyle(fontSize: 9, color: _teal, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 3),
            pw.Text(animalNom, style: pw.TextStyle(fontSize: 11, color: _dark, fontWeight: pw.FontWeight.bold)),
            info('Espèce / race', animalEspeceRace),
            info('Sexe', animalSexe),
            info('Âge', animalAge),
            info('Identification', animalIdentification),
            info('Poids', animalPoids),
          ])),
          pw.SizedBox(width: 16),
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Propriétaire', style: pw.TextStyle(fontSize: 9, color: _teal, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 3),
            pw.Text(proprietaire.isEmpty ? '—' : proprietaire, style: const pw.TextStyle(fontSize: 10, color: _dark)),
          ])),
        ]),
      ),
      pw.SizedBox(height: 18),

      // Prescription
      for (var i = 0; i < lignes.length; i++) pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(
            width: 18, height: 18, alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(color: _teal, shape: pw.BoxShape.circle),
            child: pw.Text('${i + 1}', style: pw.TextStyle(fontSize: 9, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(lignes[i].medicament, style: pw.TextStyle(fontSize: 11, color: _dark, fontWeight: pw.FontWeight.bold)),
            if (lignes[i].posologie.trim().isNotEmpty)
              pw.Text(lignes[i].posologie, style: const pw.TextStyle(fontSize: 10, color: _dark)),
            if (lignes[i].dureeJours != null)
              pw.Text('Pendant ${lignes[i].dureeJours} jour${lignes[i].dureeJours! > 1 ? 's' : ''}',
                  style: const pw.TextStyle(fontSize: 9.5, color: _grey)),
            if ((lignes[i].notes ?? '').trim().isNotEmpty)
              pw.Text(lignes[i].notes!, style: pw.TextStyle(fontSize: 9, color: _grey, fontStyle: pw.FontStyle.italic)),
          ])),
        ]),
      ),
      if ((remarques ?? '').trim().isNotEmpty) ...[
        pw.SizedBox(height: 6),
        pw.Text('Remarques', style: pw.TextStyle(fontSize: 9, color: _teal, fontWeight: pw.FontWeight.bold)),
        pw.Text(remarques!, style: const pw.TextStyle(fontSize: 9.5, color: _dark)),
      ],
      pw.Spacer(),

      // Prescripteur
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (prescripteur.trim().isNotEmpty && prescripteur.trim().toLowerCase() != 'vétérinaire')
            pw.Text('Dr $prescripteur', style: pw.TextStyle(fontSize: 10, color: _dark, fontWeight: pw.FontWeight.bold)),
          pw.Text('Vétérinaire', style: const pw.TextStyle(fontSize: 9, color: _grey)),
          signature != null
              ? pw.Container(width: 160, height: 56, alignment: pw.Alignment.bottomLeft,
                  child: pw.Image(pw.MemoryImage(signature), fit: pw.BoxFit.contain))
              : pw.SizedBox(height: 30),
          pw.Container(width: 160, height: 0.6, color: _grey),
          pw.Text('Signature', style: const pw.TextStyle(fontSize: 8, color: _grey)),
        ]),
      ]),
      pw.SizedBox(height: 14),
      pw.Text('Ordonnance établie via PetsMatch — à présenter en pharmacie / à conserver dans le carnet de santé.',
          style: pw.TextStyle(fontSize: 7.5, color: _grey, fontStyle: pw.FontStyle.italic)),
    ]),
  ));
  return doc.save();
}

/// Compte rendu de consultation en PDF (impression / envoi au propriétaire).
Future<Uint8List> compteRenduPdfBytes({
  required String cliniqueNom,
  String cliniqueAdresse = '',
  String cliniqueTel = '',
  String cliniqueEmail = '',
  required String praticien,
  required String animalNom,
  String animalEspeceRace = '',
  String animalSexe = '',
  String animalAge = '',
  String animalIdentification = '',
  String proprietaire = '',
  required String contenu,
  DateTime? date,
  /// Signature manuscrite du vétérinaire (PNG).
  Uint8List? signature,
}) async {
  final doc = pw.Document(theme: await _chargerTheme());
  final jour = date ?? DateTime.now();
  // Sans nom de praticien : pas de « Dr Vétérinaire ».
  final nomPraticien = praticien.trim().toLowerCase() == 'vétérinaire' ? '' : praticien.trim();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
    build: (_) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(cliniqueNom, style: pw.TextStyle(fontSize: 15, color: _teal, fontWeight: pw.FontWeight.bold)),
          if (cliniqueAdresse.isNotEmpty) pw.Text(cliniqueAdresse, style: const pw.TextStyle(fontSize: 9, color: _dark)),
          if (cliniqueTel.isNotEmpty) pw.Text('Tél. $cliniqueTel', style: const pw.TextStyle(fontSize: 9, color: _dark)),
          if (cliniqueEmail.isNotEmpty) pw.Text(cliniqueEmail, style: const pw.TextStyle(fontSize: 9, color: _dark)),
        ])),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('COMPTE RENDU', style: pw.TextStyle(fontSize: 13, color: _teal, fontWeight: pw.FontWeight.bold, letterSpacing: 1)),
          pw.Text('Le ${_date(jour)}', style: const pw.TextStyle(fontSize: 9, color: _dark)),
        ]),
      ]),
      pw.SizedBox(height: 12),
      pw.Divider(color: _line, thickness: 1),
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFF4F7F6), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Patient', style: pw.TextStyle(fontSize: 9, color: _teal, fontWeight: pw.FontWeight.bold)),
            pw.Text(animalNom, style: pw.TextStyle(fontSize: 11, color: _dark, fontWeight: pw.FontWeight.bold)),
            for (final (l, v) in [('Espèce / race', animalEspeceRace), ('Sexe', animalSexe), ('Âge', animalAge),
                ('Identification', animalIdentification)])
              if (v.isNotEmpty) pw.RichText(text: pw.TextSpan(style: const pw.TextStyle(fontSize: 9, color: _dark), children: [
                pw.TextSpan(text: '$l : ', style: const pw.TextStyle(color: _grey)),
                pw.TextSpan(text: v),
              ])),
          ])),
          pw.SizedBox(width: 16),
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Propriétaire', style: pw.TextStyle(fontSize: 9, color: _teal, fontWeight: pw.FontWeight.bold)),
            pw.Text(proprietaire.isEmpty ? '—' : proprietaire, style: const pw.TextStyle(fontSize: 10, color: _dark)),
          ])),
        ]),
      ),
      pw.SizedBox(height: 16),
      ..._paragraphesCr(contenu),
      // Bloc signature : nom du vétérinaire, date du jour, « Signature : » puis la signature.
      pw.SizedBox(height: 28),
      pw.Align(alignment: pw.Alignment.centerRight, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        if (nomPraticien.isNotEmpty)
          pw.Text('Dr $nomPraticien', style: pw.TextStyle(fontSize: 10, color: _dark, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 3),
        pw.Text('Le ${_date(DateTime.now())}', style: const pw.TextStyle(fontSize: 10, color: _dark)),
        pw.SizedBox(height: 3),
        pw.Text('Signature :', style: const pw.TextStyle(fontSize: 10, color: _dark)),
        if (signature != null)
          pw.Container(width: 160, height: 56, alignment: pw.Alignment.centerLeft,
              child: pw.Image(pw.MemoryImage(signature), fit: pw.BoxFit.contain))
        else
          pw.SizedBox(height: 40),
      ])),
    ],
  ));
  return doc.save();
}
