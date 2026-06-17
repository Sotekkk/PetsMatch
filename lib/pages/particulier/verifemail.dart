import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/bottom_nav.dart';
import 'package:PetsMatch/pages/eleveur/info_elevage.dart';
import 'package:PetsMatch/pages/eleveur/verification_page.dart';
import 'package:PetsMatch/pages/particulier/description_page.dart';
import 'package:PetsMatch/utils.dart';
import 'package:PetsMatch/utils/french_geo.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

class VerifyEmailPage extends StatefulWidget {
  final String email;

  VerifyEmailPage({required this.email});

  @override
  _VerifyEmailPageState createState() => _VerifyEmailPageState();
}



Future<bool> registerUser(String email, String password) async {
  try {
    String uid = User_Info.uid;

    // Ajouter des informations à Firestore dans la collection 'users'
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'uid': uid,
      'role': 'user',
      'isAdmin': false,
      'verificationStatus': 'none',
      'firstname': User_Info.firstname,
      'lastname': User_Info.lastname,
      'dateofbirth': User_Info.dateofbirth,
      'codeISO': User_Info.codeISO,
      'codeISOElevage': User_Info.codeISOElevage,
      'phone_number': User_Info.phone_number,
      'adress': User_Info.adress,
      'profilePictureUrl': User_Info.profilePictureUrl,
      'profilePictureUrlElevage': User_Info.profilePictureUrlElevage,
      'isElevage': User_Info.isElevage,
      'isAssociation': User_Info.isAssociation,
      'adressElevage': User_Info.adressElevage,
      'nameElevage': User_Info.nameElevage,
      'numeroElevage': User_Info.numeroElevage,
      'isDev': User_Info.isDev,
      'email': User_Info.email,
      'isValidate': User_Info.isValidate,
      'siret': User_Info.siret,
      'numeroTVA': User_Info.numeroTVA,

      // 'password': User_Info.password,
      'desc': User_Info.desc,
      'documentElevage': User_Info.documentElevage,
      'validateAccountElevage': User_Info.validateAccountElevage,
      'adoptProject': User_Info.adoptProject,
      'descEntreprise': User_Info.descEntreprise,
      'isPub': User_Info.isPub,
      'isPro': User_Info.isPro,
      'catPro': User_Info.catPro,
      'professionPro': User_Info.professionPro,
      'isPartenaire': User_Info.isPartenaire,

      'CGU': true,
      'mentionlegal': true,

      // Ajouter d'autres champs comme nécessaire
    });

    return true; // Succès de l'enregistrement
  } catch (e) {
    print("Erreur lors de la création de l'utilisateur: $e");
    return false; // Échec de l'enregistrement
  }
}

Future<Object> registerElevage(String email, String password) async {
  try {
    String uid = User_Info.uid;

    // Ajouter des informations à Firestore dans la collection 'users'
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'uid': uid,
      'role': 'user',
      'isAdmin': false,
      // Particuliers auto-validés, seuls éleveurs/pros/assos nécessitent review admin
      'verificationStatus': (User_Info.isElevage || User_Info.isPro || User_Info.isAssociation) ? 'pending' : 'approved',
      'kbisUrl': User_Info.kbisUrl,
      'firstname': User_Info.firstname,
      'lastname': User_Info.lastname,
      'dateofbirth': User_Info.dateofbirth,
      'codeISO': User_Info.codeISO,
      'codeISOElevage': User_Info.codeISOElevage,
      'phone_number': User_Info.phone_number,
      'adress': User_Info.adress,
      'profilePictureUrl': User_Info.profilePictureUrl,
      'profilePictureUrlElevage': User_Info.profilePictureUrlElevage,
      'isElevage': User_Info.isElevage,
      'isAssociation': User_Info.isAssociation,
      'adressElevage': User_Info.adressElevage,
      'nameElevage': User_Info.nameElevage,
      'numeroElevage': User_Info.numeroElevage,
      'isDev': User_Info.isDev,
      'email': User_Info.email,
      'isValidate': !User_Info.isElevage && !User_Info.isPro && !User_Info.isAssociation,
      'siret': User_Info.siret,
      'numeroTVA': User_Info.numeroTVA,
      // 'password': User_Info.password,
      'desc': User_Info.desc,
      'documentElevage': User_Info.documentElevage,
      'validateAccountElevage': User_Info.validateAccountElevage,
      'adoptProject': User_Info.adoptProject,
      'descEntreprise': User_Info.descEntreprise,
      'isPub': User_Info.isPub,
      'isPro': User_Info.isPro,
      'catPro': User_Info.catPro,
      'professionPro': User_Info.professionPro,
      'isPartenaire': User_Info.isPartenaire,
      'rna': User_Info.rna,
      'agrementPrefectoral': User_Info.agrementPrefectoral,
      'acacedNumero': User_Info.acacedNumero,
      'acacedDateObtention': User_Info.acacedDateObtention,
      'acacedDocUrl': User_Info.acacedDocUrl,
      'isDog': User_Info.isDog,
      'isCat': User_Info.isCat,
      'dogBreeds': User_Info.dogBreeds,
      'catBreeds': User_Info.catBreeds,
      'especesElevees': User_Info.especesElevees,
      if (User_Info.bannerUrl.isNotEmpty) 'bannerUrl': User_Info.bannerUrl,

      // Adresse de l'élevage (dénormalisée pour les filtres)
      'rueElevage':          User_Info.rueElevage,
      'codePostalElevage':   User_Info.codePostalElevage,
      'villeElevage':        User_Info.villeElevage,
      'paysElevage':         User_Info.paysElevage,
      'city':                User_Info.villeElevage,
      ...() {
        final geo = FrenchGeo.fromPostalCode(User_Info.codePostalElevage);
        return {
          'departementElevage': geo?.departement ?? '',
          'regionElevage':      geo?.region      ?? '',
        };
      }(),

      'CGU': true,
      'mentionlegal': true,
      // Ajouter d'autres champs comme nécessaire
    });

    // Sync to Supabase users table
    try {
      final geoPerso  = FrenchGeo.fromPostalCode(User_Info.codePostal);
      final geoElev   = FrenchGeo.fromPostalCode(User_Info.codePostalElevage);

      // especes_elevees : format [{espece, races}] pour éleveurs
      final especesEleveesJson = User_Info.isElevage
          ? User_Info.especesElevees.map((e) => {
              'espece': e,
              'races': e == 'chien'
                  ? User_Info.dogBreeds
                  : e == 'chat'
                      ? User_Info.catBreeds
                      : <String>[],
            }).toList()
          : null;

      // especes_acceptees : liste capitalisée pour pros
      final especesAccepteesJson = User_Info.isPro
          ? User_Info.especesElevees
              .map((e) => e.isEmpty ? e : e[0].toUpperCase() + e.substring(1))
              .toList()
          : null;

      await Supabase.instance.client.from('users').upsert({
        'uid':                   uid,
        'firstname':             User_Info.firstname,
        'lastname':              User_Info.lastname,
        'email':                 User_Info.email,
        'phone_number':          User_Info.phone_number,
        'code_iso':              User_Info.codeISO,
        'adress':                User_Info.adress,
        'rue':                   User_Info.rue,
        'ville':                 User_Info.ville,
        'code_postal':           User_Info.codePostal,
        'pays':                  User_Info.pays,
        'departement':           geoPerso?.departement ?? '',
        'region':                geoPerso?.region      ?? '',
        'profile_picture_url':   User_Info.profilePictureUrl,
        'is_elevage':            User_Info.isElevage,
        'is_validate':           !User_Info.isElevage && !User_Info.isPro && !User_Info.isAssociation,
        'name_elevage':          User_Info.nameElevage,
        'adress_elevage':        User_Info.adressElevage,
        'rue_elevage':           User_Info.rueElevage,
        'ville_elevage':         User_Info.villeElevage,
        'code_postal_elevage':   User_Info.codePostalElevage,
        'pays_elevage':          User_Info.paysElevage,
        'departement_elevage':   geoElev?.departement ?? '',
        'region_elevage':        geoElev?.region      ?? '',
        'numero_elevage':        User_Info.numeroElevage,
        'code_iso_elevage':      User_Info.codeISOElevage,
        'is_pub':                User_Info.isPub,
        'is_pro':                User_Info.isPro,
        'is_partenaire':         User_Info.isPartenaire,
        'is_admin':              User_Info.isAdmin,
        'is_dev':                User_Info.isDev,
        // Champs pro/éleveur
        'cat_pro':               User_Info.catPro,
        'profession_pro':        User_Info.professionPro,
        'desc_entreprise':       User_Info.descEntreprise,
        'siret':                 User_Info.siret,
        'numero_tva':            User_Info.numeroTVA,
        'is_dog':                User_Info.isDog,
        'is_cat':                User_Info.isCat,
        'dog_breeds':            User_Info.dogBreeds,
        'cat_breeds':            User_Info.catBreeds,
        if (especesEleveesJson != null)    'especes_elevees':    especesEleveesJson,
        if (especesAccepteesJson != null)  'especes_acceptees':  especesAccepteesJson,
        if (User_Info.certifications.isNotEmpty) 'certifications': User_Info.certifications,
        if (User_Info.isPro || User_Info.isElevage) 'statut_pro': 'en_attente',
        if (User_Info.bannerUrl.isNotEmpty) 'banner_url': User_Info.bannerUrl,
        'is_association': User_Info.isAssociation,
        if (User_Info.isAssociation) ...{
          'rna':                  User_Info.rna,
          'agrement_prefectoral': User_Info.agrementPrefectoral,
          'capacite_accueil':     User_Info.capaciteAccueil,
          'especes_accueillies':  User_Info.especesElevees,
          'statut_pro':           'en_attente',
        },
        if (User_Info.profilePictureUrlElevage.isNotEmpty)
          'profile_picture_url_elevage': User_Info.profilePictureUrlElevage,
        'cgu_accepted_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print("Supabase user sync error: $e");
    }

    return uid; // Succès de l'enregistrement
  } catch (e) {
    print("Erreur lors de la création de l'utilisateur: $e");
    return false; // Échec de l'enregistrement
  }
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  bool _isVerified = false;
  bool _isResendEnabled = true;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _checkEmailVerified();
  }

  void _startTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        if (_isResendEnabled) {
          _isResendEnabled = false;
          Future.delayed(Duration(minutes: 1), () {
            setState(() {
              _isResendEnabled = true;
            });
          });
        }
      });
    });
  }

  Future<void> _checkEmailVerified() async {
    User? user = FirebaseAuth.instance.currentUser;
    await user?.reload();
    if (user != null && user.emailVerified) {
      setState(() {
        _isVerified = true;
      });
      _timer.cancel();
      if (User_Info.isElevage || User_Info.isPro || User_Info.isAssociation) {

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
                builder: (context) => VerificationRegistrationPage()),
          );
      } else {
        bool isRegistered =
            await registerUser(User_Info.email, User_Info.password);

        if (isRegistered) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => BottomNav()),
          );
        } else {
          // Affichez un message d'erreur ou gérez l'échec d'enregistrement ici
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('Échec de l\'enregistrement. Veuillez réessayer.')),
          );
        }
      }
    }
  }

  Future<void> _resendVerificationEmail() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
      setState(() {
        _isResendEnabled = false;
        Future.delayed(Duration(minutes: 1), () {
          setState(() {
            _isResendEnabled = true;
          });
        });
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          children: [
            SizedBox(
                width: UTILS.widthReference(context),
                height: UTILS.calculHeight(104, UTILS.heightReference(context)),
                child: Stack(children: [
                  Image.asset(
                    'assets/deco/arrondi_rose_2.png',
              color: const Color(0xFFA7C79A),
              colorBlendMode: BlendMode.srcIn,
                    fit: BoxFit.cover,
                    width:
                        UTILS.calculWidth(211, UTILS.widthReference(context)),
                    height:
                        UTILS.calculHeight(104, UTILS.heightReference(context)),
                  ),
                  Positioned(
                    top: UTILS.calculHeight(42, UTILS.heightReference(context)),
                    left: UTILS.calculWidth(10, UTILS.widthReference(context)),
                    child: IconButton(
                      icon: Icon(Icons.arrow_back,
                          color: Colors.black), // Icône de la flèche noire
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                  Positioned(
                    top: UTILS.calculHeight(53, UTILS.heightReference(context)),
                    left: 0,
                    right: 0,
                    child: Align(
                      alignment: Alignment.center,
                      child: Text(
                        'INSCRIPTION',
                        textAlign: TextAlign.center,
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
            SizedBox(
                height: UTILS.calculHeight(14, UTILS.heightReference(context))),
            Align(
              alignment: Alignment(-0.8, 0),
              child: Text(
                'Sécurité',
                style: TextStyle(
                    fontSize:
                        UTILS.calculWidth(30, UTILS.widthReference(context)),
                    fontFamily: 'Galey',
                    color: Color(0xFF0C5C6C),
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.left,
              ),
            ),
            Center(
                child: Text(
                    textAlign: TextAlign.center,
                    "Un e-mail de vérification à été envoyer à cette adresse ${widget.email}. Vérifier l'email pour continuer.")),
            SizedBox(
                height: UTILS.calculHeight(20, UTILS.heightReference(context))),
            ElevatedButton(
              onPressed: _isResendEnabled ? _resendVerificationEmail : null,
              child: Text('Renvoyer un e-mail de vérification'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color.fromARGB(
                    255, 255, 192, 187), // Couleur de fond du bouton
              ),
            ),
            SizedBox(
                height: UTILS.calculHeight(20, UTILS.heightReference(context))),
            _isVerified
                ? Text('Email vérifié! Vous pouvez continuez.')
                : Text('En attente de vérification...'),
            ElevatedButton(
              onPressed: _checkEmailVerified,
              child: Text("J'ai reçu le mail de vérification"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color.fromARGB(
                    255, 255, 192, 187), // Couleur de fond du bouton
              ),
            ),
          ],
        ),
      ),
    );
  }
}
