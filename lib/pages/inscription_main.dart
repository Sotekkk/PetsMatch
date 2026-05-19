import 'package:PetsMatch/animation/delayed_animation.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/particulier/first_page.dart';
import 'package:PetsMatch/pages/eleveur/first_page.dart';

import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';

class InscriptionChoicePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Center(
            child: DelayedAnimation(
                delay: 0,
                child: Container(
                    child: Column(children: [
                  SizedBox(
                      width: UTILS.widthReference(context),
                      height: UTILS.calculHeight(
                          105,
                          UTILS.heightReference(
                              context)), // Hauteur fixe pour le Stack
                      child: Stack(children: [
                        Image.asset('assets/deco/arrondi_rose_2.png',
                          fit: BoxFit.cover,
                          width: UTILS.calculWidth(
                              211, UTILS.widthReference(context)),
                          height: UTILS.calculHeight(
                              104,
                              UTILS.heightReference(
                                  context)), // Hauteur fixe pour le Stack
                        ),
                        Positioned(
                          top: UTILS.calculHeight(
                              53, UTILS.heightReference(context)),
                          left: 0,
                          right:
                              0, // Assurez-vous que left et right sont définis à 0 pour permettre au texte de centrer exactement
                          child: Align(
                            alignment: Alignment.center,
                            child: Text(
                              'INSCRIPTION',
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
                  SizedBox(
                      height: UTILS.calculHeight(
                          30, UTILS.heightReference(context))),
                  Text(
                    'Qui êtes vous ?',
                    style: TextStyle(
                        fontSize: UTILS.calculWidth(
                            33, UTILS.widthReference(context)),
                        fontFamily: 'Galey',
                        color: Color.fromARGB(174, 0, 0, 0),
                        fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(
                      height: UTILS.calculHeight(45, UTILS.heightReference(context))),
                  const UserChoiceButton(
                    title: 'Particulier',
                    subtitle:
                        'Découvrez le compagnon idéal qui attend de partager une vie de joie et d’amitié à vos côtés.',
                    imagePath:
                        'assets/page/logo_particulier.png', // Ajoutez votre image appropriée
                  ),
                  const UserChoiceButtonSecond(
                    title: 'Éleveur',
                    subtitle:
                        'Éleveur de confiance pour des animaux équilibrés et en pleine santé.',
                    imagePath:
                        'assets/page/logo_eleveur.png', // Ajoutez votre image appropriée
                  ),
                   const UserChoiceButton3(
                    title: 'Professionnel',
                    subtitle:
                        'Partagez votre savoir faire.',
                    imagePath:
                        'assets/page/logo_professionnel.png', // Ajoutez votre image appropriée
                  ),
                  SizedBox(height: UTILS.calculHeight(40, UTILS.heightReference(context))),
                  Align(
                      alignment: Alignment.center, // Alignez le bouton à droite
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(context);
                        },
                        child: RichText(
                          text: const TextSpan(
                            text: "",
                            style: TextStyle(color: Colors.black),
                            children: <TextSpan>[
                              TextSpan(
                                text: 'RETOUR',
                                style: TextStyle(
                                  fontFamily: 'Galey',
                                  fontWeight: FontWeight.w500,
                                  color: Color.fromARGB(255, 0, 0, 0), // Mettez ici la couleur de votre choix
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    ),
                    SizedBox(height: UTILS.calculHeight(38.8, UTILS.heightReference(context))),
                    Image.asset('assets/deco/arrondi_green_deco_2.png',
                        fit: BoxFit.cover,
                        width: UTILS.calculWidth(233, UTILS.widthReference(context)),
                        height: UTILS.calculHeight(52, UTILS.heightReference(context)), // Hauteur fixe pour l'image
                      ), // Espac
                ]
              )
            )
          )
        )
      );
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
        // splashColor: Color.fromARGB(255, 255, 255, 255), // Personnalisation de la couleur de l'animation d'onde
        // highlightColor: Color.fromARGB(255, 255, 241, 227).withOpacity(0.5),
        onTap: () {
          User_Info.isElevage = false;
          User_Info.isPro = false;
          Navigator.of(context).push(MaterialPageRoute(builder: (context) => RegisterParticulierInformationPage()));
        },
        child: Padding(
          padding: const EdgeInsets.all(0.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(imagePath,
                  width: UTILS.calculWidth(183, UTILS.widthReference(context)),
                  height:
                      UTILS.calculHeight(183, UTILS.heightReference(context))),
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
                            color: Color.fromARGB(174, 0, 0, 0),
                            fontWeight: FontWeight.w500),
                      ),
                      Center(
                        child: Text(
                          subtitle,
                          style: TextStyle(
                              fontSize: UTILS.calculWidth(
                                  12, UTILS.widthReference(context)),
                              fontFamily: 'Galey',
                              color: Color.fromARGB(255, 255, 132, 132),
                              fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                        ),
                      )
                    ],
                  ))
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
          User_Info.isElevage = true;
          User_Info.isPro = false;

          Navigator.of(context).push(MaterialPageRoute(builder: (context) => RegisterEleveurInformationPage()));

          // _RegisterEleveurInformationPageState
          // Ajoutez votre action pour le bouton ici
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
                            color: Color.fromARGB(174, 0, 0, 0),
                            fontWeight: FontWeight.w500),
                      ),
                      Center(
                        child: Text(
                          subtitle,
                          style: TextStyle(
                              fontSize: UTILS.calculWidth(
                                  12, UTILS.widthReference(context)),
                              fontFamily: 'Galey',
                              color: Color.fromARGB(255, 255, 132, 132),
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


class UserChoiceButton3 extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imagePath;

  const UserChoiceButton3({
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
        // splashColor: Color.fromARGB(255, 255, 255, 255), // Personnalisation de la couleur de l'animation d'onde
        // highlightColor: Color.fromARGB(255, 255, 241, 227).withOpacity(0.5),
        onTap: () {
          User_Info.isElevage = false;
          User_Info.isPro = true;

          Navigator.of(context).push(MaterialPageRoute(builder: (context) => RegisterEleveurInformationPage()));
        },
        child: Padding(
          padding: const EdgeInsets.all(0.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(imagePath,
                  width: UTILS.calculWidth(183, UTILS.widthReference(context)),
                  height:
                      UTILS.calculHeight(183, UTILS.heightReference(context))),
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
                            color: Color.fromARGB(174, 0, 0, 0),
                            fontWeight: FontWeight.w500),
                      ),
                      Center(
                        child: Text(
                          subtitle,
                          style: TextStyle(
                              fontSize: UTILS.calculWidth(
                                  12, UTILS.widthReference(context)),
                              fontFamily: 'Galey',
                              color: Color.fromARGB(255, 255, 132, 132),
                              fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                        ),
                      )
                    ],
                  ))
            ],
          ),
        ),
      ),
    );
  }
}

class _RegisterEleveurInformationPageState {
}
