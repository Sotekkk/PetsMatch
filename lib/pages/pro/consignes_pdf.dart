// PDF « Consignes après l'intervention de … » pour le propriétaire : en-tête
// de la clinique, animal / propriétaire, sections (titres, listes, gras),
// signature du vétérinaire, pages numérotées. Miroir site :
// website/src/lib/consignes-pdf.ts.

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:PetsMatch/utils/consignes_postop.dart';

const _teal = PdfColor.fromInt(0xFF0C5C6C);
const _dark = PdfColor.fromInt(0xFF1E2025);
const _grey = PdfColor.fromInt(0xFF6F767B);
const _line = PdfColor.fromInt(0xFFDDE2DC);

Future<pw.ThemeData> _theme() async {
  Future<pw.Font> load(String p) async => pw.Font.ttf(await rootBundle.load('assets/font/$p'));
  return pw.ThemeData.withFont(
    base: await load('NotoSans-Regular.ttf'),
    bold: await load('NotoSans-Bold.ttf'),
    italic: await load('NotoSans-Italic.ttf'),
  );
}

String _jj(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

pw.Widget _texte(List<SegmentConsigne> segments, {double taille = 10, bool toutGras = false}) => pw.RichText(
      text: pw.TextSpan(
        style: pw.TextStyle(fontSize: taille, color: _dark, lineSpacing: 2),
        children: [
          for (final s in segments)
            pw.TextSpan(text: s.texte, style: pw.TextStyle(fontWeight: s.gras || toutGras ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );

Future<Uint8List> consignesPdfBytes({
  required String cliniqueNom,
  String cliniqueAdresse = '',
  String cliniqueTel = '',
  String cliniqueEmail = '',
  required String praticien,
  required String animalNom,
  String animalEspeceRace = '',
  String proprietaire = '',
  DateTime? dateIntervention,
  required List<SectionConsigne> sections,
  Uint8List? signature,
  bool apercu = false,
}) async {
  final doc = pw.Document(theme: await _theme());
  final sous = [
    animalEspeceRace,
    if (dateIntervention != null) 'Intervention du ${_jj(dateIntervention)}',
    if (proprietaire.isNotEmpty) 'Propriétaire : $proprietaire',
  ].where((x) => x.isNotEmpty).join(' · ');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
    footer: (ctx) => pw.Row(children: [
      pw.Expanded(child: pw.Text('En cas de doute ou d’inquiétude, contactez la clinique.',
          style: pw.TextStyle(fontSize: 7.5, color: _grey, fontStyle: pw.FontStyle.italic))),
      pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 7.5, color: _grey)),
    ]),
    build: (_) => [
      pw.Text(cliniqueNom, style: pw.TextStyle(fontSize: 14, color: _teal, fontWeight: pw.FontWeight.bold)),
      for (final l in [cliniqueAdresse, if (cliniqueTel.isNotEmpty) 'Tél. $cliniqueTel', cliniqueEmail])
        if (l.isNotEmpty) pw.Text(l, style: const pw.TextStyle(fontSize: 9, color: _dark)),
      pw.SizedBox(height: 16),
      pw.Text("Consignes après l'intervention de $animalNom",
          style: pw.TextStyle(fontSize: 16, color: _teal, fontWeight: pw.FontWeight.bold)),
      if (sous.isNotEmpty) pw.Text(sous, style: const pw.TextStyle(fontSize: 9.5, color: _grey)),
      if (apercu)
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 8),
          padding: const pw.EdgeInsets.symmetric(vertical: 5),
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFFFF8EA), borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Text('APERÇU — document non validé par le vétérinaire',
              style: pw.TextStyle(fontSize: 9, color: const PdfColor.fromInt(0xFF8A5A00), fontWeight: pw.FontWeight.bold)),
        ),
      pw.SizedBox(height: 10),
      pw.Divider(color: _line, thickness: 1),
      pw.SizedBox(height: 8),
      for (final s in sections.where((x) => x.texte.trim().isNotEmpty)) ...[
        pw.Padding(padding: const pw.EdgeInsets.only(top: 6, bottom: 3),
            child: pw.Text(s.titre, style: pw.TextStyle(fontSize: 11.5, color: _teal, fontWeight: pw.FontWeight.bold))),
        for (final b in blocsConsigne(s.texte))
          b.type == 'titre'
              ? pw.Padding(padding: const pw.EdgeInsets.only(top: 2), child: _texte(b.segments, taille: 10.5, toutGras: true))
              : b.type == 'puce'
                  ? pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Padding(padding: const pw.EdgeInsets.fromLTRB(4, 0, 8, 0), child: pw.Text('•', style: const pw.TextStyle(fontSize: 10, color: _dark))),
                      pw.Expanded(child: _texte(b.segments)),
                    ])
                  : _texte(b.segments),
        pw.SizedBox(height: 6),
      ],
      pw.SizedBox(height: 20),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (praticien.trim().isNotEmpty && praticien.trim().toLowerCase() != 'vétérinaire')
            pw.Text('Dr ${praticien.trim()}', style: pw.TextStyle(fontSize: 10, color: _dark, fontWeight: pw.FontWeight.bold)),
          pw.Text('Vétérinaire', style: const pw.TextStyle(fontSize: 9, color: _grey)),
          if (signature != null && !apercu)
            pw.Container(width: 150, height: 52, alignment: pw.Alignment.bottomLeft,
                child: pw.Image(pw.MemoryImage(signature), fit: pw.BoxFit.contain)),
        ]),
      ]),
    ],
  ));
  return doc.save();
}
