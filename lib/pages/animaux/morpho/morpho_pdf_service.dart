import 'dart:typed_data';
import 'package:flutter/material.dart' show Color;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/utils/signature_pro.dart';
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
  Map<String, dynamic> proprietaire = const {},
  required List<Map<String, dynamic>> photos,
  required List<Map<String, dynamic>> points,
  required List<Map<String, dynamic>> observations,
  required List<Map<String, dynamic>> mouvements,
  List<Map<String, dynamic>> exercices = const [],
}) async {
  final pdf = pw.Document(theme: await _pdfTheme());
  final espece = morphoSpeciesKey(animal['espece']?.toString()) ?? 'chien';
  final date = DateTime.tryParse(suivi['date']?.toString() ?? '');
  final source = suivi['source']?.toString() ?? 'proprietaire';
  // Signature du praticien : seulement sur ses propres séances (signatures_pro).
  final auteurUid = suivi['uid_auteur']?.toString();
  final signature = source == 'professionnel' && auteurUid != null && auteurUid == FirebaseAuth.instance.currentUser?.uid
      ? octetsSignature(await maSignaturePro()) : null;

  // Photos de référence (4 vues + extra) — téléchargées depuis Supabase Storage.
  final photosByVue = <String, pw.MemoryImage>{};
  final photosExtra = <pw.MemoryImage>[];
  for (final p in photos) {
    final vue = p['vue']?.toString() ?? '';
    if (kVuesPhotos.any((v) => v.$1 == vue)) {
      final img = await _fetchNetworkImage(p['url'] as String);
      if (img != null) photosByVue[vue] = img;
    } else if (vue == 'autre') {
      final img = await _fetchNetworkImage(p['url'] as String);
      if (img != null) photosExtra.add(img);
    }
  }
  // Illustrations des exercices (facultatives)
  final photosExercices = <int, pw.MemoryImage>{};
  for (final (i, e) in exercices.indexed) {
    final url = e['photo_url']?.toString();
    if (url != null && url.isNotEmpty) {
      final img = await _fetchNetworkImage(url);
      if (img != null) photosExercices[i] = img;
    }
  }
  // Bilan anatomique facultatif : désactivé → aucune silhouette dans le PDF.
  if (suivi['avec_anatomie'] == false) points = const [];

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
      // En-tête professionnel — n'apparaît que si le suivi a été réalisé par
      // un pro identifié (pro['nom'] non vide) : identifie clairement
      // l'émetteur du compte rendu (nom, profession, coordonnées), comme un
      // papier à en-tête de cabinet.
      if ((pro['nom'] as String?)?.trim().isNotEmpty == true) ...[
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF0F7F7), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(pro['nom'] as String, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _teal)),
            if ((pro['profession'] as String?)?.trim().isNotEmpty == true)
              pw.Text(pro['profession'] as String, style: _small()),
            pw.SizedBox(height: 3),
            pw.Wrap(spacing: 12, children: [
              if ((pro['adresse'] as String?)?.trim().isNotEmpty == true) pw.Text(pro['adresse'] as String, style: _small()),
              if ((pro['tel'] as String?)?.trim().isNotEmpty == true) pw.Text(pro['tel'] as String, style: _small()),
              if ((pro['email'] as String?)?.trim().isNotEmpty == true) pw.Text(pro['email'] as String, style: _small()),
            ]),
          ]),
        ),
        pw.SizedBox(height: 14),
      ],

      // Séance d'un professionnel : titre d'après le type de prestation
      // (Compte rendu ostéopathique…) ; suivi saisi par le propriétaire :
      // titre historique.
      pw.Center(child: pw.Text(
          (source == 'professionnel' ? titreCompteRendu(suivi['type_suivi']?.toString()) : 'Suivi morphologique & bien-être').toUpperCase(),
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _teal, letterSpacing: 0.8))),
      pw.SizedBox(height: 4),
      pw.Center(child: pw.Text(
          [
            if (_txt(suivi['intitule']) != null) _txt(suivi['intitule'])!,
            if (source != 'professionnel') labelTypeSuivi(suivi['type_suivi']?.toString()),
            if (suivi['statut'] == 'brouillon') 'Brouillon — document de travail',
          ].join('  ·  '),
          style: _small())),
      pw.SizedBox(height: 18),

      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Animal', style: _artTitle()),
          pw.SizedBox(height: 4),
          _line('Nom', animal['nom'] as String?),
          _line('Espèce / race', [animal['espece'], animal['race']].where((e) => e != null && '$e'.trim().isNotEmpty).join(' — ')),
          if ((animal['sexe']?.toString() ?? '').isNotEmpty) _line('Sexe', animal['sexe'].toString()),
          if (DateTime.tryParse(animal['date_naissance']?.toString() ?? '') != null)
            _line('Né(e) le', _fmt(DateTime.parse(animal['date_naissance'].toString()))),
          if ((animal['identification']?.toString() ?? '').isNotEmpty) _line('Identification', animal['identification'].toString()),
          if (suivi['poids'] != null) _line('Poids', '${suivi['poids']} kg'),
          if (suivi['taille'] != null) _line('Taille', '${suivi['taille']} cm'),
          if ((suivi['checkpoint_age'] as String?)?.isNotEmpty == true) _line('Étape', suivi['checkpoint_age']),
        ])),
        pw.SizedBox(width: 20),
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(source == 'professionnel' ? 'Séance' : 'Suivi', style: _artTitle()),
          pw.SizedBox(height: 4),
          _line('Date', date != null ? _fmt(date) : null),
          if (suivi['lieu'] == 'cabinet' || suivi['lieu'] == 'exterieur')
            _line('Lieu', suivi['lieu'] == 'cabinet' ? 'Cabinet' : 'Intervention extérieure'),
          // Profil pro identifié : le bloc « Réalisé par » fait foi.
          if ((pro['nom'] as String?)?.trim().isNotEmpty != true && (suivi['professionnel_nom'] as String?)?.isNotEmpty == true)
            _line('Professionnel', suivi['professionnel_nom'] as String?),
          if ((pro['nom'] as String?)?.trim().isNotEmpty == true)
            _line('Réalisé par', [pro['nom'], pro['profession']].where((e) => '${e ?? ''}'.trim().isNotEmpty).join(' — '))
          else
            _line('Source', kSourceLabels[source]),
          if (suivi['niveau_activite'] != null && suivi['niveau_activite'] != 'non_evalue')
            _line('Niveau d\'activité', kNiveauxActivite.firstWhere((n) => n.$1 == suivi['niveau_activite'], orElse: () => ('', '')).$2),
          if (_txt(suivi['activite_sportive']) != null) _line('Activité sportive', _txt(suivi['activite_sportive'])),
        ])),
      ]),

      if (proprietaire.values.any((v) => '${v ?? ''}'.trim().isNotEmpty)) ...[
        pw.SizedBox(height: 12),
        pw.Text('Propriétaire', style: _artTitle()),
        pw.SizedBox(height: 4),
        for (final e in [('Nom', 'nom'), ('Adresse', 'adresse'), ('Téléphone', 'tel'), ('E-mail', 'email'), ('Contact', 'contact')])
          if ('${proprietaire[e.$2] ?? ''}'.trim().isNotEmpty) _line(e.$1, proprietaire[e.$2].toString()),
      ],

      ..._sectionTexte('Motif de consultation', suivi['motif']),

      // Observations et bilan : texte + posture + mouvement (chacun facultatif)
      ..._sectionTexte('Observations et bilan', suivi['observations_bilan']),
      if (observations.isNotEmpty) ...[
        pw.SizedBox(height: 10),
        _titreAvec(_txt(suivi['observations_bilan']) == null ? 'Observations et bilan — posture' : 'Posture',
            pw.SizedBox(height: 2)),
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
        pw.SizedBox(height: 10),
        _titreAvec('En mouvement', pw.SizedBox(height: 2)),
        for (final m in mouvements)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: _line(labelActivite(m['activite']?.toString()),
                [m['observation'], m['gene_observee'] == true ? 'Gêne observée' : null, m['commentaire']]
                    .where((e) => e != null && '$e'.trim().isNotEmpty).join(' — ')),
          ),
      ],

      ..._sectionTexte('Intervention réalisée', suivi['intervention']),

      // Conseils et exercices — un bloc insécable par élément (jamais coupé)
      if (exercices.isNotEmpty) ...[
        pw.SizedBox(height: 14),
        for (final (i, e) in exercices.indexed)
          pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              if (i == 0) ...[pw.Text('Conseils et exercices', style: _artTitle()), pw.SizedBox(height: 6)],
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF7FAFA), border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                    borderRadius: pw.BorderRadius.circular(4)),
                child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('${i + 1}. ${e['nom'] ?? ''}', style: _bold()),
                    if (_txt(e['description']) != null) ...[pw.SizedBox(height: 2), pw.Text(_txt(e['description'])!, style: _body())],
                    pw.SizedBox(height: 2),
                    _line('Consignes', _txt(e['consignes'])),
                    _line('Fréquence', _txt(e['frequence'])),
                    _line('Durée', _txt(e['duree'])),
                    _line('Précautions', _txt(e['precautions'])),
                  ])),
                  if (photosExercices[i] != null) ...[
                    pw.SizedBox(width: 8),
                    pw.Container(width: 80, height: 80, child: pw.Image(photosExercices[i]!, fit: pw.BoxFit.cover)),
                  ],
                ]),
              ),
            ]),
          ),
        pw.Text('Ces recommandations ne constituent pas une prescription vétérinaire.', style: _small()),
      ],

      // Suivi recommandé
      if (_txt(suivi['suivi_recommande']) != null || suivi['orientation_veto'] == true
          || DateTime.tryParse(suivi['prochain_controle']?.toString() ?? '') != null) ...[
        ..._sectionTexte('Suivi recommandé', suivi['suivi_recommande'] ?? '',
            toujours: true),
        if (suivi['orientation_veto'] == true) _line('Orientation', 'consultation vétérinaire conseillée'),
        if (DateTime.tryParse(suivi['prochain_controle']?.toString() ?? '') != null)
          _line('Contrôle conseillé', _fmt(DateTime.parse(suivi['prochain_controle'].toString()))),
      ],

      if (photosByVue.isNotEmpty || photosExtra.isNotEmpty) ...[
        pw.SizedBox(height: 16),
        _titreAvec('Photos', pw.SizedBox(height: 4)),
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
          for (final img in photosExtra)
            pw.Container(width: 130, height: 130,
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
                child: pw.Image(img, fit: pw.BoxFit.cover)),
        ]),
      ],

      if (silhouettes.isNotEmpty) ...[
        pw.SizedBox(height: 16),
        // Un bloc INSÉCABLE par vue (Container non découpable) : si la
        // silhouette ne tient plus, elle passe sur la page suivante AVEC le
        // titre (avant : titre orphelin en bas de page). Silhouettes centrées.
        for (final (i, v) in vuesAvecPoints.where((v) => silhouettes[v] != null).indexed)
          pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(bottom: 12),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              if (i == 0) ...[
                pw.Text('Bilan anatomique — points relevés', style: _artTitle()),
                pw.SizedBox(height: 6),
              ],
              pw.Center(child: pw.Text(
                vuesDisponibles(espece).firstWhere((e) => e.$1 == v, orElse: () => (v, v)).$2,
                style: _small())),
              pw.SizedBox(height: 4),
              pw.Center(child: pw.Container(
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
                            color: _pdfColor(colorPointEffectif(p['categorie']?.toString() ?? 'autre', p['couleur']?.toString())),
                            border: pw.Border.all(color: PdfColors.white, width: 1),
                          ),
                        ),
                      ),
                  ]),
                ),
              )),
            ]),
          ),
        // Légende par point : couleur propre + libellé (ce qui a été
        // travaillé) — plus lisible que par catégorie quand deux points de
        // même catégorie ont une couleur ou un motif différents.
        for (final p in points.where((p) => (p['note'] as String?)?.isNotEmpty == true))
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Container(
                width: 8, height: 8, margin: const pw.EdgeInsets.only(top: 2, right: 5),
                decoration: pw.BoxDecoration(
                  shape: pw.BoxShape.circle,
                  color: _pdfColor(colorPointEffectif(p['categorie']?.toString() ?? 'autre', p['couleur']?.toString())),
                ),
              ),
              pw.Expanded(
                child: pw.RichText(text: pw.TextSpan(children: [
                  pw.TextSpan(text: '${p['note']}  ', style: _bold()),
                  pw.TextSpan(text: labelCategoriePoint(p['categorie']?.toString() ?? 'autre'), style: _small()),
                ])),
              ),
            ]),
          ),
      ],

      ..._sectionTexte('Notes complémentaires', suivi['commentaires']),

      // Auteur du compte rendu (identification + finalisation)
      if (source == 'professionnel' && ((pro['nom'] as String?)?.trim().isNotEmpty == true
          || _txt(suivi['professionnel_nom']) != null)) ...[
        pw.SizedBox(height: 16),
        pw.Text(
          [
            'Compte rendu rédigé par ${(pro['nom'] as String?)?.trim().isNotEmpty == true ? pro['nom'] : suivi['professionnel_nom']}',
            if (DateTime.tryParse(suivi['finalise_a']?.toString() ?? '') != null)
              'finalisé le ${_fmt(DateTime.parse(suivi['finalise_a'].toString()).toLocal())}',
            if ((suivi['version'] as num?) != null && (suivi['version'] as num) > 1) 'version ${suivi['version']}',
          ].join(' — '),
          style: _small(),
        ),
        // Bloc signature : nom du praticien, date du jour, « Signature : » puis la signature.
        pw.SizedBox(height: 16),
        pw.Align(alignment: pw.Alignment.centerRight, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('${(pro['nom'] as String?)?.trim().isNotEmpty == true ? pro['nom'] : suivi['professionnel_nom']}',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          pw.Text('Le ${_fmt(DateTime.now())}', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 3),
          pw.Text('Signature :', style: const pw.TextStyle(fontSize: 10)),
          if (signature != null)
            pw.Container(width: 160, height: 56, alignment: pw.Alignment.centerLeft,
                child: pw.Image(pw.MemoryImage(signature), fit: pw.BoxFit.contain))
          else
            pw.SizedBox(height: 40),
        ])),
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

String? _txt(dynamic v) {
  final t = v?.toString().trim() ?? '';
  return t.isEmpty ? null : t;
}

/// Titre + premier élément dans un bloc insécable : jamais de titre isolé
/// en bas de page.
pw.Widget _titreAvec(String titre, pw.Widget premier) => pw.Container(
      width: double.infinity,
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(titre, style: _artTitle()),
        pw.SizedBox(height: 3),
        premier,
      ]),
    );

/// Section de texte libre : rien si vide ; le titre reste avec le premier
/// paragraphe, la suite s'écoule sur les pages suivantes (jamais tronquée).
List<pw.Widget> _sectionTexte(String titre, dynamic texte, {bool toujours = false}) {
  final t = _txt(texte);
  if (t == null && !toujours) return const [];
  final paras = (t ?? '').split(RegExp(r'\n+')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
  // Premier paragraphe très long : il ne peut pas rester dans un bloc
  // insécable (plus haut qu'une page) — il s'écoule alors normalement.
  final premierCourt = paras.isNotEmpty && paras.first.length <= 700;
  return [
    pw.SizedBox(height: 12),
    _titreAvec(titre, premierCourt ? pw.Text(paras.first, style: _body(), textAlign: pw.TextAlign.justify) : pw.SizedBox()),
    for (final para in paras.skip(premierCourt ? 1 : 0))
      pw.Padding(padding: const pw.EdgeInsets.only(top: 3),
          child: pw.Paragraph(text: para, style: _body(), textAlign: pw.TextAlign.justify, margin: pw.EdgeInsets.zero)),
  ];
}

/// kCategoriesOsteo utilise Color (Material) — converti en PdfColor pour
/// les widgets `pdf`.
PdfColor _pdfColor(Color c) => PdfColor.fromInt(c.toARGB32());

/// Ouvre le sélecteur natif de partage (email, messagerie…) avec le PDF —
/// même mécanisme que contrat_signature_page.dart / cession_sheet.dart.
Future<void> sharemorphoSuiviPdf(Uint8List bytes, {String filename = 'suivi_morphologique.pdf'}) =>
    Printing.sharePdf(bytes: bytes, filename: filename);

/// Ouvre l'aperçu d'impression natif.
Future<void> printMorphoSuiviPdf(Uint8List bytes) => Printing.layoutPdf(onLayout: (_) async => bytes);
