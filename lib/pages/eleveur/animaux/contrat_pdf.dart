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
