import 'package:PetsMatch/animation/delayed_animation.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/choice_publication.dart';
import 'package:PetsMatch/pages/eleveur/post/create_post.dart';
import 'package:PetsMatch/pages/eleveur/elevage_gestion_select_menu.dart';
import 'package:PetsMatch/pages/eleveur/pets_menu.dart';
import 'package:PetsMatch/pages/services/services_page.dart';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';

class BoardMainPage extends StatefulWidget {
  const BoardMainPage({super.key});

  @override
  State<BoardMainPage> createState() => _BoardMainPageState();
}

class _BoardMainPageState extends State<BoardMainPage> {
  @override
  Widget build(BuildContext context) {
    return Navigator(onGenerateRoute: (RouteSettings settings) {
      return MaterialPageRoute(
          builder: (context) => Scaffold(
                  body: SingleChildScrollView(
                      child: Center(
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
                      Positioned(
                        top: UTILS.calculHeight(
                            53, UTILS.heightReference(context)),
                        left: 0,
                        right:
                            0, // Assurez-vous que left et right sont définis à 0 pour permettre au texte de centrer exactement
                        child: Align(
                          alignment: Alignment.center,
                          child: Text(
                            'GESTION',
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
                if (!User_Info.isElevage)
                  SizedBox(
                      height: UTILS.calculHeight(
                          30, UTILS.heightReference(context))),
                if (!User_Info.isElevage)
                  SizedBox(
                      height: UTILS.calculHeight(
                          150, UTILS.heightReference(context))),
                const UserChoiceButton(
                  title: 'Publication',
                  subtitle:
                      'Publiez votre annonce pour trouver le nouveau foyer idéal pour votre animal.',
                  imagePath:
                      'assets/page/publication.png', // Ajoutez votre image appropriée
                ),
                SizedBox(
                    height:
                        UTILS.calculHeight(64, UTILS.heightReference(context))),
                if (User_Info.isElevage)
                  const UserChoiceButtonSecond(
                    title: 'Elevage',
                    subtitle:
                        'Optimisez la gestion de votre élevage grâce à nos outils dédiés.',
                    imagePath:
                        'assets/page/elevage.png', // Ajoutez votre image appropriée
                  ),
                if (User_Info.isElevage)
                  SizedBox(
                      height: UTILS.calculHeight(
                          64, UTILS.heightReference(context))),
                if (User_Info.isElevage)
                  const UserChoiceButtonThird(
                    title: 'Bien être',
                    subtitle: 'Le monde animalier regroupé en un seul espace.',
                    imagePath:
                        'assets/page/prestataire.png', // Ajoutez votre image appropriée
                  ),
                if (User_Info.isPro)
                  const UserChoiceButtonFour(
                    title: 'Bien être',
                    subtitle: 'Le monde animalier regroupé en un seul espace.',
                    imagePath:
                        'assets/page/prestataire.png', // Ajoutez votre image appropriée
                  ),
              ]))))));
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
      height: UTILS.calculHeight(183, UTILS.heightReference(context)),
      child: InkWell(
        borderRadius: BorderRadius.circular(500),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ChoicePublicationType()),
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
                        color: Color.fromARGB(174, 0, 0, 0),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(
                      height: UTILS.calculHeight(8, UTILS.heightReference(context)),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: UTILS.calculWidth(
                            18, UTILS.widthReference(context)), // Taille augmentée
                        fontFamily: 'Galey',
                        color: Color.fromARGB(174, 0, 0, 0),
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
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ElevageSelectGestionPage()),
          );
        },
        borderRadius: BorderRadius.circular(500),
        child: Padding(
          padding: const EdgeInsets.all(0.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: UTILS.calculWidth(194, UTILS.widthReference(context)),
                height: UTILS.calculHeight(183, UTILS.heightReference(context)),
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
                        color: Color.fromARGB(174, 0, 0, 0),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(
                      height: UTILS.calculHeight(8, UTILS.heightReference(context)),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: UTILS.calculWidth(
                            18, UTILS.widthReference(context)), // Taille augmentée
                        fontFamily: 'Galey',
                        color: Color.fromARGB(174, 0, 0, 0),
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: UTILS.calculWidth(6, UTILS.widthReference(context)),
              ),
              Image.asset(
                imagePath,
                width: UTILS.calculWidth(183, UTILS.widthReference(context)),
                height: UTILS.calculHeight(183, UTILS.heightReference(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class UserChoiceButtonThird extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imagePath;

  const UserChoiceButtonThird({
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
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ServicesPage()),
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
                width: UTILS.calculWidth(8, UTILS.widthReference(context)),
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
                        color: Color.fromARGB(174, 0, 0, 0),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(
                      height: UTILS.calculHeight(8, UTILS.heightReference(context)),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: UTILS.calculWidth(
                            18, UTILS.widthReference(context)), // Taille augmentée
                        fontFamily: 'Galey',
                        color: Color.fromARGB(174, 0, 0, 0),
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


class UserChoiceButtonFour extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imagePath;

  const UserChoiceButtonFour({
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
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ServicesPage()),
          );
        },
        borderRadius: BorderRadius.circular(500),
        child: Padding(
          padding: const EdgeInsets.all(0.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                        color: Color.fromARGB(174, 0, 0, 0),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(
                      height: UTILS.calculHeight(8, UTILS.heightReference(context)),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: UTILS.calculWidth(
                            18, UTILS.widthReference(context)), // Taille augmentée
                        fontFamily: 'Galey',
                        color: Color.fromARGB(174, 0, 0, 0),
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: UTILS.calculWidth(6, UTILS.widthReference(context)),
              ),
              Image.asset(
                imagePath,
                width: UTILS.calculWidth(183, UTILS.widthReference(context)),
                height: UTILS.calculHeight(183, UTILS.heightReference(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

