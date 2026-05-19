import 'package:PetsMatch/animation/delayed_animation.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/post/createPostVideo.dart';
import 'package:PetsMatch/pages/eleveur/post/create_post.dart';
import 'package:PetsMatch/pages/eleveur/elevage_gestion_select_menu.dart';
import 'package:PetsMatch/pages/eleveur/pets_menu.dart';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';

class NewPostClass {
  static String uidEleveur = "";
  static String desc = "Aucune description";
  static List<Map<String, dynamic>> mediaStockage = [];
  static List<Map<String, dynamic>> tags = [];
  static bool isPhoto = false;
  static bool isUrgent = false;
  static bool isBoost = false;
  static bool isCat = false;
  static bool isDog = false;
  static bool moreEightWeeks = false;
  static bool isSell = false;
  static bool isSailli = false;
  static bool isRetraite = false;
  static bool isLoof = false;
  static bool isLof = false;
  static bool isVaccined = false;
  static bool isAdult = false;
  static bool isMale = false;
  static String title = "Aucun titre";
  static String dateOfBirth = "Pas de date de naissance enregistrée";
  static String puceNumber = "Aucun numéro de puce enregistré";
  static String numberPorter = "1";
  static bool isPro = false;
  static String price = "0";

  static String genealogieText = '';

  static bool hasGenealogie = false;

  static void updateUserInfo(Map<String, dynamic> data) {
    uidEleveur = data['uidEleveur'] ?? uidEleveur;
    desc = data['desc'] ?? desc;
    isPhoto = data['isPhoto'] ?? isPhoto;
    isMale = data['isMale'] ?? isMale;
    isUrgent = data['isUrgent'] ?? isUrgent;
    isBoost = data['isBoost'] ?? isBoost;
    isCat = data['isCat'] ?? isCat;
    isDog = data['isDog'] ?? isDog;
    moreEightWeeks = data['moreEightWeeks'] ?? moreEightWeeks;
    isSell = data['isSell'] ?? isSell;
    isSailli = data['isSailli'] ?? isSailli;
    isRetraite = data['isRetraite'] ?? isRetraite;
    isLoof = data['isLoof'] ?? isLoof;
    isLof = data['isLof'] ?? isLof;
    isVaccined = data['isVaccined'] ?? isVaccined;
    isAdult = data['isAdult'] ?? isAdult;
    title = data['title'] ?? title;
    puceNumber = data['puceNumber'] ?? puceNumber;
    dateOfBirth = data['dateOfBirth'] ?? dateOfBirth;
    isPro = data['isPro'] ?? isPro;
    numberPorter = data['numberPorter'] ?? numberPorter;

    mediaStockage =
        List<Map<String, dynamic>>.from(data['mediaStockage'] ?? mediaStockage);
    tags = List<Map<String, dynamic>>.from(data['tags'] ?? tags);
  }
}

class ChoicePublicationType extends StatefulWidget {
  const ChoicePublicationType({super.key});

  @override
  State<ChoicePublicationType> createState() => _ChoicePublicationTypeState();
}

class _ChoicePublicationTypeState extends State<ChoicePublicationType> {
  @override
  Widget build(BuildContext context) {
    // Bloquer la publication si compte non validé
    if ((User_Info.isElevage || User_Info.isPro) && !User_Info.isValidate) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 64, color: Colors.orange),
                const SizedBox(height: 20),
                const Text(
                  'Publication désactivée',
                  style: TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w500,
                    fontSize: 22,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Votre compte professionnel doit être vérifié par notre équipe avant de pouvoir publier des annonces.\n\nContactez-nous à support@petsmatch.fr si vous avez des questions.',
                  style: TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 15,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA7C79A),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                  ),
                  child: const Text(
                    'Retour',
                    style: TextStyle(
                        color: Colors.black,
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
        body: Center(
            child: Container(
                child: Column(children: [
      SizedBox(
          width: UTILS.widthReference(context),
          height: UTILS.calculHeight(105,
              UTILS.heightReference(context)), // Hauteur fixe pour le Stack
          child: Stack(children: [
            Image.asset(
              'assets/deco/arrondi_rose_2.png',
              color: const Color(0xFFA7C79A),
              colorBlendMode: BlendMode.srcIn,
              fit: BoxFit.cover,
              width: UTILS.calculWidth(211, UTILS.widthReference(context)),
              height: UTILS.calculHeight(104,
                  UTILS.heightReference(context)), // Hauteur fixe pour le Stack
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
                )),
            Positioned(
              top: UTILS.calculHeight(53, UTILS.heightReference(context)),
              left: 0,
              right:
                  0, // Assurez-vous que left et right sont définis à 0 pour permettre au texte de centrer exactement
              child: Align(
                alignment: Alignment.center,
                child: Text(
                  'PUBLICATION',
                  textAlign: TextAlign
                      .center, // Assurez-vous d'utiliser textAlign pour garantir que le texte est centré à l'intérieur du Text widget.
                  style: TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w500,
                    fontSize:
                        UTILS.calculWidth(20, UTILS.widthReference(context)),
                  ),
                ),
              ),
            )
          ])),
      SizedBox(height: UTILS.calculHeight(150, UTILS.heightReference(context))),

      const UserChoiceButton(
        title: 'Photo',
        subtitle:
            'Publiez votre annonce avec une possibilité a 4 photo maximum',
        imagePath:
            'assets/page/photographe.png', // Ajoutez votre image appropriée
      ),
      SizedBox(height: UTILS.calculHeight(64, UTILS.heightReference(context))),
      // const UserChoiceButtonSecond(
      //   title: 'Vidéo',
      //   subtitle:
      //       'Publiez votre annonce en vidéo pour un maximum de dinamisme',
      //   imagePath:
      //       'assets/page/vid.png', // Ajoutez votre image appropriée
      // ),
    ]))));
  }
}

class UserChoiceButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imagePath;

  const UserChoiceButton({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.imagePath,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: UTILS.calculWidth(385, UTILS.widthReference(context)),
      height: UTILS.calculHeight(183, UTILS.heightReference(context)),
      child: InkWell(
        borderRadius: BorderRadius.circular(500),
        onTap: () {
          NewPostClass.isPhoto = true;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => NewPostPage()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(0.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                imagePath,
                width: UTILS.calculWidth(183, UTILS.widthReference(context)),
                height: UTILS.calculHeight(183, UTILS.heightReference(context)),
              ),
              SizedBox(
                width: UTILS.calculWidth(194, UTILS.widthReference(context)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: UTILS.calculWidth(
                            28, UTILS.widthReference(context)),
                        fontFamily: 'Galey',
                        color: Color(0xFF0C5C6C),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(
                      height:
                          UTILS.calculHeight(8, UTILS.heightReference(context)),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: UTILS.calculWidth(18,
                            UTILS.widthReference(context)), // Taille augmentée
                        fontFamily: 'Galey',
                        color: Color.fromARGB(
                            174, 0, 0, 0), // Couleur grise uniforme
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UserChoiceButtonSecond extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imagePath;

  const UserChoiceButtonSecond({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.imagePath,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: UTILS.calculWidth(385, UTILS.widthReference(context)),
      height: UTILS.calculHeight(183, UTILS.heightReference(context)),
      child: InkWell(
        onTap: () {
          NewPostClass.isPhoto = false;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => NewVideoPostPage()),
          );
          // Navigator.of(context).push(
          //   MaterialPageRoute(builder: (context) => ElevageSelectGestionPage()),
          // );
        },
        borderRadius: BorderRadius.circular(500),
        child: Padding(
          padding: const EdgeInsets.all(0.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                  width: UTILS.calculWidth(194, UTILS.widthReference(context)),
                  height: UTILS.calculWidth(100, UTILS.widthReference(context)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                          width: UTILS.calculWidth(
                              6, UTILS.widthReference(context))),
                      Text(
                        title,
                        style: TextStyle(
                            fontSize: UTILS.calculWidth(
                                28, UTILS.widthReference(context)),
                            fontFamily: 'Galey',
                            color: Color(0xFF0C5C6C),
                            fontWeight: FontWeight.w500),
                      ),
                      Center(
                        child: Text(
                          subtitle,
                          style: TextStyle(
                              fontSize: UTILS.calculWidth(
                                  12, UTILS.widthReference(context)),
                              fontFamily: 'Galey',
                              color: Color(0xFF6E9E57),
                              fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  )),
              SizedBox(
                  width: UTILS.calculWidth(6, UTILS.widthReference(context))),
              Image.asset(imagePath,
                  width: UTILS.calculWidth(183, UTILS.widthReference(context)),
                  height:
                      UTILS.calculHeight(183, UTILS.heightReference(context))),
            ],
          ),
        ),
      ),
    );
  }
}
