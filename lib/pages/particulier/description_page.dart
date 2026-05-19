import 'package:PetsMatch/animation/delayed_animation.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/desc_entreprise.dart';
import 'package:PetsMatch/pages/particulier/futur_project.dart';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_google_places_hoc081098/flutter_google_places_hoc081098.dart';
import 'package:google_maps_webservice/places.dart';

class DescriptionRegistrationPage extends StatefulWidget {
  const DescriptionRegistrationPage({super.key});

  @override
  State<DescriptionRegistrationPage> createState() =>
      _DescriptionRegistrationPageState();
}

class _DescriptionRegistrationPageState
    extends State<DescriptionRegistrationPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  TextEditingController _descriptionController = TextEditingController(text: "");
  final String apiKey = getApiKey();
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: SingleChildScrollView(
            child: Center(
                child: DelayedAnimation(
                    delay: 0,
                    child: Column(children: [
                      SizedBox(
                          width: UTILS.widthReference(context),
                          height: UTILS.calculHeight(
                              104,
                              UTILS.heightReference(
                                  context)), // Hauteur fixe pour le Stack
                          child: Stack(children: [
                            Image.asset(
                              'assets/deco/arrondi_rose_2.png',
              color: const Color(0xFFA7C79A),
              colorBlendMode: BlendMode.srcIn,
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
                              14, UTILS.heightReference(context))),
                      Align(
                        alignment: Alignment(-0.8, 0),
                        child: Text(
                          'Description',
                          style: TextStyle(
                              fontSize: UTILS.calculWidth(
                                  30, UTILS.widthReference(context)),
                              fontFamily: 'Galey',
                              color: Color(0xFF0C5C6C),
                              fontWeight: FontWeight.w500),
                          textAlign: TextAlign.left,
                        ),
                      ),
                      Align(
                          alignment: Alignment(0.1, 0),
                          child: SizedBox(
                            width: UTILS.calculWidth(
                                379, UTILS.widthReference(context)),
                            child: Text(
                              'Parlez-nous un peu de vous ',
                              style: TextStyle(
                                  fontSize: UTILS.calculWidth(
                                      15, UTILS.widthReference(context)),
                                  fontFamily: 'Galey',
                                  color: Color(0xFF0C5C6C),
                                  fontWeight: FontWeight.w500),
                              textAlign: TextAlign.left,
                            ),
                          )),
                      SizedBox(
                          height: UTILS.calculHeight(
                              10, UTILS.heightReference(context))),
                      SizedBox(
                          height: UTILS.calculHeight(
                              286, UTILS.heightReference(context)),
                          width: UTILS.calculWidth(
                              286, UTILS.widthReference(context)),
                          child: Image.asset('assets/page/Description.png')),
                      Container(
                          width: UTILS.calculWidth(372,
                              UTILS.widthReference(context)), // Largeur fixe
                          height: UTILS.calculHeight(255,
                              UTILS.heightReference(context)), // Hauteur fixe
                          padding: EdgeInsets.all(
                              8), // Ajustez selon le besoin pour le padding intérieur
                          decoration: BoxDecoration(
                            color: Color.fromARGB(
                                176, 250, 192, 187), // Couleur de fond
                            borderRadius:
                                BorderRadius.circular(20), // Bord arrondi
                          ),
                          child: SingleChildScrollView(
                            child: TextFormField(
                              controller: _descriptionController,
                              maxLines:
                                  null, // Permet à l'utilisateur d'entrer plusieurs lignes de texte
                              decoration: InputDecoration(
                                hintText: "Parlez-nous un peu de vous",
                                hintStyle: TextStyle(color: Colors.grey),
                                border: InputBorder.none, // Supprime la bordure
                              ),
                            ),
                          )),
                      SizedBox(
                          height: UTILS.calculHeight(
                              16,
                              UTILS.heightReference(
                                  context))), // Espace entre les champs de texte et la date de naissance

                      Align(
                        alignment:
                            Alignment.center, // Alignez le bouton à droite
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
                                    color: Color.fromARGB(255, 0, 0,
                                        0), // Mettez ici la couleur de votre choix
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                          height: UTILS.calculHeight(
                              19,
                              UTILS.heightReference(
                                  context))), // Espace entre les champs de texte et la date de naissance

                      SizedBox(
                          height: UTILS.calculHeight(
                              66, UTILS.heightReference(context)),
                          width: UTILS.calculWidth(
                              367, UTILS.widthReference(context)),
                          child: ElevatedButton(
                            onPressed: () {
                              User_Info.desc = _descriptionController.text;
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (context) => FuturProjectRegistrationPage()),
                              );
                             
                            },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Color(0xFFA7C79A)), // Couleur de fond du bouton

                            child: Text(
                              'CONTINUER',
                              style: TextStyle(
                                fontFamily: 'Galey',
                                fontWeight: FontWeight.w500,
                                color: Color.fromARGB(255, 0, 0, 0),
                                fontSize: UTILS.calculWidth(
                                    17, UTILS.widthReference(context)),
                              ),
                            ),
                            // Personnaliser le style du bouton
                          )),
                      SizedBox(
                          height: UTILS.calculHeight(
                              19.6, UTILS.heightReference(context))),
                      Image.asset(
                        'assets/deco/arrondi_green_deco_2.png',
                        fit: BoxFit.cover,
                        width: UTILS.calculWidth(
                            233, UTILS.widthReference(context)),
                        height: UTILS.calculHeight(
                            52,
                            UTILS.heightReference(
                                context)), // Hauteur fixe pour l'image
                      ), // Espac
                    ])))));
  }
}
