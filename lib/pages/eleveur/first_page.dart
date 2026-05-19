// ignore_for_file: prefer_const_constructors

import 'package:PetsMatch/animation/delayed_animation.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/particulier/numberadressregistration.dart';
import 'package:PetsMatch/pages/particulier/securityregister.dart';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'dart:io';

class RegisterEleveurInformationPage extends StatefulWidget {
  const RegisterEleveurInformationPage({super.key});

  @override
  State<RegisterEleveurInformationPage> createState() =>
      _RegisterEleveurInformationPageState();
}

class _RegisterEleveurInformationPageState
    extends State<RegisterEleveurInformationPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  TextEditingController controllerNom = TextEditingController();
  TextEditingController controllerPrenom = TextEditingController();
  TextEditingController controllerDateNaissance = TextEditingController();

  final ImagePicker _picker =
      ImagePicker(); // S'assurer que ceci est bien déclaré dans la portée de la classe
  File? _imageFile;
  bool _isImagePickerActive = false;
  late String imagePath;

  bool _isNomValid = true;
  bool _isPrenomValid = true;
  bool _isDateNaissanceValid = true;

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

  void _validateAndContinue() {
    setState(() {
      _isNomValid = controllerNom.text.trim().isNotEmpty;
      _isPrenomValid = controllerPrenom.text.trim().isNotEmpty;
    });

    if (_isNomValid && _isPrenomValid && _isDateNaissanceValid) {
      User_Info.firstname = controllerPrenom.text;
      User_Info.lastname = controllerNom.text;
      User_Info.dateofbirth = controllerDateNaissance.text.isNotEmpty
          ? controllerDateNaissance.text
          : '01/01/1900';
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => RegisterSecurity()),
      );
    } else {
      print("pas possible");
    }
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
                          'Information',
                          style: TextStyle(
                              fontSize: UTILS.calculWidth(
                                  30, UTILS.widthReference(context)),
                              fontFamily: 'Galey',
                              color: const Color(0xFF0C5C6C),
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
                              'Veuillez entrer vos informations',
                              style: TextStyle(
                                  fontSize: UTILS.calculWidth(
                                      15, UTILS.widthReference(context)),
                                  fontFamily: 'Galey',
                                  color: const Color(0xFF0C5C6C),
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
                          child: Image.asset(
                              'assets/page/register_with_icon.png')),
                      SizedBox(
                          height: UTILS.calculHeight(
                              37, UTILS.heightReference(context))),
                      SizedBox(
                        height: UTILS.calculHeight(
                            53, UTILS.heightReference(context)),
                        width: UTILS.calculWidth(
                            367, UTILS.widthReference(context)),
                        child: TextFormField(
                          controller: controllerNom,
                          cursorColor: Colors.black,
                          decoration: InputDecoration(
                            labelText: 'Nom',
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
                                  color: _isNomValid
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
                                  17, UTILS.widthReference(context)),
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
                              30, UTILS.heightReference(context))),
                      SizedBox(
                        height: UTILS.calculHeight(
                            53, UTILS.heightReference(context)),
                        width: UTILS.calculWidth(
                            367, UTILS.widthReference(context)),
                        child: TextFormField(
                          cursorColor: Colors.black,
                          controller: controllerPrenom,
                          decoration: InputDecoration(
                            labelText: 'Prénom',
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
                                  color: _isPrenomValid
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
                                  17, UTILS.widthReference(context)),
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
                              30, UTILS.heightReference(context))),
                      SizedBox(
                        height: UTILS.calculHeight(
                            53, UTILS.heightReference(context)),
                        width: UTILS.calculWidth(
                            367, UTILS.widthReference(context)),
                        child: TextFormField(
                          controller: controllerDateNaissance,
                          decoration: InputDecoration(
                            labelText: 'Date de naissance',
                            filled: true,
                            contentPadding: EdgeInsets.symmetric(
                                vertical: UTILS.calculHeight(
                                    12.0, UTILS.heightReference(context)),
                                horizontal: UTILS.calculWidth(
                                    20.0, UTILS.widthReference(context))),
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
                                  color: _isDateNaissanceValid
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
                              color: Color.fromARGB(255, 0, 0, 0),
                            ),
                            suffixIcon: Icon(Icons.calendar_today),
                          ),
                          onTap: () async {
                            FocusScope.of(context)
                                .requestFocus(new FocusNode());
                            DateTime? pickedDate = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(1900),
                                lastDate: DateTime.now());
                            if (pickedDate != null) {
                              String formattedDate =
                                  '${pickedDate.day}/${pickedDate.month}/${pickedDate.year}';
                              setState(() {
                                controllerDateNaissance.text = formattedDate;
                              });
                            }
                          },
                        ),
                      ),
                      SizedBox(
                          height: UTILS.calculHeight(
                              19, UTILS.heightReference(context))),
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
                            onPressed: _validateAndContinue,
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
                              15.6, UTILS.heightReference(context))),
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
