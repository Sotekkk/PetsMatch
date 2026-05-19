import 'package:PetsMatch/animation/delayed_animation.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/board.dart';
import 'package:PetsMatch/pages/eleveur/choice_publication.dart';
import 'package:PetsMatch/pages/eleveur/post/create_post.dart';
import 'package:PetsMatch/pages/eleveur/elevage_gestion_select_menu.dart';
import 'package:PetsMatch/pages/eleveur/pets_menu.dart';
import 'package:PetsMatch/pages/pro/partenaire.dart';
import 'package:PetsMatch/pages/pro/santeanimal.dart';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';

class BienEtrePage extends StatefulWidget {
  const BienEtrePage({super.key});

  @override
  State<BienEtrePage> createState() => _BienEtrePageState();
}

class _BienEtrePageState extends State<BienEtrePage> {
  @override
  Widget build(BuildContext context) {
    return Navigator(onGenerateRoute: (RouteSettings settings) {
      return MaterialPageRoute(
          builder: (context) => Scaffold(
                  body: Center(
                      child: Container(
                          child: Column(children: [
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
                        width: UTILS.calculWidth(
                            211, UTILS.widthReference(context)),
                        height: UTILS.calculHeight(
                            104,
                            UTILS.heightReference(
                                context)), // Hauteur fixe pour le Stack
                      ),
                      if (User_Info.isPro || User_Info.isElevage)
                        Positioned(
                            top: UTILS.calculHeight(42, UTILS.heightReference(context)),
                            left:  UTILS.calculWidth(10, UTILS.widthReference(context)),
                            child :IconButton(
                            icon: Icon(Icons.arrow_back, color: Colors.black), // Icône de la flèche noire
                            onPressed: () {
                               Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => BoardMainPage()),
                              );
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
                            'Bien être',
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
                    height: UTILS.calculHeight(
                        150, UTILS.heightReference(context))),
                const UserChoiceButton(
                  title: 'Prestataire',
                  subtitle:
                      "Prestataires spécialisés en soins et éducation",
                  imagePath:
                      'assets/page/prestataire.png', // Ajoutez votre image appropriée
                ),
                SizedBox(
                    height:
                        UTILS.calculHeight(64, UTILS.heightReference(context))),
            
                  const UserChoiceButtonSecond(
                    title: 'Santé animal',
                    subtitle: "Tous les experts pour la santé de votre animal sont ici.",
                    imagePath:
                        'assets/page/santeanimal.png', // Ajoutez votre image appropriée
                  ),
              ])))));
    });
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
      height: UTILS.calculHeight(200, UTILS.heightReference(context)), // Ajusté pour centrer mieux
      child: InkWell(
        borderRadius: BorderRadius.circular(500),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => PrestatairePage()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center, // Centrer horizontalement
            crossAxisAlignment: CrossAxisAlignment.center, // Centrer verticalement
            children: [
              Image.asset(
                imagePath,
                width: UTILS.calculWidth(170, UTILS.widthReference(context)),
                height: UTILS.calculHeight(170, UTILS.heightReference(context)),
              ),
              SizedBox(width: UTILS.calculWidth(16, UTILS.widthReference(context))),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, // Centrer verticalement dans la colonne
                  crossAxisAlignment: CrossAxisAlignment.center, // Centrer horizontalement
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: UTILS.calculWidth(24, UTILS.widthReference(context)),
                        fontFamily: 'Galey',
                        color: Color.fromARGB(174, 0, 0, 0),
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center, // Centrer le texte
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis, // Gérer les titres longs
                    ),
                    SizedBox(height: UTILS.calculHeight(8, UTILS.heightReference(context))),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: UTILS.calculWidth(18, UTILS.widthReference(context)), // Taille augmentée
                        fontFamily: 'Galey',
                        color: Color.fromARGB(174, 0, 0, 0),
                        fontWeight: FontWeight.w400,
                      ),
                      textAlign: TextAlign.center, // Centrer le texte
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis, // Gérer les sous-titres longs
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
      height: UTILS.calculHeight(200, UTILS.heightReference(context)), // Hauteur ajustée
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => SanteAnimal()),
          );
        },
        borderRadius: BorderRadius.circular(500),
        child: Padding(
          padding: const EdgeInsets.all(0.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center, // Centrer horizontalement
            crossAxisAlignment: CrossAxisAlignment.center, // Centrer verticalement
            children: [
              SizedBox(
                width: UTILS.calculWidth(194, UTILS.widthReference(context)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, // Centrer verticalement dans la colonne
                  crossAxisAlignment: CrossAxisAlignment.center, // Centrer horizontalement
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: UTILS.calculWidth(28, UTILS.widthReference(context)),
                        fontFamily: 'Galey',
                        color: Color.fromARGB(174, 0, 0, 0),
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center, // Centrer le texte
                    ),
                    SizedBox(height: UTILS.calculHeight(8, UTILS.heightReference(context))),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: UTILS.calculWidth(18, UTILS.widthReference(context)), // Taille augmentée
                        fontFamily: 'Galey',
                        color: Color.fromARGB(174, 0, 0, 0),
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center, // Centrer le texte
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: UTILS.calculWidth(16, UTILS.widthReference(context)), // Espacement ajusté
              ),
              Image.asset(
                imagePath,
                width: UTILS.calculWidth(170, UTILS.widthReference(context)), // Taille ajustée
                height: UTILS.calculHeight(170, UTILS.heightReference(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

