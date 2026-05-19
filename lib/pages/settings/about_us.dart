import 'package:PetsMatch/pages/particulier/numberadressregistration.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:PetsMatch/utils.dart';
import 'package:PetsMatch/main.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
class AboutUs extends StatefulWidget {
  @override
  State<AboutUs> createState() => _AboutUsState();
}
class _AboutUsState extends State<AboutUs> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
            child: Column(
              children: [
                SizedBox(
                  width: UTILS.widthReference(context),
                  height:
                      UTILS.calculHeight(104, UTILS.heightReference(context)),
                  child: Stack(
                    children: [
                      Image.asset(
                        'assets/deco/arrondi_rose_2.png',
              color: const Color(0xFFA7C79A),
              colorBlendMode: BlendMode.srcIn,
                        fit: BoxFit.cover,
                        width: UTILS.calculWidth(
                            211, UTILS.widthReference(context)),
                        height: UTILS.calculHeight(
                            104, UTILS.heightReference(context)),
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
                        ),
                      ),
                      Positioned(
                        top: UTILS.calculHeight(
                            53, UTILS.heightReference(context)),
                        left: 0,
                        right: 0,
                        child: Align(
                          alignment: Alignment.center,
                          child: Text(
                            'A propos',
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
                    ],
                  ),
                ),
                SizedBox(
                    height:
                        UTILS.calculHeight(14, UTILS.heightReference(context))),
                Align(
                  alignment: Alignment(-0.8, 0),
                  child: Text(
                    "A propos",
                    style: TextStyle(
                      fontSize:
                          UTILS.calculWidth(25, UTILS.widthReference(context)),
                      fontFamily: 'Galey',
                      color: Color.fromARGB(255, 0, 0, 0),
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    """
1. Éditeur de l’application
  -  Dénomination sociale : PETSMATCH (PM)
  -  Forme juridique : SAS (Société par Actions Simplifiée)
  -  Adresse du siège social : 15 La Ville Marchand, 22210 Plumieux, France
  -  SIREN : 931 344 816
  -  SIRET : 931 344 816 00018
  -  Numéro de TVA Intracommunautaire : FR94 931 344 816
  -  Date de création : 20 juillet 2024
  -  Email de contact : petsmatch.contact@gmail.com
  -  Téléphone : 07 81 03 49 84

2. Responsable de la publication
  -  Nom : Nabil Ksouri
  -  Fonction : Président de PETSMATCH SAS
  -  Nom: Mevinn Allee
  -  Fonction: Directeur général de PETSMATCH SAS

3. Hébergement de l’application
  -  Nom de l’hébergeur : Google Firebase (Google LLC)
  -  Adresse : 1600 Amphitheatre Parkway, Mountain View, CA 94043, USA
  -  Contact : support@firebase.google.com
  Si un hébergeur additionnel est utilisé pour votre site web ou d’autres services, ajoutez ses informations ici.

4. Propriété intellectuelle
  -  Tous les éléments de l’application PetsMatch, y compris les textes, graphismes, logos, images, vidéos et autres contenus, sont protégés par des droits d’auteur et appartiennent exclusivement à PETSMATCH SAS.
  -  Toute reproduction, modification, diffusion ou exploitation, totale ou partielle, sans autorisation écrite préalable, est strictement interdite.
  -  Si vous utilisez des ressources sous licence ou appartenant à des tiers, précisez que leurs droits sont respectés.

5. Données personnelles
  -  L’utilisation des données personnelles est régie par notre Politique de Confidentialité, accessible directement dans l’application https://petsmatchapp.com/404.
  -  Collecte des données : Nous collectons des informations nécessaires au bon fonctionnement de l’application, comme les données d’inscription (nom, email, téléphone), les données de profil (professionnels, éleveurs), et les interactions dans l’application.
  -  Conformité RGPD :
    -  Les utilisateurs disposent de droits d’accès, de rectification, de suppression, et d’opposition sur leurs données.
    -  Pour toute demande relative aux données personnelles, contactez-nous à petsmatch.contact@gmail.com.

6. Limitation de responsabilité
  -  PETSMATCH SAS agit en tant qu’intermédiaire entre les clients, les professionnels du monde animalier, et les éleveurs. Nous ne sommes pas responsables :
    -  Des interactions ou des transactions entre utilisateurs.
    -  Des contenus publiés par les utilisateurs (annonces, profils, avis).
    -  Des dommages liés à une mauvaise utilisation de l’application ou à des interruptions de service (notamment pour des raisons techniques).

7. Litiges et juridiction compétente
  -  En cas de litige, les parties s’efforceront de trouver une solution à l’amiable.
  -  À défaut, la juridiction compétente est celle des tribunaux de Rennes, France.

                    """,
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                SizedBox(
                    height:
                        UTILS.calculHeight(30, UTILS.heightReference(context))),
              ],
            ),
          ),
        ),

    );
  }
}