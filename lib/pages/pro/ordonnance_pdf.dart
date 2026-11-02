// Ordonnance vétérinaire (contenu structuré, migration_ordonnances_v2.sql) :
// en-tête de la clinique (n° d'Ordre), numéro d'ordonnance, patient,
// propriétaire, médicaments (présentation, posologie, voie, durée, quantité,
// renouvellement, instructions, mentions), prescripteur, pages numérotées. Même police que les contrats
// (contrat_pdf.dart, NotoSans : accents).

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:PetsMatch/utils/majuscule.dart';

const _teal = PdfColor.fromInt(0xFF0C5C6C);
const _dark = PdfColor.fromInt(0xFF1E2025);
const _grey = PdfColor.fromInt(0xFF6F767B);
const _line = PdfColor.fromInt(0xFFDDE2DC);

class LigneOrdonnance {
  final String medicament;
  final String posologie;
  final int? dureeJours;
  /// Instructions particulières.
  final String? notes;
  final String? principeActif, presentation, voie, duree, quantite, renouvellement, mentions;
  const LigneOrdonnance({required this.medicament, required this.posologie, this.dureeJours, this.notes,
      this.principeActif, this.presentation, this.voie, this.duree, this.quantite, this.renouvellement, this.mentions});
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
  /// Coordonnées du propriétaire (adresse, téléphone, e-mail), sous son nom.
  List<String> proprietaireCoord = const [],
  required List<LigneOrdonnance> lignes,
  String? remarques,
  DateTime? date,
  /// Numéro attribué à la validation (absent : aperçu).
  String? numero,
  /// Version rectificative : numéro et date de l'ordonnance remplacée.
  bool rectificative = false,
  String? remplaceNumero,
  DateTime? remplaceDate,
  /// Aperçu avant validation : bandeau « Aperçu — non validée », sans signature.
  bool apercu = false,
  /// Signature manuscrite du prescripteur (PNG), apposée au-dessus du trait.
  Uint8List? signature,
}) async {
  final doc = pw.Document(theme: await _chargerTheme());
  final jour = date ?? DateTime.now();
  final titre = rectificative ? 'ORDONNANCE RECTIFICATIVE' : 'ORDONNANCE';
  final numeroTxt = (numero ?? '').isNotEmpty ? 'N° $numero' : (apercu ? 'N° attribué à la validation' : '');
  pw.Widget info(String label, String valeur) => valeur.trim().isEmpty
      ? pw.SizedBox()
      : pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.RichText(text: pw.TextSpan(children: [
            pw.TextSpan(text: '$label : ', style: const pw.TextStyle(fontSize: 9, color: _grey)),
            pw.TextSpan(text: majuscule(valeur), style: const pw.TextStyle(fontSize: 9, color: _dark)),
          ])),
        );

  pw.Widget enTete(pw.Context ctx) => ctx.pageNumber == 1
      ? pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(cliniqueNom, style: pw.TextStyle(fontSize: 15, color: _teal, fontWeight: pw.FontWeight.bold)),
              if (cliniqueAdresse.isNotEmpty) pw.Text(cliniqueAdresse, style: const pw.TextStyle(fontSize: 9, color: _dark)),
              if (cliniqueTel.isNotEmpty) pw.Text('Tél. $cliniqueTel', style: const pw.TextStyle(fontSize: 9, color: _dark)),
              if (numeroOrdre.isNotEmpty) pw.Text("N° d'inscription à l'Ordre : $numeroOrdre", style: const pw.TextStyle(fontSize: 9, color: _dark)),
            ])),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text(titre, style: pw.TextStyle(fontSize: 13, color: _teal, fontWeight: pw.FontWeight.bold, letterSpacing: 1)),
              pw.SizedBox(height: 2),
              pw.Text([numeroTxt, 'Le ${_date(jour)}'].where((x) => x.isNotEmpty).join(' · '),
                  style: const pw.TextStyle(fontSize: 9, color: _dark)),
            ]),
          ]),
          pw.SizedBox(height: 14),
          pw.Divider(color: _line, thickness: 1),
          pw.SizedBox(height: 10),
        ])
      : pw.Column(children: [
          pw.Row(children: [
            pw.Expanded(child: pw.Text(cliniqueNom, style: pw.TextStyle(fontSize: 11, color: _teal, fontWeight: pw.FontWeight.bold))),
            pw.Text('$titre${numeroTxt.isNotEmpty ? ' · $numeroTxt' : ''} · Le ${_date(jour)}',
                style: const pw.TextStyle(fontSize: 9, color: _dark)),
          ]),
          pw.Divider(color: _line, thickness: 1),
          pw.SizedBox(height: 8),
        ]);

  pw.Widget ligne(int i, LigneOrdonnance l) {
    final structuree = l.duree != null || l.voie != null || l.quantite != null;
    final carac = [
      if ((l.voie ?? '').trim().isNotEmpty) 'Voie : ${l.voie!.trim()}',
      if ((l.duree ?? '').trim().isNotEmpty) 'Durée : ${l.duree!.trim()}'
      else if (l.dureeJours != null) 'Pendant ${l.dureeJours} jour${l.dureeJours! > 1 ? 's' : ''}',
      if ((l.quantite ?? '').trim().isNotEmpty) 'Quantité à délivrer : ${l.quantite!.trim()}',
      if (structuree) 'Renouvellement : ${(l.renouvellement ?? '').trim().isEmpty ? 'non' : l.renouvellement!.trim()}',
    ].join(' · ');
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Container(
          width: 18, height: 18, alignment: pw.Alignment.center,
          decoration: const pw.BoxDecoration(color: _teal, shape: pw.BoxShape.circle),
          child: pw.Text('${i + 1}', style: pw.TextStyle(fontSize: 9, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text([l.medicament, l.presentation ?? ''].where((x) => x.trim().isNotEmpty).join(' — '),
              style: pw.TextStyle(fontSize: 11, color: _dark, fontWeight: pw.FontWeight.bold)),
          if ((l.principeActif ?? '').trim().isNotEmpty)
            pw.Text('Principe actif : ${l.principeActif!.trim()}', style: const pw.TextStyle(fontSize: 9.5, color: _grey)),
          if (l.posologie.trim().isNotEmpty)
            pw.Text(l.posologie, style: const pw.TextStyle(fontSize: 10, color: _dark)),
          if (carac.isNotEmpty) pw.Text(carac, style: const pw.TextStyle(fontSize: 9.5, color: _grey)),
          if ((l.notes ?? '').trim().isNotEmpty)
            pw.Text(l.notes!, style: pw.TextStyle(fontSize: 9, color: _grey, fontStyle: pw.FontStyle.italic)),
          if ((l.mentions ?? '').trim().isNotEmpty)
            pw.Text('Mentions : ${l.mentions!.trim()}', style: const pw.TextStyle(fontSize: 9.5, color: _dark)),
        ])),
      ]),
    );
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
    header: enTete,
    footer: (ctx) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(children: [
        pw.Expanded(child: pw.Text('Ordonnance établie via PetsMatch — à présenter en pharmacie / à conserver dans le carnet de santé.',
            style: pw.TextStyle(fontSize: 7.5, color: _grey, fontStyle: pw.FontStyle.italic))),
        pw.Text([if ((numero ?? '').isNotEmpty) 'N° $numero', 'Page ${ctx.pageNumber} / ${ctx.pagesCount}'].join(' · '),
            style: const pw.TextStyle(fontSize: 7.5, color: _grey)),
      ]),
    ),
    build: (_) => [
      if (apercu)
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 10),
          padding: const pw.EdgeInsets.symmetric(vertical: 5),
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFFFF8EA), borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Text('APERÇU — ordonnance non validée, sans valeur de prescription',
              style: pw.TextStyle(fontSize: 9, color: const PdfColor.fromInt(0xFF8A5A00), fontWeight: pw.FontWeight.bold)),
        ),
      if (rectificative)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text([
            "Annule et remplace l'ordonnance${(remplaceNumero ?? '').isNotEmpty ? ' n° $remplaceNumero' : ''}",
            if (remplaceDate != null) 'du ${_date(remplaceDate)}',
          ].join(' ') + '.', style: pw.TextStyle(fontSize: 9, color: _dark, fontStyle: pw.FontStyle.italic)),
        ),
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
            for (final l in proprietaireCoord) pw.Text(l, style: const pw.TextStyle(fontSize: 9, color: _dark)),
          ])),
        ]),
      ),
      pw.SizedBox(height: 18),

      // Prescription
      for (var i = 0; i < lignes.length; i++) ligne(i, lignes[i]),
      if ((remarques ?? '').trim().isNotEmpty) ...[
        pw.SizedBox(height: 6),
        pw.Text('Remarques', style: pw.TextStyle(fontSize: 9, color: _teal, fontWeight: pw.FontWeight.bold)),
        pw.Text(remarques!, style: const pw.TextStyle(fontSize: 9.5, color: _dark)),
      ],
      pw.SizedBox(height: 30),

      // Prescripteur
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (prescripteur.trim().isNotEmpty && prescripteur.trim().toLowerCase() != 'vétérinaire')
            pw.Text('Dr $prescripteur', style: pw.TextStyle(fontSize: 10, color: _dark, fontWeight: pw.FontWeight.bold)),
          pw.Text('Vétérinaire', style: const pw.TextStyle(fontSize: 9, color: _grey)),
          signature != null && !apercu
              ? pw.Container(width: 160, height: 56, alignment: pw.Alignment.bottomLeft,
                  child: pw.Image(pw.MemoryImage(signature), fit: pw.BoxFit.contain))
              : pw.SizedBox(height: 30),
          pw.Container(width: 160, height: 0.6, color: _grey),
          pw.Text('Signature', style: const pw.TextStyle(fontSize: 8, color: _grey)),
        ]),
      ]),
    ],
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
  /// Coordonnées du propriétaire (adresse, téléphone, e-mail), sous son nom.
  List<String> proprietaireCoord = const [],
  required String contenu,
  DateTime? date,
  /// Signature manuscrite du vétérinaire (PNG).
  Uint8List? signature,
  /// Autres métiers (éducateur…) : titre du document, « Dr » ou rien devant
  /// le nom, libellé de l'encadré animal. Miroir site : CompteRenduData.
  String titre = 'COMPTE RENDU',
  String prefixePraticien = 'Dr ',
  String libelleAnimal = 'Patient',
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
          pw.Text(titre, style: pw.TextStyle(fontSize: 13, color: _teal, fontWeight: pw.FontWeight.bold, letterSpacing: 1)),
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
            pw.Text(libelleAnimal, style: pw.TextStyle(fontSize: 9, color: _teal, fontWeight: pw.FontWeight.bold)),
            pw.Text(animalNom, style: pw.TextStyle(fontSize: 11, color: _dark, fontWeight: pw.FontWeight.bold)),
            for (final (l, v) in [('Espèce / race', animalEspeceRace), ('Sexe', animalSexe), ('Âge', animalAge),
                ('Identification', animalIdentification)])
              if (v.isNotEmpty) pw.RichText(text: pw.TextSpan(style: const pw.TextStyle(fontSize: 9, color: _dark), children: [
                pw.TextSpan(text: '$l : ', style: const pw.TextStyle(color: _grey)),
                pw.TextSpan(text: majuscule(v)),
              ])),
          ])),
          pw.SizedBox(width: 16),
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Propriétaire', style: pw.TextStyle(fontSize: 9, color: _teal, fontWeight: pw.FontWeight.bold)),
            pw.Text(proprietaire.isEmpty ? '—' : proprietaire, style: const pw.TextStyle(fontSize: 10, color: _dark)),
            for (final l in proprietaireCoord) pw.Text(l, style: const pw.TextStyle(fontSize: 9, color: _dark)),
          ])),
        ]),
      ),
      pw.SizedBox(height: 16),
      ..._paragraphesCr(contenu),
      // Bloc signature : nom du vétérinaire, date du jour, « Signature : » puis la signature.
      pw.SizedBox(height: 28),
      pw.Align(alignment: pw.Alignment.centerRight, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        if (nomPraticien.isNotEmpty)
          pw.Text('$prefixePraticien$nomPraticien', style: pw.TextStyle(fontSize: 10, color: _dark, fontWeight: pw.FontWeight.bold)),
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

/// Compte rendu de toilettage (fiche technique du RDV) : rubriques titrées,
/// bloc signature du salon. Miroir site : pdfCompteRenduToilettage
/// (website/src/lib/toilettage-pdf.ts).
Future<Uint8List> compteRenduToilettagePdfBytes({
  required String salon,
  String adresse = '',
  String tel = '',
  String email = '',
  required String animalNom,
  String especeRace = '',
  DateTime? date,
  required List<(String, String)> rubriques,
  Uint8List? signature,
}) async {
  final doc = pw.Document(theme: await _chargerTheme());
  final jour = date ?? DateTime.now();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
    build: (_) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(salon, style: pw.TextStyle(fontSize: 15, color: _teal, fontWeight: pw.FontWeight.bold)),
          if (adresse.isNotEmpty) pw.Text(adresse, style: const pw.TextStyle(fontSize: 9, color: _dark)),
          if (tel.isNotEmpty) pw.Text('Tél. $tel', style: const pw.TextStyle(fontSize: 9, color: _dark)),
          if (email.isNotEmpty) pw.Text(email, style: const pw.TextStyle(fontSize: 9, color: _dark)),
        ])),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('COMPTE RENDU DE TOILETTAGE', style: pw.TextStyle(fontSize: 12, color: _teal, fontWeight: pw.FontWeight.bold)),
          pw.Text('Le ${_date(jour)}', style: const pw.TextStyle(fontSize: 9, color: _dark)),
        ]),
      ]),
      pw.SizedBox(height: 12),
      pw.Divider(color: _line, thickness: 1),
      pw.SizedBox(height: 8),
      pw.Text(animalNom, style: pw.TextStyle(fontSize: 12, color: _dark, fontWeight: pw.FontWeight.bold)),
      if (especeRace.isNotEmpty) pw.Text(majuscule(especeRace), style: const pw.TextStyle(fontSize: 10, color: _dark)),
      pw.SizedBox(height: 14),
      for (final (titre, texte) in rubriques)
        if (texte.trim().isNotEmpty) ...[
          pw.Text(titre, style: pw.TextStyle(fontSize: 10.5, color: _teal, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          pw.Text(texte.trim(), style: const pw.TextStyle(fontSize: 10.5, color: _dark, lineSpacing: 2)),
          pw.SizedBox(height: 10),
        ],
      // Bloc signature : salon, date du jour, « Signature : » puis la signature.
      pw.SizedBox(height: 20),
      pw.Align(alignment: pw.Alignment.centerRight, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(salon, style: pw.TextStyle(fontSize: 10, color: _dark, fontWeight: pw.FontWeight.bold)),
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
