import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/material.dart';

const _teal = PdfColor.fromInt(0xFF0C5C6C);
const _grey = PdfColor.fromInt(0xFF888888);
const _dark = PdfColor.fromInt(0xFF1F2A2E);

// Termes par espèce
Map<String, String> _termes(String? espece) {
  switch ((espece ?? '').toLowerCase()) {
    case 'chien':  return {'jeune': 'chiot',    'vices': 'maladie de Carré, de Rubarth, parvovirose, dysplasie coxo-fémorale, atrophie rétinienne, ectopie testiculaire', 'pedigree': 'LOF ou pedigree FFP', 'sterilM': '12 mois', 'sterilF': '12 mois (ou après premières chaleurs)'};
    case 'chat':   return {'jeune': 'chaton',   'vices': 'leucopénie et péritonite infectieuses félines, FeLV, FIV', 'pedigree': 'LOOF', 'sterilM': '6 mois', 'sterilF': '6 mois (ou après premières chaleurs)'};
    case 'lapin':  return {'jeune': 'lapereau', 'vices': 'myxomatose, VHD', 'pedigree': 'N° registre', 'sterilM': '5 mois', 'sterilF': '5 mois'};
    case 'cheval': return {'jeune': 'poulain',  'vices': 'cornage chronique, emphysème pulmonaire, immobilité, stringhalt', 'pedigree': 'SIRE', 'sterilM': 'N/A', 'sterilF': 'N/A'};
    default:       return {'jeune': 'animal',   'vices': 'vices rédhibitoires définis par le code rural', 'pedigree': 'N° registre', 'sterilM': 'à convenir', 'sterilF': 'à convenir'};
  }
}

pw.TextStyle _body()  => pw.TextStyle(fontSize: 9, color: _dark, lineSpacing: 3);
pw.TextStyle _small() => pw.TextStyle(fontSize: 8, color: _grey);
pw.TextStyle _bold()  => pw.TextStyle(fontSize: 9, color: _dark, fontWeight: pw.FontWeight.bold);
pw.TextStyle _artTitle() => pw.TextStyle(fontSize: 9, color: _teal, fontWeight: pw.FontWeight.bold, letterSpacing: 0.5);

pw.Widget _signBlock(String role, String nom) => pw.Expanded(
  child: pw.Container(
    margin: const pw.EdgeInsets.only(top: 4),
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
      pw.Text(role.toUpperCase(), style: pw.TextStyle(fontSize: 8, color: _teal, fontWeight: pw.FontWeight.bold, letterSpacing: 0.5)),
      pw.SizedBox(height: 2),
      pw.Text(nom, style: pw.TextStyle(fontSize: 8, color: _dark)),
      pw.SizedBox(height: 40),
      pw.Divider(color: PdfColors.grey600, thickness: 0.5),
      pw.SizedBox(height: 4),
      pw.Text('« Lu et approuvé » · Date et signature', style: _small()),
      pw.SizedBox(height: 6),
      // Case à cocher "exemplaire reçu"
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
        pw.Container(width: 10, height: 10, decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey600, width: 0.5))),
        pw.SizedBox(width: 4),
        pw.Text('J\'ai reçu mon exemplaire original', style: pw.TextStyle(fontSize: 7, color: _grey)),
      ]),
    ]),
  ),
);

pw.Widget _copyBanner(String text) => pw.Container(
  margin: const pw.EdgeInsets.symmetric(vertical: 8),
  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 5),
  decoration: pw.BoxDecoration(
    border: pw.Border.all(color: _teal, width: 1),
    borderRadius: pw.BorderRadius.circular(5),
  ),
  child: pw.Center(
    child: pw.Text(text, style: pw.TextStyle(fontSize: 8, color: _teal, fontWeight: pw.FontWeight.bold)),
  ),
);

pw.Widget _art(String titre, String corps) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.SizedBox(height: 8),
    pw.Text(titre, style: _artTitle()),
    pw.SizedBox(height: 3),
    pw.Text(corps, style: _body()),
  ],
);

pw.Widget _field(String label, String value) => pw.Row(children: [
  pw.Text('$label : ', style: _bold()),
  pw.Text(value.isEmpty ? '…………………' : value, style: _body()),
]);

Future<void> genererContratPDF({
  required BuildContext context,
  required Map<String, dynamic> animal,
  required Map<String, dynamic> eleveur,
  String acquereurNom      = '',
  String acquereurAdresse  = '',
  String acquereurEmail    = '',
  String acquereurTel      = '',
  String prix              = '0',
  DateTime? dateCession,
  String notes             = '',
}) async {
  final pdf = pw.Document();
  final t = _termes(animal['espece'] as String?);
  final today = _fmt(DateTime.now());
  final dateVente = dateCession != null ? _fmt(dateCession) : '___/___/______';
  final isMasculin = ['male', 'mâle', 'm'].contains((animal['sexe'] as String? ?? '').toLowerCase());
  final sterilDelai = isMasculin ? (t['sterilM'] ?? '') : (t['sterilF'] ?? '');
  final prixDouble = double.tryParse(prix.replaceAll(',', '.')) ?? 0;
  final isGratuit = prixDouble == 0;
  final prixStr = isGratuit ? 'gratuit' : '${prixDouble.toStringAsFixed(0)} euros TTC';
  final dn = animal['date_naissance'] != null ? _fmt(DateTime.tryParse(animal['date_naissance'] as String) ?? DateTime.now()) : '';

  final eleveurNom    = (eleveur['name_elevage'] as String?) ?? '${eleveur['firstname'] ?? ''} ${eleveur['lastname'] ?? ''}'.trim();
  final eleveurAdresse= (eleveur['adress_elevage'] as String?) ?? (eleveur['adress'] as String?) ?? '';
  final eleveurSiret  = (eleveur['siret'] as String?) ?? '';
  final eleveurTel    = '${eleveur['code_iso_elevage'] ?? '+33'} ${eleveur['numero_elevage'] ?? ''}'.trim();

  // ── PAGE 1 : Contrat de vente ──────────────────────────────────────────────
  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
    build: (ctx) => [
      pw.Center(child: pw.Text('CONTRAT DE VENTE',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _dark, letterSpacing: 1.5))),
      pw.SizedBox(height: 16),

      // Parties
      pw.Text('ENTRE :', style: _bold()),
      pw.SizedBox(height: 2),
      pw.Text('$eleveurNom${eleveurAdresse.isNotEmpty ? ", demeurant $eleveurAdresse" : ""}${eleveurSiret.isNotEmpty ? " — SIRET $eleveurSiret" : ""}${eleveurTel.trim().isNotEmpty ? " — $eleveurTel" : ""}',
          style: _body()),
      pw.Text('Le Vendeur', style: pw.TextStyle(fontSize: 8, color: _grey, fontStyle: pw.FontStyle.italic)),
      pw.SizedBox(height: 8),
      pw.Center(child: pw.Text('ET :', style: pw.TextStyle(fontSize: 8, color: _grey, fontStyle: pw.FontStyle.italic))),
      pw.SizedBox(height: 4),
      pw.Text('$acquereurNom${acquereurAdresse.isNotEmpty ? ", demeurant $acquereurAdresse" : ""}${acquereurTel.isNotEmpty ? " — $acquereurTel" : ""}${acquereurEmail.isNotEmpty ? " — $acquereurEmail" : ""}',
          style: _body()),
      pw.Text('L\'Acheteur', style: pw.TextStyle(fontSize: 8, color: _grey, fontStyle: pw.FontStyle.italic)),

      pw.SizedBox(height: 10),
      pw.Divider(color: PdfColors.grey300, thickness: 0.5),

      // Articles
      _art('Article 1 – Objet de la vente',
        'Un ${t['jeune']} du nom : ${animal['nom'] ?? '…'}\n'
        'Race : ${animal['race'] ?? '…'}   Né le : $dn   Sexe : ${isMasculin ? 'M' : 'F'}\n'
        'Identification transpondeur n° : ${animal['identification'] ?? '…'}\n'
        '${t['pedigree']} n° : …'),

      _art('Article 2 – Prix de vente – Stérilisation',
        'Prix de vente : $prixStr\n'
        'Tranche 2 (si non-présentation certificat stérilisation sous $sterilDelai) : 2 000 euros\n'
        'Payé par : □ virement  □ espèces  □ autre'),

      _art('Article 3 – Conditions de la vente',
        'L\'Acheteur s\'engage à détenir l\'animal dans des conditions compatibles avec ses besoins biologiques et '
        'comportementaux. Il assume la responsabilité de son bien-être dès le premier jour. Si l\'Acheteur souhaite '
        'se séparer de l\'animal, il s\'engage à prévenir le Vendeur prioritairement.'),

      _art('Article 4 – Transfert de propriété',
        'Le Vendeur conserve la propriété de l\'animal jusqu\'à encaissement complet du prix. Le volet B de la '
        'carte I-CAD ne sera transmis qu\'après encaissement total.'),

      _art('Article 5 – Garanties',
        'Sont garantis les vices rédhibitoires (art. L.213-1 à L.213-9 du code rural) : ${t['vices']}.\n'
        'L\'Acheteur ne bénéficie pas de la garantie des vices cachés (art. 1641 c.civ.). Toute euthanasie ou '
        'intervention sans accord écrit du Vendeur décharge ce dernier de toute obligation de garantie.'),

      _art('Article 6 – Confidentialité',
        'Toutes les informations échangées sont confidentielles. Chaque Partie s\'engage à n\'en faire aucun '
        'usage autre que l\'exécution du présent contrat.'),

      _art('Article 7 – Droit de rétractation (non applicable)',
        'L\'Acheteur reconnaît qu\'un ${t['jeune']} est un être vivant unique et irremplaçable. Le droit de '
        'rétractation (art. L.221-18 C. conso.) ne s\'applique pas.'),

      _art('Article 8 – Règlement amiable',
        'En cas de litige, les Parties saisissent prioritairement le médiateur SNPPC (https://snpcc.com/) '
        'avant toute instance judiciaire.'),

      if (notes.isNotEmpty) ...[
        pw.SizedBox(height: 6),
        pw.Text('Conditions particulières :', style: _bold()),
        pw.Text(notes, style: _body()),
      ],

      pw.SizedBox(height: 10),
      pw.Text('Fait à …………………, le $dateVente', style: _body()),

      // Signatures
      pw.SizedBox(height: 8),
      _copyBanner('📄 Contrat établi en DEUX exemplaires originaux — un pour chaque partie'),
      pw.Row(children: [
        _signBlock('Le Vendeur', eleveurNom),
        pw.SizedBox(width: 16),
        _signBlock('L\'Acheteur', acquereurNom),
      ]),

      pw.SizedBox(height: 8),
      pw.Center(child: pw.Text('$today · PetsMatch', style: pw.TextStyle(fontSize: 7, color: _grey))),
    ],
  ));

  // ── PAGE 2 : Attestation de cession ───────────────────────────────────────
  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
    build: (ctx) => [
      pw.Center(child: pw.Text('ATTESTATION DE CESSION À TITRE ${isGratuit ? "GRATUIT" : "ONÉREUX"}',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _dark, letterSpacing: 1))),
      pw.SizedBox(height: 16),

      pw.Text('Entre les soussignés :', style: _bold()),
      pw.SizedBox(height: 4),
      pw.Text('$eleveurNom${eleveurAdresse.isNotEmpty ? ", $eleveurAdresse" : ""}${eleveurSiret.isNotEmpty ? " — SIRET $eleveurSiret" : ""}',
          style: _body()),
      pw.Text('ci-après dénommé « le cessionnaire »', style: pw.TextStyle(fontSize: 8, color: _grey, fontStyle: pw.FontStyle.italic)),
      pw.SizedBox(height: 4),
      pw.Text('$acquereurNom${acquereurAdresse.isNotEmpty ? ", demeurant $acquereurAdresse" : ""}',
          style: _body()),
      pw.Text('ci-après dénommé « le cédant »', style: pw.TextStyle(fontSize: 8, color: _grey, fontStyle: pw.FontStyle.italic)),

      pw.SizedBox(height: 10),
      pw.Text('Concernant l\'animal :', style: _bold()),
      pw.SizedBox(height: 4),
      _field('Nom', animal['nom'] as String? ?? ''),
      _field('Né le', '$dn   Sexe : ${isMasculin ? 'M' : 'F'}'),
      _field('Race', animal['race'] as String? ?? ''),
      _field('Identifié', animal['identification'] as String? ?? ''),

      pw.SizedBox(height: 10),
      pw.Text(
        'Le $dateVente, le cédant a manifesté sa volonté de céder l\'animal à $eleveurNom pour convenances personnelles.',
        style: _body()),

      _art('Art. 1 – Cession',
        'Les parties conviennent de la cession à titre ${isGratuit ? 'gratuit' : 'onéreux'} de l\'animal '
        '${isGratuit ? 'sans contrepartie financière' : 'pour la somme de $prixStr'}. '
        'L\'animal a été remis le $dateVente à ………h………\n'
        'Le cédant a été informé de la force obligatoire attachée aux présentes.'),

      _art('Art. 2 – Documents remis',
        'Carte I-CAD originale signée, carnet de vaccination/passeport, certificat vétérinaire avant cession'
        '${animal['race'] != null ? ", document généalogique (${t['pedigree']})" : ""}.'),

      pw.SizedBox(height: 10),
      pw.Text('Fait à …………………, le $dateVente', style: _body()),

      pw.SizedBox(height: 8),
      _copyBanner('📄 Attestation établie en DEUX exemplaires originaux — un pour chaque partie'),
      pw.Row(children: [
        _signBlock('Le cédant (Acheteur)', acquereurNom),
        pw.SizedBox(width: 16),
        _signBlock('Le cessionnaire (Vendeur)', eleveurNom),
      ]),

      pw.SizedBox(height: 8),
      pw.Center(child: pw.Text('$today · PetsMatch', style: pw.TextStyle(fontSize: 7, color: _grey))),
    ],
  ));

  await Printing.layoutPdf(onLayout: (format) => pdf.save());
}

String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
