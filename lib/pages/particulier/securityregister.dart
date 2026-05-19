import 'package:PetsMatch/animation/delayed_animation.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/info_elevage.dart';
import 'package:PetsMatch/pages/particulier/description_page.dart';
import 'package:PetsMatch/pages/particulier/verifemail.dart';
import 'package:PetsMatch/utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class RegisterSecurity extends StatefulWidget {
  const RegisterSecurity({super.key});

  @override
  State<RegisterSecurity> createState() => _RegisterSecurityState();
}

class _RegisterSecurityState extends State<RegisterSecurity> {
  final TextEditingController email = TextEditingController();
  final TextEditingController password = TextEditingController();
  final TextEditingController verifPassword = TextEditingController();

  bool _passwordVisible = false;
  bool _passwordVisible2 = false;
  bool _isEmailValid = true;
  bool _isPasswordValid = true;
  bool _isVerifPasswordValid = true;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    verifPassword.dispose();
    super.dispose();
  }

  // void _validateAndContinue() async {
  //   setState(() {
  //     _isEmailValid = email.text.trim().isNotEmpty;
  //     _isPasswordValid = password.text.trim().isNotEmpty && password.text.length >= 6;
  //     _isVerifPasswordValid = verifPassword.text.trim().isNotEmpty && verifPassword.text == password.text;
  //   });

  //   if (_isEmailValid && _isPasswordValid && _isVerifPasswordValid) {
  //     try {
  //       UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
  //         email: email.text,
  //         password: password.text,
  //       );

  //       User? user = userCredential.user;
  //       if (user != null && !user.emailVerified) {
  //         await user.sendEmailVerification();

  //         Navigator.of(context).push(
  //           MaterialPageRoute(
  //             builder: (context) => VerifyEmailPage(email: email.text),
  //           ),
  //         );
  //       }
  //     } on FirebaseAuthException catch (e) {
  //       print(e.message);
  //     }
  //   }
  // }

  int _calculatePasswordStrength(String password) {
    int strength = 0;
    if (password.length >= 8) strength++;
    if (RegExp(r'[A-Z]').hasMatch(password)) strength++;
    if (RegExp(r'[a-z]').hasMatch(password)) strength++;
    if (RegExp(r'[0-9]').hasMatch(password)) strength++;
    if (RegExp(r'[\W]').hasMatch(password)) strength++;
    return strength;
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
                              104, UTILS.heightReference(context)),
                          child: Stack(children: [
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
                                  53, UTILS.heightReference(context)),
                              left: 0,
                              right: 0,
                              child: Align(
                                alignment: Alignment.center,
                                child: Text(
                                  'INSCRIPTION',
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
                              14, UTILS.heightReference(context))),
                      Align(
                        alignment: Alignment(-0.8, 0),
                        child: Text(
                          'Sécurité',
                          style: TextStyle(
                              fontSize: UTILS.calculWidth(
                                  30, UTILS.widthReference(context)),
                              fontFamily: 'Galey',
                              color: Color(0xFF0C5C6C),
                              fontWeight: FontWeight.w500),
                          textAlign: TextAlign.left,
                        ),
                      ),
                      SizedBox(
                          height: UTILS.calculHeight(
                              10, UTILS.heightReference(context))),
                      SizedBox(
                          height: UTILS.calculHeight(
                              286, UTILS.heightReference(context)),
                          width: UTILS.calculWidth(
                              286, UTILS.widthReference(context)),
                          child: Image.asset('assets/page/password.png')),
                      SizedBox(
                          height: UTILS.calculHeight(
                              28, UTILS.heightReference(context))),
                      SizedBox(
                        height: UTILS.calculHeight(
                            53, UTILS.heightReference(context)),
                        width: UTILS.calculWidth(
                            372, UTILS.widthReference(context)),
                        child: TextFormField(
                          controller: email,
                          cursorColor: Colors.black,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            filled: true,
                            contentPadding: EdgeInsets.symmetric(
                                vertical: UTILS.calculHeight(
                                    12.0, UTILS.heightReference(context)),
                                horizontal: UTILS.calculWidth(
                                    15.0, UTILS.widthReference(context))),
                            fillColor: Color(0xFFA7C79A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  UTILS.calculWidth(
                                      50.0, UTILS.widthReference(context))),
                              borderSide: BorderSide(color: Colors.transparent),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  UTILS.calculWidth(
                                      30.0, UTILS.widthReference(context))),
                              borderSide: BorderSide(
                                  color: _isEmailValid
                                      ? Colors.transparent
                                      : Colors.red,
                                  width: UTILS.calculWidth(
                                      2.0, UTILS.widthReference(context))),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  UTILS.calculWidth(
                                      30.0, UTILS.widthReference(context))),
                              borderSide: BorderSide(
                                  color: Color(0xFFA7C79A),
                                  width: UTILS.calculWidth(
                                      2.0, UTILS.widthReference(context))),
                            ),
                            labelStyle: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                              fontSize: UTILS.calculWidth(
                                  18, UTILS.widthReference(context)),
                            ),
                            prefixIcon: Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: UTILS.calculWidth(
                                      15.0, UTILS.widthReference(context))),
                              child: Icon(Icons.person),
                            ),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                      ),
                      SizedBox(
                          height: UTILS.calculHeight(
                              22, UTILS.heightReference(context))),
                      SizedBox(
                        height: UTILS.calculHeight(
                            53, UTILS.heightReference(context)),
                        width: UTILS.calculWidth(
                            372, UTILS.widthReference(context)),
                        child: TextFormField(
                          cursorColor: Colors.black,
                          controller: password,
                          obscureText: !_passwordVisible,
                          decoration: InputDecoration(
                            labelText: 'Mot de passe',
                            filled: true,
                            contentPadding: EdgeInsets.symmetric(
                                vertical: UTILS.calculHeight(
                                    12.0, UTILS.heightReference(context)),
                                horizontal: UTILS.calculWidth(
                                    15.0, UTILS.widthReference(context))),
                            fillColor: Color(0xFFA7C79A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  UTILS.calculWidth(
                                      50.0, UTILS.widthReference(context))),
                              borderSide: BorderSide(color: Colors.transparent),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  UTILS.calculWidth(
                                      30.0, UTILS.widthReference(context))),
                              borderSide: BorderSide(
                                  color: _isPasswordValid
                                      ? Colors.transparent
                                      : Colors.red,
                                  width: UTILS.calculWidth(
                                      2.0, UTILS.widthReference(context))),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  UTILS.calculWidth(
                                      30.0, UTILS.widthReference(context))),
                              borderSide: BorderSide(
                                  color: Color(0xFFA7C79A),
                                  width: UTILS.calculWidth(
                                      2.0, UTILS.widthReference(context))),
                            ),
                            labelStyle: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                              fontSize: UTILS.calculWidth(
                                  18, UTILS.widthReference(context)),
                            ),
                            prefixIcon: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 15.0),
                              child: Icon(Icons.lock),
                            ),
                            suffixIcon: IconButton(
                              iconSize: UTILS.calculWidth(
                                  20.0, UTILS.widthReference(context)),
                              icon: Icon(
                                _passwordVisible
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _passwordVisible = !_passwordVisible;
                                });
                              },
                            ),
                          ),
                          keyboardType: TextInputType.text,
                          onChanged: (value) {
                            setState(() {});
                          },
                        ),
                      ),
                      SizedBox(
                          height: UTILS.calculHeight(
                              10, UTILS.heightReference(context))),
                      Container(
                        width: UTILS.calculWidth(
                            372, UTILS.widthReference(context)),
                        child: LinearProgressIndicator(
                          value: _calculatePasswordStrength(password.text) / 5,
                          backgroundColor: Color.fromARGB(0, 255, 255, 255),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _calculatePasswordStrength(password.text) < 2
                                ? Colors.red
                                : _calculatePasswordStrength(password.text) < 4
                                    ? Colors.orange
                                    : Colors.green,
                          ),
                        ),
                      ),
                      SizedBox(
                          height: UTILS.calculHeight(
                              22, UTILS.heightReference(context))),
                      SizedBox(
                        height: UTILS.calculHeight(
                            53, UTILS.heightReference(context)),
                        width: UTILS.calculWidth(
                            372, UTILS.widthReference(context)),
                        child: TextFormField(
                          controller: verifPassword,
                          cursorColor: Colors.black,
                          obscureText: !_passwordVisible2,
                          decoration: InputDecoration(
                            labelText: 'Confirmer votre mot de passe',
                            filled: true,
                            contentPadding: EdgeInsets.symmetric(
                                vertical: UTILS.calculHeight(
                                    12.0, UTILS.heightReference(context)),
                                horizontal: UTILS.calculWidth(
                                    15.0, UTILS.widthReference(context))),
                            fillColor: Color(0xFFA7C79A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  UTILS.calculWidth(
                                      50.0, UTILS.widthReference(context))),
                              borderSide: BorderSide(color: Colors.transparent),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  UTILS.calculWidth(
                                      30.0, UTILS.widthReference(context))),
                              borderSide: BorderSide(
                                  color: _isVerifPasswordValid
                                      ? Colors.transparent
                                      : Colors.red,
                                  width: UTILS.calculWidth(
                                      2.0, UTILS.widthReference(context))),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  UTILS.calculWidth(
                                      30.0, UTILS.widthReference(context))),
                              borderSide: BorderSide(
                                  color: Color(0xFFA7C79A),
                                  width: UTILS.calculWidth(
                                      2.0, UTILS.widthReference(context))),
                            ),
                            labelStyle: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                              fontSize: UTILS.calculWidth(
                                  18, UTILS.widthReference(context)),
                            ),
                            prefixIcon: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 15.0),
                              child: Icon(Icons.lock),
                            ),
                            suffixIcon: IconButton(
                              iconSize: UTILS.calculWidth(
                                  20.0, UTILS.widthReference(context)),
                              icon: Icon(
                                _passwordVisible2
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _passwordVisible2 = !_passwordVisible2;
                                });
                              },
                            ),
                          ),
                          keyboardType: TextInputType.text,
                        ),
                      ),
                      SizedBox(
                          height: UTILS.calculHeight(
                              49, UTILS.heightReference(context))),
                      Align(
                        alignment: Alignment.center,
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
                                    color: Color.fromARGB(255, 0, 0, 0),
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
                              19, UTILS.heightReference(context))),
                      SizedBox(
                          height: UTILS.calculHeight(
                              66, UTILS.heightReference(context)),
                          width: UTILS.calculWidth(
                              367, UTILS.widthReference(context)),
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                  _isEmailValid = email.text.trim().isNotEmpty;
                                  _isPasswordValid = password.text.trim().isNotEmpty && password.text.length >= 6;
                                  _isVerifPasswordValid = verifPassword.text.trim().isNotEmpty && verifPassword.text == password.text;
                              });
                              if (_isEmailValid &&
                                  _isPasswordValid &&
                                  _isVerifPasswordValid) {
                                  User_Info.email = email.text;
                                  User_Info.password = password.text;
                                  if (User_Info.isElevage || User_Info.isPro) {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            RegisterElevageInformation(),
                                      ),
                                    );
                                  } else {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            DescriptionRegistrationPage(),
                                      ),
                                    );
                                  }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Color(0xFFA7C79A)),
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
                          )),
                      SizedBox(
                          height: UTILS.calculHeight(
                              18.5, UTILS.heightReference(context))),
                      Image.asset(
                        'assets/deco/arrondi_green_deco_2.png',
                        fit: BoxFit.cover,
                        width: UTILS.calculWidth(
                            233, UTILS.widthReference(context)),
                        height: UTILS.calculHeight(
                            52, UTILS.heightReference(context)),
                      ),
                    ])))));
  }
}
