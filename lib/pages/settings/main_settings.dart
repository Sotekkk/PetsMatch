import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/connect_page.dart';
import 'package:PetsMatch/pages/pro/pro_profile_edit.dart';
import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:PetsMatch/pages/settings/about_us.dart';
import 'package:PetsMatch/pages/settings/connectionSecu.dart';
import 'package:PetsMatch/pages/settings/info_utilisateur.dart';
import 'package:PetsMatch/pages/settings/parametre_config.dart';
import 'package:PetsMatch/utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsMainPage extends StatefulWidget {
  const SettingsMainPage({super.key});

  @override
  State<SettingsMainPage> createState() => _SettingsMainPageState();
}

class _SettingsMainPageState extends State<SettingsMainPage>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  AnimationController? _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }

  void _triggerVaccinationReminder() async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
      final HttpsCallable callable =
          functions.httpsCallable('triggerVaccinationReminder');
      // final HttpsCallable callable =
      //     FirebaseFunctions.instance.httpsCallable('triggerVaccinationReminder');
      final response = await callable();
      print('Réponse de la fonction : ${response.data}');
    } catch (e) {
      print('Erreur lors de l’appel de la fonction : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          child: Column(
            children: [
              SizedBox(
                width: UTILS.widthReference(context),
                height: UTILS.calculHeight(
                  105,
                  UTILS.heightReference(context),
                ),
                child: Stack(
                  children: [
                    Image.asset(
                      'assets/deco/arrondi_rose_2.png',
              color: const Color(0xFFA7C79A),
              colorBlendMode: BlendMode.srcIn,
                      fit: BoxFit.cover,
                      width:
                          UTILS.calculWidth(211, UTILS.widthReference(context)),
                      height: UTILS.calculHeight(
                        104,
                        UTILS.heightReference(context),
                      ),
                    ),
                    Positioned(
                      top: UTILS.calculHeight(
                          42, UTILS.heightReference(context)),
                      left:
                          UTILS.calculWidth(10, UTILS.widthReference(context)),
                      child: IconButton(
                        icon: Icon(Icons.arrow_back, color: Colors.black),
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
                          'Paramètres',
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
                  ],
                ),
              ),
              SizedBox(
                height: UTILS.calculHeight(20, UTILS.heightReference(context)),
              ),
              Text(
                'A propos du compte',
                style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w500,
                  fontSize:
                      UTILS.calculWidth(18, UTILS.widthReference(context)),
                ),
              ),
              SizedBox(
                height: UTILS.calculHeight(10, UTILS.heightReference(context)),
              ),
              buildSettingsOption(
                context,
                icon: Icons.account_circle,
                text: 'Information utilisateur',
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => InfoUserSettings()));
                },
              ),
              if (User_Info.isPro) ...[
                buildSettingsOption(
                  context,
                  icon: Icons.business_center_outlined,
                  text: 'Mon profil professionnel',
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const ProProfileEditPage()));
                  },
                ),
                buildSettingsOption(
                  context,
                  icon: Icons.calendar_month_outlined,
                  text: 'Mon agenda RDV',
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const ProAgendaPage()));
                  },
                ),
              ],
              buildSettingsOption(
                context,
                icon: Icons.security,
                text: 'Connexion et sécurité',
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => SecuConnectionSetting()));
                  // Naviguer vers la page des paramètres de sécurité
                },
              ),
              // buildSettingsOption(
              //   context,
              //   icon: Icons.favorite,
              //   text: 'Bien être utilisateur',
              //   onTap: () {
              //     // Naviguer vers la page des paramètres de bien-être
              //   },
              // ),
              SizedBox(
                height: UTILS.calculHeight(20, UTILS.heightReference(context)),
              ),
              Text(
                'A propos de l’application',
                style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w500,
                  fontSize:
                      UTILS.calculWidth(18, UTILS.widthReference(context)),
                ),
              ),
              SizedBox(
                height: UTILS.calculHeight(10, UTILS.heightReference(context)),
              ),
              buildSettingsOption(
                context,
                icon: Icons.privacy_tip,
                text: 'Paramètre de confidentialité',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ParametreConfi(),
                    ),
                  );
                },
              ),
              // buildSettingsOption(
              //   context,
              //   icon: Icons.help,
              //   text: 'Aide',
              //   onTap: () {
              //        _triggerVaccinationReminder();
              //     // Naviguer vers la page d'aide
              //   },
              // ),
              buildSettingsOption(
                context,
                icon: Icons.info,
                text: 'A propos',
                onTap: () {
                  // Naviguer vers la page à propos
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => AboutUs(),
                    ),
                  );
                },
              ),
              SizedBox(
                height: UTILS.calculHeight(30, UTILS.heightReference(context)),
              ),
              ElevatedButton(
                onPressed: () async {
                  await _auth.signOut();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => WelcomePage()),
                    (Route<dynamic> route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      Colors.red, // Couleur rouge pour le bouton de déconnexion
                  minimumSize: Size(
                    UTILS.calculWidth(406, UTILS.widthReference(context)),
                    UTILS.calculHeight(45, UTILS.heightReference(context)),
                  ),
                ),
                child: Text(
                  'SE DÉCONNECTER',
                  style: TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    fontSize:
                        UTILS.calculWidth(17, UTILS.widthReference(context)),
                  ),
                ),
              ),
              SizedBox(
                height: UTILS.calculHeight(30, UTILS.heightReference(context)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final user = FirebaseAuth.instance.currentUser;
                  final email = user?.email;

                  if (user == null || email == null) return;

                  String? passwordInput;

                  final result = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      final TextEditingController passwordController =
                          TextEditingController();
                      return AlertDialog(
                        title: Text('Confirmation de suppression'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                                'Pour des raisons de sécurité, entre ton mot de passe pour confirmer la suppression de ton compte.'),
                            SizedBox(height: 12),
                            TextField(
                              controller: passwordController,
                              obscureText: true,
                              decoration:
                                  InputDecoration(labelText: 'Mot de passe'),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, null),
                            child: Text('Annuler'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(
                                  context, passwordController.text.trim());
                            },
                            child: Text('Supprimer'),
                          ),
                        ],
                      );
                    },
                  );

                  passwordInput = result;

                  if (passwordInput == null || passwordInput.trim().isEmpty)
                    return;

                  try {
                    // Re-authenticate
                    final credential = EmailAuthProvider.credential(
                      email: email,
                      password: passwordInput,
                    );
                    await user.reauthenticateWithCredential(credential);

                    final uid = user.uid;
                    final firestore = FirebaseFirestore.instance;

                    final collectionsWithUidAsDocID = [
                      'users',
                      'dogfiche',
                      'catfiche',
                      'subscription',
                      'likedPost',
                    ];

                    for (final collection in collectionsWithUidAsDocID) {
                      await firestore
                          .collection(collection)
                          .doc(uid)
                          .delete()
                          .catchError((e) {
                        print('Erreur suppression $collection: $e');
                      });
                    }

                    final postSnapshot = await firestore
                        .collection('post')
                        .where('uidEleveur', isEqualTo: uid)
                        .get();
                    for (final doc in postSnapshot.docs) {
                      await doc.reference.delete().catchError((e) {
                        print('Erreur suppression post: $e');
                      });
                    }

                    // Supprimer compte Firebase Auth
                    await user.delete();

                    // Rediriger
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => WelcomePage()),
                      (Route<dynamic> route) => false,
                    );
                  } catch (e) {
                    print('Erreur : $e');
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Erreur'),
                        content: Text('La suppression du compte a échoué.\n$e'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text('OK'),
                          )
                        ],
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  minimumSize: Size(
                    UTILS.calculWidth(406, UTILS.widthReference(context)),
                    UTILS.calculHeight(45, UTILS.heightReference(context)),
                  ),
                ),
                child: Text(
                  'Supprimer le compte',
                  style: TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    fontSize:
                        UTILS.calculWidth(17, UTILS.widthReference(context)),
                  ),
                ),
              ),
              SizedBox(
                height: UTILS.calculHeight(30, UTILS.heightReference(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildSettingsOption(BuildContext context,
      {required IconData icon, required String text, required Function onTap}) {
    return Padding(
      padding: EdgeInsets.symmetric(
          vertical: UTILS.calculHeight(8, UTILS.heightReference(context))),
      child: GestureDetector(
        onTap: () => onTap(),
        child: Container(
          width: UTILS.calculWidth(406, UTILS.widthReference(context)),
          height: UTILS.calculHeight(45, UTILS.heightReference(context)),
          decoration: BoxDecoration(
            color: Color.fromARGB(177, 250, 192, 187),
            borderRadius: BorderRadius.circular(500),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  SizedBox(
                      width:
                          UTILS.calculWidth(16, UTILS.widthReference(context))),
                  Icon(icon, color: Colors.black),
                  SizedBox(
                      width:
                          UTILS.calculWidth(16, UTILS.widthReference(context))),
                  Text(
                    text,
                    style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w500,
                      fontSize:
                          UTILS.calculWidth(17, UTILS.widthReference(context)),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: EdgeInsets.only(
                    right:
                        UTILS.calculWidth(16, UTILS.widthReference(context))),
                child: Icon(Icons.arrow_forward_ios,
                    color: Colors.black,
                    size: UTILS.calculWidth(20, UTILS.widthReference(context))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
