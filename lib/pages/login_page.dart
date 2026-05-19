import 'package:PetsMatch/animation/delayed_animation.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/admin/admin_panel.dart';
import 'package:PetsMatch/pages/bottom_nav.dart';
import 'package:PetsMatch/pages/eleveur/verification_page.dart';
import 'package:PetsMatch/pages/inscription_main.dart';
import 'package:PetsMatch/pages/password_oublier.dart';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _passwordVisible = false;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _emailError = false;
  bool _passwordError = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _validateAndLogin() async {
    setState(() {
      _emailError = false;
      _passwordError = false;
    });

    try {
      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );

      // Fetch additional user info from Firestore
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();
      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

      // Update User_Info with fetched data
      User_Info.updateUserInfo(userData);

      if (mounted) {
        Widget destination;
        if (User_Info.isAdmin) {
          destination = AdminPanel();
        } else if (User_Info.isValidate) {
          destination = BottomNav();
        } else {
          destination = VerificationRegistrationPage();
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => destination),
        );
      }
    } on FirebaseAuthException catch (e) {
 

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Email ou mot de passe incorrect.')),
        );
        
      setState(() {
          _emailError = true;
          _passwordError = true;
          
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: DelayedAnimation(
            delay: 0,
            child: Column(
              children: [
                SizedBox(
                  width: UTILS.widthReference(context),
                  height: UTILS.calculHeight(141, UTILS.heightReference(context)), // Hauteur fixe pour le Stack
                  child: Stack(
                    children: [
                      Image.asset(
                        'assets/deco/arrondideco.png',
                        fit: BoxFit.cover,
                        width: UTILS.calculWidth(151, UTILS.widthReference(context)),
                        height: UTILS.calculHeight(141, UTILS.heightReference(context)), // Hauteur fixe pour le Stack
                      ),
                      Positioned(
                        top: UTILS.calculHeight(53, UTILS.heightReference(context)),
                        left: 0,
                        right: 0, // Assurez-vous que left et right sont définis à 0 pour permettre au texte de centrer exactement
                        child: Align(
                          alignment: Alignment.center,
                          child: Text(
                            'CONNECTION',
                            textAlign: TextAlign.center, // Assurez-vous d'utiliser textAlign pour garantir que le texte est centré à l'intérieur du Text widget.
                            style: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              fontSize: UTILS.calculWidth(20, UTILS.widthReference(context)),
                            ),
                          ),
                        ),
                      )
                    ],
                  ),
                ),
                SizedBox(
                  height: UTILS.calculHeight(275, UTILS.heightReference(context)),
                  width: UTILS.calculWidth(275, UTILS.widthReference(context)),
                  child: Image.asset('assets/page/girl_with_cat.png'),
                ),
                SizedBox(
                  height: UTILS.calculHeight(32, UTILS.heightReference(context)),
                ),
                SizedBox(
                  height: UTILS.calculHeight(55, UTILS.heightReference(context)),
                  width: UTILS.calculWidth(325, UTILS.widthReference(context)),
                  child: TextFormField(
                    controller: _emailController,
                    cursorColor: Colors.black,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      filled: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 15.0),
                      fillColor: Color.fromARGB(255, 250, 192, 187),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(50.0),
                        borderSide: BorderSide(color: Colors.transparent),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30.0),
                        borderSide: BorderSide(
                          color: _emailError ? Colors.red : Colors.transparent,
                          width: 2.0, // Couleur de la bordure lorsque le champ est inactif
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30.0),
                        borderSide: BorderSide(
                          color: _emailError ? Colors.red : Color.fromARGB(255, 250, 192, 187),
                          width: 2.0, // Couleur de la bordure lorsque le champ est sélectionné
                        ),
                      ),
                      labelStyle: TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                        fontSize: UTILS.calculWidth(18, UTILS.widthReference(context)),
                      ),
                      prefixIcon: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 15.0),
                        child: Icon(Icons.person),
                      ),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                SizedBox(
                  height: UTILS.calculHeight(20, UTILS.heightReference(context)),
                ),
                SizedBox(
                  height: UTILS.calculHeight(55, UTILS.heightReference(context)),
                  width: UTILS.calculWidth(325, UTILS.widthReference(context)),
                  child: TextFormField(
                    controller: _passwordController,
                    cursorColor: Colors.black,
                    obscureText: !_passwordVisible, // Ici, nous utilisons la variable d'état pour le texte masqué
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      filled: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 15.0),
                      fillColor: Color.fromARGB(255, 250, 192, 187),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(50.0),
                        borderSide: BorderSide(color: Colors.transparent),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30.0),
                        borderSide: BorderSide(
                          color: _passwordError ? Colors.red : Colors.transparent,
                          width: 2.0,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30.0),
                        borderSide: BorderSide(
                          color: _passwordError ? Colors.red : Color.fromARGB(255, 250, 192, 187),
                          width: 2.0,
                        ),
                      ),
                      labelStyle: TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                        fontSize: UTILS.calculWidth(18, UTILS.widthReference(context)),
                      ),
                      prefixIcon: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 15.0),
                        child: Icon(Icons.lock),
                      ),
                      suffixIcon: IconButton(
                        iconSize: 20.0,
                        icon: Icon(
                          _passwordVisible ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _passwordVisible = !_passwordVisible;
                          });
                        },
                      ),
                    ),
                    keyboardType: TextInputType.text,
                  ),
                ),
                SizedBox(
                  height: UTILS.calculHeight(11, UTILS.heightReference(context)),
                ),
                Align(
                  alignment: Alignment.center, // Alignez le bouton à droite
                  child: InkWell(
                    onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => PasswordResetPage()));
                    },
                    child: RichText(
                      text: const TextSpan(
                        text: "",
                        style: TextStyle(color: Colors.black),
                        children: <TextSpan>[
                          TextSpan(
                            text: 'Mot de passe oublié?',
                            style: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Color.fromARGB(255, 255, 132, 132), // Mettez ici la couleur de votre choix
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: UTILS.calculHeight(23, UTILS.heightReference(context)),
                ),
                SizedBox(
                  height: UTILS.calculHeight(61, UTILS.heightReference(context)),
                  width: UTILS.calculWidth(325, UTILS.widthReference(context)),
                  child: ElevatedButton(
                    onPressed: _validateAndLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromARGB(255, 255, 132, 132), // Couleur de fond du bouton
                    ),
                    child: Text(
                      'SE CONNECTER',
                      style: TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w500,
                        color: Color.fromARGB(255, 255, 255, 255),
                        fontSize: UTILS.calculWidth(17, UTILS.widthReference(context)),
                      ),
                    ),
                    // Personnaliser le style du bouton
                  ),
                ),
                SizedBox(height: UTILS.calculHeight(22, UTILS.heightReference(context))), // Espace vertical entre le texte et les boutons
                InkWell(
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => InscriptionChoicePage()));
                  },
                  child: RichText(
                    text: const TextSpan(
                      text: "Vous n'avez pas de compte ? ",
                      style: TextStyle(
                        color: Colors.black,
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w500,
                      ),
                      children: <TextSpan>[
                        TextSpan(
                          text: 'Inscrivez vous',
                          style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            color: Color.fromARGB(255, 255, 132, 132), // Mettez ici la couleur de votre choix
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: UTILS.calculHeight(13, UTILS.heightReference(context))), // Espace vertical entre le texte et les boutons
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 138, // Largeur du premier divider
                      child: Divider(
                        color: Color.fromARGB(255, 176, 193, 187),
                        thickness: 1,
                      ),
                    ),
                    SizedBox(
                      width: 138, // Largeur du premier divider
                      child: Divider(
                        color: Color.fromARGB(255, 176, 193, 187),
                        thickness: 1,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: UTILS.calculHeight(20, UTILS.heightReference(context))), // Espace vertical entre le texte et les boutons
                SizedBox(height: UTILS.calculHeight(91.5, UTILS.heightReference(context))),
                Image.asset(
                  'assets/deco/arrondi_green_deco_2.png',
                  fit: BoxFit.cover,
                  width: UTILS.calculWidth(233, UTILS.widthReference(context)),
                  height: UTILS.calculHeight(52, UTILS.heightReference(context)), // Hauteur fixe pour l'image
                ), // Espace vertical entre le texte et les boutons
              ],
            ),
          ),
        ),
      ),
    );
  }
}


