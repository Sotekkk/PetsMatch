import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

const _teal = PdfColor.fromInt(0xFF0C5C6C);
const _grey = PdfColor.fromInt(0xFF888888);
const _dark = PdfColor.fromInt(0xFF1F2A2E);

// ─── Helpers ──────────────────────────────────────────────────────────────────

pw.MemoryImage? _sigImage(String? dataUrl) {
  if (dataUrl == null || dataUrl.isEmpty) return null;
  try {
    final b64 = dataUrl.contains(',') ? dataUrl.substring(dataUrl.indexOf(',') + 1) : dataUrl;
    return pw.MemoryImage(base64Decode(b64));
  } catch (_) {
    return null;
  }
}

/// Termes juridiques par espèce (aligné sur website/src/lib/contrat-vente.ts).
/// Termes du contrat par espèce. `pedigree` vide = pas de livre généalogique
/// officiel → le n° d'identification devient obligatoire dans le contrat.
/// ⚠️ Garder identique à `animalTerms()` du site (website/src/lib/contrat-vente.ts).
Map<String, String> _termes(String? espece) {
  switch ((espece ?? '').toLowerCase()) {
    case 'chien':
      return {
        'jeune': 'chiot', 'pedigree': 'LOF ou n° de pedigree (autre club)',
        'vices': 'maladie de Carré, hépatite contagieuse (maladie de Rubarth), parvovirose, '
            'dysplasie coxo-fémorale, atrophie rétinienne, ectopie testiculaire (uniquement si cédé âgé de plus de six mois)',
        'sterilM': '12 mois à compter de la date de naissance pour un mâle',
        'sterilF': '12 mois à compter de la date de naissance pour une femelle (ou après ses premières chaleurs)',
      };
    case 'chat':
      return {
        'jeune': 'chaton', 'pedigree': 'LOOF n°',
        'vices': 'leucopénie infectieuse (typhus), péritonite infectieuse féline (PIF), '
            'virus leucémogène félin (FeLV), virus de l\'immunodéficience féline (FIV)',
        'sterilM': '6 mois à compter de la date de naissance',
        'sterilF': '6 mois à compter de la date de naissance (ou après les premières chaleurs)',
      };
    case 'lapin':
      return {'jeune': 'lapereau', 'pedigree': '',
        'vices': 'myxomatose, maladie hémorragique virale (VHD)', 'sterilM': '5 mois', 'sterilF': '5 mois'};
    case 'cheval':
      return {'jeune': 'poulain', 'pedigree': '',
        'vices': 'cornage chronique, emphysème pulmonaire, immobilité, tic proprement dit avec ou sans usure des dents, boiterie intermittente (stringhalt), uvéite isolée',
        'sterilM': 'à convenir', 'sterilF': 'à convenir'};
    case 'ovin':
      return {'jeune': 'agneau', 'pedigree': '', 'vices': 'clavelée, piétin chronique', 'sterilM': 'à convenir', 'sterilF': 'à convenir'};
    case 'caprin':
      return {'jeune': 'chevreau', 'pedigree': '', 'vices': 'arthrite encéphalite caprine (CAEV), brucellose', 'sterilM': 'à convenir', 'sterilF': 'à convenir'};
    default:
      return {'jeune': 'animal', 'pedigree': '',
        'vices': 'vices rédhibitoires définis aux articles L.213-1 et suivants du code rural', 'sterilM': 'à convenir', 'sterilF': 'à convenir'};
  }
}

String _fmt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// « Nom (puce XXX) » — puce optionnelle.
String? _avecPuce(dynamic nom, dynamic puce) {
  final n = '${nom ?? ''}'.trim();
  if (n.isEmpty) return null;
  final p = '${puce ?? ''}'.trim();
  return p.isEmpty ? n : '$n (puce $p)';
}

pw.TextStyle _body()  => pw.TextStyle(fontSize: 9, color: _dark, lineSpacing: 2.5);
pw.TextStyle _small() => pw.TextStyle(fontSize: 7.5, color: _grey);
pw.TextStyle _bold()  => pw.TextStyle(fontSize: 9, color: _dark, fontWeight: pw.FontWeight.bold);
pw.TextStyle _artTitle() => pw.TextStyle(fontSize: 10, color: _teal, fontWeight: pw.FontWeight.bold, letterSpacing: 0.3);

/// « Label : » (gras) + valeur, une info par ligne.
/// Ligne **omise** si la valeur est vide (pas de tiret ni de blanc à remplir).
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

pw.Widget _para(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 4),
  child: pw.Text(text, style: _body(), textAlign: pw.TextAlign.justify),
);

/// Un article : titre + corps, rendu uniquement si non désactivé.
pw.Widget? _art(String key, Set<String> off, String titre, List<pw.Widget> corps) {
  if (off.contains(key)) return null;
  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    pw.SizedBox(height: 9),
    pw.Text(titre, style: _artTitle()),
    pw.SizedBox(height: 3),
    ...corps,
  ]);
}

/// Case à cocher dessinée (pas de police spéciale) : carré bordé, rempli en teal
/// quand coché. + libellé.
pw.Widget _checkbox(bool checked, String label) => pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.center,
  children: [
    pw.Container(
      width: 8, height: 8,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _dark, width: 0.8),
        color: checked ? _teal : null,
      ),
    ),
    pw.SizedBox(width: 4),
    pw.Text(label, style: pw.TextStyle(fontSize: 8, color: _dark)),
  ],
);

pw.Widget _signBlock(String role, String nom, {String? signature}) {
  final img = _sigImage(signature);
  return pw.Expanded(
    child: pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4, right: 8),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('$role : $nom', style: pw.TextStyle(fontSize: 8, color: _dark, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        _checkbox(img != null, 'Lu et approuvé'),
        img != null
            ? pw.Container(height: 46, alignment: pw.Alignment.centerLeft,
                child: pw.Image(img, height: 44, fit: pw.BoxFit.contain))
            : pw.SizedBox(height: 46),
        pw.Container(width: 150, height: 0.6, color: PdfColors.grey500),
        pw.SizedBox(height: 2),
        pw.Text('Date et signature', style: _small()),
      ]),
    ),
  );
}

pw.Widget _copyBanner(String text) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 6),
  child: pw.Text(text, style: pw.TextStyle(fontSize: 8, color: _grey, fontStyle: pw.FontStyle.italic)),
);

// ─── Police PDF ───────────────────────────────────────────────────────────────
// Les polices base-14 du paquet `pdf` ne rendent pas correctement tirets longs,
// guillemets « », apostrophes typographiques… (carrés « tofu »). On embarque
// Noto Sans (via `printing`, mis en cache après le 1er téléchargement).

pw.ThemeData? _cachedTheme;
Future<pw.ThemeData> _pdfTheme() async {
  if (_cachedTheme != null) return _cachedTheme!;
  try {
    Future<pw.Font> load(String p) async =>
        pw.Font.ttf(await rootBundle.load('assets/font/$p'));
    _cachedTheme = pw.ThemeData.withFont(
      base:   await load('NotoSans-Regular.ttf'),
      bold:   await load('NotoSans-Bold.ttf'),
      italic: await load('NotoSans-Italic.ttf'),
    );
  } catch (_) {
    try {
      _cachedTheme = pw.ThemeData.withFont(
        base:   await PdfGoogleFonts.notoSansRegular(),
        bold:   await PdfGoogleFonts.notoSansBold(),
        italic: await PdfGoogleFonts.notoSansItalic(),
      );
    } catch (_) {
      _cachedTheme = pw.ThemeData();
    }
  }
  return _cachedTheme!;
}

// ─── Données communes ─────────────────────────────────────────────────────────

class _Parties {
  final String eleveurNom, eleveurAdresse, eleveurSiret, eleveurTel, eleveurEmail;
  _Parties(this.eleveurNom, this.eleveurAdresse, this.eleveurSiret, this.eleveurTel, this.eleveurEmail);
}

_Parties _parties(Map<String, dynamic> eleveur) {
  final nom = (eleveur['name_elevage'] as String?)?.trim().isNotEmpty == true
      ? eleveur['name_elevage'] as String
      : '${eleveur['firstname'] ?? ''} ${eleveur['lastname'] ?? ''}'.trim();
  final adresse = (eleveur['adress_elevage'] as String?) ?? (eleveur['adress'] as String?) ?? '';
  final siret = (eleveur['siret'] as String?) ?? '';
  var tel = '${eleveur['code_iso_elevage'] ?? '+33'} ${eleveur['numero_elevage'] ?? ''}'.trim();
  tel = tel.replaceAll(RegExp(r'^\+33\s*$'), '');
  final email = (eleveur['email'] as String?) ?? (eleveur['email_contact'] as String?) ?? '';
  return _Parties(nom, adresse, siret, tel, email);
}

// ─── CONTRAT DE VENTE ─────────────────────────────────────────────────────────

Future<void> genererContratPDF({
  required BuildContext context,
  required Map<String, dynamic> animal,
  required Map<String, dynamic> eleveur,
  String acquereurNom = '', String acquereurAdresse = '', String acquereurEmail = '',
  String acquereurTel = '', String prix = '0', DateTime? dateCession, String notes = '',
}) async {
  final doc = await _contratVenteDoc(animal: animal, eleveur: eleveur, acquereurNom: acquereurNom,
      acquereurAdresse: acquereurAdresse, acquereurEmail: acquereurEmail, acquereurTel: acquereurTel,
      prix: prix, dateCession: dateCession, notes: notes);
  await Printing.layoutPdf(onLayout: (_) => doc.save());
}

Future<Uint8List> contratVentePdfBytes({
  required Map<String, dynamic> animal,
  required Map<String, dynamic> eleveur,
  String acquereurNom = '', String acquereurAdresse = '', String acquereurEmail = '',
  String acquereurTel = '', String prix = '0', DateTime? dateCession, String notes = '',
  String? sigVendeur, String? sigAcheteur,
  String civiliteAcheteur = '', String prenomAcheteur = '', String nomAcheteur = '',
  String cpAcheteur = '', String villeAcheteur = '', String villeNaissance = '',
  String acompte = '', String tranche1 = '', String tva = '', String tvaTaux = '', String modePaiement = '',
  String montantTranche2 = '2 000',
  String mediateurNom = 'Yves Legeay', String mediateurUrl = 'https://snpcc.com/',
  String? sterilisationClause, String villeSignature = '',
  Set<String> clausesOff = const {},
}) async => (await _contratVenteDoc(
      animal: animal, eleveur: eleveur, acquereurNom: acquereurNom, acquereurAdresse: acquereurAdresse,
      acquereurEmail: acquereurEmail, acquereurTel: acquereurTel, prix: prix, dateCession: dateCession,
      notes: notes, sigVendeur: sigVendeur, sigAcheteur: sigAcheteur,
      civiliteAcheteur: civiliteAcheteur, prenomAcheteur: prenomAcheteur, nomAcheteur: nomAcheteur,
      cpAcheteur: cpAcheteur, villeAcheteur: villeAcheteur, villeNaissance: villeNaissance,
      acompte: acompte, tranche1: tranche1, tva: tva, tvaTaux: tvaTaux, modePaiement: modePaiement,
      mediateurNom: mediateurNom, mediateurUrl: mediateurUrl,
      montantTranche2: montantTranche2, sterilisationClause: sterilisationClause,
      villeSignature: villeSignature, clausesOff: clausesOff,
    )).save();

Future<pw.Document> _contratVenteDoc({
  required Map<String, dynamic> animal,
  required Map<String, dynamic> eleveur,
  String acquereurNom = '', String acquereurAdresse = '', String acquereurEmail = '',
  String acquereurTel = '', String prix = '0', DateTime? dateCession, String notes = '',
  String? sigVendeur, String? sigAcheteur,
  String civiliteAcheteur = '', String prenomAcheteur = '', String nomAcheteur = '',
  String cpAcheteur = '', String villeAcheteur = '', String villeNaissance = '',
  String acompte = '', String tranche1 = '', String tva = '', String tvaTaux = '', String modePaiement = '',
  String montantTranche2 = '2 000',
  String mediateurNom = 'Yves Legeay', String mediateurUrl = 'https://snpcc.com/',
  String? sterilisationClause, String villeSignature = '',
  Set<String> clausesOff = const {},
}) async {
  final pdf = pw.Document(theme: await _pdfTheme());
  final t = _termes(animal['espece'] as String?);
  final p = _parties(eleveur);
  final today = _fmt(DateTime.now());
  final dateVente = dateCession != null ? _fmt(dateCession) : today;
  final isMasculin = ['male', 'mâle', 'm'].contains((animal['sexe'] as String? ?? '').toLowerCase());
  final prixDouble = double.tryParse(prix.replaceAll(',', '.').replaceAll(' ', '')) ?? 0;
  final isGratuit = prixDouble == 0;
  final dn = animal['date_naissance'] != null
      ? _fmt(DateTime.tryParse(animal['date_naissance'] as String) ?? DateTime.now()) : '';
  final tranche1Str = tranche1.trim().isNotEmpty
      ? tranche1
      : (isGratuit ? 'néant (cession gratuite)' : prixDouble.toStringAsFixed(0));
  final acheteurNomComplet = [civiliteAcheteur, prenomAcheteur, nomAcheteur]
      .where((s) => s.trim().isNotEmpty).join(' ').trim();
  final acheteurLabel = acheteurNomComplet.isNotEmpty ? acheteurNomComplet : acquereurNom;
  final steril = sterilisationClause ??
      (isMasculin ? t['sterilM'] : t['sterilF']);

  final vices = t['vices'];
  final jeune = t['jeune'];

  final articles = <pw.Widget?>[
    // ── Article 1 ──
    pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.SizedBox(height: 9),
      pw.Text('Article 1 - Objet de la vente', style: _artTitle()),
      pw.SizedBox(height: 3),
      _line('Un $jeune du nom', animal['nom'] as String?),
      _line('De race', animal['race'] as String?),
      _line('Né le', dn.isEmpty ? null : '$dn${villeNaissance.trim().isNotEmpty ? ' à ${villeNaissance.trim()}' : ''}'),
      _line('Sexe', isMasculin ? 'Mâle' : 'Femelle'),
      _line('Couleur / robe', animal['couleur'] as String?),
      _line(
        (t['pedigree'] ?? '').isEmpty
            ? 'Numéro d\'identification (obligatoire)'
            : 'Identification (transpondeur / puce) n°',
        animal['identification'] as String?),
      if ((t['pedigree'] ?? '').isNotEmpty)
        _line('${t['pedigree']}',
            (animal['pedigree_lof'] as String?)?.trim().isNotEmpty == true
                ? animal['pedigree_lof'] as String?
                : animal['pedigree_numero'] as String?),
      _line('Nom du père', _avecPuce(animal['nom_pere'], animal['puce_pere'])),
      _line('Nom de la mère', _avecPuce(animal['nom_mere'], animal['puce_mere'])),
      pw.SizedBox(height: 3),
      _para('L\'animal est cédé avec : un certificat vétérinaire de bonne santé, un carnet de santé '
          'ou passeport, un certificat provisoire d\'identification, un certificat d\'engagement et de '
          'connaissance signé au moins 7 jours avant le départ, et un document d\'information sur '
          'l\'accueil d\'un $jeune.'),
    ]),
    // ── Article 2 ──
    pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.SizedBox(height: 9),
      pw.Text('Article 2 - Prix de vente${steril != null ? ' - Stérilisation' : ''}', style: _artTitle()),
      pw.SizedBox(height: 3),
      _line('Acompte déjà versé', acompte.trim().isEmpty ? null : '${acompte.trim()} €'),
      _line('Tranche 1 (payable au départ effectif de l\'animal)',
          isGratuit && tranche1.trim().isEmpty ? 'néant (cession gratuite)' : '$tranche1Str €'),
      _line('Dont TVA${tvaTaux.trim().isEmpty ? '' : ' (${tvaTaux.trim()} %)'}',
          tva.trim().isEmpty ? null : '${tva.trim()} €'),
      _line('Payé par', modePaiement.trim().isEmpty ? null : modePaiement.trim()),
      if (steril != null) ...[
        pw.SizedBox(height: 3),
        _para('Tranche 2 (payable au terme du délai de stérilisation ($steril) en cas de '
            'non-présentation du certificat de stérilisation établi par un vétérinaire agréé) : '
            '${montantTranche2.trim().isEmpty ? '2 000' : montantTranche2.trim()} euros.'),
        _para('La Tranche 2 n\'est pas due par l\'Acheteur si la stérilisation a été effectuée par le '
            'Vendeur avant la livraison effective de l\'animal.'),
      ],
    ]),
    // ── Articles 3 à 8 (désactivables) ──
    _art('art3', clausesOff, 'Article 3 - Les conditions de la vente', [
      _para('L\'Acheteur s\'engage à détenir l\'animal dans des conditions compatibles avec ses besoins '
          'biologiques et comportementaux et à lui donner des soins attentifs conformément aux obligations '
          'légales (art. D.214-32-1 du code rural).'),
      _para('Responsabilité de l\'Acheteur : en adoptant un animal, l\'Acheteur assume la responsabilité '
          'de son bien-être, ce qui inclut les soins quotidiens et les soins vétérinaires nécessaires. '
          'Si l\'Acheteur souhaite se séparer de l\'animal, il s\'engage à prévenir le Vendeur '
          'prioritairement et dans les plus brefs délais afin que celui-ci l\'aide à trouver une nouvelle famille.'),
      _para('Obligations financières : dès le premier jour, l\'Acheteur est responsable financièrement de '
          'l\'animal (entretien, nourriture, soins vétérinaires et autres besoins).'),
      _para('Proposition d\'une assurance santé animale : le Vendeur peut proposer une mutuelle partenaire '
          'pour aider à couvrir les frais vétérinaires. Le Vendeur n\'est toutefois pas responsable des '
          'frais médicaux de l\'animal après la vente ; la prise en charge médicale relève entièrement de '
          'la responsabilité de l\'Acheteur à compter de la vente.'),
    ]),
    _art('art4', clausesOff, 'Article 4 - Le transfert de propriété', [
      _para('L\'Acheteur déclare avoir été informé et accepter que, quel que soit le mode de règlement, '
          'le Vendeur conserve la propriété de l\'animal jusqu\'à encaissement de la totalité de la somme '
          'convenue, et que cet encaissement conditionne le transfert de propriété. L\'Acheteur convient '
          'qu\'en compensation de la jouissance immédiate de l\'animal il assumera, pendant cette période, '
          'l\'entière responsabilité de tous les risques de perte, vol, accident, décès ou maladie, quelle '
          'qu\'en soit la cause, y compris cas fortuit ou force majeure, à l\'exception de ceux mentionnés '
          'au paragraphe garantie. Le « volet B » de la carte d\'identification I-CAD ne sera adressé au '
          'fichier national qu\'après encaissement de la totalité du prix.'),
    ]),
    _art('art5', clausesOff, 'Article 5 - Les garanties', [
      _para('L\'Acheteur admet avoir été informé de ce que ne sont garantis que les maladies et défauts '
          'définis comme vices rédhibitoires par les articles L.213-1 à L.213-9 du code rural ($vices), '
          'qui surviendraient dans les conditions, modalités et délais déterminés par les articles R.213-3 '
          'à R.213-7 du code rural. Cette garantie donne droit, dans les conditions de ce code, à une '
          'réduction de prix si l\'animal est conservé par l\'Acheteur, ou à un remboursement intégral '
          'contre restitution de l\'animal.'),
      _para('L\'Acheteur ne bénéficie pas de la garantie des vices cachés des articles 1641 et suivants du '
          'code civil ; la vente est assortie de la seule garantie légale des vices rédhibitoires.'),
      _para('L\'Acheteur, ayant le jour de la livraison examiné les caractéristiques de l\'animal, atteste '
          'que celles-ci ne soulèvent de sa part ni réserve ni objection. La vente ne peut être assortie '
          'd\'aucune garantie de confirmation ultérieure, de réussite en élevage, concours, dressage, '
          'expositions ou de conformité au standard.'),
      _para('Préalablement à toute action au titre des garanties, le vétérinaire de l\'Acheteur devra se '
          'rapprocher de celui du Vendeur et lui communiquer par écrit ses constats et diagnostic. Dans '
          'l\'attente de la réponse du Vendeur, l\'animal sera autant que possible conservé en vie et dans '
          'un état permettant les contre-expertises. Toute euthanasie ou intervention non motivée par un '
          'pronostic vital effectuée sans accord écrit du Vendeur décharge ce dernier de toute obligation '
          'de garantie. Le Vendeur ne prend en charge aucun frais vétérinaire qui ne serait du fait de son '
          'propre vétérinaire, sauf accord exprès et écrit préalable.'),
    ]),
    _art('art6', clausesOff, 'Article 6 - Clause de confidentialité', [
      _para('Toutes les informations, de quelque nature que ce soit, que l\'une des Parties a pu recueillir '
          'sur l\'autre, par écrit ou oralement, sont confidentielles. Chaque Partie s\'engage à ne pas les '
          'divulguer ni les communiquer à quiconque, à prendre toute disposition pour en préserver la '
          'confidentialité, et à n\'en faire aucun usage dans un but autre que l\'exécution du présent contrat.'),
    ]),
    _art('art7', clausesOff, 'Article 7 - Droit de rétractation - Non applicable', [
      _para('Lorsque la vente ou la réservation s\'est réalisée à distance, l\'Acheteur reconnaît que '
          'l\'animal entre dans la catégorie visée par l\'article L.221-28 3° du code de la consommation '
          '(« biens confectionnés selon les spécifications du consommateur ou nettement personnalisés »). '
          'Un $jeune est un être vivant unique et irremplaçable, destiné à recevoir l\'affection de son '
          'maître, sans vocation économique. L\'Acheteur reconnaît en conséquence qu\'il ne pourra invoquer '
          'le droit de rétractation issu de l\'article L.221-18 du code de la consommation.'),
    ]),
    _art('art8', clausesOff, 'Article 8 - Clause de règlement amiable préalable obligatoire', [
      _para('En cas de litige ou réclamation relatif au présent contrat (formation, validité, '
          'interprétation, exécution, violation), les Parties tenteront d\'abord de le résoudre à l\'amiable '
          'préalablement à toute instance judiciaire, notamment par la saisine du médiateur '
          '${mediateurNom.trim().isEmpty ? 'de la consommation compétent' : mediateurNom.trim()}'
          '${mediateurUrl.trim().isEmpty ? '' : ' (${mediateurUrl.trim()})'}.'),
    ]),
    if (notes.trim().isNotEmpty)
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(height: 9),
        pw.Text('Conditions particulières', style: _artTitle()),
        pw.SizedBox(height: 3),
        _para(notes.trim()),
      ]),
  ].whereType<pw.Widget>().toList();

  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 40),
    build: (ctx) => [
      pw.Center(child: pw.Text('CONTRAT DE VENTE',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _dark, letterSpacing: 1.5))),
      pw.SizedBox(height: 16),

      pw.Text('ENTRE :', style: _bold()),
      pw.SizedBox(height: 3),
      _line('Vendeur', p.eleveurNom),
      _line('Demeurant à', p.eleveurAdresse),
      _line('Téléphone', p.eleveurTel),
      _line('SIRET', p.eleveurSiret),
      _line('Email', p.eleveurEmail),
      pw.Text('Le Vendeur', style: pw.TextStyle(fontSize: 8, color: _grey, fontStyle: pw.FontStyle.italic)),
      pw.SizedBox(height: 10),

      pw.Text('ET :', style: _bold()),
      pw.SizedBox(height: 3),
      _line('Acheteur', acheteurLabel.isEmpty ? null : acheteurLabel),
      _line('Demeurant à', acquereurAdresse),
      _line('Ville, code postal', [cpAcheteur, villeAcheteur].where((s) => s.trim().isNotEmpty).join(' ')),
      _line('Téléphone', acquereurTel),
      _line('Email', acquereurEmail),
      pw.Text('L\'Acheteur', style: pw.TextStyle(fontSize: 8, color: _grey, fontStyle: pw.FontStyle.italic)),

      pw.SizedBox(height: 8),
      pw.Text('Désignés séparément comme la « Partie » et collectivement comme les « Parties ».',
          style: _body()),
      pw.SizedBox(height: 4),
      pw.Text('Il a été convenu ce qui suit :', style: pw.TextStyle(fontSize: 9, color: _dark, fontStyle: pw.FontStyle.italic)),
      pw.SizedBox(height: 4),
      pw.Divider(color: PdfColors.grey300, thickness: 0.5),

      ...articles,

      pw.SizedBox(height: 12),
      pw.Text(villeSignature.trim().isEmpty ? 'Le $dateVente.' : 'Fait à ${villeSignature.trim()}, le $dateVente.', style: _body()),

      pw.SizedBox(height: 8),
      _copyBanner('Contrat établi en deux exemplaires originaux, un pour chaque partie.'),
      pw.Row(children: [
        _signBlock('Le Vendeur', p.eleveurNom, signature: sigVendeur),
        pw.SizedBox(width: 16),
        _signBlock('L\'Acheteur', acheteurLabel, signature: sigAcheteur),
      ]),
      pw.SizedBox(height: 6),
      pw.Center(child: pw.Text('$today · PetsMatch', style: _small())),
    ],
  ));

  return pdf;
}

// ─── CERTIFICAT DE CESSION ────────────────────────────────────────────────────

Future<void> genererCertificatCessionPDF({
  required BuildContext context,
  required Map<String, dynamic> animal,
  required Map<String, dynamic> eleveur,
  String acquereurNom = '', String acquereurAdresse = '', String acquereurEmail = '',
  String acquereurTel = '', String prix = '', DateTime? dateCession, String notes = '',
}) async {
  final doc = await _certificatCessionDoc(animal: animal, eleveur: eleveur, acquereurNom: acquereurNom,
      acquereurAdresse: acquereurAdresse, acquereurEmail: acquereurEmail, acquereurTel: acquereurTel,
      prix: prix, dateCession: dateCession, notes: notes);
  await Printing.layoutPdf(onLayout: (_) => doc.save());
}

Future<Uint8List> certificatCessionPdfBytes({
  required Map<String, dynamic> animal,
  required Map<String, dynamic> eleveur,
  String acquereurNom = '', String acquereurAdresse = '', String acquereurEmail = '',
  String acquereurTel = '', String prix = '', DateTime? dateCession, String notes = '',
  String? sigVendeur, String? sigAcheteur,
  String civiliteAcheteur = '', String prenomAcheteur = '', String nomAcheteur = '',
  String cpAcheteur = '', String villeAcheteur = '',
  String modePaiement = '', String tva = '', String tvaTaux = '',
  String? sterilisationClause, String villeSignature = '',
}) async => (await _certificatCessionDoc(
      animal: animal, eleveur: eleveur, acquereurNom: acquereurNom, acquereurAdresse: acquereurAdresse,
      acquereurEmail: acquereurEmail, acquereurTel: acquereurTel, prix: prix, dateCession: dateCession,
      notes: notes, sigVendeur: sigVendeur, sigAcheteur: sigAcheteur,
      civiliteAcheteur: civiliteAcheteur, prenomAcheteur: prenomAcheteur, nomAcheteur: nomAcheteur,
      cpAcheteur: cpAcheteur, villeAcheteur: villeAcheteur, modePaiement: modePaiement,
      tva: tva, tvaTaux: tvaTaux,
      sterilisationClause: sterilisationClause, villeSignature: villeSignature,
    )).save();

Future<pw.Document> _certificatCessionDoc({
  required Map<String, dynamic> animal,
  required Map<String, dynamic> eleveur,
  String acquereurNom = '', String acquereurAdresse = '', String acquereurEmail = '',
  String acquereurTel = '', String prix = '', DateTime? dateCession, String notes = '',
  String? sigVendeur, String? sigAcheteur,
  String civiliteAcheteur = '', String prenomAcheteur = '', String nomAcheteur = '',
  String cpAcheteur = '', String villeAcheteur = '',
  String modePaiement = '', String tva = '', String tvaTaux = '',
  String? sterilisationClause, String villeSignature = '',
}) async {
  final pdf = pw.Document(theme: await _pdfTheme());
  final t = _termes(animal['espece'] as String?);
  final p = _parties(eleveur);
  final today = _fmt(DateTime.now());
  final dateVente = dateCession != null ? _fmt(dateCession) : today;
  final dn = animal['date_naissance'] != null
      ? _fmt(DateTime.tryParse(animal['date_naissance'] as String) ?? DateTime.now()) : '';
  final isMasculin = ['male', 'mâle', 'm'].contains((animal['sexe'] as String? ?? '').toLowerCase());
  final espece = (animal['espece'] as String? ?? '');
  final especeLabel = espece.isNotEmpty ? (espece[0].toUpperCase() + espece.substring(1)) : '';
  final acheteurLabel = [civiliteAcheteur, prenomAcheteur, nomAcheteur]
      .where((s) => s.trim().isNotEmpty).join(' ').trim();
  final acqLabel = acheteurLabel.isNotEmpty ? acheteurLabel : acquereurNom;

  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 40),
    build: (ctx) => [
      pw.Center(child: pw.Text('CERTIFICAT DE CESSION',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _teal, letterSpacing: 1))),
      pw.SizedBox(height: 3),
      pw.Center(child: pw.Text('Établi conformément aux articles L.214-8 et suivants du code rural', style: _small())),
      pw.SizedBox(height: 16),

      pw.Text('ENTRE :', style: _bold()),
      pw.SizedBox(height: 3),
      _line('Vendeur / Cédant', p.eleveurNom),
      _line('Demeurant à', p.eleveurAdresse),
      _line('Téléphone', p.eleveurTel),
      _line('SIRET', p.eleveurSiret),
      _line('Email', p.eleveurEmail),
      pw.SizedBox(height: 8),
      pw.Text('ET :', style: _bold()),
      pw.SizedBox(height: 3),
      _line('Acquéreur', acqLabel.isEmpty ? null : acqLabel),
      _line('Demeurant à', acquereurAdresse),
      _line('Ville, code postal', [cpAcheteur, villeAcheteur].where((s) => s.trim().isNotEmpty).join(' ')),
      _line('Téléphone', acquereurTel),
      _line('Email', acquereurEmail),

      pw.SizedBox(height: 12),
      pw.Text('Article 1 : Animal cédé', style: _artTitle()),
      pw.SizedBox(height: 3),
      _line('Espèce', especeLabel),
      _line('Race', animal['race'] as String?),
      _line('Sexe', isMasculin ? 'Mâle' : 'Femelle'),
      _line('Nom de l\'animal', animal['nom'] as String?),
      _line('Date de naissance', dn.isEmpty ? null : dn),
      _line(
        (t['pedigree'] ?? '').isEmpty
            ? 'Numéro d\'identification (obligatoire)'
            : 'N° d\'identification (puce / tatouage)',
        animal['identification'] as String?),
      if ((t['pedigree'] ?? '').isNotEmpty)
        _line('${t['pedigree']}',
            (animal['pedigree_lof'] as String?)?.trim().isNotEmpty == true
                ? animal['pedigree_lof'] as String?
                : animal['pedigree_numero'] as String?),
      _line('Nom du père', _avecPuce(animal['nom_pere'], animal['puce_pere'])),
      _line('Nom de la mère', _avecPuce(animal['nom_mere'], animal['puce_mere'])),

      pw.SizedBox(height: 10),
      pw.Text('Article 2 : Conditions de cession', style: _artTitle()),
      pw.SizedBox(height: 3),
      _line('Date effective de cession', dateVente),
      if (prix.trim().isNotEmpty) _line('Prix de cession', '${prix.trim()} euros TTC'),
      _line('Dont TVA${tvaTaux.trim().isEmpty ? '' : ' (${tvaTaux.trim()} %)'}',
          tva.trim().isEmpty ? null : '${tva.trim()} €'),
      _line('Mode de règlement', modePaiement.trim().isEmpty ? null : modePaiement.trim()),
      if (sterilisationClause != null) ...[
        pw.SizedBox(height: 3),
        _para(sterilisationClause),
      ],
      if (notes.trim().isNotEmpty) ...[
        pw.SizedBox(height: 3),
        _para('Conditions particulières : ${notes.trim()}'),
      ],

      pw.SizedBox(height: 10),
      pw.Text('Article 3 : Garanties légales', style: _artTitle()),
      pw.SizedBox(height: 3),
      _para('Le cédant certifie que l\'animal est, à sa connaissance, en bonne santé au jour de la cession. '
          'La cession est soumise aux garanties légales contre les vices rédhibitoires suivants : ${t['vices']}. '
          'Délai de garantie légale : 30 jours à compter de la livraison.'),

      pw.SizedBox(height: 10),
      pw.Text('Article 4 : Documents remis à l\'acquéreur', style: _artTitle()),
      pw.SizedBox(height: 3),
      _para('Carte d\'identification I-CAD, carnet de santé / passeport européen, certificat vétérinaire de '
          'bonne santé, certificat d\'engagement et de connaissance'
          '${(animal['pedigree_lof'] as String?)?.isNotEmpty == true ? ', document de filiation (${t['pedigree']})' : ''}.'),

      pw.SizedBox(height: 16),
      pw.Text(villeSignature.trim().isEmpty
          ? 'Le ${dateCession != null ? dateVente : today}.'
          : 'Fait à ${villeSignature.trim()}, le ${dateCession != null ? dateVente : today}.', style: _body()),
      pw.SizedBox(height: 8),
      _copyBanner('Document établi en deux exemplaires originaux, un pour chaque partie.'),
      pw.Row(children: [
        _signBlock('Le Vendeur', p.eleveurNom, signature: sigVendeur),
        pw.SizedBox(width: 16),
        _signBlock('L\'Acquéreur', acqLabel, signature: sigAcheteur),
      ]),
      pw.SizedBox(height: 6),
      pw.Center(child: pw.Text('$today - PetsMatch. Ne remplace pas les obligations légales d\'identification (I-CAD)', style: _small())),
    ],
  ));

  return pdf;
}

// ─── FACTURE ──────────────────────────────────────────────────────────────────

/// Facture de vente d'un animal. Montants TTC ; si [tvaTaux] > 0, la TVA est
/// considérée incluse dans [montantTtc] et détaillée (HT / TVA / TTC).
Future<Uint8List> factureVentePdfBytes({
  required Map<String, dynamic> eleveur,
  required Map<String, dynamic> animal,
  required String numero,
  required double montantTtc,
  double acompte = 0,
  double tvaTaux = 0,
  String acquereurNom = '',
  String acquereurAdresse = '',
  String acquereurEmail = '',
  String acquereurTel = '',
  String modePaiement = '',
  DateTime? date,
}) async {
  final pdf = pw.Document(theme: await _pdfTheme());
  final p = _parties(eleveur);
  final d = date ?? DateTime.now();
  final dateStr = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  String eur(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

  final assujetti = tvaTaux > 0;
  final ht = assujetti ? montantTtc / (1 + tvaTaux / 100) : montantTtc;
  final tva = montantTtc - ht;
  final reste = montantTtc - acompte;

  final especeRace = [animal['espece'], animal['race']]
      .where((e) => e != null && '$e'.trim().isNotEmpty).join(' — ');
  final design = [
    if ('${animal['nom'] ?? ''}'.trim().isNotEmpty) 'Animal : ${animal['nom']}',
    if (especeRace.isNotEmpty) especeRace,
    if ('${animal['identification'] ?? ''}'.trim().isNotEmpty) 'Puce n° ${animal['identification']}',
    if ('${animal['date_naissance'] ?? ''}'.toString().length >= 10)
      'Né(e) le ${'${animal['date_naissance']}'.substring(8, 10)}/${'${animal['date_naissance']}'.substring(5, 7)}/${'${animal['date_naissance']}'.substring(0, 4)}',
  ].join('  ·  ');

  pw.Widget totLine(String label, String value, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(label, style: bold ? _bold() : _body()),
          pw.Text(value, style: bold ? _bold() : _body()),
        ]),
      );

  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 44, 40, 44),
    build: (context) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('FACTURE', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _dark, letterSpacing: 1.5)),
      pw.SizedBox(height: 2),
      pw.Text('N° $numero   ·   $dateStr', style: _small()),
      pw.SizedBox(height: 16),

      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Émetteur', style: _bold()),
          pw.SizedBox(height: 2),
          _line('Nom', p.eleveurNom),
          _line('Adresse', p.eleveurAdresse),
          _line('SIRET', p.eleveurSiret),
          _line('Téléphone', p.eleveurTel),
          _line('Email', p.eleveurEmail),
        ])),
        pw.SizedBox(width: 20),
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Client', style: _bold()),
          pw.SizedBox(height: 2),
          _line('Nom', acquereurNom.trim().isEmpty ? null : acquereurNom.trim()),
          _line('Adresse', acquereurAdresse.trim().isEmpty ? null : acquereurAdresse.trim()),
          _line('Téléphone', acquereurTel.trim().isEmpty ? null : acquereurTel.trim()),
          _line('Email', acquereurEmail.trim().isEmpty ? null : acquereurEmail.trim()),
        ])),
      ]),
      pw.SizedBox(height: 18),

      pw.Text('Désignation', style: _bold()),
      pw.SizedBox(height: 3),
      _para(design.isEmpty ? 'Cession d\'un animal de compagnie' : 'Cession d\'un animal de compagnie — $design'),
      pw.SizedBox(height: 14),

      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.6)),
        child: pw.Column(children: [
          if (assujetti) ...[
            totLine('Total HT', eur(ht)),
            totLine('TVA (${tvaTaux.toString().replaceAll('.', ',')} %)', eur(tva)),
          ],
          totLine('Total TTC', eur(montantTtc), bold: true),
          if (acompte > 0) ...[
            pw.Divider(color: PdfColors.grey300, height: 10),
            totLine('Acompte déjà versé', '- ${eur(acompte)}'),
            totLine('Reste à payer', eur(reste), bold: true),
          ],
        ]),
      ),
      pw.SizedBox(height: 10),
      if (modePaiement.trim().isNotEmpty) _line('Mode de règlement', modePaiement.trim()),
      if (!assujetti)
        pw.Text('TVA non applicable, art. 293 B du CGI.', style: _small()),

      pw.Spacer(),
      pw.Center(child: pw.Text('Facture générée via PetsMatch le $dateStr', style: _small())),
    ]),
  ));

  return pdf.save();
}

// ─── CERTIFICAT D'ENGAGEMENT ET DE CONNAISSANCE ───────────────────────────────
// Loi n° 2021-1539 · Décret n° 2022-1012 du 18 juillet 2022.
// ⚠️ Contenu par espèce à garder identique au rendu web
// (website/src/app/certificat/[token]/page.tsx — objet CONTENT).

class _CertContent {
  final String intro;
  final List<List<String>> physio; // [titre, contenu]
  final List<List<String>> psycho;
  final List<String> sante;
  final List<String> documents;
  final List<List<String>> budget; // [poste, montant]
  final String identNote;
  const _CertContent(this.intro, this.physio, this.psycho, this.sante,
      this.documents, this.budget, this.identNote);
}

const Map<String, _CertContent> _kCertContent = {
  'chien': _CertContent(
    "Ce certificat a pour objectif de vous donner toutes les informations pour accueillir votre chien au mieux, et de vous engager à respecter ses besoins. Il est établi conformément à la Loi n° 2021-1539 et au décret n° 2022-1012 du 18 juillet 2022.",
    [
      ['Boire', "Votre animal doit avoir en permanence de l'eau fraîche et propre à sa disposition. Adaptez la hauteur et la forme des gamelles à la taille de votre chien."],
      ['Dormir', "Un chien dort en moyenne 12h/jour en discontinu. Prévoyez-lui un coin calme et sécurisé (panier, coussin) où il sera respecté dans son repos."],
      ['Manger', "Le chien est carnivore. Prévoyez une alimentation adaptée à son âge, son poids et sa dépense physique. Deux repas par jour minimum sont recommandés pour limiter le risque de torsion d'estomac. Consultez votre vétérinaire pour toute transition alimentaire."],
    ],
    [
      ['Mastiquer et renifler', "Ces comportements instinctifs permettent au chien de canaliser son énergie et de réduire son stress. Encouragez-les avec des promenades variées, tapis de fouille, jouets et friandises naturelles."],
      ['Socialiser', "Le chien est une espèce sociale. Il a besoin d'interactions positives avec d'autres chiens et avec des humains tout au long de sa vie. Un chiot exposé à des environnements variés dès ses premiers mois sera plus équilibré."],
      ['Sortir et se dépenser', "Au-delà de la dépense physique quotidienne indispensable, le chien a besoin de stimulation mentale. Jouets, jeux de recherche, éducation positive : variez les activités pour prévenir l'ennui."],
      ['Éducation', "Instaurez des règles cohérentes dès l'arrivée du chien. Les commandements essentiels (stop, rappel) sont indispensables pour sa sécurité. Évitez toute méthode coercitive (art. R214-24 du Code rural)."],
    ],
    [
      "Vaccination : première injection dès 7-8 semaines, rappels annuels selon le protocole vétérinaire.",
      "Visite annuelle chez le vétérinaire même en l'absence de problèmes apparents.",
      "Nettoyage régulier des oreilles et des yeux avec des produits adaptés à l'espèce.",
      "Entretien du pelage adapté au type de poil (brossage, tonte si nécessaire).",
      "Contrôle du tartre dentaire ; brossage, friandises à mâcher recommandés.",
      "Vérification et taille des griffes si elles ne s'usent pas naturellement.",
      "Antiparasitaires (puces, tiques, vers) selon les recommandations de votre vétérinaire.",
      "Stérilisation recommandée sauf projet d'élevage (à discuter avec votre vétérinaire).",
    ],
    [
      "Carnet de santé à jour avec les vaccinations effectuées",
      "Certificat de cession (présent document)",
      "Justificatif d'identification (puce électronique ou tatouage — obligatoire avant cession)",
      "Certificat de naissance / livre des origines si chien de race inscrit au LOF",
      "Passeport européen si déplacements à l'étranger prévus",
    ],
    [
      ['Alimentation', '50 à 150 € / mois selon la taille'],
      ['Soins vétérinaires (suivi courant)', '200 € / an minimum'],
      ['Antiparasitaires & vaccins', '100 à 200 € / an'],
      ['Matériel (panier, laisse, jouets)', "150 à 300 € à l'arrivée"],
      ['Assurance santé animale', '20 à 60 € / mois (recommandée)'],
      ['Toilettage (selon la race)', '30 à 80 € toutes les 6 à 8 semaines'],
    ],
    "En cas de changement d'adresse ou de propriétaire, signalez-le à I-CAD : 09 77 40 30 77 ou i-cad.fr",
  ),
  'chat': _CertContent(
    "Ce certificat a pour objectif de vous donner toutes les informations pour accueillir votre chat au mieux, et de vous engager à respecter ses besoins. Il est établi conformément à la Loi n° 2021-1539 et au décret n° 2022-1012 du 18 juillet 2022.",
    [
      ['Boire', "Le chat boit peu et préfère l'eau courante ou une fontaine. Éloignez la gamelle d'eau de la gamelle de nourriture. Une alimentation humide (pâtée) contribue à son hydratation."],
      ['Dormir', "Le chat dort entre 12 et 16h par jour. Prévoyez plusieurs zones de repos en hauteur où il se sentira en sécurité. Respectez ses périodes de sommeil."],
      ['Manger', "Le chat est un carnivore strict. Son alimentation doit être riche en protéines animales. Plusieurs petits repas par jour sont préférables. Évitez les aliments interdits (oignon, ail, chocolat, raisins)."],
    ],
    [
      ['Chasser et jouer', "L'instinct de chasse est fondamental chez le chat. Prévoyez des sessions de jeu quotidiennes avec des jouets stimulant cet instinct (cannes à plumes, souris). Cela prévient l'ennui et l'obésité."],
      ['Griffer', "Le griffage est un besoin naturel permettant de marquer son territoire et d'entretenir ses griffes. Mettez à disposition des griffoirs adaptés à la taille de votre chat."],
      ['Environnement enrichi', "Le chat a besoin d'explorer, grimper et se cacher. Arbres à chat, cachettes, fenêtres accessibles sont essentiels. Pour un chat d'intérieur, l'enrichissement est encore plus important."],
      ['Socialisation', "L'exposition à l'humain dès les premières semaines de vie est déterminante pour son sociabilité. Respectez son rythme et évitez de le forcer à des interactions non désirées."],
    ],
    [
      "Vaccination : typhus, coryza, leucose si sorties — rappels annuels.",
      "Visite vétérinaire annuelle, plus fréquente à partir de 7 ans (chat senior).",
      "Nettoyage des oreilles et des yeux si nécessaire (sécrétions, cérumen).",
      "Entretien du pelage (brossage régulier, surtout pour les chats à poils longs).",
      "Contrôle dentaire ; tartres fréquents chez le chat.",
      "Antiparasitaires (puces, tiques, vers intestinaux) selon protocole vétérinaire.",
      "Stérilisation recommandée entre 4 et 6 mois sauf projet d'élevage.",
    ],
    [
      "Carnet de santé avec vaccinations à jour",
      "Certificat de cession (présent document)",
      "Justificatif d'identification (puce ou tatouage — obligatoire avant cession)",
      "Pedigree LOOF si chat de race",
    ],
    [
      ['Alimentation', '30 à 80 € / mois'],
      ['Soins vétérinaires (suivi courant)', '150 à 300 € / an'],
      ['Litière', '20 à 50 € / mois'],
      ['Matériel (griffoir, jouets, arbre à chat)', "100 à 250 € à l'arrivée"],
      ['Assurance santé animale', '15 à 40 € / mois'],
    ],
    "En cas de changement de propriétaire, signalez-le à I-CAD : 09 77 40 30 77 ou i-cad.fr",
  ),
  'lapin': _CertContent(
    "Ce certificat vous informe des besoins essentiels de votre lapin et formalise vos engagements envers son bien-être, conformément à la Loi n° 2021-1539.",
    [
      ['Alimentation', "Le lapin est herbivore strict. Le foin doit représenter 80% de son alimentation (disponible à volonté). Complétez avec des légumes verts frais (persil, roquette, endive) et limitez les granulés. Évitez les laitues iceberg, les choux en grande quantité et tout aliment sucré."],
      ['Eau', "Eau fraîche disponible en permanence. Le biberon ou la gamelle sont tous deux adaptés ; nettoyez-les quotidiennement."],
      ['Espace', "Un lapin a besoin d'un minimum de 4 m² d'espace de vie. Le confinement permanent dans une cage est contraire à son bien-être. Prévoyez des sorties quotidiennes dans un espace sécurisé."],
    ],
    [
      ['Enrichissement', "Le lapin a besoin de mâcher, creuser et explorer. Mettez à sa disposition des jouets adaptés (blocs de bois non traité, tunnels, cartons). Cela prévient les stéréotypies."],
      ['Vie en duo', "Le lapin est grégaire. Il souffre de la solitude. Il est fortement recommandé d'adopter des lapins par paires (stérilisés ou de même sexe)."],
    ],
    [
      "Vaccination contre la myxomatose et la VHD (VHD1 + VHD2) — rappels annuels obligatoires.",
      "Visite vétérinaire annuelle et en urgence à la moindre modification du transit intestinal.",
      "Stérilisation recommandée (prévient les cancers de l'utérus chez la femelle, fréquents après 4 ans).",
      "Contrôle des dents (les incisives et molaires poussent en continu ; le foin les use naturellement).",
      "Entretien des griffes toutes les 4 à 8 semaines.",
    ],
    [
      "Certificat de cession (présent document)",
      "Carnet de santé avec vaccinations si débutées",
    ],
    [
      ['Alimentation (foin, légumes, granulés)', '20 à 40 € / mois'],
      ['Soins vétérinaires + vaccins', '100 à 200 € / an'],
      ['Litière', '15 à 30 € / mois'],
      ['Matériel (cage, jouets, accessoires)', "100 à 200 € à l'arrivée"],
    ],
    "",
  ),
  'default': _CertContent(
    "Ce certificat vous informe des besoins essentiels de votre animal et formalise vos engagements envers son bien-être, conformément à la Loi n° 2021-1539 du 30 novembre 2021.",
    [
      ['Alimentation', "Fournissez une alimentation adaptée à l'espèce, à l'âge et au poids de l'animal. Consultez un vétérinaire ou un spécialiste pour établir une ration équilibrée."],
      ['Eau', "Eau fraîche disponible en permanence, renouvelée quotidiennement."],
      ['Espace et logement', "Prévoyez un espace de vie suffisant et adapté aux besoins spécifiques de l'espèce (température, humidité, lumière)."],
    ],
    [
      ['Enrichissement', "Offrez à votre animal des stimulations adaptées à son espèce : jeux, exploration, activité physique. L'ennui peut générer des troubles comportementaux."],
      ['Socialisation', "Respectez les besoins sociaux propres à l'espèce. Certains animaux vivent en groupe, d'autres sont solitaires. Renseignez-vous auprès d'un spécialiste."],
    ],
    [
      "Consultez un vétérinaire spécialisé dans l'espèce dès l'arrivée de l'animal et au minimum une fois par an.",
      "Respectez le protocole de vaccination et de vermifugation adapté à l'espèce.",
      "Surveillez tout changement de comportement, d'appétit ou d'aspect physique.",
      "Prévenez ou faites traiter tout parasitisme interne ou externe.",
    ],
    [
      "Certificat de cession (présent document)",
      "Carnet de santé ou document sanitaire si disponible",
    ],
    [
      ['Alimentation', "Variable selon l'espèce"],
      ['Soins vétérinaires', '100 à 300 € / an minimum'],
      ['Matériel et logement', "Variable selon l'espèce"],
    ],
    "",
  ),
};

_CertContent _certContent(String? espece) =>
    _kCertContent[(espece ?? '').toLowerCase()] ?? _kCertContent['default']!;

pw.Widget _certHeading(String lettre, String titre) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
      child: pw.Row(children: [
        pw.Container(
          width: 14, height: 14, alignment: pw.Alignment.center,
          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8F4F6), shape: pw.BoxShape.circle),
          child: pw.Text(lettre, style: pw.TextStyle(fontSize: 8, color: _teal, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(width: 6),
        pw.Text(titre, style: _artTitle()),
      ]),
    );

pw.Widget _certBesoin(List<String> item) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(text: '${item[0]} — ', style: _bold()),
        pw.TextSpan(text: item[1], style: _body()),
      ])),
    );

pw.Widget _certPuce(String texte, {String marque = '•'}) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('$marque ', style: _body()),
        pw.Expanded(child: pw.Text(texte, style: _body())),
      ]),
    );

/// PDF du certificat d'engagement — `cert` = ligne `certificats_engagement`,
/// `eleveur` = map profil (cf. `_mapEleveur` de contrat_signature_page.dart).
Future<Uint8List> certificatEngagementPdfBytes({
  required Map<String, dynamic> cert,
  required Map<String, dynamic> eleveur,
  String? sigAcheteur,
}) async {
  final pdf = pw.Document(theme: await _pdfTheme());
  final p = _parties(eleveur);
  final espece = (cert['espece'] as String? ?? '');
  final especeLabel = espece.isNotEmpty ? (espece[0].toUpperCase() + espece.substring(1)) : '—';
  final c = _certContent(espece);
  final today = _fmt(DateTime.now());
  final dateRemise = cert['date_remise'] != null
      ? _fmt(DateTime.tryParse('${cert['date_remise']}')?.toLocal() ?? DateTime.now())
      : today;
  final dateLimite = cert['date_limite_signature'] != null
      ? DateTime.tryParse('${cert['date_limite_signature']}')?.toLocal()
      : null;
  final dateSig = cert['date_signature_acquereur'] != null
      ? _fmt(DateTime.tryParse('${cert['date_signature_acquereur']}')?.toLocal() ?? DateTime.now())
      : null;
  final acqNom = '${cert['acquereur_prenom'] ?? ''} ${cert['acquereur_nom'] ?? ''}'.trim();
  final dnA = cert['date_naissance_animal'] != null
      ? _fmt(DateTime.tryParse('${cert['date_naissance_animal']}') ?? DateTime.now())
      : '';
  final prix = cert['prix'];
  final prixStr = (prix != null && '$prix'.trim().isNotEmpty)
      ? '${(prix is num ? prix.toStringAsFixed(prix % 1 == 0 ? 0 : 2) : '$prix')} €'
      : null;
  final modalite = (cert['modalite_cession'] as String? ?? 'vente');
  final idClean = '${cert['id'] ?? ''}'.replaceAll('-', '');
  final ref = 'CERT-${(idClean.length >= 8 ? idClean.substring(0, 8) : idClean).toUpperCase()}';

  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 40),
    build: (ctx) => [
      pw.Center(child: pw.Text('CERTIFICAT D\'ENGAGEMENT ET DE CONNAISSANCE',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _teal, letterSpacing: 0.6))),
      pw.SizedBox(height: 3),
      pw.Center(child: pw.Text('Loi n° 2021-1539 · Décret n° 2022-1012 du 18 juillet 2022 · Réf. $ref', style: _small())),
      pw.SizedBox(height: 10),
      _para(c.intro),

      _certHeading('A', 'Parties'),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Cédant', style: _bold()),
          _line('Nom', p.eleveurNom),
          _line('Adresse', p.eleveurAdresse),
          _line('SIRET', p.eleveurSiret),
          _line('Téléphone', p.eleveurTel),
          _line('Email', p.eleveurEmail),
          _line('Date de remise', dateRemise),
        ])),
        pw.SizedBox(width: 20),
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Acquéreur', style: _bold()),
          _line('Nom', acqNom.isEmpty ? null : acqNom),
          _line('Email', cert['acquereur_email'] as String?),
          _line('Téléphone', cert['acquereur_telephone'] as String?),
          _line('Adresse', cert['acquereur_adresse'] as String?),
        ])),
      ]),

      _certHeading('B', 'Animal concerné'),
      _line('Nom', cert['nom_animal'] as String?),
      _line('Espèce', especeLabel),
      _line('Race', cert['race'] as String?),
      _line('Date de naissance', dnA.isEmpty ? null : dnA),
      _line('Identification', cert['num_identification'] as String?),
      _line('Modalité', modalite == 'gratuit' ? 'Cession gratuite' : modalite == 'adoption' ? 'Adoption' : 'Vente'),
      if (prixStr != null) _line('Prix', prixStr),

      _certHeading('C', 'Besoins physiologiques'),
      ...c.physio.map(_certBesoin),

      _certHeading('D', 'Besoins comportementaux et psychologiques'),
      ...c.psycho.map(_certBesoin),

      _certHeading('E', 'Santé'),
      ...c.sante.map((s) => _certPuce(s, marque: '☑')),

      _certHeading('F', 'Dépenses à prévoir'),
      ...c.budget.map((b) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 1.5),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Expanded(child: pw.Text(b[0], style: _body())),
              pw.Text(b[1], style: _bold()),
            ]),
          )),
      if (c.identNote.isNotEmpty) ...[
        pw.SizedBox(height: 3),
        pw.Text(c.identNote, style: _small()),
      ],

      _certHeading('G', 'Documents remis avec l\'animal'),
      ...c.documents.map((d) => _certPuce(d, marque: '□')),

      if (dateLimite != null) ...[
        _certHeading('H', 'Délai de réflexion légal ($especeLabel)'),
        _para('Pour les ${espece}s, l\'acquéreur dispose de 7 jours calendaires à compter de la remise du '
            'certificat ($dateRemise) avant de pouvoir le signer. Signature possible à partir du '
            '${_fmt(dateLimite)}. Aucune somme ne peut être perçue pendant ce délai.'),
      ],

      _certHeading('I', 'Signatures'),
      pw.Row(children: [
        pw.Expanded(child: pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4, right: 8),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Le Cédant : ${p.eleveurNom}', style: pw.TextStyle(fontSize: 8, color: _dark, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Remis le $dateRemise', style: _small()),
            pw.SizedBox(height: 46),
            pw.Container(width: 150, height: 0.6, color: PdfColors.grey500),
            pw.SizedBox(height: 2),
            pw.Text('Signature électronique PetsMatch', style: _small()),
          ]),
        )),
        pw.SizedBox(width: 16),
        _signBlock('L\'Acquéreur', cert['signataire_nom'] as String? ?? acqNom, signature: sigAcheteur),
      ]),
      pw.SizedBox(height: 4),
      if (dateSig != null)
        pw.Text('Signé le $dateSig — « Je m\'engage à respecter les besoins de l\'animal. »',
            style: pw.TextStyle(fontSize: 8, color: _teal, fontStyle: pw.FontStyle.italic)),
      pw.SizedBox(height: 6),
      pw.Center(child: pw.Text('$today · Document généré via PetsMatch · Réf. ${cert['id'] ?? ''}', style: _small())),
    ],
  ));

  return pdf.save();
}
