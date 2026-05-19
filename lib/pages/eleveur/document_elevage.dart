// ignore_for_file: prefer_const_constructors

import 'package:PetsMatch/animation/delayed_animation.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/desc_entreprise.dart';
import 'package:PetsMatch/pages/particulier/description_page.dart';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class RegisterDocumentElevage extends StatefulWidget {
  const RegisterDocumentElevage({super.key});

  @override
  State<RegisterDocumentElevage> createState() =>
      _RegisterDocumentElevageState();
}

class _RegisterDocumentElevageState extends State<RegisterDocumentElevage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isSiretUploaded = false;
  String? selectedCategory;
  String? selectedProfession;

  final Map<String, List<String>> professionsByCategory = {
    'Prestataire': [
      'Educateurs comportementalistes',
      'Handleurs',
      'Mushers',
      // 'Pension canine',
      'Promeneurs de chiens',
      'Petsitter',
      // 'Refuge',
      'Toiletteur',
    ],
    'Santé animal': [
      'Vétérinaire',
      'Auxiliaire de santé',
      'Spécialistes de santé',
    ],
  };
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
    if (User_Info.isPro) {
      if (_isSiretUploaded && 
          selectedCategory != null &&
          selectedProfession != null && User_Info.siret.isNotEmpty ) {
        User_Info.catPro = selectedCategory!;
        User_Info.professionPro = selectedProfession!;

        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => DescProEntreprise()),
        );
      } else {
        final snackBar = SnackBar(
          content: Text(
              "Le document Siret, le numéro Siret, la catégorie professionnelle et la profession sont obligatoires."),
        );
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      }
    } else {
      if (_isSiretUploaded && User_Info.siret.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => DescProEntreprise()),
        );
      } else {
        final snackBar = SnackBar(
          content: Text("Le document Siret et le numéro siret sont obligatoire."),
        );
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      }
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
                          'Documents élevage',
                          style: TextStyle(
                              fontSize: UTILS.calculWidth(
                                  30, UTILS.widthReference(context)),
                              fontFamily: 'Galey',
                              color: const Color.fromARGB(174, 0, 0, 0),
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
                              '',
                              style: TextStyle(
                                  fontSize: UTILS.calculWidth(
                                      15, UTILS.widthReference(context)),
                                  fontFamily: 'Galey',
                                  color: const Color.fromARGB(174, 0, 0, 0),
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
                          child:
                              Image.asset('assets/page/document_elevage.png')),
                      if (User_Info.isPro)
                        SizedBox(
                          width: UTILS.calculWidth(
                              355, UTILS.widthReference(context)),
                          child: DropdownButtonFormField<String>(
                            dropdownColor: Colors.pink[100],
                            decoration: InputDecoration(
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: Color.fromARGB(255, 250, 192, 187),
                                ),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: Color.fromARGB(255, 250, 192, 187),
                                ),
                              ),
                              labelText: 'Catégorie Professionnel',
                            ),
                            items: ['Prestataire', 'Santé animal']
                                .map((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              setState(() {
                                selectedCategory = newValue;
                                selectedProfession =
                                    null; // Reset profession when category changes
                              });
                            },
                            value:
                                selectedCategory, // Ensure value is reset properly
                          ),
                        ),
                      SizedBox(
                        height: UTILS.calculHeight(
                            10, UTILS.heightReference(context)),
                      ),
                      if (User_Info.isPro && selectedCategory != null)
                        SizedBox(
                          width: UTILS.calculWidth(
                              355, UTILS.widthReference(context)),
                          child: DropdownButtonFormField<String>(
                            dropdownColor: Colors.pink[100],
                            decoration: InputDecoration(
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: Color.fromARGB(255, 250, 192, 187),
                                ),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: Color.fromARGB(255, 250, 192, 187),
                                ),
                              ),
                              labelText: 'Profession',
                            ),
                            items: professionsByCategory[selectedCategory]!
                                .map((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              setState(() {
                                selectedProfession = newValue;
                              });
                            },
                            value:
                                selectedProfession, // Ensure value is reset properly
                          ),
                        ),
                      SizedBox(
                          height: UTILS.calculHeight(
                              15, UTILS.heightReference(context))),
                      DocumentManager(
                        onSiretUploaded: (bool uploaded) {
                          setState(() {
                            _isSiretUploaded = uploaded;
                          });
                        },
                      ),
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
                                    Color.fromARGB(255, 250, 192, 187)),
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

class DocumentManager extends StatefulWidget {
  final Function(bool) onSiretUploaded;

  DocumentManager({required this.onSiretUploaded});

  @override
  _DocumentManagerState createState() => _DocumentManagerState();
}

class _DocumentManagerState extends State<DocumentManager> {
  double containerHeight = 350;
  bool _isSiretValid = true; // Indicateur pour valider le SIRET
  TextEditingController controllerSiret = TextEditingController();
  TextEditingController controllerTVA = TextEditingController();

  @override
  void initState() {
    super.initState();
    containerHeight = User_Info.isPro ? 350 : 500;
  }

  Future<void> pickFile(String category) async {
    FilePickerResult? pickedFile = await FilePicker.platform.pickFiles();
    if (pickedFile != null) {
      String? fileName = pickedFile.files.single.name;
      File file = File(pickedFile.files.single.path!);

      // Upload the file to Firebase Storage
      String fileUrl = await uploadFileToFirebase(file, category);

      setState(() {
        User_Info.documentElevage.add({
          'name': fileName,
          'category': category,
          'url': fileUrl,
          'uploaded': false
        });
        updateContainerHeight();
        if (category == 'Siret') {
          widget.onSiretUploaded(true);
          User_Info.kbisUrl = fileUrl;
        }
      });
    }
  }

  Future<String> uploadFileToFirebase(File file, String category) async {
    final ref = FirebaseStorage.instance
        .ref()
        .child('documentElevage/$category/${file.path.split('/').last}');
    var uploadTask = ref.putFile(file);

    final snapshot = await uploadTask;
    final fileUrl = await snapshot.ref.getDownloadURL();

    return fileUrl;
  }

  void updateContainerHeight() {
    setState(() {
      if (User_Info.documentElevage.length == 0 ||
          User_Info.documentElevage.length == 1) {
        containerHeight = User_Info.isPro ? 350 : 500;
      } else {
        containerHeight = User_Info.isPro
            ? 350.0
            : 500.0 + 50.0 * User_Info.documentElevage.length.toDouble();
      }
    });
  }
  void _validateTva() {
     setState(() {
        User_Info.numeroTVA = controllerTVA.text;
    });
  }

  // Validation pour le champ Siret
  void _validateSiret() {
    setState(() {
      _isSiretValid = controllerSiret.text.isNotEmpty ||
          User_Info.documentElevage.any((doc) => doc['category'] == 'Siret');
        User_Info.siret = controllerSiret.text;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height:
          UTILS.calculHeight(containerHeight, UTILS.heightReference(context)),
      child: Column(
        children: [
          Align(
            alignment: Alignment(-0.8, 0),
            child: Text(
              'Siret',
              textAlign: TextAlign.left,
              style: TextStyle(
                fontFamily: 'Galey',
                color: Color.fromARGB(193, 30, 30, 30),
                fontWeight: FontWeight.w500,
                fontSize: UTILS.calculWidth(20, UTILS.widthReference(context)),
              ),
            ),
          ),
          SizedBox(
              height: UTILS.calculHeight(13, UTILS.heightReference(context))),

          // Champ Numéro Siret
          SizedBox(
            height: UTILS.calculHeight(53, UTILS.heightReference(context)),
            width: UTILS.calculWidth(367, UTILS.widthReference(context)),
            child: TextFormField(
              keyboardType: TextInputType.number,
              controller: controllerSiret,
              cursorColor: Colors.black,
              onChanged: (value) =>
                  _validateSiret(), // Valider à chaque changement
              decoration: InputDecoration(
                labelText: 'Numéro Siret',
                
                filled: true,
                contentPadding: EdgeInsets.symmetric(
                  vertical:
                      UTILS.calculHeight(12.0, UTILS.heightReference(context)),
                  horizontal:
                      UTILS.calculWidth(15.0, UTILS.widthReference(context)),
                ),
                fillColor: Color.fromARGB(255, 250, 192, 187),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide(
                    color: Colors.transparent,
                    width:
                        2.0, // Couleur de la bordure lorsque le champ est inactif
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide(
                    color: Color.fromARGB(255, 250, 192, 187),
                    width:
                        2.0, // Couleur de la bordure lorsque le champ est sélectionné
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    UTILS.calculWidth(50.0, UTILS.widthReference(context)),
                  ),
                  borderSide: BorderSide(color: Colors.transparent),
                ),
              ),
            ),
          ),
          SizedBox(
              height: UTILS.calculHeight(13, UTILS.heightReference(context))),

          // Bouton pour ajouter un fichier Siret
          SizedBox(
            height: UTILS.calculHeight(53, UTILS.heightReference(context)),
            width: UTILS.calculWidth(372, UTILS.widthReference(context)),
            child: ElevatedButton(
              onPressed: () => pickFile('Siret'),
              child: Text(
                '📁 Joindre un fichier Siret',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Galey',
                  color: Color.fromARGB(255, 0, 0, 0),
                  fontWeight: FontWeight.w500,
                  fontSize:
                      UTILS.calculWidth(18, UTILS.widthReference(context)),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color.fromARGB(255, 252, 207, 200),
              ),
            ),
          ),

          // Affichage des documents Siret
          if (User_Info.documentElevage
              .any((doc) => doc['category'] == 'Siret'))
            ...User_Info.documentElevage
                .where((doc) => doc['category'] == 'Siret')
                .map((doc) => ListTile(
                      title: Text(doc['name']),
                      trailing: IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          setState(() {
                            widget.onSiretUploaded(false);
                            User_Info.documentElevage.remove(doc);
                            updateContainerHeight();
                          });
                        },
                      ),
                    ))
                .toList(),

          SizedBox(
              height: UTILS.calculHeight(23, UTILS.heightReference(context))),

          // Champ Numéro TVA (optionnel)
          Align(
            alignment: Alignment(-0.65, 0),
            child: Text(
              'Numéro TVA (Optionel)',
              textAlign: TextAlign.left,
              style: TextStyle(
                fontFamily: 'Galey',
                color: Color.fromARGB(193, 30, 30, 30),
                fontWeight: FontWeight.w500,
                fontSize: UTILS.calculWidth(20, UTILS.widthReference(context)),
              ),
            ),
          ),
          SizedBox(
              height: UTILS.calculHeight(13, UTILS.heightReference(context))),
          SizedBox(
            height: UTILS.calculHeight(53, UTILS.heightReference(context)),
            width: UTILS.calculWidth(367, UTILS.widthReference(context)),
            child: TextFormField(
              keyboardType: TextInputType.number,
              controller: controllerTVA,
              cursorColor: Colors.black,
               onChanged: (value) =>
                  _validateTva(), // Valider à chaque changement
              decoration: InputDecoration(
                labelText: 'Numéro TVA',
                filled: true,
                contentPadding: EdgeInsets.symmetric(
                  vertical:
                      UTILS.calculHeight(12.0, UTILS.heightReference(context)),
                  horizontal:
                      UTILS.calculWidth(15.0, UTILS.widthReference(context)),
                ),
                fillColor: Color.fromARGB(255, 250, 192, 187),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    UTILS.calculWidth(50.0, UTILS.widthReference(context)),
                  ),
                  borderSide: BorderSide(color: Colors.transparent),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide(
                    color: Colors.transparent,
                    width:
                        2.0, // Couleur de la bordure lorsque le champ est inactif
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide(
                    color: Color.fromARGB(255, 250, 192, 187),
                    width:
                        2.0, // Couleur de la bordure lorsque le champ est sélectionné
                  ),
                ),
              ),
            ),
          ),

          SizedBox(
              height: UTILS.calculHeight(13, UTILS.heightReference(context))),

          // Champs et bouton Acaced pour isElevage
          if (User_Info.isElevage) ...[
            Align(
              alignment: Alignment(-0.62, 0),
              child: Text(
                'Acaced ou équivalent',
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontFamily: 'Galey',
                  color: Color.fromARGB(193, 30, 30, 30),
                  fontWeight: FontWeight.w500,
                  fontSize:
                      UTILS.calculWidth(20, UTILS.widthReference(context)),
                ),
              ),
            ),
            SizedBox(
                height: UTILS.calculHeight(13, UTILS.heightReference(context))),
            SizedBox(
              height: UTILS.calculHeight(53, UTILS.heightReference(context)),
              width: UTILS.calculWidth(372, UTILS.widthReference(context)),
              child: ElevatedButton(
                onPressed: () => pickFile('Acaced_ou_autre'),
                child: Text(
                  '📁 Joindre un fichier',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Galey',
                    color: Color.fromARGB(255, 0, 0, 0),
                    fontWeight: FontWeight.w500,
                    fontSize:
                        UTILS.calculWidth(18, UTILS.widthReference(context)),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color.fromARGB(255, 252, 207, 200),
                ),
              ),
            ),

            // Affichage des documents Acaced
            if (User_Info.documentElevage
                .any((doc) => doc['category'] == 'Acaced_ou_autre'))
              ...User_Info.documentElevage
                  .where((doc) => doc['category'] == 'Acaced_ou_autre')
                  .map((doc) => ListTile(
                        title: Text(doc['name']),
                        trailing: IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            setState(() {
                              User_Info.documentElevage.remove(doc);
                              updateContainerHeight();
                            });
                          },
                        ),
                      ))
                  .toList(),
          ],
        ],
      ),
    );
  }
}
