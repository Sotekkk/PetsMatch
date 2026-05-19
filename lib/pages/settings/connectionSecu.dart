import 'dart:io';
import 'package:PetsMatch/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:PetsMatch/utils.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:email_validator/email_validator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class SecuConnectionSetting extends StatefulWidget {
  const SecuConnectionSetting({super.key});

  @override
  State<SecuConnectionSetting> createState() => _SecuConnectionSettingState();
}

class _SecuConnectionSettingState extends State<SecuConnectionSetting> {
  @override
  void initState() {
    super.initState();
    Firebase.initializeApp(); // Initialize Firebase
  }

  void _openAppSettings() {
    if (Platform.isAndroid) {
      final intent = AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:com.example.PetsMatch', // Remplacez par le nom de votre package
      );
      intent.launch();
    } else if (Platform.isIOS) {
      // Ouvre les paramètres de l'application sur iOS
      launch('app-settings:');
    }
  }

  void _sendQuestionEmail(String recipient, String subject, String body) async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: recipient,
      query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );
    if (await canLaunch(emailLaunchUri.toString())) {
      await launch(emailLaunchUri.toString());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible d\'envoyer l\'email.')),
      );
    }
  }

  void _sendPasswordResetEmail(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Email de réinitialisation de mot de passe envoyé.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString()}')),
      );
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
                height: UTILS.calculHeight(105, UTILS.heightReference(context)),
                child: Stack(
                  children: [
                    Image.asset(
                      'assets/deco/arrondi_rose_2.png',
              color: const Color(0xFFA7C79A),
              colorBlendMode: BlendMode.srcIn,
                      fit: BoxFit.cover,
                      width: UTILS.calculWidth(211, UTILS.widthReference(context)),
                      height: UTILS.calculHeight(104, UTILS.heightReference(context)),
                    ),
                    Positioned(
                      top: UTILS.calculHeight(42, UTILS.heightReference(context)),
                      left: UTILS.calculWidth(10, UTILS.widthReference(context)),
                      child: IconButton(
                        icon: Icon(Icons.arrow_back, color: Colors.black),
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                    Positioned(
                      top: UTILS.calculHeight(53, UTILS.heightReference(context)),
                      left: 0,
                      right: 0,
                      child: Align(
                        alignment: Alignment.center,
                        child: Text(
                          'Connexion et sécurité',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            fontSize: UTILS.calculWidth(20, UTILS.widthReference(context)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              buildSettingsOption(
                context,
                icon: Icons.perm_device_info,
                text: 'Gestion des permissions',
                onTap: _openAppSettings,
              ),
              buildSettingsOption(
                context,
                icon: Icons.question_mark,
                text: 'Posez-nous une question',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => QuestionPage(),
                    ),
                  );
                },
              ),
              buildSettingsOption(
                context,
                icon: Icons.password,
                text: 'Réinitialisation de mot de passe',
                onTap: () {
                  _sendPasswordResetEmail(User_Info.email);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildSettingsOption(BuildContext context, {required IconData icon, required String text, required Function onTap}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: UTILS.calculHeight(8, UTILS.heightReference(context))),
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
                  SizedBox(width: UTILS.calculWidth(16, UTILS.widthReference(context))),
                  Icon(icon, color: Colors.black),
                  SizedBox(width: UTILS.calculWidth(16, UTILS.widthReference(context))),
                  Text(
                    text,
                    style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w500,
                      fontSize: UTILS.calculWidth(17, UTILS.widthReference(context)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QuestionPage extends StatefulWidget {
  @override
  _QuestionPageState createState() => _QuestionPageState();
}

class _QuestionPageState extends State<QuestionPage> {
  final TextEditingController _questionController = TextEditingController();
  bool _isLoading = false;

  void _sendRegistrationEmail(Object uid, String msg) async {
  setState(() {
    _isLoading = true;
  });

  String username = 'petsmatch.contact@gmail.com'; // Remplacez par votre adresse email
  String password = 'dppu ctgp buve bxjd'; // Remplacez par votre mot de passe d'application (ou le mot de passe de l'email, si applicable)

  final smtpServer = gmail(username, password);

  if (msg.trim().isEmpty) {
    setState(() {
      _isLoading = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Votre message est vide.')),
      );
    });
    return;
  }

  String documents = User_Info.documentElevage.map((doc) {
    return '''
      Catégorie: ${doc['category']}
      Nom: ${doc['name']}
      Téléchargé: ${doc['uploaded']}
      URL: ${doc['url']}
    ''';
  }).join('\n');

  final message = Message()
    ..from = Address(username, 'Application PetsMatch')
    ..recipients.add('petsmatch.contact@gmail.com')
    ..subject = 'Question Support'
    ..text = '''
      Détails de la personne:
      UID: ${uid}
      Nom: ${User_Info.firstname} ${User_Info.lastname}
      Email: ${User_Info.email}
      Date de naissance: ${User_Info.dateofbirth}
      Numéro de téléphone: ${User_Info.phone_number}
      Adresse: ${User_Info.adress}
      Élevage: ${User_Info.isElevage ? "Oui" : "Non"}
      Adresse de l'élevage: ${User_Info.adressElevage}
      Nom de l'élevage: ${User_Info.nameElevage}
      Code ISO Elevage: ${User_Info.codeISOElevage}
      Numéro de l'élevage: ${User_Info.numeroElevage}
      
      Message de la demande : $msg
    ''';

  try {
    final sendReport = await send(message, smtpServer);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Votre question a été envoyée.')),
    );
  } on MailerException catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Erreur : message non envoyé.')),
    );
    for (var p in e.problems) {
      print('Problème: ${p.code}: ${p.msg}');
    }
  } finally {
    setState(() {
      _isLoading = false;
    });
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(

      body: Center(
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
                          'Posez nous une question ?',
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
                )),
              SizedBox(height: UTILS.calculHeight(50, UTILS.heightReference(context))),

            _buildStyledTextField(_questionController, 'Votre question', Icons.question_mark, maxLines: 5),
            SizedBox(height: UTILS.calculHeight(20, UTILS.heightReference(context))),
            SizedBox(
                  height:
                      UTILS.calculHeight(50, UTILS.heightReference(context)),
                  width: UTILS.calculWidth(367, UTILS.widthReference(context)),
                  child:ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      _sendRegistrationEmail(User_Info.uid, _questionController.text);
                    },
              style: ButtonStyle(
                backgroundColor: MaterialStateProperty.resolveWith<Color>(
                  (Set<MaterialState> states) {
                    if (states.contains(MaterialState.disabled)) return Colors.grey;
                    return Color.fromARGB(255, 249, 150, 143); // Use the component's default.
                  },
                ),
              ),
              child: _isLoading
                  ? CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    )
                  : Text('Envoyer'),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildStyledTextField(TextEditingController controller, String label, IconData icon, {int maxLines = 1}) {
    return SizedBox(
      height: maxLines == 1 ? UTILS.calculHeight(53, UTILS.heightReference(context)) : null,
      width: UTILS.calculWidth(367, UTILS.widthReference(context)),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          contentPadding: EdgeInsets.symmetric(
            vertical: UTILS.calculHeight(12.0, UTILS.heightReference(context)),
            horizontal: UTILS.calculWidth(15.0, UTILS.widthReference(context)),
          ),
          fillColor: Color(0xFFA7C79A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(UTILS.calculWidth(50.0, UTILS.widthReference(context))),
            borderSide: BorderSide(color: Colors.transparent),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(UTILS.calculWidth(30.0, UTILS.widthReference(context))),
            borderSide: BorderSide(color: Colors.transparent),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(UTILS.calculWidth(30.0, UTILS.widthReference(context))),
            borderSide: BorderSide(color: Color(0xFFA7C79A), width: UTILS.calculWidth(2.0, UTILS.widthReference(context))),
          ),
          labelStyle: TextStyle(
            fontFamily: 'Galey',
            fontWeight: FontWeight.w500,
            color: Colors.black,
            fontSize: UTILS.calculWidth(17, UTILS.widthReference(context)),
          ),
          prefixIcon: Padding(
            padding: EdgeInsets.symmetric(horizontal: UTILS.calculWidth(15.0, UTILS.widthReference(context))),
            child: Icon(icon),
          ),
        ),
      ),
    );
  }
}