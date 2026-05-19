import 'dart:convert';

import 'package:PetsMatch/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class ContratReservationPage extends StatefulWidget {
  @override
  _ContratReservationPageState createState() => _ContratReservationPageState();
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


class _ContratReservationPageState extends State<ContratReservationPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers pour les informations de l'éleveur et du client
  TextEditingController nomElevageController = TextEditingController();
  TextEditingController adresseElevageController = TextEditingController();
  final TextEditingController codeISOElevageController = TextEditingController();
  final TextEditingController codeISOClientController = TextEditingController();
  TextEditingController telephoneElevageController = TextEditingController();
  TextEditingController siretController = TextEditingController();
  TextEditingController numeroTVAController = TextEditingController();
  List<Country> countries = [];
  Country? selectedCountry;
  Country? selectedCountry1;
  TextEditingController nomClientController = TextEditingController();
  TextEditingController adresseClientController = TextEditingController();
  TextEditingController codePostalVilleController = TextEditingController();
  TextEditingController telephoneClientController = TextEditingController();
  TextEditingController emailClientController = TextEditingController();
  TextEditingController siretClientController = TextEditingController();

  TextEditingController numeroDossierController = TextEditingController();
  TextEditingController raceController = TextEditingController();
  TextEditingController apparenceRaceController = TextEditingController();

  TextEditingController dateController = TextEditingController();
  TextEditingController nomMediateurController = TextEditingController();

  String? logoUrl;
  bool isAnimalANaitre = false;
  String? selectedAnimal;
  DateTime? selectedDate;

  bool isLOF = false;
  bool isLOOF = false;

  // Nouvelles cases à cocher
  bool isNonInscritOrigine = false;
  bool isNonRace = false;
  bool isApparenceRace = false;
  bool _isUpdatingHT = false;
  bool _isUpdatingTTC = false;
  // Champs supplémentaires : sexe, couleur de robe, numéro de puce, informations complémentaires
  String? selectedSexe;
  TextEditingController couleurRobeController = TextEditingController();
  TextEditingController numeroPuceController = TextEditingController();
  TextEditingController infoComplementaireController = TextEditingController();

  // Champs pour le prix
  TextEditingController prixHTController = TextEditingController();
  TextEditingController prixTTCController = TextEditingController();
  TextEditingController tvaController =
      TextEditingController(text: "20.0"); // Par défaut 20%
  bool isTvaApplicable = false; // Si la TVA est applicable ou non

  // Champs pour le montant des arrhes
  TextEditingController arrhesController = TextEditingController();

  // Champs pour les dates de disponibilité
  TextEditingController disponibiliteDebutController = TextEditingController();
  TextEditingController disponibiliteFinController = TextEditingController();

  // Champ pour le nombre de mois (réservation reportable)
  TextEditingController nombreMoisController = TextEditingController();

  // Modes de paiement
  String? selectedPaymentMethod;
  TextEditingController chequeNumeroController = TextEditingController();
  TextEditingController chequeDateEncaissementController =
      TextEditingController();
  TextEditingController virementDateController = TextEditingController();
  // Nouveaux champs pour le lieu et la date
  TextEditingController lieuSignatureController = TextEditingController();
  TextEditingController dateSignatureController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    prixHTController.addListener(_onHTChanged);
    prixTTCController.addListener(_onTTCChanged);
    _loadUserData();
    _loadCountries();

  }

  @override
  void dispose() {
    // Retirer les écouteurs quand la page est détruite pour éviter les fuites de mémoire
    prixHTController.removeListener(_onHTChanged);
    prixTTCController.removeListener(_onTTCChanged);

    prixHTController.dispose();
    prixTTCController.dispose();
    super.dispose();
  }
  Future<void> _loadCountries() async {
    final String response =
        await rootBundle.loadString('assets/CountryCodes.json');
    final List<dynamic> data = json.decode(response);
    setState(() {
      countries = data.map((e) => Country.fromJson(e)).toList();
         // Si le code ISO est déjà défini, sélectionner le pays correspondant
      if (codeISOClientController.text.isNotEmpty) {
        selectedCountry1 = countries.firstWhere(
          (country) => country.code == codeISOClientController.text,
          orElse: () => countries[0],
        );
      } else {
        selectedCountry1 = countries[0]; // Valeur par défaut
        codeISOClientController.text = "+33";
      }
    });
  }
  // Fonction pour charger les informations de l'éleveur depuis Firebase
  Future<void> _loadUserData() async {
    final User? user = _auth.currentUser;
    if (user != null) {
      final String uid = user.uid;

      final DocumentSnapshot userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>?;
        if (data != null) {
          setState(() {
            nomElevageController.text = data['nameElevage'] ?? '';
            adresseElevageController.text = data['adressElevage'] ?? '';
            codeISOElevageController.text = data['codeISOElevage'] ?? '+33';
            telephoneElevageController.text = data['numeroElevage'] ?? '';
            siretController.text = data['siret'] ?? '';
            numeroTVAController.text = data['numeroTVA'] ?? '';
            logoUrl = data['profilePictureUrlElevage'] ?? '';
          });
        }
      }
       if (codeISOElevageController.text.isNotEmpty) {
        selectedCountry = countries.firstWhere(
          (country) => country.code == codeISOElevageController.text,
          orElse: () => countries[0],
        );
      } else {
        selectedCountry = countries[0]; // Valeur par défaut
      }
    }
  }

  // Fonction pour sélectionner une date pour les champs de disponibilité
  Future<void> _selectDate(
      BuildContext context, TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        controller.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  void _onHTChanged() {
    if (!_isUpdatingTTC &&
        isTvaApplicable &&
        prixHTController.text.isNotEmpty) {
      _isUpdatingHT = true;
      double prixHT = double.tryParse(prixHTController.text) ?? 0.0;
      double tva = double.tryParse(tvaController.text) ?? 20.0;
      double prixTTC = prixHT * (1 + tva / 100);
      prixTTCController.text = prixTTC.toStringAsFixed(2);
      _isUpdatingHT = false;
    }
  }

  // Fonction pour mettre à jour le prix HT lorsque le prix TTC change
  void _onTTCChanged() {
    if (!_isUpdatingHT &&
        isTvaApplicable &&
        prixTTCController.text.isNotEmpty) {
      _isUpdatingTTC = true;
      double prixTTC = double.tryParse(prixTTCController.text) ?? 0.0;
      double tva = double.tryParse(tvaController.text) ?? 20.0;
      double prixHT = prixTTC / (1 + tva / 100);
      prixHTController.text = prixHT.toStringAsFixed(2);
      _isUpdatingTTC = false;
    }
  }

// Fonction pour sélectionner une date avec un minimum de 8 jours dans le futur
  Future<void> _selectDateWithMinimumDays(
      BuildContext context, TextEditingController controller) async {
    // La date actuelle + 8 jours
    final DateTime minDate = DateTime.now().add(Duration(days: 8));

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: minDate,
      firstDate: minDate, // Empêche la sélection d'une date avant le minDate
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        controller.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  // Fonction pour générer le PDF avec les informations fournies
  Future<void> _generateReservationContractPdf() async {
    final pdf = pw.Document();
    Uint8List? logoBytes;

    // Calculer la date de retour sous 8 jours
    final DateTime retourDate = DateTime.now().add(Duration(days: 8));
    final String retourDateFormatted =
        DateFormat('dd/MM/yyyy').format(retourDate);

    // Télécharger le logo de l'éleveur si disponible
    if (logoUrl != null && logoUrl!.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(logoUrl!));
        if (response.statusCode == 200) {
          logoBytes = response.bodyBytes;
        }
      } catch (e) {
        print('Erreur lors du téléchargement du logo: $e');
      }
    }

    // Charger le logo de PetsMatch depuis les assets
    final petsMatchLogo = pw.MemoryImage(
        (await rootBundle.load("assets/logofacture.png")).buffer.asUint8List());
    final font = await PdfGoogleFonts.robotoRegular();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              pw.Center(
                child: pw.Opacity(
                  opacity: 0.2,
                  child: pw.Image(petsMatchLogo, width: 400, height: 400),
                ),
              ),
              pw.SizedBox(height: 0),

              // Footer avec logo et informations de contact
              pw.Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    // Logo en bas à gauche
                    pw.Image(
                      petsMatchLogo,
                      width: 50,
                      height: 50,
                    ),
                    // Informations de contact en bas à droite
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          "Édité par PETSMATCH",
                          style: pw.TextStyle(
                            fontSize: 8,
                            font: font,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          "Société par Actions Simplifiée (SAS) déclarée conformément au Code du travail",
                          style: pw.TextStyle(fontSize: 7, font: font),
                        ),
                        pw.Text(
                          "15 la ville marchand - 22210 PLUMIEUX - Tél 07 81 03 49 84",
                          style: pw.TextStyle(fontSize: 7, font: font),
                        ),
                        pw.Text(
                          "petsmatch.contact@gmail.com - www.petsmatchapp.com",
                          style: pw.TextStyle(fontSize: 7, font: font),
                        ),
                        pw.Text(
                          "N° SIRET 93134481600018 - NAF 7010Z",
                          style: pw.TextStyle(fontSize: 7, font: font),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (logoBytes != null)
                        pw.Image(pw.MemoryImage(logoBytes!),
                            width: 70, height: 70),
                      pw.SizedBox(width: 20),
                      pw.Expanded(
                        flex: 2,
                        child: _buildEleveurInfo(font),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Text(
                              "CONTRAT",
                              style: pw.TextStyle(
                                fontSize: 24,
                                fontWeight: pw.FontWeight.bold,
                                font: font,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                            pw.Text(
                              "DE",
                              style: pw.TextStyle(
                                fontSize: 18,
                                font: font,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                            pw.Text(
                              "RÉSERVATION",
                              style: pw.TextStyle(
                                fontSize: 20,
                                fontWeight: pw.FontWeight.bold,
                                font: font,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 20),
                  _buildClientInfo(font),
                  pw.SizedBox(height: 15),
                  pw.Text(
                    "Soumet la réservation d'un ${selectedAnimal ?? '..................................'} Né(e) le ${isAnimalANaitre ? 'À naître' : (selectedDate != null ? DateFormat('dd/MM/yyyy').format(selectedDate!) : '.................')}",
                    style: pw.TextStyle(
                      fontSize: 8,
                      font: font,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  // Sexe de l'animal
                  pw.Row(
                    children: [
                      pw.Text(
                        "Sexe: ",
                        style: pw.TextStyle(
                          fontSize: 8,
                          font: font,
                        ),
                      ),
                      pw.Container(
                        width: 7,
                        height: 7,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(),
                        ),
                        child: selectedSexe == "M"
                            ? pw.Center(
                                child: pw.Text(
                                'X',
                                style: pw.TextStyle(
                                  fontSize: 7,
                                  font: font,
                                ),
                              ))
                            : pw.Container(),
                      ),
                      pw.Text(
                        "  Mâle",
                        style: pw.TextStyle(
                          fontSize: 8,
                          font: font,
                        ),
                      ),
                      pw.SizedBox(width: 20),
                      pw.Container(
                        width: 7,
                        height: 7,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(),
                        ),
                        child: selectedSexe == "F"
                            ? pw.Center(
                                child: pw.Text(
                                'X',
                                style: pw.TextStyle(
                                  fontSize: 7,
                                  font: font,
                                ),
                              ))
                            : pw.Container(),
                      ),
                      pw.Text(
                        "  Femelle",
                        style: pw.TextStyle(
                          fontSize: 8,
                          font: font,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 5),
                  // Couleur de la robe
                  pw.Text(
                    "Couleur de la Robe: ${couleurRobeController.text.isNotEmpty ? couleurRobeController.text : '....................................................................'}",
                    style: pw.TextStyle(font: font, fontSize: 8),
                  ),
                  pw.SizedBox(height: 5),
                  // Numéro de puce
                  pw.Text(
                    "Identifié(e) par le numéro de puce: ${numeroPuceController.text.isNotEmpty ? numeroPuceController.text : '....................................................................'}",
                    style: pw.TextStyle(font: font, fontSize: 8),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Row(
                    children: [
                      pw.Text(
                        "LOF: ",
                        style: pw.TextStyle(
                          fontSize: 8,
                          font: font,
                        ),
                      ),
                      pw.Container(
                        width: 7,
                        height: 7,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(),
                        ),
                        child: isLOF
                            ? pw.Center(
                                child: pw.Text(
                                'X',
                                style: pw.TextStyle(
                                  fontSize: 7,
                                  font: font,
                                ),
                              ))
                            : pw.Container(),
                      ),
                      pw.SizedBox(width: 20),
                      pw.Text(
                        "LOOF: ",
                        style: pw.TextStyle(
                          fontSize: 8,
                          font: font,
                        ),
                      ),
                      pw.Container(
                        width: 7,
                        height: 7,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(),
                        ),
                        child: isLOOF
                            ? pw.Center(
                                child: pw.Text(
                                'X',
                                style: pw.TextStyle(
                                  fontSize: 7,
                                  font: font,
                                ),
                              ))
                            : pw.Container(),
                      ),
                      pw.SizedBox(width: 20),
                      pw.Text(
                        "(Ce chien/chat est/sera de race car inscrit au Livre des Origines Français ou au Livre Officiel des Origines Félines)",
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontStyle: pw.FontStyle.italic,
                          font: font,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text(
                    "Dossier n°: ${numeroDossierController.text.isNotEmpty ? numeroDossierController.text : '....................................................................'}",
                    style: pw.TextStyle(font: font, fontSize: 8),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text(
                    "Race: ${raceController.text.isNotEmpty ? raceController.text : '....................................................................'}",
                    style: pw.TextStyle(font: font, fontSize: 8),
                  ),
                  pw.SizedBox(height: 5),

                  // Informations complémentaires

                  pw.Row(
                    children: [
                      pw.Container(
                        width: 7,
                        height: 7,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(),
                        ),
                        child: isNonInscritOrigine
                            ? pw.Center(
                                child: pw.Text(
                                'X',
                                style: pw.TextStyle(
                                  fontSize: 7,
                                  font: font,
                                ),
                              ))
                            : pw.Container(),
                      ),
                      pw.Text(
                        " Non inscrit à un Livre des origines: ",
                        style: pw.TextStyle(
                          fontSize: 8,
                          font: font,
                        ),
                      ),
                      pw.SizedBox(width: 20),
                      pw.Container(
                        width: 7,
                        height: 7,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(),
                        ),
                        child: isNonRace
                            ? pw.Center(
                                child: pw.Text(
                                'X',
                                style: pw.TextStyle(
                                  fontSize: 7,
                                  font: font,
                                ),
                              ))
                            : pw.Container(),
                      ),
                      pw.Text(
                        " N'appartient pas à une race: ",
                        style: pw.TextStyle(
                          fontSize: 8,
                          font: font,
                        ),
                      ),
                      pw.SizedBox(width: 20),
                      pw.Container(
                        width: 7,
                        height: 7,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(),
                        ),
                        child: isApparenceRace
                            ? pw.Center(
                                child: pw.Text(
                                'X',
                                style: pw.TextStyle(
                                  fontSize: 7,
                                  font: font,
                                ),
                              ))
                            : pw.Container(),
                      ),
                      pw.Text(
                        " Apparence de race: ",
                        style: pw.TextStyle(
                          fontSize: 8,
                          font: font,
                        ),
                      ),
                      if (isApparenceRace)
                        pw.Text(
                          " ${apparenceRaceController.text.isNotEmpty ? apparenceRaceController.text : '....................................................................'}",
                          style: pw.TextStyle(font: font, fontSize: 8),
                        ),
                    ],
                  ),
                  pw.SizedBox(height: 5),

                  pw.Text(
                    "Informations complémentaires: ${infoComplementaireController.text.isNotEmpty ? infoComplementaireController.text : '.......................................................................................................................................................................................................................................................................................'}",
                    style: pw.TextStyle(font: font, fontSize: 8),
                  ),
                  pw.SizedBox(height: 15),

                  // Affichage du prix
                  _buildPrixSection(font),
                  pw.SizedBox(height: 5),

                  // Mention légale
                  pw.Text(
                    "Pas d'escompte en cas de paiement anticipé (Article L 441-9 du code du commerce).",
                    style: pw.TextStyle(font: font, fontSize: 8),
                  ),
                  pw.SizedBox(height: 5),

                  // Montant des arrhes
                  pw.Text(
                    "Je m'engage à verser à titre d'arrhes la somme de ${arrhesController.text.isNotEmpty ? arrhesController.text : '....................................................................'} €.",
                    style: pw.TextStyle(font: font, fontSize: 8),
                  ),

                  // Mode de paiement
                  _buildPaymentMethodSection(font),

                  pw.SizedBox(height: 5),

                  // Date de disponibilité
                  pw.Text(
                    "Date de disponibilité*: du ${disponibiliteDebutController.text.isNotEmpty ? disponibiliteDebutController.text : '.................'} au ${disponibiliteFinController.text.isNotEmpty ? disponibiliteFinController.text : '.................'} (date butoir) (article L.1657 du code civil).",
                    style: pw.TextStyle(font: font, fontSize: 8),
                  ),

                  // Texte associé à l'étoile
                  pw.SizedBox(height: 5),
                  pw.Text(
                    "*A défaut de solde payé ou d'enlèvement du chiot/chaton à cette échéance, l'acheteur sera considéré comme renonçant à l'achat et les arrhes seront acquises au vendeur sans autre formalité.",
                    style: pw.TextStyle(
                        font: font,
                        fontSize: 8,
                        fontStyle: pw.FontStyle.italic),
                  ),

                  // CONDITIONS GÉNÉRALES DE RÉSERVATION (encadré gris)
                  pw.SizedBox(height: 5),
                  pw.Container(
                    padding: pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                          color: PdfColors.black), // Bordure noire
                      color: PdfColors.grey, // Fond gris clair
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          "CONDITIONS GÉNÉRALES DE RÉSERVATION :",
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            font: font,
                            fontSize: 8,
                            color: PdfColors.black, // Texte en noir
                          ),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          "Animal destiné à usage de compagnie et d'agrément conformément à l'article L. 214-6 du code rural.",
                          style: pw.TextStyle(
                              font: font, fontSize: 7, color: PdfColors.black),
                        ),
                        pw.Text(
                          "Arrhes : somme versée d'avance pour la réservation d'un chiot/chaton.",
                          style: pw.TextStyle(
                              font: font, fontSize: 7, color: PdfColors.black),
                        ),
                        pw.Text(
                          "Le droit de rétractation n'est pas applicable dans le cadre de la présente réservation.",
                          style: pw.TextStyle(
                              font: font, fontSize: 7, color: PdfColors.black),
                        ),
                        pw.Text(
                          "En cas d'annulation de la réservation à l'initiative de l'acquéreur, les arrhes sont conservées par le vendeur (article L.214-1 du code de la consommation).",
                          style: pw.TextStyle(
                              font: font, fontSize: 7, color: PdfColors.black),
                        ),
                        pw.Text(
                          "L'acquéreur accepte, au regard du fait que la réservation porte sur un être vivant, que cette réservation puisse faire l'objet d'un report d'une portée à une autre dans la limite de ${nombreMoisController.text.isNotEmpty ? nombreMoisController.text : '.................'} mois à compter de la date apposée sur cet acte.",
                          style: pw.TextStyle(
                              font: font, fontSize: 7, color: PdfColors.black),
                        ),
                        pw.Text(
                          "En cas de problème sur la portée initialement prévue, le vendeur s'engage à prévenir rapidement l'acquéreur.",
                          style: pw.TextStyle(
                              font: font, fontSize: 7, color: PdfColors.black),
                        ),
                        pw.Text(
                          "Par dérogation aux dispositions de l'article 1583 du code civil, la vente ne sera considérée comme parfaite qu'au jour de la signature du contrat de vente et de la remise concomitante de l'animal.",
                          style: pw.TextStyle(
                              font: font, fontSize: 7, color: PdfColors.black),
                        ),
                        pw.Text(
                          "Cette vente future sera régie par les seules dispositions des articles L.213-1 et suivants du code rural.",
                          style: pw.TextStyle(
                              font: font, fontSize: 7, color: PdfColors.black),
                        ),
                        pw.Text(
                          "Validité : le présent bon de réservation, accompagné du versement des arrhes, doit être renvoyé au vendeur sous 8 jours, sous peine de nullité.",
                          style: pw.TextStyle(
                              font: font, fontSize: 7, color: PdfColors.black),
                        ),
                      ],
                    ),
                  ),

                  // Texte concernant le médiateur
                  pw.SizedBox(height: 5),
                  pw.Text(
                    "Dans le cadre de l'obligation de désignation d'un médiateur, le vendeur désigne le médiateur : ${nomMediateurController.text.isNotEmpty ? nomMediateurController.text : '........................'}",
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 8, // Police de taille 8
                      color: PdfColors.black,
                    ),
                  ),

                  // Phrase ajoutée pour la date de retour du contrat
                  pw.SizedBox(height: 5),
                  // Utilisez la date sélectionnée dans le champ du formulaire
                  pw.Text(
                    "Le contrat doit être retourné signé avant le ${disponibiliteDebutController.text.isNotEmpty ? disponibiliteDebutController.text : '..............'} (sous 8 jours) sous peine de nullité.",
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 8,
                      color: PdfColors.black,
                    ),
                  ),
                  pw.SizedBox(height: 5),

                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment
                        .center, // Centre le contenu de la row
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment
                            .center, // Centre le texte de la colonne
                        children: [
                          pw.Text(
                            "Signature du vendeur",
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 10,
                              font: font,
                            ),
                          ),
                          pw.SizedBox(
                              height:
                                  20), // Compense la hauteur de la mention manuscrite
                        ],
                      ),
                      pw.SizedBox(
                          width:
                              100), // Ajoute un espacement entre les deux signatures

                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment
                            .center, // Centre le texte de la colonne
                        children: [
                          pw.Text(
                            "Signature de l'acquéreur",
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 10,
                              font: font,
                            ),
                          ),
                          pw.SizedBox(
                              height:
                                  5), // Ajoute un espace avant la mention manuscrite
                          pw.Text(
                            "Mention manuscrite < Bon pour accord. Lu, approuvé et compris >\n- Ne pas oublier de parapher au verso",
                            style: pw.TextStyle(
                              font: font,
                              fontSize:
                                  6, // Police de taille 6 pour cette mention
                            ),
                            textAlign: pw.TextAlign
                                .center, // Centre le texte de la mention manuscrite
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
    final ByteData imageData =
        await rootBundle.load('assets/loi-contrat-reservation.png');
    final Uint8List imageBytes = imageData.buffer.asUint8List();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(
              pw.MemoryImage(imageBytes),
              fit: pw.BoxFit.cover, // L'image recouvre toute la page
            ),
          );
        },
      ),
    );
    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save());
  }

  // Fonction pour afficher les informations du prix dans le PDF
  pw.Widget _buildPrixSection(pw.Font font) {
    double prixHT = double.tryParse(prixHTController.text) ?? 0.0;
    double prixTTC = double.tryParse(prixTTCController.text) ?? 0.0;
    double tva = double.tryParse(tvaController.text) ?? 20.0;

    if (isTvaApplicable) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            "Dont le prix a été fixé à $prixHT € HT + ${prixTTC - prixHT} € de TVA (${tva.toStringAsFixed(2)}%) = $prixTTC € T.T.C.",
            style: pw.TextStyle(font: font, fontSize: 8),
          ),
        ],
      );
    } else {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            "Dont le prix a été fixé à $prixHT € NET (TVA non applicable, article 293 B du Code général des impôts).",
            style: pw.TextStyle(font: font, fontSize: 8),
          ),
        ],
      );
    }
  }

  // Fonction pour afficher les informations de l'éleveur dans le PDF
  pw.Widget _buildEleveurInfo(pw.Font font) {
    List<pw.Widget> eleveurWidgets = [];

    if (nomElevageController.text.isNotEmpty) {
      eleveurWidgets.add(
          pw.Text(nomElevageController.text, style: pw.TextStyle(font: font)));
    }
    if (adresseElevageController.text.isNotEmpty) {
      eleveurWidgets.add(pw.Text(adresseElevageController.text,
          style: pw.TextStyle(font: font)));
    }
    if (codeISOElevageController.text.isNotEmpty &&
        telephoneElevageController.text.isNotEmpty) {
      eleveurWidgets.add(pw.Text(
          '${codeISOElevageController.text} ${telephoneElevageController.text}',
          style: pw.TextStyle(font: font)));
    }
    if (siretController.text.isNotEmpty) {
      eleveurWidgets.add(pw.Text('SIRET: ${siretController.text}',
          style: pw.TextStyle(font: font)));
    }
    if (numeroTVAController.text.isNotEmpty) {
      eleveurWidgets.add(pw.Text('TVA: ${numeroTVAController.text}',
          style: pw.TextStyle(font: font)));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: eleveurWidgets,
    );
  }

  // Fonction pour afficher les informations du client dans le PDF
  pw.Widget _buildClientInfo(pw.Font font) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildLineWithText(
            "Je soussigné(e) ",
            nomClientController.text.isNotEmpty
                ? nomClientController.text
                : '........................................',
            font),
        pw.SizedBox(height: 5),
        _buildLineWithText(
            "Adresse",
            adresseClientController.text.isNotEmpty
                ? adresseClientController.text
                : '........................................',
            font),
        pw.SizedBox(height: 5),
        _buildLineWithText(
            "Code Postal et Ville",
            codePostalVilleController.text.isNotEmpty
                ? codePostalVilleController.text
                : '........................................',
            font),
        pw.SizedBox(height: 5),
        pw.Row(
          children: [
         _buildLineWithText(
              "Téléphone",
              codeISOClientController.text.isNotEmpty
                  ? "${codeISOClientController.text} ${telephoneClientController.text}"
                  : '...................................................',
              font,
            ),

            pw.SizedBox(width: 20),
            _buildLineWithText(
                "Email",
                emailClientController.text.isNotEmpty
                    ? emailClientController.text
                    : '................................................................',
                font),
          ],
        ),
        pw.SizedBox(height: 5),
        _buildLineWithText(
            "SIRET (si professionel)",
            siretClientController.text.isNotEmpty
                ? siretClientController.text
                : '........................................',
            font),
      ],
    );
  }

  // Fonction pour formater une ligne de texte dans le PDF avec un label et une donnée
  pw.Widget _buildLineWithText(String label, String value, pw.Font font) {
    return pw.Row(
      children: [
        pw.Text("$label: ",
            style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold, font: font, fontSize: 8)),
        pw.Text(value, style: pw.TextStyle(font: font, fontSize: 8)),
      ],
    );
  }

  // Fonction pour afficher la section du mode de paiement dans le PDF
  pw.Widget _buildPaymentMethodSection(pw.Font font) {
    if (selectedPaymentMethod == "carte" || selectedPaymentMethod == "espece") {
      return pw.Text(
        "Mode de paiement: ${selectedPaymentMethod == "carte" ? "Carte bancaire" : "Espèces"}",
        style: pw.TextStyle(font: font, fontSize: 8),
      );
    } else if (selectedPaymentMethod == "cheque_reception") {
      return pw.Text(
        "Mode de paiement: Chèque n°${chequeNumeroController.text} encaissé à réception.",
        style: pw.TextStyle(font: font, fontSize: 8),
      );
    } else if (selectedPaymentMethod == "cheque_delai") {
      return pw.Text(
        "Mode de paiement: Chèque n°${chequeNumeroController.text} à encaisser le ${chequeDateEncaissementController.text} (dans un délai inférieur à 6 mois).",
        style: pw.TextStyle(font: font, fontSize: 8),
      );
    } else if (selectedPaymentMethod == "virement") {
      return pw.Text(
        "Mode de paiement: Virement bancaire à effectuer avant le ${virementDateController.text} sous peine de nullité de la réservation.",
        style: pw.TextStyle(font: font, fontSize: 8),
      );
    }
    return pw.Container();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(title: Text('Contrat de Réservation')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(0.0),
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
              color: const Color(0xFFA7C79A),
              colorBlendMode: BlendMode.srcIn,
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
                          'CONTRAT DE RÉSERVATION',
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

              // Menu déroulant pour les informations de l'éleveur
              ExpansionTile(
                title: Text(
                  "Informations Éleveur",
                  style: TextStyle(
                      fontSize:
                          UTILS.calculWidth(25, UTILS.widthReference(context)),
                      fontFamily: 'Galey',
                      color: const Color(0xFF0C5C6C),
                      fontWeight: FontWeight.w500),
                ),
                initiallyExpanded: true,
                children: <Widget>[
                  _buildTextField("Nom de l'élevage", nomElevageController),
                  _buildTextField("Adresse", adresseElevageController),
                  // _buildTextField("Code ISO", codeISOElevageController),
                    SizedBox(
                      width:
                          UTILS.calculWidth(355, UTILS.widthReference(context)),
                      child: _buildDropdownWithFlagsEnterprise(),
                    ),
                  _buildTextField("Téléphone", telephoneElevageController),
                  _buildTextField("SIRET", siretController),
                  _buildTextField("Numéro de TVA", numeroTVAController),
                ],
              ),
              //Divider,
              ExpansionTile(
                title: Text(
                  "Information Client",
                  style: TextStyle(
                      fontSize:
                          UTILS.calculWidth(25, UTILS.widthReference(context)),
                      fontFamily: 'Galey',
                      color: const Color(0xFF0C5C6C),
                      fontWeight: FontWeight.w500),
                ),
                initiallyExpanded: false,
                children: <Widget>[
                  _buildTextField(
                      "Nom et prénom du client", nomClientController),
                  _buildTextField("Adresse du client", adresseClientController),
                  _buildTextField(
                      "Code Postal et Ville", codePostalVilleController),
                  SizedBox(
                      width:
                          UTILS.calculWidth(355, UTILS.widthReference(context)),
                      child: _buildDropdownWithFlagsClient(),
                  ),
                  _buildTextField(
                      "Téléphone du client", telephoneClientController),
                  _buildTextField("Email du client", emailClientController),
                  _buildTextField(
                      "SIRET (si Professionnel)", siretClientController),
                ],
              ),
              // Formulaire pour les informations du client

              //Divider,
              ExpansionTile(
                title: Text(
                  "Informations Réservation",
                  style: TextStyle(
                      fontSize:
                          UTILS.calculWidth(25, UTILS.widthReference(context)),
                      fontFamily: 'Galey',
                      color: const Color(0xFF0C5C6C),
                      fontWeight: FontWeight.w500),
                ),
                initiallyExpanded: false,
                children: <Widget>[
                  SizedBox(height: 20),
                  Text("Informations de l'animal",
                      style: TextStyle(
                          fontSize: UTILS.calculWidth(
                              18, UTILS.widthReference(context)),
                          fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          activeColor: Color(0xFFA7C79A),
                          title: Text("Chien"),
                          value: selectedAnimal == "chien",
                          onChanged: (value) {
                            setState(() {
                              selectedAnimal = value == true ? "chien" : null;
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: CheckboxListTile(
                          activeColor: Color(0xFFA7C79A),
                          title: Text("Chiot"),
                          value: selectedAnimal == "chiot",
                          onChanged: (value) {
                            setState(() {
                              selectedAnimal = value == true ? "chiot" : null;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          activeColor: Color(0xFFA7C79A),
                          title: Text("Chat"),
                          value: selectedAnimal == "chat",
                          onChanged: (value) {
                            setState(() {
                              selectedAnimal = value == true ? "chat" : null;
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: CheckboxListTile(
                          activeColor: Color(0xFFA7C79A),
                          title: Text("Chaton"),
                          value: selectedAnimal == "chaton",
                          onChanged: (value) {
                            setState(() {
                              selectedAnimal = value == true ? "chaton" : null;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  //Divider,

                  // Né(e) le / À naître
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          activeColor: Color(0xFFA7C79A),
                          title: Text("Né(e) le"),
                          value: !isAnimalANaitre,
                          onChanged: (value) {
                            setState(() {
                              isAnimalANaitre = !(value == true);
                              if (!isAnimalANaitre) {
                                _selectDate(context, dateController);
                              } else {
                                dateController.clear();
                              }
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: CheckboxListTile(
                          activeColor: Color(0xFFA7C79A),
                          title: Text("À naître"),
                          value: isAnimalANaitre,
                          onChanged: (value) {
                            setState(() {
                              isAnimalANaitre = value == true;
                              if (isAnimalANaitre) {
                                dateController.clear();
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  // Champ de sélection de la date
                  if (!isAnimalANaitre)
                    SizedBox(
                        width: UTILS.calculWidth(
                            355, UTILS.widthReference(context)),
                        child: TextFormField(
                          controller: dateController,
                          decoration: InputDecoration(
                            labelText: "Date de naissance",
                            hintText: 'JJ/MM/AAAA',
                            filled: false,
                            fillColor: const Color.fromARGB(0, 2, 1, 1),
                            labelStyle: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Color.fromARGB(255, 0, 0, 0),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Color(0xFFA7C79A)),
                            ),
                          ),
                          readOnly: true,
                          onTap: () => _selectDate(context, dateController),
                        )),

                  //Divider,

                  // Cases à cocher LOF et LOOF
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          activeColor: Color(0xFFA7C79A),
                          title: Text("LOF"),
                          value: isLOF,
                          onChanged: (value) {
                            setState(() {
                              isLOF = value ?? false;
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: CheckboxListTile(
                          activeColor: Color(0xFFA7C79A),
                          title: Text("LOOF"),
                          value: isLOOF,
                          onChanged: (value) {
                            setState(() {
                              isLOOF = value ?? false;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  //Divider,

                  // Numéro de dossier et race
                  _buildTextField("Numéro de dossier", numeroDossierController),
                  _buildTextField("Race de l'animal", raceController),

                  //Divider,

                  // Trois nouvelles cases
                  CheckboxListTile(
                    activeColor: Color(0xFFA7C79A),
                    title: Text("Non inscrit à un Livre des origines"),
                    value: isNonInscritOrigine,
                    onChanged: (value) {
                      setState(() {
                        isNonInscritOrigine = value ?? false;
                      });
                    },
                  ),
                  CheckboxListTile(
                    activeColor: Color(0xFFA7C79A),
                    title: Text("N'appartient pas à une race"),
                    value: isNonRace,
                    onChanged: (value) {
                      setState(() {
                        isNonRace = value ?? false;
                      });
                    },
                  ),
                  CheckboxListTile(
                    activeColor: Color(0xFFA7C79A),
                    title: Text("Apparence de race"),
                    value: isApparenceRace,
                    onChanged: (value) {
                      setState(() {
                        isApparenceRace = value ?? false;
                      });
                    },
                  ),
                  if (isApparenceRace)
                    _buildTextField(
                        "Race (si apparence)", apparenceRaceController),

                  // Sélection du sexe de l'animal

                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          activeColor: Color(0xFFA7C79A),
                          title: Text("Mâle"),
                          value: selectedSexe == "M",
                          onChanged: (value) {
                            setState(() {
                              selectedSexe = value == true ? "M" : null;
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: CheckboxListTile(
                          activeColor: Color(0xFFA7C79A),
                          title: Text("Femelle"),
                          value: selectedSexe == "F",
                          onChanged: (value) {
                            setState(() {
                              selectedSexe = value == true ? "F" : null;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  //Divider,

                  // Couleur de la robe
                  _buildTextField("Couleur de la Robe", couleurRobeController),
                  //Divider,

                  // Numéro de puce
                  _buildTextField("Identifié(e) par le numéro de puce",
                      numeroPuceController),
                  //Divider,

                  // Informations complémentaires
                  _buildTextField("Informations complémentaires",
                      infoComplementaireController),

                  //Divider,

                  // Champs pour la gestion du prix HT et TTC
                  SizedBox(height: 20),

                  Text("Prix de la réservation",
                      style: TextStyle(
                          fontSize: UTILS.calculWidth(
                              18, UTILS.widthReference(context)),
                          fontWeight: FontWeight.bold)),

                  // Champ Prix HT
                  _buildTextField("Prix HT", prixHTController),

                  // Champ Prix TTC, uniquement si TVA est applicable
                  if (isTvaApplicable)
                    _buildTextField("Prix TTC", prixTTCController),

                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          activeColor: Color(0xFFA7C79A),
                          title: Text("TVA applicable"),
                          value: isTvaApplicable,
                          onChanged: (value) {
                            setState(() {
                              isTvaApplicable = value ?? false;
                              if (!isTvaApplicable) {
                                prixTTCController.clear();
                                tvaController.text = ""; // Retirer la TVA
                              } else {
                                tvaController.text = "20.0"; // Par défaut 20%
                                _onHTChanged(); // Recalcule le TTC avec le taux de TVA par défaut
                              }
                            });
                          },
                        ),
                      ),

                      // Champ Pourcentage TVA, uniquement si TVA est applicable
                      if (isTvaApplicable)
                        Expanded(
                          child: _buildTextField(
                              "Pourcentage de TVA (%)", tvaController),
                        ),
                    ],
                  ),

                  //Divider,
                  SizedBox(height: 20),

                  // Mention légale
                  Text("Arrhes",
                      style: TextStyle(
                          fontSize: UTILS.calculWidth(
                              18, UTILS.widthReference(context)),
                          fontWeight: FontWeight.bold)),

                  // Montant des arrhes
                  _buildTextField("Montant des arrhes (€)", arrhesController),

                  //Divider,
                  SizedBox(height: 20),

                  // Modes de paiement
                  Text("Mode de paiement:",
                      style: TextStyle(
                          fontSize: UTILS.calculWidth(
                              18, UTILS.widthReference(context)),
                          fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          activeColor: Color(0xFFA7C79A),
                          title: Text("Par carte bancaire"),
                          value: selectedPaymentMethod == "carte",
                          onChanged: (value) {
                            setState(() {
                              selectedPaymentMethod =
                                  value == true ? "carte" : null;
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: CheckboxListTile(
                          activeColor: Color(0xFFA7C79A),
                          title: Text("En espèces"),
                          value: selectedPaymentMethod == "espece",
                          onChanged: (value) {
                            setState(() {
                              selectedPaymentMethod =
                                  value == true ? "espece" : null;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  CheckboxListTile(
                    activeColor: Color(0xFFA7C79A),
                    title: Text("Par chèque n°........ encaissé à réception"),
                    value: selectedPaymentMethod == "cheque_reception",
                    onChanged: (value) {
                      setState(() {
                        selectedPaymentMethod =
                            value == true ? "cheque_reception" : null;
                      });
                    },
                  ),
                  if (selectedPaymentMethod == "cheque_reception")
                    _buildTextField("Numéro de chèque", chequeNumeroController),
                  CheckboxListTile(
                    activeColor: Color(0xFFA7C79A),
                    title: Text(
                        "Par chèque n°........ à encaisser le ....... (dans un délai inférieur à 6 mois)"),
                    value: selectedPaymentMethod == "cheque_delai",
                    onChanged: (value) {
                      setState(() {
                        selectedPaymentMethod =
                            value == true ? "cheque_delai" : null;
                      });
                    },
                  ),
                  if (selectedPaymentMethod == "cheque_delai") ...[
                    _buildTextField("Numéro de chèque", chequeNumeroController),
                    SizedBox(
                        width: UTILS.calculWidth(
                            355, UTILS.widthReference(context)),
                        child: TextFormField(
                          controller: chequeDateEncaissementController,
                          decoration: InputDecoration(
                            labelText: "Date d'encaissement",
                            hintText: 'JJ/MM/AAAA',
                            filled: false,
                            fillColor: const Color.fromARGB(0, 2, 1, 1),
                            labelStyle: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Color.fromARGB(255, 0, 0, 0),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Color(0xFFA7C79A)),
                            ),
                          ),
                          readOnly: true,
                          onTap: () => _selectDate(
                              context, chequeDateEncaissementController),
                        )),
                  ],
                  CheckboxListTile(
                    activeColor: Color(0xFFA7C79A),
                    title: Text(
                        "Par virement bancaire effectué avant le ....... sous peine de nullité de la réservation"),
                    value: selectedPaymentMethod == "virement",
                    onChanged: (value) {
                      setState(() {
                        selectedPaymentMethod =
                            value == true ? "virement" : null;
                      });
                    },
                  ),
                  if (selectedPaymentMethod == "virement")
                    SizedBox(
                        width: UTILS.calculWidth(
                            355, UTILS.widthReference(context)),
                        child: TextFormField(
                          controller: virementDateController,
                          decoration: InputDecoration(
                            labelText: "Date du virement",
                            hintText: 'JJ/MM/AAAA',
                            filled: false,
                            fillColor: const Color.fromARGB(0, 2, 1, 1),
                            labelStyle: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Color.fromARGB(255, 0, 0, 0),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Color(0xFFA7C79A)),
                            ),
                          ),
                          readOnly: true,
                          onTap: () =>
                              _selectDate(context, virementDateController),
                        )),

                  //Divider,
                  SizedBox(height: 20),

                  // Dates de disponibilité
                  Text("Date de disponibilité",
                      style: TextStyle(
                          fontSize: UTILS.calculWidth(
                              18, UTILS.widthReference(context)),
                          fontWeight: FontWeight.bold)),
                  SizedBox(
                      width:
                          UTILS.calculWidth(355, UTILS.widthReference(context)),
                      child: TextFormField(
                        controller: disponibiliteDebutController,
                        decoration: InputDecoration(
                          labelText: "Date de début",
                          hintText: 'JJ/MM/AAAA',
                          filled: false,
                          fillColor: const Color.fromARGB(0, 2, 1, 1),
                          labelStyle: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            color: Color.fromARGB(255, 0, 0, 0),
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: Color(0xFFA7C79A)),
                          ),
                        ),
                        readOnly: true,
                        onTap: () =>
                            _selectDate(context, disponibiliteDebutController),
                      )),
                  SizedBox(
                      width:
                          UTILS.calculWidth(355, UTILS.widthReference(context)),
                      child: TextFormField(
                        controller: disponibiliteFinController,
                        decoration: InputDecoration(
                          labelText: "Date butoir",
                          hintText: 'JJ/MM/AAAA',
                          filled: false,
                          fillColor: const Color.fromARGB(0, 2, 1, 1),
                          labelStyle: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            color: Color.fromARGB(255, 0, 0, 0),
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: Color(0xFFA7C79A)),
                          ),
                        ),
                        readOnly: true,
                        onTap: () =>
                            _selectDate(context, disponibiliteFinController),
                      )),

                  // Champ pour le nombre de mois pour le report de réservation
                  _buildTextField("Nombre de mois pour report de réservation",
                      nombreMoisController),
                  SizedBox(
                      width:
                          UTILS.calculWidth(355, UTILS.widthReference(context)),
                      child: TextFormField(
                        controller: disponibiliteDebutController,
                        decoration: InputDecoration(
                          labelText: "Date de retour du contrat",
                          hintText: 'JJ/MM/AAAA',
                          filled: false,
                          fillColor: const Color.fromARGB(0, 2, 1, 1),
                          labelStyle: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            color: Color.fromARGB(255, 0, 0, 0),
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: Color(0xFFA7C79A)),
                          ),
                        ),
                        readOnly: true,
                        onTap: () => _selectDateWithMinimumDays(
                            context, disponibiliteDebutController),
                      )),
                  //Divider,
                  SizedBox(height: 20),

                  Text("Médiateur",
                      style: TextStyle(
                          fontSize: UTILS.calculWidth(
                              18, UTILS.widthReference(context)),
                          fontWeight: FontWeight.bold)),
                  // Champ pour le nom du médiateur
                  _buildTextField("Nom du médiateur", nomMediateurController),
                  //Divider,
                  SizedBox(height: 20),

                  Text("Signature",
                      style: TextStyle(
                          fontSize: UTILS.calculWidth(
                              18, UTILS.widthReference(context)),
                          fontWeight: FontWeight.bold)),
                  _buildTextField("Lieu de signature", lieuSignatureController),
                  _buildTextField("Date de signature", dateSignatureController,
                      readOnly: true,
                      onTap: () =>
                          _selectDate(context, dateSignatureController)),
                ],
              ),
              // Sélection de l'animal

              SizedBox(height: 20),
              Center(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color.fromARGB(
                        255, 255, 192, 187), // Couleur de fond du bouton
                  ),
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      _generateReservationContractPdf();
                    }
                  },
                  child: Text(
                    "Imprimer ou enregistrer le contrat",
                    style: TextStyle(color: Colors.black),
                  ),
                ),
              ),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownWithFlagsEnterprise() {
    return DropdownButtonFormField<Country>(
      value: selectedCountry,
      isExpanded: true,
      dropdownColor: Color(0xFFEEF5EA), // Couleur de fond de la liste déroulante
      decoration: InputDecoration(
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFA7C79A)),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFA7C79A)),
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
          codeISOElevageController.text =
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
   Widget _buildDropdownWithFlagsClient() {
    return DropdownButtonFormField<Country>(
      value: selectedCountry1,
      isExpanded: true,
      dropdownColor: Color(0xFFEEF5EA), // Couleur de fond de la liste déroulante
      decoration: InputDecoration(
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFA7C79A)),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFA7C79A)),
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
  // Fonction pour générer un champ de texte avec label et controller
  Widget _buildTextField(String label, TextEditingController controller,
      {bool readOnly = false, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: SizedBox(
          width: UTILS.calculWidth(355, UTILS.widthReference(context)),
          child: TextFormField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              filled: false,
              fillColor: const Color.fromARGB(0, 2, 1, 1),
              labelStyle: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w500,
                color: Color.fromARGB(255, 0, 0, 0),
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide:
                    BorderSide(color: Color(0xFFA7C79A)),
              ),
            ),
            readOnly: readOnly,
            onTap: onTap,
            validator: (value) {
              return null; // Validation si nécessaire
            },
          )),
    );
  }
}
