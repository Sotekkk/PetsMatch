import 'dart:typed_data';
import 'package:flutter/material.dart' show Color;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'morpho_constants.dart';

// ── Export PDF d'un suivi morphologique — compte rendu imprimable/partageable
// (par email) pour un client qui n'utilise pas l'application. Service
// dédié, même patron que planning_pdf_service.dart/contrat_pdf.dart (pas
// de builder PDF générique partagé dans ce projet).

const _teal = PdfColor.fromInt(0xFF0C5C6C);
const _grey = PdfColor.fromInt(0xFF888888);
const _dark = PdfColor.fromInt(0xFF1F2A2E);

pw.ThemeData? _cachedTheme;
Future<pw.ThemeData> _pdfTheme() async {
  if (_cachedTheme != null) return _cachedTheme!;
  try {
    Future<pw.Font> load(String p) async => pw.Font.ttf(await rootBundle.load('assets/font/$p'));
    _cachedTheme = pw.ThemeData.withFont(
      base: await load('NotoSans-Regular.ttf'),
      bold: await load('NotoSans-Bold.ttf'),
      italic: await load('NotoSans-Italic.ttf'),
    );
  } catch (_) {
    try {
      _cachedTheme = pw.ThemeData.withFont(
        base: await PdfGoogleFonts.notoSansRegular(),
        bold: await PdfGoogleFonts.notoSansBold(),
        italic: await PdfGoogleFonts.notoSansItalic(),
      );
    } catch (_) {
      _cachedTheme = pw.ThemeData();
    }
  }
  return _cachedTheme!;
}

pw.TextStyle _body() => pw.TextStyle(fontSize: 9, color: _dark, lineSpacing: 2.5);
pw.TextStyle _small() => pw.TextStyle(fontSize: 7.5, color: _grey);
pw.TextStyle _bold() => pw.TextStyle(fontSize: 9, color: _dark, fontWeight: pw.FontWeight.bold);
pw.TextStyle _artTitle() => pw.TextStyle(fontSize: 10.5, color: _teal, fontWeight: pw.FontWeight.bold, letterSpacing: 0.3);

pw.Widget _line(String label, String? value) {
  if (value == null || value.trim().isEmpty) return pw.SizedBox();
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.RichText(text: pw.TextSpan(children: [
      pw.TextSpan(text: '$label : ', style: _bold()),
      pw.TextSpan(text: value.trim(), style: _body()),
    ])),
  );
}

Future<pw.MemoryImage?> _fetchNetworkImage(String url) async {
  try {
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode == 200) return pw.MemoryImage(resp.bodyBytes);
  } catch (_) {}
  return null;
}

Future<pw.MemoryImage?> _loadAssetImage(String assetPath) async {
  try {
    final data = await rootBundle.load(assetPath);
    return pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

/// Génère le compte rendu PDF d'un suivi morphologique. [animal]/[pro]
/// sont des Map simples (nom, espece/race pour l'animal ; nom, adresse,
/// tel, email pour le pro — déjà résolus par l'appelant).
Future<Uint8List> morphoSuiviPdfBytes({
  required Map<String, dynamic> suivi,
  required Map<String, dynamic> animal,
  required Map<String, dynamic> pro,
  required List<Map<String, dynamic>> photos,
  required List<Map<String, dynamic>> points,
  required List<Map<String, dynamic>> observations,
  required List<Map<String, dynamic>> mouvements,
}) async {
  final pdf = pw.Document(theme: await _pdfTheme());
  final espece = morphoSpeciesKey(animal['espece']?.toString()) ?? 'chien';
  final date = DateTime.tryParse(suivi['date']?.toString() ?? '');
  final source = suivi['source']?.toString() ?? 'proprietaire';

  // Photos de référence (4 vues + extra) — téléchargées depuis Supabase Storage.
  final photosByVue = <String, pw.MemoryImage>{};
  for (final p in photos) {
    final vue = p['vue']?.toString() ?? '';
    if (kVuesPhotos.any((v) => v.$1 == vue)) {
      final img = await _fetchNetworkImage(p['url'] as String);
      if (img != null) photosByVue[vue] = img;
    }
  }

  // Silhouette(s) avec points — image d'assets + pastilles superposées,
  // une page par vue effectivement pointée.
  final vuesAvecPoints = points.map((p) => p['vue']?.toString() ?? '').toSet().where((v) => v.isNotEmpty).toList();
  final silhouettes = <String, pw.MemoryImage>{};
  for (final v in vuesAvecPoints) {
    final asset = kMorphoSilhouetteAssets[espece]?[v];
    if (asset != null) {
      final img = await _loadAssetImage(asset.path);
      if (img != null) silhouettes[v] = img;
    }
  }

  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 40),
    footer: (ctx) => pw.Center(
      child: pw.Text('Compte rendu généré via PetsMatch le ${_fmt(DateTime.now())} — page ${ctx.pageNumber}/${ctx.pagesCount}', style: _small()),
    ),
    build: (ctx) => [
      pw.Center(child: pw.Text('SUIVI MORPHOLOGIQUE & BIEN-ÊTRE',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _teal, letterSpacing: 0.8))),
      pw.SizedBox(height: 4),
      pw.Center(child: pw.Text(labelTypeSuivi(suivi['type_suivi']?.toString()), style: _small())),
      pw.SizedBox(height: 18),

      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Animal', style: _artTitle()),
          pw.SizedBox(height: 4),
          _line('Nom', animal['nom'] as String?),
          _line('Espèce / race', [animal['espece'], animal['race']].where((e) => e != null && '$e'.trim().isNotEmpty).join(' — ')),
          if (suivi['poids'] != null) _line('Poids', '${suivi['poids']} kg'),
          if (suivi['taille'] != null) _line('Taille', '${suivi['taille']} cm'),
          if ((suivi['checkpoint_age'] as String?)?.isNotEmpty == true) _line('Étape', suivi['checkpoint_age']),
        ])),
        pw.SizedBox(width: 20),
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Suivi', style: _artTitle()),
          pw.SizedBox(height: 4),
          _line('Date', date != null ? _fmt(date) : null),
          _line('Professionnel', (suivi['professionnel_nom'] as String?) ?? pro['nom'] as String?),
          _line('Motif', suivi['motif'] as String?),
          _line('Source', kSourceLabels[source]),
        ])),
      ]),

      if ((suivi['commentaires'] as String?)?.isNotEmpty == true) ...[
        pw.SizedBox(height: 10),
        pw.Text('Commentaires généraux', style: _artTitle()),
        pw.SizedBox(height: 3),
        pw.Text(suivi['commentaires'], style: _body(), textAlign: pw.TextAlign.justify),
      ],

      if (photosByVue.isNotEmpty) ...[
        pw.SizedBox(height: 16),
        pw.Text('Photos de référence', style: _artTitle()),
        pw.SizedBox(height: 6),
        pw.Wrap(spacing: 10, runSpacing: 10, children: [
          for (final v in kVuesPhotos)
            if (photosByVue[v.$1] != null)
              pw.Column(children: [
                pw.Container(
                  width: 130, height: 130,
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
                  child: pw.Image(photosByVue[v.$1]!, fit: pw.BoxFit.cover),
                ),
                pw.SizedBox(height: 2),
                pw.Text(v.$2, style: _small()),
              ]),
        ]),
      ],

      if (silhouettes.isNotEmpty) ...[
        pw.SizedBox(height: 16),
        pw.Text('Silhouette — points relevés', style: _artTitle()),
        pw.SizedBox(height: 6),
        for (final v in vuesAvecPoints)
          if (silhouettes[v] != null) ...[
            pw.Container(
              width: 260,
              child: pw.AspectRatio(
                aspectRatio: (kMorphoSilhouetteAssets[espece]?[v]?.ratio) ?? 1.5,
                child: pw.Stack(children: [
                  pw.Positioned.fill(child: pw.Image(silhouettes[v]!, fit: pw.BoxFit.contain)),
                  for (final p in points.where((p) => p['vue'] == v))
                    pw.Positioned(
                      left: ((p['x_pct'] as num).toDouble() / 100) * 260 - 5,
                      top: ((p['y_pct'] as num).toDouble() / 100) * (260 / ((kMorphoSilhouetteAssets[espece]?[v]?.ratio) ?? 1.5)) - 5,
                      child: pw.Container(
                        width: 10, height: 10,
                        decoration: pw.BoxDecoration(
                          shape: pw.BoxShape.circle,
                          color: _pdfColor(colorCategoriePoint(p['categorie']?.toString() ?? 'autre')),
                          border: pw.Border.all(color: PdfColors.white, width: 1),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
            pw.SizedBox(height: 4),
          ],
        pw.Wrap(spacing: 10, runSpacing: 4, children: [
          for (final c in kCategoriesOsteo)
            if (points.any((p) => p['categorie'] == c.$1))
              pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
                pw.Container(width: 7, height: 7, decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, color: _pdfColor(c.$3))),
                pw.SizedBox(width: 3),
                pw.Text(c.$2, style: _small()),
              ]),
        ]),
        pw.SizedBox(height: 6),
        for (final p in points.where((p) => (p['note'] as String?)?.isNotEmpty == true))
          _line(labelCategoriePoint(p['categorie']?.toString() ?? 'autre'), p['note'] as String?),
      ],

      if (observations.isNotEmpty) ...[
        pw.SizedBox(height: 16),
        pw.Text('Observation statique', style: _artTitle()),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
          columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(1.4), 2: pw.FlexColumnWidth(2.5)},
          children: [
            for (final o in observations)
              pw.TableRow(children: [
                pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3),
                    child: pw.Text(kCategoriesObservationStatique.firstWhere((c) => c.$1 == o['categorie'], orElse: () => ('', o['categorie'].toString())).$2, style: _bold())),
                pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3),
                    child: pw.Text(labelsValeurObservation(o['categorie'].toString())[o['valeur']] ?? '', style: _body())),
                pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3),
                    child: pw.Text((o['commentaire'] as String?) ?? '', style: _body())),
              ]),
          ],
        ),
      ],

      if (mouvements.isNotEmpty) ...[
        pw.SizedBox(height: 16),
        pw.Text('Observation en mouvement', style: _artTitle()),
        pw.SizedBox(height: 4),
        for (final m in mouvements)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: _line(labelActivite(m['activite']?.toString()),
                [m['observation'], m['gene_observee'] == true ? 'Gêne observée' : null, m['commentaire']]
                    .where((e) => e != null && '$e'.trim().isNotEmpty).join(' — ')),
          ),
      ],

      pw.SizedBox(height: 20),
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
        child: pw.Text(kMorphoAvertissement, style: _small(), textAlign: pw.TextAlign.justify),
      ),
    ],
  ));

  return pdf.save();
}

String _fmt(DateTime d) => DateFormat('d MMMM yyyy', 'fr_FR').format(d);

/// kCategoriesOsteo utilise Color (Material) — converti en PdfColor pour
/// les widgets `pdf`.
PdfColor _pdfColor(Color c) => PdfColor.fromInt(c.toARGB32());

/// Ouvre le sélecteur natif de partage (email, messagerie…) avec le PDF —
/// même mécanisme que contrat_signature_page.dart / cession_sheet.dart.
Future<void> sharemorphoSuiviPdf(Uint8List bytes, {String filename = 'suivi_morphologique.pdf'}) =>
    Printing.sharePdf(bytes: bytes, filename: filename);

/// Ouvre l'aperçu d'impression natif.
Future<void> printMorphoSuiviPdf(Uint8List bytes) => Printing.layoutPdf(onLayout: (_) async => bytes);
