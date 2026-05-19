import 'package:PetsMatch/animation/delayed_animation.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/condition_general.dart';
import 'package:PetsMatch/pages/eleveur/verification_page.dart';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/pages/bottom_nav.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';



class DescProEntreprise extends StatefulWidget {
  const DescProEntreprise({super.key});

  @override
  State<DescProEntreprise> createState() =>
      _DescProEntrepriseState();
}

class _DescProEntrepriseState
    extends State<DescProEntreprise>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final TextEditingController _futurProject = TextEditingController();
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
                       if (User_Info.isPro)
                        Align(
                          alignment: Alignment(-0.71, 0),
                          child: Text(
                            "Votre société",
                            style: TextStyle(
                                fontSize: UTILS.calculWidth(
                                    30, UTILS.widthReference(context)),
                                fontFamily: 'Galey',
                                color: Color(0xFF0C5C6C),
                                fontWeight: FontWeight.w500),
                            textAlign: TextAlign.left,
                          ),
                        ),
                      if (User_Info.isElevage)
                        Align(
                          alignment: Alignment(-0.71, 0),
                          child: Text(
                            "Votre élevage",
                            style: TextStyle(
                                fontSize: UTILS.calculWidth(
                                    30, UTILS.widthReference(context)),
                                fontFamily: 'Galey',
                                color: Color(0xFF0C5C6C),
                                fontWeight: FontWeight.w500),
                            textAlign: TextAlign.left,
                          ),
                        ),
                      if (User_Info.isPro)

                        Align(
                            alignment: Alignment(0.1, 0),
                            child: SizedBox(
                              width: UTILS.calculWidth(
                                  379, UTILS.widthReference(context)),
                              child: Text(
                                'Parlez nous de votre entreprise',
                                style: TextStyle(
                                    fontSize: UTILS.calculWidth(
                                        15, UTILS.widthReference(context)),
                                    fontFamily: 'Galey',
                                    color: Color(0xFF0C5C6C),
                                    fontWeight: FontWeight.w500),
                                textAlign: TextAlign.left,
                              ),
                            )),
                      if (User_Info.isElevage)

                        Align(
                            alignment: Alignment(0.1, 0),
                            child: SizedBox(
                              width: UTILS.calculWidth(
                                  379, UTILS.widthReference(context)),
                              child: Text(
                                'Parlez nous de votre élevage',
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
                          child: Image.asset('assets/page/adoption_project.png')),
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
                              controller: _futurProject,
                              maxLines:
                                  null, // Permet à l'utilisateur d'entrer plusieurs lignes de texte
                              decoration: InputDecoration(
                                hintText: "Parlez nous de votre entreprise",
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
                      height: UTILS.calculHeight(66, UTILS.heightReference(context)),
                      width: UTILS.calculWidth(367, UTILS.widthReference(context)),
                      child: ElevatedButton(
                        onPressed: () async {
                          User_Info.descEntreprise = _futurProject.text;
                          User_Info.isValidate = false;
                          Navigator.of(context).push(
                              MaterialPageRoute(builder: (context) => ConditionGeneral()),
                            );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFA7C79A), // Couleur de fond du bouton
                        ),
                        child: Text(
                          'FINALISER',
                          style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            color: Color.fromARGB(255, 0, 0, 0),
                            fontSize: UTILS.calculWidth(17, UTILS.widthReference(context)),
                          ),
                        ),
                      ),
                    ),
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
