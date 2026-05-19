import 'dart:convert';

import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, rootBundle;

class CreerFacturePage extends StatefulWidget {
  @override
  _CreerFacturePageState createState() => _CreerFacturePageState();
}

class Country {
  final String name;
  final String dialCode;
  final String code;

  Country({required this.name, required this.dialCode, required this.code});

  factory Country.fromJson(Map<String, dynamic> json) {
    return Country(
      name: json['name'],
      dialCode: json['dial_code'],
      code: json['code'],
    );
  }
}

class _CreerFacturePageState extends State<CreerFacturePage> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  TextEditingController nomElevageController = TextEditingController();
  TextEditingController adresseElevageController = TextEditingController();
  final TextEditingController codeISOElevageController = TextEditingController();
  final TextEditingController codeISOClientController = TextEditingController();
  List<Country> countries = [];
  Country? selectedCountry;
  Country? selectedCountry1;

  TextEditingController telephoneElevageController = TextEditingController();
  TextEditingController siretController = TextEditingController();
  TextEditingController numeroTVAController = TextEditingController();

  TextEditingController nomClientController = TextEditingController();
  TextEditingController adresseClientController = TextEditingController();
  TextEditingController telephoneClientController = TextEditingController();
  TextEditingController numeroTVAClientController = TextEditingController();
  TextEditingController siretClientController = TextEditingController();

  TextEditingController numeroFactureController = TextEditingController();
  TextEditingController modePaiementController = TextEditingController();

  bool isProExpanded = false;
  bool isClientExpanded = false;
  bool isMereExpanded = false;
  bool isSanteExpanded = false;
  bool isInfoFactureExpanded = false;

  List<Map<String, dynamic>> dates = [
    {
      "labelController": TextEditingController(text: "Date de facture"),
      "dateController": TextEditingController(),
      "isActive": true,
    },
    {
      "labelController": TextEditingController(text: "Date de livraison"),
      "dateController": TextEditingController(),
      "isActive": true,
    },
    // {
    //   "labelController": TextEditingController(text: "Échéance de paiement"),
    //   "dateController": TextEditingController(),
    //   "isActive": true,
    // },
  ];

  String devise = '€';
  double tauxTVA = 20.0;
  bool tvaActive = true;
  List<Map<String, dynamic>> lignesFacture = [];

  String logoUrl = '';
  String infoComplementaire = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadCountries();
    isProExpanded = false;
    isClientExpanded = false;
    isMereExpanded = false;
    isSanteExpanded = false;
    isInfoFactureExpanded = false;
    final now = DateTime.now();
    dates[0]["dateController"].text = DateFormat('dd/MM/yyyy').format(now);
    dates[1]["dateController"].text =
        DateFormat('dd/MM/yyyy').format(now.add(Duration(days: 7)));
    // dates[2]["dateController"].text =
    //     DateFormat('dd/MM/yyyy').format(now.add(Duration(days: 30)));
  }

  Future<void> _loadCountries() async {
    final String response =
        await rootBundle.loadString('assets/CountryCodes.json');
    final List<dynamic> data = json.decode(response);
    setState(() {
      countries = data.map((e) => Country.fromJson(e)).toList();

      // Si le code ISO est déjà défini, sélectionner le pays correspondant
      if (codeISOClientController.text.isNotEmpty) {
        selectedCountry = countries.firstWhere(
          (country) => country.code == codeISOClientController.text,
          orElse: () => countries[0],
        );
      } else {
        selectedCountry = countries[0]; // Valeur par défaut
        codeISOClientController.text = "+33";
      }
    });
  }

  Future<void> _loadUserData() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (userDoc.exists) {
        setState(() {
          logoUrl = userDoc.data()?['profilePictureUrlElevage'] ?? '';
          nomElevageController.text = userDoc.data()?['nameElevage'] ?? '';
          adresseElevageController.text =
              userDoc.data()?['adressElevage'] ?? '';
          codeISOElevageController.text =
              userDoc.data()?['codeISOElevage'] ?? '+33';
          telephoneElevageController.text =
              userDoc.data()?['numeroElevage'] ?? '';
          siretController.text = userDoc.data()?['siret'] ?? '';
          numeroTVAController.text = userDoc.data()?['numeroTVA'] ?? '';
        });
      }
      if (codeISOElevageController.text.isNotEmpty) {
        selectedCountry1 = countries.firstWhere(
          (country) => country.code == codeISOElevageController.text,
          orElse: () => countries[0],
        );
      } else {
        selectedCountry1 = countries[0]; // Valeur par défaut
      }
      // Récupérer le dernier numéro de facture et incrémenter
      final factureCollection = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('factures')
          .orderBy('numeroFacture', descending: true)
          .limit(1)
          .get();

      int lastInvoiceNumber = 0;
      if (factureCollection.docs.isNotEmpty) {
        lastInvoiceNumber = factureCollection.docs.first['numeroFacture'];
      }

      setState(() {
        numeroFactureController.text = (lastInvoiceNumber + 1).toString();
      });
    }
  }

  void _ajouterLigneFacture() {
    setState(() {
      lignesFacture.add({
        'titre': '',
        'description': '',
        'quantite': 1,
        'prixUnitaireHT': TextEditingController(text: '0'),
        'prixUnitaireTTC': TextEditingController(text: '0'),
        'focusHT': FocusNode(),
        'focusTTC': FocusNode(),
      });
    });
  }

  Future<Uint8List> _downloadLogo(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Failed to load logo image');
    }
  }

  Future<Uint8List> generateInvoicePdf(
    String logoUrl,
    Map<String, String> elevageInfo,
    Map<String, String> clientInfo,
    String factureNumber,
    List<Map<String, dynamic>> dates,
    List<Map<String, dynamic>> lignesFacture,
    double totalHT,
    double? tauxTVA,
    double totalTTC,
    String? infoComplementaire,
    String? modePaiement,
    bool tvaActive,
  ) async {
    final pdf = pw.Document();

    Uint8List? logoBytes;
    if (logoUrl.isNotEmpty) {
      try {
        logoBytes = await _downloadLogo(logoUrl);
      } catch (e) {
        print('Error downloading logo: $e');
      }
    }

    // Charger le logo de PetsMatch depuis les assets
    final petsMatchLogo = pw.MemoryImage(
        (await rootBundle.load("assets/logofacture.png")).buffer.asUint8List());

    // Utilisation de la police Roboto qui supporte le symbole €
    final font = await PdfGoogleFonts.robotoRegular();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4, // Utiliser le format A4
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              // Logo de PetsMatch en fond avec une opacité réduite (alpha)
              pw.Center(
                child: pw.Opacity(
                  opacity: 0.2, // Alpha à 50%
                  child: pw.Image(petsMatchLogo,
                      width: 450, height: 450), // Taille du logo ajustée
                ),
              ),
              // Contenu par-dessus le logo en fond
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Informations Éleveur et Client réorganisées
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Informations Éleveur
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          if (logoBytes != null)
                            pw.Image(pw.MemoryImage(logoBytes),
                                width: 70, height: 70),
                          pw.SizedBox(height: 10),
                          pw.Text(elevageInfo['nomElevage'] ?? '',
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold, font: font)),
                          pw.Text(elevageInfo['adresseElevage'] ?? '',
                              style: pw.TextStyle(font: font)),
                          pw.Text(
                              elevageInfo['codeISOElevage']! +
                                  ' ' +
                                  elevageInfo['telephoneElevage']!,
                              style: pw.TextStyle(font: font)),
                          if (elevageInfo['siret'] != null &&
                              elevageInfo['siret']!.isNotEmpty)
                            pw.Text('SIRET: ${elevageInfo['siret']}',
                                style: pw.TextStyle(font: font)),
                          if (elevageInfo['numeroTVA'] != null &&
                              elevageInfo['numeroTVA']!.isNotEmpty)
                            pw.Text('TVA: ${elevageInfo['numeroTVA']}',
                                style: pw.TextStyle(font: font)),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('Facture n° $factureNumber',
                              style: pw.TextStyle(fontSize: 16, font: font)),
                        ],
                      ),
                    ],
                  ),

                  // Espace avant les informations client
                  pw.SizedBox(height: 20),

                  // Informations Client
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.SizedBox(
                          width: 200), // Espacement pour aligner à droite
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(clientInfo['nomClient'] ?? '',
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold, font: font)),
                          pw.Text(clientInfo['adresseClient'] ?? '',
                              style: pw.TextStyle(font: font)),
                          pw.Text(
                              clientInfo['codeISOClient']! +
                                  ' ' +
                                  clientInfo['telephoneClient']!,
                              style: pw.TextStyle(font: font)),
                          if (clientInfo['siretClient'] != null &&
                              clientInfo['siretClient']!.isNotEmpty)
                            pw.Text('SIRET: ${clientInfo['siretClient']}',
                                style: pw.TextStyle(font: font)),
                          if (clientInfo['numeroTVAClient'] != null &&
                              clientInfo['numeroTVAClient']!.isNotEmpty)
                            pw.Text('TVA: ${clientInfo['numeroTVAClient']}',
                                style: pw.TextStyle(font: font)),
                        ],
                      ),
                    ],
                  ),

                  // Espace entre les informations client et les dates
                  pw.SizedBox(height: 20),

                  // Dates de la facture
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: dates
                        .where((date) => date["isActive"])
                        .map((date) => pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.start,
                              children: [
                                pw.Text(
                                  "${date['labelController'].text} : ",
                                  style: pw.TextStyle(
                                      fontWeight: pw.FontWeight.bold,
                                      font: font),
                                ),
                                pw.Text(date["dateController"].text,
                                    style: pw.TextStyle(font: font)),
                              ],
                            ))
                        .toList(),
                  ),
                  pw.SizedBox(height: 20),

                  // Tableau des lignes de facture
                  pw.Table.fromTextArray(
                    headerDecoration:
                        pw.BoxDecoration(color: PdfColor.fromHex('#FFC0CB')),
                    headerStyle: pw.TextStyle(
                        color: PdfColor.fromHex('#000000'), font: font),
                    cellStyle: pw.TextStyle(font: font),
                    cellAlignment: pw.Alignment.center,
                    headers: tvaActive
                        ? [
                            'Description',
                            'Quantité',
                            'Prix unitaire HT',
                            'Prix unitaire TTC'
                          ]
                        : ['Description', 'Quantité', 'Prix unitaire'],
                    data: lignesFacture.map((ligne) {
                      return tvaActive
                          ? [
                              pw.Text(
                                '${ligne['titre']}\n${ligne['description'] ?? ''}',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  font: font,
                                ),
                                textAlign: pw.TextAlign.left,
                              ),
                              ligne['quantite'].toString(),
                              '${ligne['prixUnitaireHT'].text} $devise',
                              '${ligne['prixUnitaireTTC'].text} $devise'
                            ]
                          : [
                              pw.Text(
                                '${ligne['titre']}\n${ligne['description'] ?? ''}',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  font: font,
                                ),
                                textAlign: pw.TextAlign.left,
                              ),
                              ligne['quantite'].toString(),
                              '${ligne['prixUnitaireHT'].text} $devise',
                            ];
                    }).toList(),
                  ),
                  pw.SizedBox(height: 20),

                  // Tableau des Totaux (HT, TVA, TTC)
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Container(
                      width: 200,
                      child: pw.Table(
                        border: pw.TableBorder.all(),
                        children: [
                          pw.TableRow(
                            children: [
                              pw.Container(
                                color: PdfColor.fromHex('#FFC0CB'),
                                padding: pw.EdgeInsets.all(8),
                                child: pw.Text('Total HT',
                                    style: pw.TextStyle(font: font)),
                              ),
                              pw.Container(
                                padding: pw.EdgeInsets.all(8),
                                child: pw.Text(
                                    '${totalHT.toStringAsFixed(2)} $devise',
                                    style: pw.TextStyle(font: font)),
                              ),
                            ],
                          ),
                          if (tvaActive && tauxTVA != null)
                            pw.TableRow(
                              children: [
                                pw.Container(
                                  color: PdfColor.fromHex('#FFC0CB'),
                                  padding: pw.EdgeInsets.all(8),
                                  child: pw.Text(
                                      'TVA (${tauxTVA.toStringAsFixed(2)} %)',
                                      style: pw.TextStyle(font: font)),
                                ),
                                pw.Container(
                                  padding: pw.EdgeInsets.all(8),
                                  child: pw.Text(
                                      '${(totalTTC - totalHT).toStringAsFixed(2)} $devise',
                                      style: pw.TextStyle(font: font)),
                                ),
                              ],
                            ),
                          if (tvaActive)
                            pw.TableRow(
                              children: [
                                pw.Container(
                                  color: PdfColor.fromHex('#FFC0CB'),
                                  padding: pw.EdgeInsets.all(8),
                                  child: pw.Text('Total TTC',
                                      style: pw.TextStyle(font: font)),
                                ),
                                pw.Container(
                                  padding: pw.EdgeInsets.all(8),
                                  child: pw.Text(
                                      '${totalTTC.toStringAsFixed(2)} $devise',
                                      style: pw.TextStyle(font: font)),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Informations complémentaires
                  if (infoComplementaire != null &&
                      infoComplementaire!.isNotEmpty)
                    pw.Padding(
                      padding: pw.EdgeInsets.only(top: 20),
                      child: pw.Text(
                        infoComplementaire!,
                        style: pw.TextStyle(fontSize: 10, font: font),
                      ),
                    ),

                  // Mode de paiement
                  if (modePaiement != null && modePaiement.isNotEmpty)
                    pw.Padding(
                      padding: pw.EdgeInsets.only(top: 40),
                      child: pw.Center(
                        child: pw.Text(
                          'Mode de paiement : $modePaiement',
                          style: pw.TextStyle(fontSize: 12, font: font),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  bool _validateLigneFacture(Map<String, dynamic> ligne) {
    return ligne['titre'].isNotEmpty &&
        ligne['prixUnitaireHT'].text.isNotEmpty &&
        double.tryParse(ligne['prixUnitaireHT'].text) != null &&
        ligne['quantite'] > 0;
  }

  Future<void> _enregistrerEtTelechargerFacture() async {
    // Validation des champs de l'éleveur
    if (nomElevageController.text.isEmpty ||
        adresseElevageController.text.isEmpty ||
        codeISOElevageController.text.isEmpty ||
        telephoneElevageController.text.isEmpty ||
        siretController.text.isEmpty) {
      _showSnackBar('Veuillez remplir toutes les informations de l\'éleveur.');
      return;
    }

    // Validation des champs du client
    if (nomClientController.text.isEmpty ||
        adresseClientController.text.isEmpty ||
        codeISOClientController.text.isEmpty ||
        telephoneClientController.text.isEmpty) {
      _showSnackBar('Veuillez remplir toutes les informations du client.');
      return;
    }

    // Validation des lignes de facture
    if (lignesFacture.isEmpty || !lignesFacture.every(_validateLigneFacture)) {
      _showSnackBar('Veuillez ajouter et remplir une ligne de facture.');
      return;
    }

    // Validation du mode de paiement
    if (modePaiementController.text.isEmpty) {
      _showSnackBar('Le mode de paiement est obligatoire.');
      return;
    }

    // Si toutes les validations passent, on génère la facture
    final totalHT = _calculateTotalHT(lignesFacture);
    final totalTTC = _calculateTotalTTC(totalHT, tauxTVA, tvaActive);

    final pdfData = await generateInvoicePdf(
      logoUrl,
      {
        'nomElevage': nomElevageController.text,
        'adresseElevage': adresseElevageController.text,
        'codeISOElevage': codeISOElevageController.text,
        'telephoneElevage': telephoneElevageController.text,
        'siret': siretController.text,
        'numeroTVA': numeroTVAController.text,
      },
      {
        'nomClient': nomClientController.text,
        'adresseClient': adresseClientController.text,
        'codeISOClient': codeISOClientController.text,
        'telephoneClient': telephoneClientController.text,
        'siretClient': siretClientController.text,
        'numeroTVAClient': numeroTVAClientController.text,
      },
      numeroFactureController.text,
      dates,
      lignesFacture,
      totalHT,
      tvaActive ? tauxTVA : null,
      totalTTC,
      infoComplementaire.isNotEmpty ? infoComplementaire : null,
      modePaiementController.text,
      tvaActive,
    );

    // Imprimer et télécharger la facture
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfData,
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  double _calculateTotalHT(List<Map<String, dynamic>> lignes) {
    return lignes.fold(
        0.0,
        (total, ligne) =>
            total +
            (ligne['quantite'] *
                double.tryParse(ligne['prixUnitaireHT'].text)!));
  }

  double _calculateTotalTTC(double totalHT, double tauxTVA, bool tvaActive) {
    return tvaActive ? totalHT * (1 + tauxTVA / 100) : totalHT;
  }

  void _onHTTTCChanged(int index, bool isHT) {
    final quantite = lignesFacture[index]['quantite'];

    final prixUnitaireHT =
        double.tryParse(lignesFacture[index]['prixUnitaireHT'].text) ?? 0.0;
    final prixUnitaireTTC =
        double.tryParse(lignesFacture[index]['prixUnitaireTTC'].text) ?? 0.0;

    if (isHT) {
      final calculatedTTC =
          tvaActive ? prixUnitaireHT * (1 + tauxTVA / 100) : prixUnitaireHT;
      lignesFacture[index]['prixUnitaireTTC'].text =
          calculatedTTC.toStringAsFixed(2);
    } else {
      final calculatedHT =
          tvaActive ? prixUnitaireTTC / (1 + tauxTVA / 100) : prixUnitaireTTC;
      lignesFacture[index]['prixUnitaireHT'].text =
          calculatedHT.toStringAsFixed(2);
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: UTILS.widthReference(context),
                  height: UTILS.calculHeight(
                      105,
                      UTILS.heightReference(
                          context)), // Hauteur fixe pour le Stack
                  child: Stack(children: [
                    Image.asset(
                      'assets/deco/arrondi_rose_2.png',
                      fit: BoxFit.cover,
                      width:
                          UTILS.calculWidth(211, UTILS.widthReference(context)),
                      height: UTILS.calculHeight(
                          104,
                          UTILS.heightReference(
                              context)), // Hauteur fixe pour le Stack
                    ),
                    Positioned(
                        top: UTILS.calculHeight(
                            42, UTILS.heightReference(context)),
                        left: UTILS.calculWidth(
                            10, UTILS.widthReference(context)),
                        child: IconButton(
                          icon: Icon(Icons.arrow_back,
                              color: Colors.black), // Icône de la flèche noire
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                        )),
                    Positioned(
                      top: UTILS.calculHeight(
                          53, UTILS.heightReference(context)),
                      left: 0,
                      right:
                          0, // Assurez-vous que left et right sont définis à 0 pour permettre au texte de centrer exactement
                      child: Align(
                        alignment: Alignment.center,
                        child: Text(
                          'FACTURATION',
                          textAlign: TextAlign
                              .center, // Assurez-vous d'utiliser textAlign pour garantir que le texte est centré à l'intérieur du Text widget.
                          style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            fontSize: UTILS.calculWidth(
                                20, UTILS.widthReference(context)),
                          ),
                        ),
                      ),
                    )
                  ])),
              SizedBox(height: 20),
              ExpansionTile(
                  initiallyExpanded: isProExpanded,
                  backgroundColor: Colors.transparent, // Supprime le fond blanc
                  collapsedBackgroundColor:
                      Colors.transparent, // Supprime le fond blanc
                  title: Row(
                    children: [
                      Text(
                        'Information éleveur',
                        style: TextStyle(
                          fontSize: UTILS.calculWidth(
                              30, UTILS.widthReference(context)),
                          fontFamily: 'Galey',
                          color: const Color.fromARGB(174, 0, 0, 0),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  onExpansionChanged: (bool expanded) {
                    setState(() => isProExpanded = expanded);
                  },
                  children: <Widget>[
                    SizedBox(
                        width: UTILS.calculWidth(
                            355, UTILS.widthReference(context)),
                        child: TextFormField(
                          controller: nomElevageController,
                          decoration: InputDecoration(
                            labelText: 'Nom de l\'élevage',
                            filled: false,
                            fillColor: Colors.transparent,
                            labelStyle: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Color.fromARGB(255, 0, 0, 0),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Color.fromARGB(255, 250, 192, 187)),
                            ),
                          ),
                        )),
                    SizedBox(
                        width: UTILS.calculWidth(
                            355, UTILS.widthReference(context)),
                        child: TextFormField(
                          controller: adresseElevageController,
                          decoration: InputDecoration(
                            labelText: 'Adresse de l\'élevage',
                            filled: false,
                            fillColor: Colors.transparent,
                            labelStyle: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Color.fromARGB(255, 0, 0, 0),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Color.fromARGB(255, 250, 192, 187)),
                            ),
                          ),
                        )),
                   SizedBox(
                      width:
                          UTILS.calculWidth(355, UTILS.widthReference(context)),
                      child: _buildDropdownWithFlagsEnterprise(),
                    ),
                    SizedBox(
                        width: UTILS.calculWidth(
                            355, UTILS.widthReference(context)),
                        child: TextFormField(
                          controller: telephoneElevageController,
                          decoration: InputDecoration(
                            labelText: 'Téléphone de l\'élevage',
                            filled: false,
                            fillColor: Colors.transparent,
                            labelStyle: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Color.fromARGB(255, 0, 0, 0),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Color.fromARGB(255, 250, 192, 187)),
                            ),
                          ),
                        )),
                    SizedBox(
                        width: UTILS.calculWidth(
                            355, UTILS.widthReference(context)),
                        child: TextFormField(
                          controller: siretController,
                          decoration: InputDecoration(
                            labelText: 'SIRET',
                            filled: false,
                            fillColor: Colors.transparent,
                            labelStyle: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Color.fromARGB(255, 0, 0, 0),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Color.fromARGB(255, 250, 192, 187)),
                            ),
                          ),
                        )),
                    SizedBox(
                        width: UTILS.calculWidth(
                            355, UTILS.widthReference(context)),
                        child: TextFormField(
                          controller: numeroTVAController,
                          decoration: InputDecoration(
                            labelText: 'Numéro de TVA',
                            filled: false,
                            fillColor: Colors.transparent,
                            labelStyle: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Color.fromARGB(255, 0, 0, 0),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Color.fromARGB(255, 250, 192, 187)),
                            ),
                          ),
                        )),
                    SizedBox(height: 20),
                    ////Divider,
                  ]),
              ExpansionTile(
                  initiallyExpanded: isClientExpanded,
                  title: Row(
                    children: [
                      Text(
                        'Information client',
                        style: TextStyle(
                          fontSize: UTILS.calculWidth(
                              30, UTILS.widthReference(context)),
                          fontFamily: 'Galey',
                          color: const Color.fromARGB(174, 0, 0, 0),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  onExpansionChanged: (bool expanded) {
                    setState(() => isClientExpanded = expanded);
                  },
                  children: <Widget>[
                    SizedBox(
                        width: UTILS.calculWidth(
                            355, UTILS.widthReference(context)),
                        child: TextFormField(
                          controller: nomClientController,
                          decoration: InputDecoration(
                            labelText: 'Nom du client',
                            filled: false,
                            fillColor: Colors.transparent,
                            labelStyle: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Color.fromARGB(255, 0, 0, 0),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Color.fromARGB(255, 250, 192, 187)),
                            ),
                          ),
                        )),
                    SizedBox(
                        width: UTILS.calculWidth(
                            355, UTILS.widthReference(context)),
                        child: TextFormField(
                          controller: adresseClientController,
                          decoration: InputDecoration(
                            labelText: 'Adresse du client',
                            filled: false,
                            fillColor: Colors.transparent,
                            labelStyle: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Color.fromARGB(255, 0, 0, 0),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Color.fromARGB(255, 250, 192, 187)),
                            ),
                          ),
                        )),
                    SizedBox(
                      width:
                          UTILS.calculWidth(355, UTILS.widthReference(context)),
                      child: _buildDropdownWithFlags(),
                    ),
                    SizedBox(
                        width: UTILS.calculWidth(
                            355, UTILS.widthReference(context)),
                        child: TextFormField(
                          controller: telephoneClientController,
                          decoration: InputDecoration(
                            labelText: 'Téléphone du client',
                            filled: false,
                            fillColor: Colors.transparent,
                            labelStyle: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Color.fromARGB(255, 0, 0, 0),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Color.fromARGB(255, 250, 192, 187)),
                            ),
                          ),
                        )),
                    SizedBox(
                        width: UTILS.calculWidth(
                            355, UTILS.widthReference(context)),
                        child: TextFormField(
                          controller: siretClientController,
                          decoration: InputDecoration(
                            labelText: 'SIRET du client (facultatif)',
                            filled: false,
                            fillColor: Colors.transparent,
                            labelStyle: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Color.fromARGB(255, 0, 0, 0),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Color.fromARGB(255, 250, 192, 187)),
                            ),
                          ),
                        )),
                    SizedBox(
                        width: UTILS.calculWidth(
                            355, UTILS.widthReference(context)),
                        child: TextFormField(
                          controller: numeroTVAClientController,
                          decoration: InputDecoration(
                            labelText: 'Numéro de TVA du client (facultatif)',
                            filled: false,
                            fillColor: Colors.transparent,
                            labelStyle: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Color.fromARGB(255, 0, 0, 0),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Color.fromARGB(255, 250, 192, 187)),
                            ),
                          ),
                        )),
                  ]),
              SizedBox(height: 20),

              ////Divider,
              ExpansionTile(
                  initiallyExpanded: isInfoFactureExpanded,
                  title: Row(
                    children: [
                      Text(
                        'Détails facture',
                        style: TextStyle(
                          fontSize: UTILS.calculWidth(
                              30, UTILS.widthReference(context)),
                          fontFamily: 'Galey',
                          color: const Color.fromARGB(174, 0, 0, 0),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  onExpansionChanged: (bool expanded) {
                    setState(() => isInfoFactureExpanded = expanded);
                  },
                  children: <Widget>[
                    SizedBox(
                        width: UTILS.calculWidth(
                            355, UTILS.widthReference(context)),
                        child: TextFormField(
                          controller: numeroFactureController,
                          decoration: InputDecoration(
                            labelText: 'Numéro de facture',
                            filled: false,
                            fillColor: Colors.transparent,
                            labelStyle: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Color.fromARGB(255, 0, 0, 0),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Color.fromARGB(255, 250, 192, 187)),
                            ),
                          ),
                        )),
                    ListView.builder(
                      shrinkWrap: true,
                      itemCount: lignesFacture.length,
                      itemBuilder: (context, index) {
                        return Column(
                          children: [
                            SizedBox(
                                width: UTILS.calculWidth(
                                    355, UTILS.widthReference(context)),
                                child: TextFormField(
                                  decoration: InputDecoration(
                                    labelText: 'Titre',
                                    filled: false,
                                    fillColor: Colors.transparent,
                                    labelStyle: TextStyle(
                                      fontFamily: 'Galey',
                                      fontWeight: FontWeight.w500,
                                      color: Color.fromARGB(255, 0, 0, 0),
                                    ),
                                    enabledBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(
                                          color: Color.fromARGB(
                                              255, 250, 192, 187)),
                                    ),
                                  ),
                                  onChanged: (value) {
                                    lignesFacture[index]['titre'] = value;
                                  },
                                )),
                            SizedBox(
                                width: UTILS.calculWidth(
                                    355, UTILS.widthReference(context)),
                                child: TextFormField(
                                  decoration: InputDecoration(
                                    labelText: 'Description',
                                    filled: false,
                                    fillColor: Colors.transparent,
                                    labelStyle: TextStyle(
                                      fontFamily: 'Galey',
                                      fontWeight: FontWeight.w500,
                                      color: Color.fromARGB(255, 0, 0, 0),
                                    ),
                                    enabledBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(
                                          color: Color.fromARGB(
                                              255, 250, 192, 187)),
                                    ),
                                  ),
                                  onChanged: (value) {
                                    lignesFacture[index]['description'] = value;
                                  },
                                )),
                            SizedBox(
                                width: UTILS.calculWidth(
                                    355, UTILS.widthReference(context)),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Focus(
                                        focusNode: lignesFacture[index]
                                            ['focusHT'],
                                        onFocusChange: (hasFocus) {
                                          if (!hasFocus) {
                                            _onHTTTCChanged(index, true);
                                          }
                                        },
                                        child: TextFormField(
                                          controller: lignesFacture[index]
                                              ['prixUnitaireHT'],
                                          decoration: InputDecoration(
                                              filled: false,
                                              fillColor: Colors.transparent,
                                              labelStyle: TextStyle(
                                                fontFamily: 'Galey',
                                                fontWeight: FontWeight.w500,
                                                color: Color.fromARGB(
                                                    255, 0, 0, 0),
                                              ),
                                              enabledBorder:
                                                  UnderlineInputBorder(
                                                borderSide: BorderSide(
                                                    color: Color.fromARGB(
                                                        255, 250, 192, 187)),
                                              ),
                                              labelText: tvaActive
                                                  ? 'Prix Unitaire HT'
                                                  : 'Prix Unitaire'),
                                          keyboardType:
                                              TextInputType.numberWithOptions(
                                                  decimal: true),
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(
                                                RegExp(r'^\d+\.?\d{0,2}'))
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (tvaActive)
                                      Expanded(
                                        child: Focus(
                                          focusNode: lignesFacture[index]
                                              ['focusTTC'],
                                          onFocusChange: (hasFocus) {
                                            if (!hasFocus) {
                                              _onHTTTCChanged(index, false);
                                            }
                                          },
                                          child: TextFormField(
                                            controller: lignesFacture[index]
                                                ['prixUnitaireTTC'],
                                            decoration: InputDecoration(
                                                filled: false,
                                                fillColor: Colors.transparent,
                                                labelStyle: TextStyle(
                                                  fontFamily: 'Galey',
                                                  fontWeight: FontWeight.w500,
                                                  color: Color.fromARGB(
                                                      255, 0, 0, 0),
                                                ),
                                                enabledBorder:
                                                    UnderlineInputBorder(
                                                  borderSide: BorderSide(
                                                      color: Color.fromARGB(
                                                          255, 250, 192, 187)),
                                                ),
                                                labelText: 'Prix Unitaire TTC'),
                                            keyboardType:
                                                TextInputType.numberWithOptions(
                                                    decimal: true),
                                            inputFormatters: [
                                              FilteringTextInputFormatter.allow(
                                                  RegExp(r'^\d+\.?\d{0,2}'))
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                )),
                            SizedBox(
                                width: UTILS.calculWidth(
                                    355, UTILS.widthReference(context)),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        decoration: InputDecoration(
                                          labelText: 'Quantité',
                                          filled: false,
                                          fillColor: Colors.transparent,
                                          labelStyle: TextStyle(
                                            fontFamily: 'Galey',
                                            fontWeight: FontWeight.w500,
                                            color: Color.fromARGB(255, 0, 0, 0),
                                          ),
                                          enabledBorder: UnderlineInputBorder(
                                            borderSide: BorderSide(
                                                color: Color.fromARGB(
                                                    255, 250, 192, 187)),
                                          ),
                                        ),
                                        keyboardType: TextInputType.number,
                                        onChanged: (value) {
                                          lignesFacture[index]['quantite'] =
                                              int.tryParse(value) ?? 1;
                                          setState(() {});
                                        },
                                      ),
                                    ),
                                    IconButton(
                                      icon:
                                          Icon(Icons.delete, color: Colors.red),
                                      onPressed: () {
                                        setState(() {
                                          lignesFacture.removeAt(index);
                                        });
                                      },
                                    ),
                                  ],
                                )),
                            SizedBox(height: 25),

                            ////Divider,
                          ],
                        );
                      },
                    ),

                    SizedBox(
                      width:
                          UTILS.calculWidth(372, UTILS.widthReference(context)),
                      child: ElevatedButton(
                        onPressed: _ajouterLigneFacture,
                        child: Text(
                          'Ajouter une ligne',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Galey',
                            color: Color.fromARGB(255, 0, 0, 0),
                            fontWeight: FontWeight.w500,
                            fontSize: UTILS.calculWidth(
                                18, UTILS.widthReference(context)),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color.fromARGB(255, 252, 207, 200),
                        ),
                      ),
                    ),
                    ////Divider,
                    SizedBox(height: 20),

                    SizedBox(
                        width: UTILS.calculWidth(
                            355, UTILS.widthReference(context)),
                        child: Column(
                          children: List.generate(dates.length, (index) {
                            return dates[index]["isActive"]
                                ? Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: dates[index]
                                              ["labelController"],
                                          decoration: InputDecoration(
                                            labelText: 'Libellé de la date',
                                            filled: false,
                                            fillColor: Colors.transparent,
                                            labelStyle: TextStyle(
                                              fontFamily: 'Galey',
                                              fontWeight: FontWeight.w500,
                                              color:
                                                  Color.fromARGB(255, 0, 0, 0),
                                            ),
                                            enabledBorder: UnderlineInputBorder(
                                              borderSide: BorderSide(
                                                  color: Color.fromARGB(
                                                      255, 250, 192, 187)),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: TextFormField(
                                          controller: dates[index]
                                              ["dateController"],
                                          decoration: InputDecoration(
                                              filled: false,
                                              fillColor: Colors.transparent,
                                              labelStyle: TextStyle(
                                                fontFamily: 'Galey',
                                                fontWeight: FontWeight.w500,
                                                color: Color.fromARGB(
                                                    255, 0, 0, 0),
                                              ),
                                              enabledBorder:
                                                  UnderlineInputBorder(
                                                borderSide: BorderSide(
                                                    color: Color.fromARGB(
                                                        255, 250, 192, 187)),
                                              ),
                                              labelText:
                                                  'Date (dd/MM/yyyy) ${dates[index]["labelController"].text}'),
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.delete),
                                        onPressed: () {
                                          setState(() {
                                            dates[index]["isActive"] = false;
                                          });
                                        },
                                      ),
                                    ],
                                  )
                                : Container();
                          }),
                        )),
                    SizedBox(height: 20),
                    SizedBox(
                      width:
                          UTILS.calculWidth(372, UTILS.widthReference(context)),
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            dates.add({
                              "labelController": TextEditingController(),
                              "dateController": TextEditingController(),
                              "isActive": true,
                            });
                          });
                        },
                        child: Text(
                          'Ajouter une date',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Galey',
                            color: Color.fromARGB(255, 0, 0, 0),
                            fontWeight: FontWeight.w500,
                            fontSize: UTILS.calculWidth(
                                18, UTILS.widthReference(context)),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color.fromARGB(255, 252, 207, 200),
                        ),
                      ),
                    ),
                    ////Divider,
                    SizedBox(height: 20),

                    SizedBox(
                        width: UTILS.calculWidth(
                            355, UTILS.widthReference(context)),
                        child: TextFormField(
                          initialValue: devise,
                          decoration: InputDecoration(
                            labelText: 'Devise',
                            filled: false,
                            fillColor: Colors.transparent,
                            labelStyle: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Color.fromARGB(255, 0, 0, 0),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Color.fromARGB(255, 250, 192, 187)),
                            ),
                          ),
                          onSaved: (value) {
                            devise = value ?? '€';
                          },
                        )),
                    SizedBox(height: 20),

                    SwitchListTile(
                      title: Text('TVA'),
                      value: tvaActive,
                      onChanged: (value) {
                        setState(() {
                          tvaActive = value;
                        });
                      },
                    ),
                    if (tvaActive)
                      SizedBox(
                          width: UTILS.calculWidth(
                              355, UTILS.widthReference(context)),
                          child: TextFormField(
                            initialValue: tauxTVA.toString(),
                            decoration: InputDecoration(
                              labelText: 'Taux de TVA',
                              filled: false,
                              fillColor: Colors.transparent,
                              labelStyle: TextStyle(
                                fontFamily: 'Galey',
                                fontWeight: FontWeight.w500,
                                color: Color.fromARGB(255, 0, 0, 0),
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: Color.fromARGB(255, 250, 192, 187)),
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            onSaved: (value) {
                              tauxTVA = double.tryParse(value ?? '20') ?? 20.0;
                            },
                          )),
                    SizedBox(height: 20),
                    SizedBox(
                        width: UTILS.calculWidth(
                            355, UTILS.widthReference(context)),
                        child: TextFormField(
                          decoration: InputDecoration(
                            labelText: 'Informations complémentaires',
                            filled: false,
                            fillColor: Colors.transparent,
                            labelStyle: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Color.fromARGB(255, 0, 0, 0),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Color.fromARGB(255, 250, 192, 187)),
                            ),
                          ),
                          onChanged: (value) {
                            infoComplementaire = value;
                          },
                        )),
                    SizedBox(height: 20),
                    SizedBox(
                        width: UTILS.calculWidth(
                            355, UTILS.widthReference(context)),
                        child: TextFormField(
                          controller: modePaiementController,
                          decoration: InputDecoration(
                            labelText: 'Mode de paiement',
                            filled: false,
                            fillColor: Colors.transparent,
                            labelStyle: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Color.fromARGB(255, 0, 0, 0),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Color.fromARGB(255, 250, 192, 187)),
                            ),
                          ),
                        )),
                    ////Divider,
                  ]),
              SizedBox(height: 20),
              Center(
                  child: SizedBox(
                width: UTILS.calculWidth(372, UTILS.widthReference(context)),
                child: ElevatedButton(
                  onPressed: _enregistrerEtTelechargerFacture,
                  child: Text(
                    'Imprimer ou enregistrer la Facture',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Galey',
                      color: Color.fromARGB(255, 0, 0, 0),
                      fontWeight: FontWeight.w500,
                      fontSize:
                          UTILS.calculWidth(18, UTILS.widthReference(context)),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color.fromARGB(255, 252, 207, 200),
                  ),
                ),
              )),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownWithFlags() {
    return DropdownButtonFormField<Country>(
      value: selectedCountry,
      isExpanded: true,
      dropdownColor: Colors.pink[100], // Couleur de fond de la liste déroulante
      decoration: InputDecoration(
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Color.fromARGB(255, 250, 192, 187)),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Color.fromARGB(255, 250, 192, 187)),
        ),
        labelText: 'Pays',
        labelStyle: TextStyle(
          fontFamily: 'Galey',
          fontWeight: FontWeight.w500,
          color: Colors.black,
        ),
      ),
      icon: Icon(Icons.arrow_drop_down),
      onChanged: (Country? newValue) {
        setState(() {
          selectedCountry = newValue;
          codeISOClientController.text =
              newValue!.code; // Mettre à jour le code ISO
        });
      },
      items: countries.map<DropdownMenuItem<Country>>((Country country) {
        return DropdownMenuItem<Country>(
          value: country,
          child: Row(
            children: [
              Image.asset(
                'assets/country/${country.code.toLowerCase()}.png',
                width: 30,
                height: 20,
                errorBuilder: (context, error, stackTrace) => Icon(Icons.flag,
                    size: 30), // Icône par défaut si le drapeau est introuvable
              ),
              SizedBox(width: 10),
              Text('${country.name} (${country.dialCode})'),
            ],
          ),
        );
      }).toList(),
    );
  }
   Widget _buildDropdownWithFlagsEnterprise() {
    return DropdownButtonFormField<Country>(
      value: selectedCountry1,
      isExpanded: true,
      dropdownColor: Colors.pink[100], // Couleur de fond de la liste déroulante
      decoration: InputDecoration(
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Color.fromARGB(255, 250, 192, 187)),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Color.fromARGB(255, 250, 192, 187)),
        ),
        labelText: 'Pays',
        labelStyle: TextStyle(
          fontFamily: 'Galey',
          fontWeight: FontWeight.w500,
          color: Colors.black,
        ),
      ),
      icon: Icon(Icons.arrow_drop_down),
      onChanged: (Country? newValue) {
        setState(() {
          selectedCountry1 = newValue;
          codeISOClientController.text =
              newValue!.code; // Mettre à jour le code ISO
        });
      },
      items: countries.map<DropdownMenuItem<Country>>((Country country) {
        return DropdownMenuItem<Country>(
          value: country,
          child: Row(
            children: [
              Image.asset(
                'assets/country/${country.code.toLowerCase()}.png',
                width: 30,
                height: 20,
                errorBuilder: (context, error, stackTrace) => Icon(Icons.flag,
                    size: 30), // Icône par défaut si le drapeau est introuvable
              ),
              SizedBox(width: 10),
              Text('${country.name} (${country.dialCode})'),
            ],
          ),
        );
      }).toList(),
    );
  }
}
