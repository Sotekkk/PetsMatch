import 'dart:convert';
import 'package:PetsMatch/animation/delayed_animation.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/all_register_pet.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class DogFiche extends StatefulWidget {
  const DogFiche({super.key});

  @override
  State<DogFiche> createState() => _DogFicheState();
}

class PedigreeFile {
  final String name;
  final String category;
  bool uploaded;

  PedigreeFile(
      {required this.name, required this.category, this.uploaded = false});
}

class _DogFicheState extends State<DogFiche> {
  File? _image;
  FocusNode _focusNode = FocusNode();
  TextEditingController controllerDateNaissanceDog = TextEditingController();
  TextEditingController _descriptionController = TextEditingController();
  TextEditingController _nameController = TextEditingController();
  TextEditingController _colorController = TextEditingController();
  TextEditingController _fatherNameController = TextEditingController();
  TextEditingController _motherNameController = TextEditingController();
  TextEditingController _fatherDNAController = TextEditingController();
  TextEditingController _motherDNAController = TextEditingController();
  TextEditingController _chipNumberController = TextEditingController();
  TextEditingController _coatTypeController = TextEditingController();
  TextEditingController _birthWeightController = TextEditingController();
  List<String> _allBreeds = [];
  List<String> _suggestedBreeds = []; // Pour stocker les suggestions filtrées
  TextEditingController _breedController = TextEditingController();
  String? _errorMessage;
  bool _loading = false;
  late Future<List<String>> dogBreedsFuture;
  String sexAnimal = "Mâle";
  String raceAnimal = "Aucun";
  bool isInfoExpanded = false;
  bool isPereExpanded = false;
  bool isMereExpanded = false;
  bool isSanteExpanded = false;
  bool isReproductionExpanded = false;

  List<Map<String, dynamic>> vaccines = [];
  List<Map<String, dynamic>> vermifuges = [];
  List<DateTime> chaleurs = [];
  List<Map<String, dynamic>> saillies = [];

  Map<String, Map<String, String>> documentElevage = {
    'ADN du pere': {'name': 'Aucun document', 'path': ''},
    'Pedigree pere': {'name': 'Aucun document', 'path': ''},
    'ADN de la mere': {'name': 'Aucun document', 'path': ''},
    'Pedigree mere': {'name': 'Aucun document', 'path': ''},
    'Test génétique du chien': {'name': 'Aucun document', 'path': ''},
    'cotation': {'name': 'Aucun document', 'path': ''},
    'Pedigree': {'name': 'Aucun document', 'path': ''},
    'Vaccin': {'name': 'Aucun document', 'path': ''},
  };

  Future<void> pickFilePedigree(String category) async {
    FilePickerResult? pickedFile = await FilePicker.pickFiles();
    if (pickedFile != null) {
      String? fileName = pickedFile.files.single.name;
      String? filePath = pickedFile.files.single.path;
      setState(() {
        documentElevage[category] = {'name': fileName!, 'path': filePath!};
      });
    }
  }

  Future<void> _showPermissionDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Permission requise',
            style: TextStyle(
              fontFamily: 'Galey',
              fontWeight: FontWeight.w500,
            ),
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                    'Cette application a besoin d\'un accès complet à votre stockage pour sélectionner les fichiers.'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Accorder accès complet'),
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
              },
            ),
            TextButton(
              child: Text('Refuser'),
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _errorMessage = 'Permission denied';
                });
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
    }
  }

  bool _viensDeVotreElevage = true;
  TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    dogBreedsFuture = loadDogBreeds();
    dogBreedsFuture.then((breeds) {
      setState(() {
        _allBreeds = breeds;
      });
    });
    if (_viensDeVotreElevage) {
      _controller.text = User_Info.nameElevage; // Texte par défaut
    }
    isInfoExpanded = false;
    isPereExpanded = false;
    isMereExpanded = false;
    isSanteExpanded = false;
    isReproductionExpanded = false;
  }

  void _handleCheckboxChange(bool? value) {
    setState(() {
      _viensDeVotreElevage = !_viensDeVotreElevage;
      if (_viensDeVotreElevage) {
        _controller.text = User_Info.nameElevage; // Texte par défaut
      } else {
        _controller
            .clear(); // Efface le texte pour permettre à l'utilisateur d'entrer un nouveau texte
      }
    });
  }

  Future<String> _uploadFile(File file, String uid, String fileName) async {
    try {
      TaskSnapshot snapshot = await FirebaseStorage.instance
          .ref('documents/$uid/$fileName')
          .putFile(file);

      String downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
      rethrow;
    }
  }

  Future<void> _saveData() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Le prénom de l\'animal n\'a pas été modifié.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() {
      _loading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _errorMessage = 'User not logged in';
        });
        return;
      }

      final uid = user.uid;
      final docRef = FirebaseFirestore.instance.collection('dogfiche').doc(uid);
      final docId = docRef.collection('entries').doc().id;

      Map<String, dynamic> dogData = {
        'description': _descriptionController.text,
        'name': _nameController.text,
        'dateOfBirth': controllerDateNaissanceDog.text,
        'race': raceAnimal, // Replace with your dropdown value
        'sex': sexAnimal, // Replace with your dropdown value
        'color': _colorController.text,
        'fatherName': _fatherNameController.text,
        'motherName': _motherNameController.text,
        'motherDNA': _motherDNAController.text,
        'chipNumber': _chipNumberController.text,
        'coatType': _coatTypeController.text,
        'birthWeight': _birthWeightController.text,
        'breeding':
            _viensDeVotreElevage ? User_Info.nameElevage : _controller.text,
        'profilePicture': 'Aucune photo de profil', // Default value
        'documents': {}, // Default value
        'vaccines': vaccines, // Save vaccines data
        'vermifuges': vermifuges, // Save vermifuges data
        'chaleurs': chaleurs
            .map((date) => date.toIso8601String())
            .toList(), // Save heat dates
        'saillies': saillies, // Save mating data
      };

      // Upload the profile picture specific to this entry
      if (_image != null) {
        String profilePictureUrl =
            await _uploadFile(_image!, docId, 'pictureDogProfile');
        dogData['profilePicture'] = profilePictureUrl;
      }
      void closeDialogAndNavigateBack(BuildContext context) {
        Navigator.of(context).pop(); // Ferme l'AlertDialog
        Future.delayed(Duration(milliseconds: 300), () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop(); // Retour à l'écran précédent
          }
        });
      }

      // Upload documents specific to this entry
      for (String category in documentElevage.keys) {
        if (documentElevage[category]!['path']!.isNotEmpty) {
          File file = File(documentElevage[category]!['path']!);
          String downloadUrl = await _uploadFile(
              file, docId, documentElevage[category]!['name']!);
          dogData['documents'][category] = downloadUrl;
        } else {
          dogData['documents'][category] = 'Aucun document';
        }
      }

      await docRef.collection('entries').doc(docId).set(dogData);

      setState(() {
        _loading = false;
        _errorMessage = null;
      });

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Succès'),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  Text('Les données ont été enregistrées avec succès.'),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text('OK'),
                onPressed: () {
                  Navigator.of(context)
                      .pop(); // Ferme l'AlertDialog avec un résultat
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => AllPetRegister()),
                  );
                },
              ),
            ],
          );
        },
      );
      Navigator.of(context).pop(); // Ferme l'AlertDialog avec un résultat

      _resetForm();
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<List<String>> loadDogBreeds() async {
    final String response =
        await rootBundle.loadString('assets/dog_breeds.json');
    final List<dynamic> data = await json.decode(response);
    return data.cast<String>();
  }

  void _resetForm() {
    setState(() {
      _image = null;
      controllerDateNaissanceDog.clear();
      _descriptionController.clear();
      _nameController.clear();
      _colorController.clear();
      _fatherNameController.clear();
      _motherNameController.clear();
      _fatherDNAController.clear();
      _motherDNAController.clear();
      _chipNumberController.clear();
      _coatTypeController.clear();
      _birthWeightController.clear();
      _controller.clear();
      _viensDeVotreElevage = true;
      vaccines.clear();
      vermifuges.clear();
      chaleurs.clear();
      saillies.clear();
      documentElevage = {
        'ADN du pere': {'name': 'Aucun document', 'path': ''},
        'Pedigree pere': {'name': 'Aucun document', 'path': ''},
        'ADN de la mere': {'name': 'Aucun document', 'path': ''},
        'Pedigree mere': {'name': 'Aucun document', 'path': ''},
        'Test génétique du chien': {'name': 'Aucun document', 'path': ''},
        'cotation': {'name': 'Aucun document', 'path': ''},
        'Pedigree': {'name': 'Aucun document', 'path': ''},
        'Vaccin': {'name': 'Aucun document', 'path': ''},
      };
    });
  }

  Future<void> _selectDate(
      BuildContext context, Function(DateTime) onSelected) async {
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (pickedDate != null) {
      onSelected(pickedDate);
    }
  }

  void _addVaccine() {
    setState(() {
      vaccines.add({'date': null, 'name': '', 'reminderDate': null});
    });
  }

  void _removeVaccine(int index) {
    setState(() {
      vaccines.removeAt(index);
    });
  }

  void _addVermifuge() {
    setState(() {
      vermifuges.add({'date': null, 'reminderDate': null});
    });
  }

  void _removeVermifuge(int index) {
    setState(() {
      vermifuges.removeAt(index);
    });
  }

  void _addChaleur() {
    setState(() {
      chaleurs.add(DateTime.now());
    });
  }

  void _removeChaleur(int index) {
    setState(() {
      chaleurs.removeAt(index);
    });
  }

  void _addSaillie() {
    setState(() {
      saillies.add({'date': null, 'maleName': ''});
    });
  }

  void _removeSaillie(int index) {
    setState(() {
      saillies.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Center(
              child: Container(
                child: Column(
                  children: [
                    SizedBox(
                      width: UTILS.widthReference(context),
                      height: UTILS.calculHeight(
                          105, UTILS.heightReference(context)),
                      child: Stack(
                        children: [
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
                                42, UTILS.heightReference(context)),
                            left: UTILS.calculWidth(
                                10, UTILS.widthReference(context)),
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
                                'FICHE CHIEN',
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
                        height: UTILS.calculHeight(
                            30, UTILS.heightReference(context))),
                    Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                  onTap: _pickImage,
                                  child: _image == null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                              UTILS.calculWidth(
                                                  8.0,
                                                  UTILS.widthReference(
                                                      context))),
                                          child: Container(
                                            width: UTILS.calculWidth(157,
                                                UTILS.widthReference(context)),
                                            height: UTILS.calculHeight(249,
                                                UTILS.heightReference(context)),
                                            color: Colors.grey[300],
                                            child: Icon(Icons.add_a_photo,
                                                size: UTILS.calculWidth(
                                                    50,
                                                    UTILS.widthReference(
                                                        context))),
                                          ))
                                      : ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                              UTILS.calculWidth(
                                                  8.0,
                                                  UTILS.widthReference(
                                                      context))),
                                          child: Image.file(
                                            _image!,
                                            width: UTILS.calculWidth(157,
                                                UTILS.widthReference(context)),
                                            height: UTILS.calculHeight(249,
                                                UTILS.heightReference(context)),
                                            fit: BoxFit.cover,
                                          ),
                                        )),
                              SizedBox(
                                  width: UTILS.calculWidth(
                                      16, UTILS.widthReference(context))),
                              Expanded(
                                child: TextField(
                                  controller: _descriptionController,
                                  maxLines: 8,
                                  decoration: InputDecoration(
                                    labelText: "Description de l'animal",
                                    alignLabelWithHint: true,
                                    border: OutlineInputBorder(
                                      borderSide:
                                          BorderSide(color: Colors.black),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                          color: Colors.black, width: 2.0),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                          color: Color.fromARGB(
                                              255, 250, 192, 187),
                                          width: 2.0),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        ])),

                    // Section Information Animal
                    ExpansionTile(
                      initiallyExpanded: isInfoExpanded,
                      title: Row(
                        children: [
                          Text(
                            'Information Animal',
                            style: TextStyle(
                              fontSize: UTILS.calculWidth(
                                  30, UTILS.widthReference(context)),
                              fontFamily: 'Galey',
                              color: const Color.fromARGB(174, 0, 0, 0),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      onExpansionChanged: (bool expanded) {
                        setState(() => isInfoExpanded = expanded);
                      },
                      children: <Widget>[
                        SizedBox(
                            width: UTILS.calculWidth(
                                355, UTILS.widthReference(context)),
                            child: TextField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                labelText: 'Nom de l\'animal (sans affixe)',
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                      color:
                                          Color.fromARGB(255, 250, 192, 187)),
                                ),
                              ),
                            )),
                        SizedBox(
                            height: UTILS.calculHeight(
                                23, UTILS.heightReference(context))),
                        SizedBox(
                            width: UTILS.calculWidth(
                                355, UTILS.widthReference(context)),
                            child: TextFormField(
                              controller: controllerDateNaissanceDog,
                              decoration: InputDecoration(
                                labelText: 'Date de naissance',
                                filled: false,
                                fillColor: Colors.transparent,
                                labelStyle: TextStyle(
                                  fontFamily: 'Galey',
                                  fontWeight: FontWeight.w500,
                                  color: Color.fromARGB(255, 0, 0, 0),
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                      color:
                                          Color.fromARGB(255, 250, 192, 187)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color.fromARGB(255, 250, 192, 187),
                                    width: UTILS.calculWidth(
                                        2, UTILS.widthReference(context)),
                                  ),
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
                                  lastDate: DateTime.now(),
                                );
                                if (pickedDate != null) {
                                  String formattedDate =
                                      '${pickedDate.day}/${pickedDate.month}/${pickedDate.year}';
                                  setState(() {
                                    controllerDateNaissanceDog.text =
                                        formattedDate;
                                  });
                                }
                              },
                            )),
                        SizedBox(
                            height: UTILS.calculHeight(
                                23, UTILS.heightReference(context))),
                        SizedBox(
                            width: UTILS.calculWidth(
                                355, UTILS.widthReference(context)),
                            child: TextField(
                              controller: _breedController,
                              decoration: InputDecoration(
                                labelText: 'Rechercher une race',
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
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _suggestedBreeds = _allBreeds
                                      .where((tag) => tag
                                          .toLowerCase()
                                          .contains(value.toLowerCase()))
                                      .toList();
                                });
                              },
                            )),
                        if (_suggestedBreeds.isNotEmpty)
                          Container(
                            width: UTILS.calculWidth(
                                355, UTILS.widthReference(context)),
                            color: Color.fromARGB(255, 250, 192, 187),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: 150,
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: _suggestedBreeds.length,
                                itemBuilder: (context, index) {
                                  return Container(
                                    color: Color.fromARGB(255, 250, 192, 187),
                                    child: ListTile(
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal:
                                              16.0), // Ajouter un padding horizontal
                                      title: Text(_suggestedBreeds[index]),
                                      onTap: () {
                                        setState(() {
                                          _breedController.text =
                                              _suggestedBreeds[index];
                                          _suggestedBreeds.clear();
                                        });
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        SizedBox(
                            height: UTILS.calculHeight(
                                23, UTILS.heightReference(context))),
                        SizedBox(
                            width: UTILS.calculWidth(
                                355, UTILS.widthReference(context)),
                            child: DropdownButtonFormField<String>(
                              dropdownColor: Colors.pink[100],
                              decoration: InputDecoration(
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                      color:
                                          Color.fromARGB(255, 250, 192, 187)),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                      color:
                                          Color.fromARGB(255, 250, 192, 187)),
                                ),
                                labelText: 'Sexe',
                              ),
                              items: ['Mâle', 'Femelle'].map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                setState(() {
                                  sexAnimal = newValue!;
                                });
                              },
                            )),
                        SizedBox(
                            height: UTILS.calculHeight(
                                23, UTILS.heightReference(context))),
                        SizedBox(
                            width: UTILS.calculWidth(
                                355, UTILS.widthReference(context)),
                            child: TextField(
                              controller: _colorController,
                              decoration: InputDecoration(
                                labelText: 'Couleur animal',
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                      color:
                                          Color.fromARGB(255, 250, 192, 187)),
                                ),
                              ),
                            )),
                        SizedBox(
                            height: UTILS.calculWidth(
                                23, UTILS.widthReference(context))),
                        SizedBox(
                            width: UTILS.calculWidth(
                                355, UTILS.widthReference(context)),
                            child: TextField(
                              controller: _chipNumberController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Numéro de puce ou tatouage',
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                      color:
                                          Color.fromARGB(255, 250, 192, 187)),
                                ),
                              ),
                            )),
                        SizedBox(
                            height: UTILS.calculHeight(
                                23, UTILS.heightReference(context))),
                      ],
                    ),

                    // Section Père
                    ExpansionTile(
                      initiallyExpanded: isPereExpanded,
                      title: Row(
                        children: [
                          Text(
                            'Père',
                            style: TextStyle(
                              fontSize: UTILS.calculWidth(
                                  30, UTILS.widthReference(context)),
                              fontFamily: 'Galey',
                              color: const Color.fromARGB(174, 0, 0, 0),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      onExpansionChanged: (bool expanded) {
                        setState(() => isPereExpanded = expanded);
                      },
                      children: <Widget>[
                        SizedBox(
                            width: UTILS.calculWidth(
                                355, UTILS.widthReference(context)),
                            child: TextField(
                              controller: _fatherNameController,
                              decoration: InputDecoration(
                                labelText: 'Nom du père',
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                      color:
                                          Color.fromARGB(255, 250, 192, 187)),
                                ),
                              ),
                            )),
                        SizedBox(
                            height: UTILS.calculHeight(
                                23, UTILS.heightReference(context))),
                        Align(
                          alignment: Alignment(-0.77, 0),
                          child: Text("ADN du père",
                              style: TextStyle(
                                  fontSize: UTILS.calculHeight(
                                      18, UTILS.heightReference(context)))),
                        ),
                        SizedBox(
                            height: UTILS.calculHeight(
                                23, UTILS.heightReference(context))),
                        SizedBox(
                          width: UTILS.calculWidth(
                              372, UTILS.widthReference(context)),
                          child: ElevatedButton(
                            onPressed: () => pickFilePedigree('ADN du pere'),
                            child: Text(
                              '📁 Joindre un fichier',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Galey',
                                color: Color.fromARGB(255, 0, 0, 0),
                                fontWeight: FontWeight.w500,
                                fontSize: UTILS.calculWidth(
                                    18, UTILS.widthReference(context)),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Color.fromARGB(255, 252, 207, 200),
                            ),
                          ),
                        ),
                        SizedBox(
                            height: UTILS.calculHeight(
                                23, UTILS.heightReference(context))),
                        Text(
                          documentElevage['ADN du pere']!['name']!,
                          style: TextStyle(
                            fontFamily: 'Galey',
                            color: Color.fromARGB(255, 0, 0, 0),
                            fontWeight: FontWeight.w500,
                            fontSize: UTILS.calculWidth(
                                13, UTILS.widthReference(context)),
                          ),
                        ),
                        if (documentElevage['ADN du pere']!['name']! !=
                            'Aucun document')
                          IconButton(
                            icon: Icon(Icons.delete,
                                color: Colors.red,
                                size: UTILS.calculWidth(
                                    20, UTILS.widthReference(context))),
                            onPressed: () {
                              setState(() {
                                documentElevage['ADN du pere'] = {
                                  'name': 'Aucun document',
                                  'path': ''
                                };
                              });
                            },
                          ),
                        SizedBox(
                            height: UTILS.calculHeight(
                                23, UTILS.heightReference(context))),
                        Align(
                          alignment: Alignment(-0.77, 0),
                          child: Text('Pedigree du père',
                              style: TextStyle(
                                  fontSize: UTILS.calculHeight(
                                      18, UTILS.heightReference(context)))),
                        ),
                        SizedBox(
                            height: UTILS.calculHeight(
                                23, UTILS.heightReference(context))),
                        SizedBox(
                          width: UTILS.calculWidth(
                              372, UTILS.widthReference(context)),
                          child: ElevatedButton(
                            onPressed: () => pickFilePedigree('Pedigree pere'),
                            child: Text(
                              '📁 Joindre un fichier',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Galey',
                                color: Color.fromARGB(255, 0, 0, 0),
                                fontWeight: FontWeight.w500,
                                fontSize: UTILS.calculWidth(
                                    18, UTILS.widthReference(context)),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Color.fromARGB(255, 252, 207, 200),
                            ),
                          ),
                        ),
                        SizedBox(
                            height: UTILS.calculHeight(
                                23, UTILS.heightReference(context))),
                        Text(
                          documentElevage['Pedigree pere']!['name']!,
                          style: TextStyle(
                            fontFamily: 'Galey',
                            color: Color.fromARGB(255, 0, 0, 0),
                            fontWeight: FontWeight.w500,
                            fontSize: UTILS.calculWidth(
                                13, UTILS.widthReference(context)),
                          ),
                        ),
                        if (documentElevage['Pedigree pere']!['name']! !=
                            'Aucun document')
                          IconButton(
                            icon: Icon(Icons.delete,
                                color: Colors.red,
                                size: UTILS.calculWidth(
                                    20, UTILS.widthReference(context))),
                            onPressed: () {
                              setState(() {
                                documentElevage['Pedigree pere'] = {
                                  'name': 'Aucun document',
                                  'path': ''
                                };
                              });
                            },
                          ),
                        SizedBox(
                            height: UTILS.calculHeight(
                                23, UTILS.heightReference(context))),
                      ],
                    ),

                    // Section Mère
                    ExpansionTile(
                      initiallyExpanded: isMereExpanded,
                      title: Row(
                        children: [
                          Text(
                            'Mère',
                            style: TextStyle(
                              fontSize: UTILS.calculWidth(
                                  30, UTILS.widthReference(context)),
                              fontFamily: 'Galey',
                              color: const Color.fromARGB(174, 0, 0, 0),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      onExpansionChanged: (bool expanded) {
                        setState(() => isMereExpanded = expanded);
                      },
                      children: <Widget>[
                        SizedBox(
                            width: UTILS.calculWidth(
                                355, UTILS.widthReference(context)),
                            child: TextField(
                              controller: _motherNameController,
                              decoration: InputDecoration(
                                labelText: 'Nom de la mère',
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                      color:
                                          Color.fromARGB(255, 250, 192, 187)),
                                ),
                              ),
                            )),
                        SizedBox(
                            height: UTILS.calculHeight(
                                23, UTILS.heightReference(context))),
                        Align(
                          alignment: Alignment(-0.77, 0),
                          child: Text('ADN de la mère',
                              style: TextStyle(
                                  fontSize: UTILS.calculHeight(
                                      18, UTILS.heightReference(context)))),
                        ),
                        SizedBox(
                            height: UTILS.calculHeight(
                                23, UTILS.heightReference(context))),
                        SizedBox(
                          width: UTILS.calculWidth(
                              372, UTILS.widthReference(context)),
                          child: ElevatedButton(
                            onPressed: () => pickFilePedigree('ADN de la mere'),
                            child: Text(
                              '📁 Joindre un fichier',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Galey',
                                color: Color.fromARGB(255, 0, 0, 0),
                                fontWeight: FontWeight.w500,
                                fontSize: UTILS.calculWidth(
                                    18, UTILS.widthReference(context)),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Color.fromARGB(255, 252, 207, 200),
                            ),
                          ),
                        ),
                        SizedBox(
                            height: UTILS.calculHeight(
                                23, UTILS.heightReference(context))),
                        Text(
                          documentElevage['ADN de la mere']!['name']!,
                          style: TextStyle(
                            fontFamily: 'Galey',
                            color: Color.fromARGB(255, 0, 0, 0),
                            fontWeight: FontWeight.w500,
                            fontSize: UTILS.calculWidth(
                                13, UTILS.widthReference(context)),
                          ),
                        ),
                        if (documentElevage['ADN de la mere']!['name']! !=
                            'Aucun document')
                          IconButton(
                            icon: Icon(Icons.delete,
                                color: Colors.red,
                                size: UTILS.calculWidth(
                                    20, UTILS.widthReference(context))),
                            onPressed: () {
                              setState(() {
                                documentElevage['ADN de la mere'] = {
                                  'name': 'Aucun document',
                                  'path': ''
                                };
                              });
                            },
                          ),
                        SizedBox(
                            height: UTILS.calculHeight(
                                23, UTILS.heightReference(context))),
                        Align(
                          alignment: Alignment(-0.77, 0),
                          child: Text('Pedigree de la mère',
                              style: TextStyle(
                                  fontSize: UTILS.calculHeight(
                                      18, UTILS.heightReference(context)))),
                        ),
                        SizedBox(
                            height: UTILS.calculHeight(
                                23, UTILS.heightReference(context))),
                        SizedBox(
                          width: UTILS.calculWidth(
                              372, UTILS.widthReference(context)),
                          child: ElevatedButton(
                            onPressed: () => pickFilePedigree('Pedigree mere'),
                            child: Text(
                              '📁 Joindre un fichier',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Galey',
                                color: Color.fromARGB(255, 0, 0, 0),
                                fontWeight: FontWeight.w500,
                                fontSize: UTILS.calculWidth(
                                    18, UTILS.widthReference(context)),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Color.fromARGB(255, 252, 207, 200),
                            ),
                          ),
                        ),
                        SizedBox(
                            height: UTILS.calculHeight(
                                23, UTILS.heightReference(context))),
                        Text(
                          documentElevage['Pedigree mere']!['name']!,
                          style: TextStyle(
                            fontFamily: 'Galey',
                            color: Color.fromARGB(255, 0, 0, 0),
                            fontWeight: FontWeight.w500,
                            fontSize: UTILS.calculWidth(
                                13, UTILS.widthReference(context)),
                          ),
                        ),
                        if (documentElevage['Pedigree mere']!['name']! !=
                            'Aucun document')
                          IconButton(
                            icon: Icon(Icons.delete,
                                color: Colors.red,
                                size: UTILS.calculWidth(
                                    20, UTILS.widthReference(context))),
                            onPressed: () {
                              setState(() {
                                documentElevage['Pedigree mere'] = {
                                  'name': 'Aucun document',
                                  'path': ''
                                };
                              });
                            },
                          ),
                        SizedBox(
                            height: UTILS.calculHeight(
                                23, UTILS.heightReference(context))),
                      ],
                    ),

                    // Section Santé
                    ExpansionTile(
                      initiallyExpanded: isSanteExpanded,
                      title: Row(
                        children: [
                          Text(
                            'Santé',
                            style: TextStyle(
                              fontSize: UTILS.calculWidth(
                                  30, UTILS.widthReference(context)),
                              fontFamily: 'Galey',
                              color: const Color.fromARGB(174, 0, 0, 0),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      onExpansionChanged: (bool expanded) {
                        setState(() => isSanteExpanded = expanded);
                      },
                      children: <Widget>[
                        Align(
                          alignment: Alignment(-0.77, 0),
                          child: Text(
                            'Vaccins',
                            style: TextStyle(
                              fontSize: UTILS.calculHeight(
                                  18, UTILS.heightReference(context)),
                            ),
                          ),
                        ),
                        ...vaccines.asMap().entries.map((entry) {
                          int index = entry.key;
                          Map<String, dynamic> vaccine = entry.value;
                          return Padding(
                            padding: EdgeInsets.symmetric(vertical: 10.0),
                            child: Column(
                              children: [
                                SizedBox(
                                  width: UTILS.calculWidth(
                                      200, UTILS.widthReference(context)),
                                  child: TextField(
                                    decoration: InputDecoration(
                                      labelText: 'Nom du vaccin',
                                      enabledBorder: UnderlineInputBorder(
                                        borderSide: BorderSide(
                                            color: Color.fromARGB(
                                                255, 250, 192, 187)),
                                      ),
                                    ),
                                    onChanged: (value) {
                                      setState(() {
                                        vaccine['name'] = value;
                                      });
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: UTILS.calculWidth(
                                      200, UTILS.widthReference(context)),
                                  child: TextField(
                                    decoration: InputDecoration(
                                      labelText: 'Date du vaccin',
                                      enabledBorder: UnderlineInputBorder(
                                        borderSide: BorderSide(
                                            color: Color.fromARGB(
                                                255, 250, 192, 187)),
                                      ),
                                    ),
                                    readOnly: true,
                                    controller: TextEditingController(
                                      text: vaccine['date'] != null
                                          ? "${vaccine['date'].day}/${vaccine['date'].month}/${vaccine['date'].year}"
                                          : '',
                                    ),
                                    onTap: () {
                                      _selectDate(context, (date) {
                                        setState(() {
                                          vaccine['date'] = date;
                                        });
                                      });
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: UTILS.calculWidth(
                                      200, UTILS.widthReference(context)),
                                  child: TextField(
                                    decoration: InputDecoration(
                                      labelText: 'Date de rappel',
                                      enabledBorder: UnderlineInputBorder(
                                        borderSide: BorderSide(
                                            color: Color.fromARGB(
                                                255, 250, 192, 187)),
                                      ),
                                    ),
                                    readOnly: true,
                                    controller: TextEditingController(
                                      text: vaccine['reminderDate'] != null
                                          ? "${vaccine['reminderDate'].day}/${vaccine['reminderDate'].month}/${vaccine['reminderDate'].year}"
                                          : '',
                                    ),
                                    onTap: () {
                                      _selectDate(context, (date) {
                                        setState(() {
                                          vaccine['reminderDate'] = date;
                                        });
                                      });
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete, color: Colors.red),
                                  onPressed: () {
                                    _removeVaccine(index);
                                  },
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        ElevatedButton(
                          onPressed: _addVaccine,
                          child: Text(
                            'Ajouter un vaccin',
                            style: TextStyle(color: Colors.black),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color.fromARGB(255, 252, 207, 200),
                          ),
                        ),
                        SizedBox(
                            height: UTILS.calculWidth(
                                23, UTILS.widthReference(context))),
                        Align(
                          alignment: Alignment(-0.77, 0),
                          child: Text(
                            'Vermifuges',
                            style: TextStyle(
                              fontSize: UTILS.calculHeight(
                                  18, UTILS.heightReference(context)),
                            ),
                          ),
                        ),
                        ...vermifuges.asMap().entries.map((entry) {
                          int index = entry.key;
                          Map<String, dynamic> vermifuge = entry.value;
                          return Padding(
                            padding: EdgeInsets.symmetric(vertical: 10.0),
                            child: Column(
                              children: [
                                SizedBox(
                                  width: UTILS.calculWidth(
                                      200, UTILS.widthReference(context)),
                                  child: TextField(
                                    decoration: InputDecoration(
                                      labelText: 'Date du vermifuge',
                                      enabledBorder: UnderlineInputBorder(
                                        borderSide: BorderSide(
                                            color: Color.fromARGB(
                                                255, 250, 192, 187)),
                                      ),
                                    ),
                                    readOnly: true,
                                    controller: TextEditingController(
                                      text: vermifuge['date'] != null
                                          ? "${vermifuge['date'].day}/${vermifuge['date'].month}/${vermifuge['date'].year}"
                                          : '',
                                    ),
                                    onTap: () {
                                      _selectDate(context, (date) {
                                        setState(() {
                                          vermifuge['date'] = date;
                                        });
                                      });
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: UTILS.calculWidth(
                                      45, UTILS.widthReference(context)),
                                ),
                                SizedBox(
                                  width: UTILS.calculWidth(
                                      200, UTILS.widthReference(context)),
                                  child: TextField(
                                    decoration: InputDecoration(
                                      labelText: 'Date de rappel',
                                      enabledBorder: UnderlineInputBorder(
                                        borderSide: BorderSide(
                                            color: Color.fromARGB(
                                                255, 250, 192, 187)),
                                      ),
                                    ),
                                    readOnly: true,
                                    controller: TextEditingController(
                                      text: vermifuge['reminderDate'] != null
                                          ? "${vermifuge['reminderDate'].day}/${vermifuge['reminderDate'].month}/${vermifuge['reminderDate'].year}"
                                          : '',
                                    ),
                                    onTap: () {
                                      _selectDate(context, (date) {
                                        setState(() {
                                          vermifuge['reminderDate'] = date;
                                        });
                                      });
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete, color: Colors.red),
                                  onPressed: () {
                                    _removeVermifuge(index);
                                  },
                                ),
                                //Divider,
                              ],
                            ),
                          );
                        }).toList(),
                        ElevatedButton(
                          onPressed: _addVermifuge,
                          child: Text('Ajouter un vermifuge',
                              style: TextStyle(color: Colors.black)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color.fromARGB(255, 252, 207, 200),
                          ),
                        ),
                      ],
                    ),

                    // Section Reproduction (Visible uniquement pour les femelles)
                    if (sexAnimal == "Femelle")
                      ExpansionTile(
                        initiallyExpanded: isReproductionExpanded,
                        title: Row(
                          children: [
                            Text(
                              'Reproduction',
                              style: TextStyle(
                                fontSize: UTILS.calculWidth(
                                    30, UTILS.widthReference(context)),
                                fontFamily: 'Galey',
                                color: const Color.fromARGB(174, 0, 0, 0),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        onExpansionChanged: (bool expanded) {
                          setState(() => isReproductionExpanded = expanded);
                        },
                        children: <Widget>[
                          Align(
                            alignment: Alignment(-0.77, 0),
                            child: Text(
                              'Chaleurs',
                              style: TextStyle(
                                fontSize: UTILS.calculHeight(
                                    18, UTILS.heightReference(context)),
                              ),
                            ),
                          ),
                          ...chaleurs.asMap().entries.map((entry) {
                            int index = entry.key;
                            DateTime chaleur = entry.value;
                            return Padding(
                              padding: EdgeInsets.symmetric(vertical: 10.0),
                              child: SizedBox(
                                  width: UTILS.calculWidth(
                                      355, UTILS.widthReference(context)),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          decoration: InputDecoration(
                                            labelText: 'Date de la chaleur',
                                            enabledBorder: UnderlineInputBorder(
                                              borderSide: BorderSide(
                                                  color: Color.fromARGB(
                                                      255, 250, 192, 187)),
                                            ),
                                          ),
                                          readOnly: true,
                                          controller: TextEditingController(
                                            text:
                                                "${chaleur.day}/${chaleur.month}/${chaleur.year}",
                                          ),
                                          onTap: () {
                                            _selectDate(context, (date) {
                                              setState(() {
                                                chaleurs[index] = date;
                                              });
                                            });
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.delete,
                                            color: Colors.red),
                                        onPressed: () {
                                          _removeChaleur(index);
                                        },
                                      ),
                                    ],
                                  )),
                            );
                          }).toList(),
                          ElevatedButton(
                            onPressed: _addChaleur,
                            child: Text('Ajouter une chaleur',
                                style: TextStyle(color: Colors.black)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Color.fromARGB(255, 252, 207, 200),
                            ),
                          ),
                          //Divider,
                          Align(
                            alignment: Alignment(-0.77, 0),
                            child: Text(
                              'Saillies',
                              style: TextStyle(
                                fontSize: UTILS.calculHeight(
                                    18, UTILS.heightReference(context)),
                              ),
                            ),
                          ),
                          ...saillies.asMap().entries.map((entry) {
                            int index = entry.key;
                            Map<String, dynamic> saillie = entry.value;
                            DateTime? saillieDate = saillie['date'];
                            return Padding(
                              padding: EdgeInsets.symmetric(vertical: 10.0),
                              child: Column(
                                children: [
                                  SizedBox(
                                      width: UTILS.calculWidth(
                                          355, UTILS.widthReference(context)),
                                      child: TextField(
                                        focusNode: _focusNode,
                                        decoration: InputDecoration(
                                          labelText: 'Nom du mâle',
                                          enabledBorder: UnderlineInputBorder(
                                            borderSide: BorderSide(
                                                color: Color.fromARGB(
                                                    255, 250, 192, 187)),
                                          ),
                                        ),
                                        onChanged: (value) {
                                          setState(() {
                                            saillie['maleName'] = value;
                                          });
                                        },
                                      )),
                                  SizedBox(
                                      height: UTILS.calculHeight(
                                          23, UTILS.heightReference(context))),
                                  SizedBox(
                                      width: UTILS.calculWidth(
                                          355, UTILS.widthReference(context)),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              decoration: InputDecoration(
                                                labelText: 'Date de la saillie',
                                                enabledBorder:
                                                    UnderlineInputBorder(
                                                  borderSide: BorderSide(
                                                      color: Color.fromARGB(
                                                          255, 250, 192, 187)),
                                                ),
                                              ),
                                              readOnly: true,
                                              controller: TextEditingController(
                                                text: saillieDate != null
                                                    ? "${saillieDate.day}/${saillieDate.month}/${saillieDate.year}"
                                                    : '',
                                              ),
                                              onTap: () {
                                                _selectDate(context, (date) {
                                                  setState(() {
                                                    saillie['date'] = date;
                                                  });
                                                });
                                              },
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.delete,
                                                color: Colors.red),
                                            onPressed: () {
                                              _removeSaillie(index);
                                            },
                                          ),
                                        ],
                                      )),
                                  if (saillieDate != null)
                                    Padding(
                                      padding: EdgeInsets.only(top: 10.0),
                                      child: Text(
                                        "Estimation de la date de mise bas : ${saillieDate.add(Duration(days: 61)).day}/${saillieDate.add(Duration(days: 61)).month}/${saillieDate.add(Duration(days: 61)).year}",
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  //Divider,
                                ],
                              ),
                            );
                          }).toList(),
                          ElevatedButton(
                            onPressed: _addSaillie,
                            child: Text('Ajouter une saillie',
                                style: TextStyle(color: Colors.black)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Color.fromARGB(255, 252, 207, 200),
                            ),
                          ),
                        ],
                      ),

                    SizedBox(
                      height: UTILS.calculHeight(
                          61, UTILS.heightReference(context)),
                      width:
                          UTILS.calculWidth(325, UTILS.widthReference(context)),
                      child: ElevatedButton(
                        onPressed: _saveData,
                        child: Text(
                          'Valider',
                          style: TextStyle(
                            fontFamily: 'Galey',
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            fontSize: UTILS.calculWidth(
                                18, UTILS.widthReference(context)),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color.fromARGB(255, 255, 132, 132),
                        ),
                      ),
                    ),

                    SizedBox(
                        height: UTILS.calculHeight(
                            30, UTILS.heightReference(context))),
                  ],
                ),
              ),
            ),
          ),
          if (_loading)
            Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
