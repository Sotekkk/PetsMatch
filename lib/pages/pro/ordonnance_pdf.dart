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

Future<Uint8List> ordonnancePdfBytes({
  required String cliniqueNom,
  String cliniqueAdresse = '',
  String cliniqueTel = '',
  String numeroOrdre = '',
  required String prescripteur,
  required String animalNom,
  String animalEspeceRace = '',
  String animalIdentification = '',
  String animalPoids = '',
  String proprietaire = '',
  required List<LigneOrdonnance> lignes,
  String? remarques,
  DateTime? date,
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
          pw.Text('Dr $prescripteur', style: pw.TextStyle(fontSize: 10, color: _dark, fontWeight: pw.FontWeight.bold)),
          pw.Text('Vétérinaire', style: const pw.TextStyle(fontSize: 9, color: _grey)),
          pw.SizedBox(height: 30),
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
  required String praticien,
  required String animalNom,
  String animalEspeceRace = '',
  String animalIdentification = '',
  String proprietaire = '',
  required String contenu,
  DateTime? date,
}) async {
  final doc = pw.Document(theme: await _chargerTheme());
  final jour = date ?? DateTime.now();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
    build: (_) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(cliniqueNom, style: pw.TextStyle(fontSize: 15, color: _teal, fontWeight: pw.FontWeight.bold)),
          if (cliniqueAdresse.isNotEmpty) pw.Text(cliniqueAdresse, style: const pw.TextStyle(fontSize: 9, color: _dark)),
          if (cliniqueTel.isNotEmpty) pw.Text('Tél. $cliniqueTel', style: const pw.TextStyle(fontSize: 9, color: _dark)),
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
            if (animalEspeceRace.isNotEmpty) pw.Text(animalEspeceRace, style: const pw.TextStyle(fontSize: 9, color: _dark)),
            if (animalIdentification.isNotEmpty) pw.Text('Identification : $animalIdentification', style: const pw.TextStyle(fontSize: 9, color: _dark)),
          ])),
          pw.SizedBox(width: 16),
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Propriétaire', style: pw.TextStyle(fontSize: 9, color: _teal, fontWeight: pw.FontWeight.bold)),
            pw.Text(proprietaire.isEmpty ? '—' : proprietaire, style: const pw.TextStyle(fontSize: 10, color: _dark)),
          ])),
        ]),
      ),
      pw.SizedBox(height: 16),
      pw.Text(contenu, style: const pw.TextStyle(fontSize: 10.5, color: _dark, lineSpacing: 2)),
      pw.SizedBox(height: 28),
      pw.Align(alignment: pw.Alignment.centerRight, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Dr $praticien', style: pw.TextStyle(fontSize: 10, color: _dark, fontWeight: pw.FontWeight.bold)),
        pw.Text('Vétérinaire', style: const pw.TextStyle(fontSize: 9, color: _grey)),
      ])),
    ],
  ));
  return doc.save();
}
