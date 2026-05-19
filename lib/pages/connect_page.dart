import 'package:PetsMatch/animation/delayed_animation.dart';
import 'package:PetsMatch/pages/inscription_main.dart';
import 'package:PetsMatch/pages/login_page.dart';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';

class WelcomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Center(
            child: DelayedAnimation(
      delay: 0,
      child: Container(
        child: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(
                width: UTILS.widthReference(context),
                height: UTILS.calculHeight(
                    141,
                    UTILS.heightReference(
                        context)), // Hauteur fixe pour le Stack
                child: Stack(children: [
                  Image.asset(
                    'assets/deco/arrondideco.png',
                    fit: BoxFit.cover,
                    width:
                        UTILS.calculWidth(151, UTILS.widthReference(context)),
                    height: UTILS.calculHeight(
                        141,
                        UTILS.heightReference(
                            context)), // Hauteur fixe pour le Stack
                  color: const Color(0xFFA7C79A),
                  colorBlendMode: BlendMode.srcIn,
                  ),
                  Positioned(
                    top: UTILS.calculHeight(53, UTILS.heightReference(context)),
                    left: 0,
                    right:
                        0, // Assurez-vous que left et right sont définis à 0 pour permettre au texte de centrer exactement
                    child: Align(
                      alignment: Alignment.center,
                      child: Text(
                        'BIENVENUE',
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

            // Ajoutez votre image ici
            SizedBox(
                height: UTILS.calculHeight(340, UTILS.heightReference(context)),
                width: UTILS.calculWidth(340, UTILS.widthReference(context)),
                child: Image.asset('assets/page/welcome_page_logo.png')),

            Text(
              'Compagnons choisis',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Galey',
                color: Color.fromARGB(194, 30, 28, 31),
                fontWeight: FontWeight.w500,
                fontSize: UTILS.calculWidth(33, UTILS.widthReference(context)),
              ),
            ),
            SizedBox(
                height: UTILS.calculHeight(12, UTILS.heightReference(context))),
            Text(
              'Bonheur promis',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w500,
                color: Color.fromARGB(194, 30, 28, 31),
                fontSize: UTILS.calculWidth(33, UTILS.widthReference(context)),
              ),
            ),
            SizedBox(
                height: UTILS.calculHeight(72, UTILS.heightReference(context))),
            SizedBox(
                height: UTILS.calculHeight(61, UTILS.heightReference(context)),
                width: UTILS.calculWidth(325, UTILS.widthReference(context)),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => LoginPage()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color.fromARGB(
                        255, 255, 132, 132), // Couleur de fond du bouton
                  ),
                  child: Text(
                    'SE CONNECTER',
                    style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w500,
                      color: Color.fromARGB(255, 255, 255, 255),
                      fontSize:
                          UTILS.calculWidth(17, UTILS.widthReference(context)),
                    ),
                  ),
                  // Personnaliser le style du bouton
                )),
            SizedBox(
                height: UTILS.calculHeight(18, UTILS.heightReference(context))),

            SizedBox(
                height: UTILS.calculHeight(61, UTILS.heightReference(context)),
                width: UTILS.calculWidth(325, UTILS.widthReference(context)),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => InscriptionChoicePage()));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color.fromARGB(
                        255, 255, 192, 187), // Couleur de fond du bouton
                  ),

                  child: Text(
                    'S\'INSCRIRE',
                    style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w500,
                      color: Color.fromARGB(255, 0, 0, 0),
                      fontSize:
                          UTILS.calculWidth(17, UTILS.widthReference(context)),
                    ),
                  ),

                  // Personnaliser le style du bouton
                )),
            SizedBox(
                height:
                    UTILS.calculHeight(9.9, UTILS.heightReference(context))),

            SizedBox(
                width: UTILS.widthReference(context),
                height: UTILS.calculHeight(
                    115,
                    UTILS.heightReference(
                        context)), // Hauteur fixe pour le Stack
                child: Stack(children: [
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Image.asset(
                      'assets/deco/arrondi_green_deco.png',
                      fit: BoxFit.cover,
                      width:
                          UTILS.calculWidth(115, UTILS.widthReference(context)),
                      height: UTILS.calculHeight(
                          115,
                          UTILS.heightReference(
                              context)), // Hauteur fixe pour le Stack
                    ),
                  )
                ])),
          ],
        ),
        ),
      ),
    )));
  }
}
