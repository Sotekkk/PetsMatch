import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserParticulierFeedDetails extends StatelessWidget {
  final String profilePictureUrl;
  final String description;
  final String adoptionProject;
  final String name;
  const UserParticulierFeedDetails({
    required this.profilePictureUrl,
    required this.description,
    required this.adoptionProject,
    required this.name,
    Key? key,
  }) : super(key: key);

  Future<void> _sendSignalementEmail({
    required String uidSignaleur,
    required String uidSignale,
    required String motif,
    String? details,
  }) async {
    String username = 'petsmatch.contact@gmail.com';
    String password = 'dppu ctgp buve bxjd';

    final smtpServer = gmail(username, password);

    final message = Message()
      ..from = Address(username, 'PetsMatch - Signalement')
      ..recipients.add('petsmatch.contact@gmail.com')
      ..subject = '🔔 Signalement utilisateur : $uidSignale'
      ..text = '''
Un utilisateur a été signalé via l'application PetsMatch.

🔹 UID de l'utilisateur signalé : $uidSignale
🔹 UID de la personne ayant signalé : $uidSignaleur
🔹 Motif : $motif
🔹 Détails : ${details ?? "Non précisé"}

Veuillez traiter ce signalement sous 24h conformément aux CGU.

- PetsMatch App
    ''';

    try {
      await send(message, smtpServer);
      print('✅ Signalement envoyé.');
    } on MailerException catch (e) {
      print('❌ Erreur d’envoi : $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            children: [
              SizedBox(
                width: UTILS.widthReference(context),
                height: UTILS.calculHeight(141, UTILS.heightReference(context)),
                child: Stack(
                  children: [
                    Image.asset(
                      'assets/deco/arrondideco.png',
                      fit: BoxFit.cover,
                      width:
                          UTILS.calculWidth(151, UTILS.widthReference(context)),
                      height: UTILS.calculHeight(
                          141, UTILS.heightReference(context)),
                    ),
                    Positioned(
                      top: UTILS.calculHeight(
                          53, UTILS.heightReference(context)),
                      left: 0,
                      right: 0,
                      child: Align(
                        alignment: Alignment.center,
                        child: Text(
                          name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            fontSize: UTILS.calculWidth(
                                20, UTILS.widthReference(context)),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: UTILS.calculHeight(
                          42, UTILS.heightReference(context)),
                      right:
                          UTILS.calculWidth(15, UTILS.widthReference(context)),
                      child: PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, color: Colors.black),
                        onSelected: (String value) async {
                          if (value == 'signaler') {
                            String selectedMotif = 'Comportement abusif';
                            TextEditingController detailController =
                                TextEditingController();

                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return StatefulBuilder(
                                  builder: (context, setState) => AlertDialog(
                                    title: Text('Signaler un utilisateur'),
                                    content: SingleChildScrollView(
                                      child: Column(
                                        children: [
                                          RadioListTile(
                                            title: Text('Comportement abusif'),
                                            value: 'Comportement abusif',
                                            groupValue: selectedMotif,
                                            onChanged: (value) => setState(
                                                () => selectedMotif = value!),
                                          ),
                                          RadioListTile(
                                            title: Text('Contenu inapproprié'),
                                            value: 'Contenu inapproprié',
                                            groupValue: selectedMotif,
                                            onChanged: (value) => setState(
                                                () => selectedMotif = value!),
                                          ),
                                          RadioListTile(
                                            title: Text('Spam ou arnaque'),
                                            value: 'Spam ou arnaque',
                                            groupValue: selectedMotif,
                                            onChanged: (value) => setState(
                                                () => selectedMotif = value!),
                                          ),
                                          RadioListTile(
                                            title: Text('Autre'),
                                            value: 'Autre',
                                            groupValue: selectedMotif,
                                            onChanged: (value) => setState(
                                                () => selectedMotif = value!),
                                          ),
                                          SizedBox(height: 10),
                                          TextField(
                                            controller: detailController,
                                            maxLines: 3,
                                            decoration: InputDecoration(
                                              hintText: 'Détails (facultatif)',
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: Text('Annuler'),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Color.fromARGB(
                                              255, 255, 192, 187),
                                        ),
                                        onPressed: () async {
                                          try {
                                            await _sendSignalementEmail(
                                              uidSignaleur: FirebaseAuth
                                                  .instance.currentUser!.uid,
                                              uidSignale: name,
                                              motif: selectedMotif,
                                              details:
                                                  detailController.text.trim(),
                                            );
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                  content: Text(
                                                      '✅ Signalement envoyé.')),
                                            );
                                            Navigator.pop(context);
                                          } catch (e) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                  content: Text(
                                                      '❌ Erreur lors de l\'envoi.')),
                                            );
                                            Navigator.pop(context);
                                          }
                                        },
                                        child: Text('Envoyer',
                                            style:
                                                TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          } else if (value == 'bloquer') {
                            String currentUserUid =
                                FirebaseAuth.instance.currentUser!.uid;

                            await FirebaseFirestore.instance
                                .collection('bloquer')
                                .doc(currentUserUid)
                                .set({name: true}, SetOptions(merge: true));

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      '🚫 Utilisateur bloqué avec succès.')),
                            );
                          }
                        },
                        itemBuilder: (BuildContext context) =>
                            <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            value: 'signaler',
                            child: Row(
                              children: [
                                Icon(Icons.report, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Signaler'),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'bloquer',
                            child: Row(
                              children: [
                                Icon(Icons.block, color: Colors.black),
                                SizedBox(width: 8),
                                Text('Bloquer'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: UTILS.calculHeight(
                          42, UTILS.heightReference(context)),
                      left:
                          UTILS.calculWidth(10, UTILS.widthReference(context)),
                      child: IconButton(
                        icon: Icon(Icons.arrow_back,
                            color: Colors.black), // Icône de la flèche noire
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.black,
                    radius: 39.5,
                    backgroundImage: NetworkImage(profilePictureUrl),
                  ),
                  SizedBox(
                    height:
                        UTILS.calculHeight(13, UTILS.heightReference(context)),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: Text(
                      'Photo de profil',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w500,
                        fontSize: UTILS.calculWidth(
                            20, UTILS.widthReference(context)),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: UTILS.calculHeight(55, UTILS.heightReference(context)),
              ),
              Align(
                alignment: Alignment(-0.87, 0),
                child: Text(
                  'Mes informations',
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontFamily: 'Galey',
                    color: Color.fromARGB(255, 0, 0, 0),
                    fontWeight: FontWeight.w700,
                    fontSize:
                        UTILS.calculWidth(17, UTILS.widthReference(context)),
                  ),
                ),
              ),
              SizedBox(
                height: UTILS.calculHeight(16, UTILS.heightReference(context)),
              ),
              Container(
                width: UTILS.calculWidth(406, UTILS.widthReference(context)),
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color.fromARGB(176, 250, 192, 187),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    description.isNotEmpty
                        ? description
                        : "Pas de description disponible.",
                    style: TextStyle(
                      fontFamily: 'Galey',
                      fontSize:
                          UTILS.calculWidth(15, UTILS.widthReference(context)),
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: UTILS.calculHeight(34, UTILS.heightReference(context)),
              ),
              Align(
                alignment: Alignment(-0.8, 0),
                child: Text(
                  "Description de votre projet d'adoption",
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontFamily: 'Galey',
                    color: Color.fromARGB(255, 0, 0, 0),
                    fontWeight: FontWeight.w700,
                    fontSize:
                        UTILS.calculWidth(17, UTILS.widthReference(context)),
                  ),
                ),
              ),
              SizedBox(
                height: UTILS.calculHeight(20, UTILS.heightReference(context)),
              ),
              Container(
                width: UTILS.calculWidth(406, UTILS.widthReference(context)),
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color.fromARGB(176, 250, 192, 187),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    adoptionProject.isNotEmpty
                        ? adoptionProject
                        : "Pas de projet d'adoption disponible.",
                    style: TextStyle(
                      fontFamily: 'Galey',
                      fontSize:
                          UTILS.calculWidth(15, UTILS.widthReference(context)),
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: UTILS.calculHeight(20, UTILS.heightReference(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
