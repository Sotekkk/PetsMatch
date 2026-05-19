import 'package:PetsMatch/pages/particulier/numberadressregistration.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:PetsMatch/utils.dart';
import 'package:PetsMatch/main.dart';

class RegisterParticulierInformationPage extends StatefulWidget {
  const RegisterParticulierInformationPage({super.key});

  @override
  State<RegisterParticulierInformationPage> createState() =>
      _RegisterParticulierInformationPageState();
}

class _RegisterParticulierInformationPageState
    extends State<RegisterParticulierInformationPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  TextEditingController controllerNom = TextEditingController();
  TextEditingController controllerPrenom = TextEditingController();
  TextEditingController controllerDateNaissance = TextEditingController();

  final ImagePicker _picker =
      ImagePicker(); // S'assurer que ceci est bien déclaré dans la portée de la classe
  File? _imageFile;
  bool _isImagePickerActive = false;
  late String imageName = "zizi";
  late String imagePath;

  bool _isNomValid = true;
  bool _isPrenomValid = true;
  bool _isDateNaissanceValid = true;

  Future<void> _pickImage() async {
    if (_isImagePickerActive) {
      // Si le sélecteur d'images est déjà actif, ne faites rien.
      return;
    }

    try {
      setState(() {
        _isImagePickerActive =
            true; // Marquez que le sélecteur d'images est actif.
      });

      final XFile? pickedFile =
          await _picker.pickImage(source: ImageSource.gallery);

      setState(() {
        _imageFile = pickedFile != null ? File(pickedFile.path) : _imageFile;
        imageName = pickedFile!.name;

        _isImagePickerActive =
            false; // Marquez que le sélecteur d'images n'est plus actif.
      });
    } catch (e) {
      // Si une erreur se produit, assurez-vous de désactiver le flag également.
      setState(() {
        _isImagePickerActive = false;
      });
    }
  }

  Future uploadFIle() async {
    if (imageName == "zizi") {
      print("Aucune image sélectionnée.");
      return;
    }
    final path = 'files/${imageName}';
    final file = _imageFile;

    final ref = FirebaseStorage.instance.ref().child(path);
    var uploadTask = ref.putFile(file!);

    final snapshot = await uploadTask;

    final urlDownload = await snapshot.ref.getDownloadURL();
    User_Info.profilePictureUrl = urlDownload;
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
      try {
        uploadFIle();
      } catch (e) {
        print('Erreur lors de l\'upload: $e');
      }
      if (User_Info.dateofbirth.isNotEmpty &&
          User_Info.firstname.trim().isNotEmpty &&
          User_Info.firstname.toLowerCase() != "none" &&
          User_Info.lastname.trim().isNotEmpty &&
          User_Info.lastname.toLowerCase() != "none") {
        Navigator.of(context).push(
          MaterialPageRoute(
              builder: (context) => RegisterPhoneAdressInformationPage()),
        );
      } else {
        print("pas possible");
      }
    }
  }

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
                child: Column(children: [
      SizedBox(
          width: UTILS.widthReference(context),
          height: UTILS.calculHeight(104,
              UTILS.heightReference(context)), // Hauteur fixe pour le Stack
          child: Stack(children: [
            Image.asset(
              'assets/deco/arrondi_rose_2.png',
              color: const Color(0xFFA7C79A),
              colorBlendMode: BlendMode.srcIn,
              fit: BoxFit.cover,
              width: UTILS.calculWidth(211, UTILS.widthReference(context)),
              height: UTILS.calculHeight(104,
                  UTILS.heightReference(context)), // Hauteur fixe pour le Stack
            ),
            Positioned(
              top: UTILS.calculHeight(53, UTILS.heightReference(context)),
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
                    fontSize:
                        UTILS.calculWidth(20, UTILS.widthReference(context)),
                  ),
                ),
              ),
            )
          ])),
      SizedBox(height: UTILS.calculHeight(14, UTILS.heightReference(context))),
      Align(
        alignment: Alignment(-0.8, 0),
        child: Text(
          'Information',
          style: TextStyle(
              fontSize: UTILS.calculWidth(30, UTILS.widthReference(context)),
              fontFamily: 'Galey',
              color: const Color(0xFF0C5C6C),
              fontWeight: FontWeight.w500),
          textAlign: TextAlign.left,
        ),
      ),
      Align(
          alignment: Alignment(0.1, 0),
          child: SizedBox(
            width: UTILS.calculWidth(379, UTILS.widthReference(context)),
            child: Text(
              'Veuillez entrer vos informations',
              style: TextStyle(
                  fontSize:
                      UTILS.calculWidth(15, UTILS.widthReference(context)),
                  fontFamily: 'Galey',
                  color: const Color(0xFF0C5C6C),
                  fontWeight: FontWeight.w500),
              textAlign: TextAlign.left,
            ),
          )),
      SizedBox(height: UTILS.calculHeight(10, UTILS.heightReference(context))),
      SizedBox(
          height: UTILS.calculHeight(286, UTILS.heightReference(context)),
          width: UTILS.calculWidth(286, UTILS.widthReference(context)),
          child: Image.asset('assets/page/register_with_icon.png')),
      SizedBox(height: UTILS.calculHeight(37, UTILS.heightReference(context))),
//////////////////////////////////////
      SizedBox(
        height: UTILS.calculHeight(127, UTILS.heightReference(context)),
        width: UTILS.calculWidth(376, UTILS.widthReference(context)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _pickImage,
                  child: Stack(
                    alignment: Alignment
                        .bottomRight, // Positionne l'icône en bas à droite de l'avatar
                    children: [
                      SizedBox(
                        height: UTILS.calculHeight(
                            80, UTILS.heightReference(context)),
                        width: UTILS.calculWidth(
                            80, UTILS.widthReference(context)),
                      ),
                      CircleAvatar(
                        radius: 39.5,
                        backgroundColor: Colors.transparent,
                        backgroundImage: _imageFile != null
                            ? FileImage(_imageFile!) as ImageProvider
                            : AssetImage(
                                'https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60'),
                      ),
                      if (_imageFile == null)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: GestureDetector(
                            onTap: () {},
                            child: CircleAvatar(
                              radius: 12, // Taille du cercle derrière l'icône
                              backgroundColor: const Color(0xFF6E9E57), // Couleur du fond du cercle
                              child: Icon(Icons.edit,
                                  size: 18,
                                  color: Colors.black), // L'icône de croix
                            ),
                          ),
                        ),
                      if (_imageFile !=
                          null) // Si une image est sélectionnée, affichez l'icône pour supprimer
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _imageFile =
                                    null; // Effacez l'image sélectionnée
                              });
                            },
                            child: CircleAvatar(
                              radius: 12, // Taille du cercle derrière l'icône
                              backgroundColor: const Color(0xFF6E9E57), // Couleur du fond du cercle
                              child: Icon(Icons.close,
                                  size: 18,
                                  color: Colors.black), // L'icône de croix
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height:
                      UTILS.calculHeight(13, UTILS.heightReference(context)),
                ),
                Container(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 0.0, left: 10.0),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.end, // Alignement du texte à droite
                      children: [
                        Text(
                          'Photo de profil',
                          style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            color: const Color.fromARGB(189, 0, 0, 0),
                            fontSize: UTILS.calculWidth(
                                20, UTILS.widthReference(context)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(
                width: UTILS.calculWidth(
                    26,
                    UTILS.widthReference(
                        context))), // Espace entre l'avatar et les champs de texte
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height:
                        UTILS.calculHeight(53, UTILS.heightReference(context)),
                    width:
                        UTILS.calculWidth(214, UTILS.widthReference(context)),
                    child: TextFormField(
                      controller: controllerNom,
                      cursorColor: Colors.black,
                      decoration: InputDecoration(
                        labelText: 'Nom',
                        filled: true,
                        contentPadding: EdgeInsets.symmetric(
                            vertical: 12.0, horizontal: 15.0),
                        fillColor: Color(0xFFA7C79A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(50.0),
                          borderSide: BorderSide(color: Colors.transparent),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30.0),
                          borderSide: BorderSide(
                            color: _isNomValid
                                ? Colors.transparent
                                : Colors
                                    .red, // Change border color based on validation
                            width:
                                2.0, // Couleur de la bordure lorsque le champ est inactif
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30.0),
                          borderSide: BorderSide(
                              color: _isNomValid
                                  ? Color(0xFFA7C79A)
                                  : Colors.red,
                              width:
                                  2.0), // Couleur de la bordure lorsque le champ est sélectionné
                        ),
                        labelStyle: TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                          fontSize: UTILS.calculWidth(
                              17, UTILS.widthReference(context)),
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
                      height: UTILS.calculHeight(
                          21,
                          UTILS.heightReference(
                              context))), // Espace entre les champs de texte
                  SizedBox(
                    height:
                        UTILS.calculHeight(53, UTILS.heightReference(context)),
                    width:
                        UTILS.calculWidth(214, UTILS.widthReference(context)),
                    child: TextFormField(
                      cursorColor: Colors.black,
                      controller: controllerPrenom,
                      decoration: InputDecoration(
                        labelText: 'Prénom',
                        filled: true,
                        contentPadding: EdgeInsets.symmetric(
                            vertical: 12.0, horizontal: 15.0),
                        fillColor: Color(0xFFA7C79A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(50.0),
                          borderSide: BorderSide(color: Colors.transparent),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30.0),
                          borderSide: BorderSide(
                            color: _isPrenomValid
                                ? Colors.transparent
                                : Colors
                                    .red, // Change border color based on validation
                            width:
                                2.0, // Couleur de la bordure lorsque le champ est inactif
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30.0),
                          borderSide: BorderSide(
                              color: _isPrenomValid
                                  ? Color(0xFFA7C79A)
                                  : Colors.red,
                              width:
                                  2.0), // Couleur de la bordure lorsque le champ est sélectionné
                        ),
                        labelStyle: TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                          fontSize: UTILS.calculWidth(
                              17, UTILS.widthReference(context)),
                        ),
                        prefixIcon: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 15.0),
                          child: Icon(Icons.person),
                        ),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      SizedBox(
          height: UTILS.calculHeight(
              39,
              UTILS.heightReference(
                  context))), // Espace entre les champs de texte et la date de naissance
      SizedBox(
        height: UTILS.calculHeight(53, UTILS.heightReference(context)),
        width: UTILS.calculWidth(367, UTILS.widthReference(context)),
        child: TextFormField(
          controller: controllerDateNaissance,
          decoration: InputDecoration(
            labelText: 'Date de naissance',
            filled: true,
            contentPadding:
                EdgeInsets.symmetric(vertical: 12.0, horizontal: 20.0),
            fillColor: Color(0xFFA7C79A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(50.0),
              borderSide: BorderSide(color: Colors.transparent),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30.0),
              borderSide: BorderSide(
                color: _isDateNaissanceValid
                    ? Colors.transparent
                    : Colors.red, // Change border color based on validation
                width:
                    2.0, // Couleur de la bordure lorsque le champ est inactif
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30.0),
              borderSide: BorderSide(
                  color: _isDateNaissanceValid
                      ? Color(0xFFA7C79A)
                      : Colors.red,
                  width:
                      2.0), // Couleur de la bordure lorsque le champ est sélectionné
            ),
            labelStyle: TextStyle(
              fontFamily: 'Galey',
              fontWeight: FontWeight.w500,
              color: Color.fromARGB(
                  255, 0, 0, 0), // Mettez ici la couleur de votre choix
            ),
            suffixIcon: Icon(Icons.calendar_today),
          ),
          onTap: () async {
            // Lorsque l'utilisateur clique sur le champ, affichez un sélecteur de date
            FocusScope.of(context).requestFocus(
                new FocusNode()); // pour prévenir l'ouverture du clavier
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
              19,
              UTILS.heightReference(
                  context))), // Espace entre les champs de texte et la date de naissance
      Align(
        alignment: Alignment.center, // Alignez le bouton à droite
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
                    color: Color.fromARGB(
                        255, 0, 0, 0), // Mettez ici la couleur de votre choix
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
            onPressed: _validateAndContinue,
            style: ElevatedButton.styleFrom(
                backgroundColor: Color.fromARGB(
                    255, 250, 192, 187)), // Couleur de fond du bouton
            child: Text(
              'CONTINUER',
              style: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w500,
                color: Color.fromARGB(255, 0, 0, 0),
                fontSize: UTILS.calculWidth(17, UTILS.widthReference(context)),
              ),
            ),
            // Personnaliser le style du bouton
          )),
      SizedBox(
          height: UTILS.calculHeight(15.6, UTILS.heightReference(context))),
      Image.asset(
        'assets/deco/arrondi_green_deco_2.png',
        fit: BoxFit.cover,
        width: UTILS.calculWidth(233, UTILS.widthReference(context)),
        height: UTILS.calculHeight(
            52, UTILS.heightReference(context)), // Hauteur fixe pour l'image
      ), // Espac
    ]))));
  }
}
