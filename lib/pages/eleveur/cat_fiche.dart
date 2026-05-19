import 'dart:convert';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class CatFiche extends StatefulWidget {
  const CatFiche({super.key});

  @override
  State<CatFiche> createState() => _CatFicheState();
}

Future<List<String>> loadCat() async {
  final String response = await rootBundle.loadString('assets/cat_breeds.json');
  final data = json.decode(response) as List;
  return List<String>.from(data);
}

class PedigreeFile {
  final String name;
  final String category;
  bool uploaded;

  PedigreeFile({
    required this.name,
    required this.category,
    this.uploaded = false,
  });
}

class _CatFicheState extends State<CatFiche> {
  File? _image;
  TextEditingController controllerDateNaissanceCat = TextEditingController();
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
  String sexAnimal = "Mâle";
  String raceAnimal = "Ragdoll";
  String? _errorMessage;
  late Future<List<String>> catBreedsFuture;

  Map<String, Map<String, dynamic>> documentElevage = {
    'ADN du père': {},
    'Pedigree père': {},
    'ADN de la mère': {},
    'Pedigree mère': {},
    'Test génétique du chat': {},
    'Cotation': {},
    'Vaccin': {},
    'Pedigree': {},
  };

  List<Map<String, dynamic>> vaccines = [];
  List<Map<String, dynamic>> vermifuges = [];
  List<DateTime> chaleurs = [];
  List<Map<String, dynamic>> saillies = [];

  bool _loading = false;
  bool _viensDeVotreElevage = true;
  bool isInfoExpanded = false;
  bool isPereExpanded = false;
  bool isMereExpanded = false;
  bool isSanteExpanded = false;
  bool isReproductionExpanded = false;

  TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    catBreedsFuture = loadCat();

    catBreedsFuture.then((breeds) {
      setState(() {
        _allBreeds = breeds;
      });
    });
    if (_viensDeVotreElevage) {
      _controller.text = User_Info.nameElevage;
    }
    isInfoExpanded = false;
    isPereExpanded = false;
    isMereExpanded = false;
    isSanteExpanded = false;
    isReproductionExpanded = false;
  }

  Future<void> pickFilePedigree(String category) async {
    FilePickerResult? pickedFile = await FilePicker.pickFiles();
    if (pickedFile != null) {
      String? fileName = pickedFile.files.single.name;
      String? filePath = pickedFile.files.single.path;
      setState(() {
        documentElevage[category] = {
          'name': fileName,
          'uploaded': false,
          'path': filePath,
        };
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
                  'Cette application a besoin d\'un accès complet à votre stockage pour sélectionner les fichiers.',
                ),
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

  void _handleCheckboxChange(bool? value) {
    setState(() {
      _viensDeVotreElevage = !_viensDeVotreElevage;
      if (_viensDeVotreElevage) {
        _controller.text = User_Info.nameElevage;
      } else {
        _controller.clear();
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
      final docRef = FirebaseFirestore.instance.collection('catfiche').doc(uid);
      final docId = docRef.collection('entries').doc().id;

      Map<String, dynamic> catData = {
        'description': _descriptionController.text,
        'name': _nameController.text,
        'dateOfBirth': controllerDateNaissanceCat.text,
        'race': raceAnimal,
        'sex': sexAnimal,
        'color': _colorController.text,
        'fatherName': _fatherNameController.text,
        'motherName': _motherNameController.text,
        'motherDNA': _motherDNAController.text,
        'chipNumber': _chipNumberController.text,
        'coatType': _coatTypeController.text,
        'birthWeight': _birthWeightController.text,
        'breeding':
            _viensDeVotreElevage ? User_Info.nameElevage : _controller.text,
        'profilePicture': 'Aucune photo de profil',
        'documents': {},
        'vaccines': vaccines,
        'vermifuges': vermifuges,
        'chaleurs': chaleurs.map((date) => date.toIso8601String()).toList(),
        'saillies': saillies,
      };

      if (_image != null) {
        String profilePictureUrl =
            await _uploadFile(_image!, docId, 'pictureCatProfile');
        catData['profilePicture'] = profilePictureUrl;
      }

      for (String category in documentElevage.keys) {
        if (documentElevage[category]!['path'] != null) {
          File file = File(documentElevage[category]!['path']);
          String downloadUrl = await _uploadFile(
              file, docId, documentElevage[category]!['name']);
          catData['documents'][category] = downloadUrl;
        } else {
          catData['documents'][category] = 'Aucun document';
        }
      }

      await docRef.collection('entries').doc(docId).set(catData);

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
                  Navigator.of(context).pop();
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

  void _resetForm() {
    setState(() {
      _image = null;
      _descriptionController.clear();
      _nameController.clear();
      controllerDateNaissanceCat.clear();
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
        'ADN du père': {},
        'Pedigree père': {},
        'ADN de la mère': {},
        'Pedigree mère': {},
        'Test génétique du chat': {},
        'Cotation': {},
        'Vaccin': {},
        'Pedigree': {},
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
      vaccines.add({'name': '', 'date': null, 'reminderDate': null});
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
      saillies.add({'maleName': '', 'date': null});
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
                                'FICHE CHAT',
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
                      height: UTILS.calculHeight(
                          30, UTILS.heightReference(context)),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: _pickImage,
                                child: _image == null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                            UTILS.calculWidth(8.0,
                                                UTILS.widthReference(context))),
                                        child: Container(
                                          width: UTILS.calculWidth(157,
                                              UTILS.widthReference(context)),
                                          height: UTILS.calculHeight(249,
                                              UTILS.heightReference(context)),
                                          color: Colors.grey[300],
                                          child: Icon(
                                            Icons.add_a_photo,
                                            size: UTILS.calculWidth(50,
                                                UTILS.widthReference(context)),
                                          ),
                                        ),
                                      )
                                    : ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                            UTILS.calculWidth(8.0,
                                                UTILS.widthReference(context))),
                                        child: Image.file(
                                          _image!,
                                          width: UTILS.calculWidth(157,
                                              UTILS.widthReference(context)),
                                          height: UTILS.calculHeight(249,
                                              UTILS.heightReference(context)),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                              ),
                              SizedBox(
                                width: UTILS.calculWidth(
                                    16, UTILS.widthReference(context)),
                              ),
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
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: UTILS.calculHeight(
                          23, UTILS.heightReference(context)),
                    ),
                    ExpansionTile(
                      initiallyExpanded: isInfoExpanded,
                      title: Row(
                        children: [
                          Text(
                            'Information du Chat',
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
                                    color: Color.fromARGB(255, 250, 192, 187)),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: UTILS.calculHeight(
                              23, UTILS.heightReference(context)),
                        ),
                        SizedBox(
                          width: UTILS.calculWidth(
                              355, UTILS.widthReference(context)),
                          child: TextFormField(
                            controller: controllerDateNaissanceCat,
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
                                    color: Color.fromARGB(255, 250, 192, 187)),
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
                              FocusScope.of(context).requestFocus(FocusNode());
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
                                  controllerDateNaissanceCat.text =
                                      formattedDate;
                                });
                              }
                            },
                          ),
                        ),
                        SizedBox(
                          height: UTILS.calculHeight(
                              23, UTILS.heightReference(context)),
                        ),
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
                              23, UTILS.heightReference(context)),
                        ),
                        SizedBox(
                          width: UTILS.calculWidth(
                              355, UTILS.widthReference(context)),
                          child: DropdownButtonFormField<String>(
                            dropdownColor: Colors.pink[100],
                            decoration: InputDecoration(
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: Color.fromARGB(255, 250, 192, 187)),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: Color.fromARGB(255, 250, 192, 187)),
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
                          ),
                        ),
                        SizedBox(
                          height: UTILS.calculHeight(
                              23, UTILS.heightReference(context)),
                        ),
                        SizedBox(
                          width: UTILS.calculWidth(
                              355, UTILS.widthReference(context)),
                          child: TextField(
                            controller: _colorController,
                            decoration: InputDecoration(
                              labelText: 'Couleur animal',
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: Color.fromARGB(255, 250, 192, 187)),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: UTILS.calculHeight(
                              23, UTILS.heightReference(context)),
                        ),
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
                                    color: Color.fromARGB(255, 250, 192, 187)),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: UTILS.calculHeight(
                              23, UTILS.heightReference(context)),
                        ),
                        SizedBox(
                          width: UTILS.calculWidth(
                              355, UTILS.widthReference(context)),
                          child: TextField(
                            controller: _coatTypeController,
                            decoration: InputDecoration(
                              labelText: 'Type de pelage',
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: Color.fromARGB(255, 250, 192, 187)),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: UTILS.calculHeight(
                              23, UTILS.heightReference(context)),
                        ),
                        SizedBox(
                          width: UTILS.calculWidth(
                              355, UTILS.widthReference(context)),
                          child: TextField(
                            controller: _birthWeightController,
                            decoration: InputDecoration(
                              labelText: 'Poids à la naissance',
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: Color.fromARGB(255, 250, 192, 187)),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: UTILS.calculHeight(
                              23, UTILS.heightReference(context)),
                        ),
                      ],
                    ),
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
                                    color: Color.fromARGB(255, 250, 192, 187)),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: UTILS.calculHeight(
                              23, UTILS.heightReference(context)),
                        ),
                        Align(
                          alignment: Alignment(-0.77, 0),
                          child: Text(
                            "ADN du père",
                            style: TextStyle(
                              fontSize: UTILS.calculHeight(
                                  18, UTILS.heightReference(context)),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: UTILS.calculHeight(
                              23, UTILS.heightReference(context)),
                        ),
                        SizedBox(
                          width: UTILS.calculWidth(
                              372, UTILS.widthReference(context)),
                          child: ElevatedButton(
                            onPressed: () => pickFilePedigree('ADN du père'),
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
                        if (documentElevage['ADN du père']?['name'] != null)
                          SizedBox(
                            height: UTILS.calculHeight(
                                50, UTILS.heightReference(context)),
                            child: Card(
                              color: Colors.transparent,
                              margin: EdgeInsets.symmetric(
                                horizontal: UTILS.calculWidth(
                                    30, UTILS.widthReference(context)),
                                vertical: 0,
                              ),
                              shadowColor: Color.fromARGB(0, 255, 255, 255),
                              surfaceTintColor: Colors.transparent,
                              child: ListTile(
                                title: Text(
                                  documentElevage['ADN du père']!['name'],
                                  style: TextStyle(
                                    fontFamily: 'Galey',
                                    color: Color.fromARGB(255, 0, 0, 0),
                                    fontWeight: FontWeight.w500,
                                    fontSize: UTILS.calculWidth(
                                        13, UTILS.widthReference(context)),
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                    size: UTILS.calculWidth(
                                        20, UTILS.widthReference(context)),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      documentElevage['ADN du père'] = {};
                                    });
                                  },
                                ),
                              ),
                            ),
                          ),
                        Align(
                          alignment: Alignment(-0.77, 0),
                          child: Text(
                            'Pedigree du père',
                            style: TextStyle(
                              fontSize: UTILS.calculHeight(
                                  18, UTILS.heightReference(context)),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: UTILS.calculHeight(
                              23, UTILS.heightReference(context)),
                        ),
                        SizedBox(
                          width: UTILS.calculWidth(
                              372, UTILS.widthReference(context)),
                          child: ElevatedButton(
                            onPressed: () => pickFilePedigree('Pedigree père'),
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
                        if (documentElevage['Pedigree père']?['name'] != null)
                          SizedBox(
                            height: UTILS.calculHeight(
                                50, UTILS.heightReference(context)),
                            child: Card(
                              color: Colors.transparent,
                              margin: EdgeInsets.symmetric(
                                horizontal: UTILS.calculWidth(
                                    30, UTILS.widthReference(context)),
                                vertical: 0,
                              ),
                              shadowColor: Color.fromARGB(0, 255, 255, 255),
                              surfaceTintColor: Colors.transparent,
                              child: ListTile(
                                title: Text(
                                  documentElevage['Pedigree père']!['name'],
                                  style: TextStyle(
                                    fontFamily: 'Galey',
                                    color: Color.fromARGB(255, 0, 0, 0),
                                    fontWeight: FontWeight.w500,
                                    fontSize: UTILS.calculWidth(
                                        13, UTILS.widthReference(context)),
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                    size: UTILS.calculWidth(
                                        20, UTILS.widthReference(context)),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      documentElevage['Pedigree père'] = {};
                                    });
                                  },
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
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
                                    color: Color.fromARGB(255, 250, 192, 187)),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: UTILS.calculHeight(
                              23, UTILS.heightReference(context)),
                        ),
                        Align(
                          alignment: Alignment(-0.77, 0),
                          child: Text(
                            'ADN de la mère',
                            style: TextStyle(
                              fontSize: UTILS.calculHeight(
                                  18, UTILS.heightReference(context)),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: UTILS.calculHeight(
                              23, UTILS.heightReference(context)),
                        ),
                        SizedBox(
                          width: UTILS.calculWidth(
                              372, UTILS.widthReference(context)),
                          child: ElevatedButton(
                            onPressed: () => pickFilePedigree('ADN de la mère'),
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
                        if (documentElevage['ADN de la mère']?['name'] != null)
                          SizedBox(
                            height: UTILS.calculHeight(
                                50, UTILS.heightReference(context)),
                            child: Card(
                              color: Colors.transparent,
                              margin: EdgeInsets.symmetric(
                                horizontal: UTILS.calculWidth(
                                    30, UTILS.widthReference(context)),
                                vertical: 0,
                              ),
                              shadowColor: Color.fromARGB(0, 255, 255, 255),
                              surfaceTintColor: Colors.transparent,
                              child: ListTile(
                                title: Text(
                                  documentElevage['ADN de la mère']!['name'],
                                  style: TextStyle(
                                    fontFamily: 'Galey',
                                    color: Color.fromARGB(255, 0, 0, 0),
                                    fontWeight: FontWeight.w500,
                                    fontSize: UTILS.calculWidth(
                                        13, UTILS.widthReference(context)),
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                    size: UTILS.calculWidth(
                                        20, UTILS.widthReference(context)),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      documentElevage['ADN de la mère'] = {};
                                    });
                                  },
                                ),
                              ),
                            ),
                          ),
                        Align(
                          alignment: Alignment(-0.77, 0),
                          child: Text(
                            'Pedigree de la mère',
                            style: TextStyle(
                              fontSize: UTILS.calculHeight(
                                  18, UTILS.heightReference(context)),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: UTILS.calculHeight(
                              23, UTILS.heightReference(context)),
                        ),
                        SizedBox(
                          width: UTILS.calculWidth(
                              372, UTILS.widthReference(context)),
                          child: ElevatedButton(
                            onPressed: () => pickFilePedigree('Pedigree mère'),
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
                        if (documentElevage['Pedigree mère']?['name'] != null)
                          SizedBox(
                            height: UTILS.calculHeight(
                                50, UTILS.heightReference(context)),
                            child: Card(
                              color: Colors.transparent,
                              margin: EdgeInsets.symmetric(
                                horizontal: UTILS.calculWidth(
                                    30, UTILS.widthReference(context)),
                                vertical: 0,
                              ),
                              shadowColor: Color.fromARGB(0, 255, 255, 255),
                              surfaceTintColor: Colors.transparent,
                              child: ListTile(
                                title: Text(
                                  documentElevage['Pedigree mère']!['name'],
                                  style: TextStyle(
                                    fontFamily: 'Galey',
                                    color: Color.fromARGB(255, 0, 0, 0),
                                    fontWeight: FontWeight.w500,
                                    fontSize: UTILS.calculWidth(
                                        13, UTILS.widthReference(context)),
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                    size: UTILS.calculWidth(
                                        20, UTILS.widthReference(context)),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      documentElevage['Pedigree mère'] = {};
                                    });
                                  },
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
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
                                    controller: TextEditingController(
                                      text: vaccine['name'] ?? '',
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height: 10,
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
                                          ? (vaccine['date'] is Timestamp)
                                              ? "${(vaccine['date'] as Timestamp).toDate().day}/${(vaccine['date'] as Timestamp).toDate().month}/${(vaccine['date'] as Timestamp).toDate().year}"
                                              : "${(vaccine['date'] as DateTime).day}/${(vaccine['date'] as DateTime).month}/${(vaccine['date'] as DateTime).year}"
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
                                  height: 10,
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
                                          ? (vaccine['reminderDate']
                                                  is Timestamp)
                                              ? "${(vaccine['reminderDate'] as Timestamp).toDate().day}/${(vaccine['reminderDate'] as Timestamp).toDate().month}/${(vaccine['reminderDate'] as Timestamp).toDate().year}"
                                              : "${(vaccine['reminderDate'] as DateTime).day}/${(vaccine['reminderDate'] as DateTime).month}/${(vaccine['reminderDate'] as DateTime).year}"
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
                              23, UTILS.widthReference(context)),
                        ),
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
                                    ),
                                  ),
                                  SizedBox(
                                    height: UTILS.calculHeight(
                                        23, UTILS.heightReference(context)),
                                  ),
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
                                    ),
                                  ),
                                  if (saillieDate != null)
                                    Padding(
                                      padding: EdgeInsets.only(top: 10.0),
                                      child: Text(
                                        "Estimation de la date de mise bas : ${saillieDate.add(Duration(days: 63)).day}/${saillieDate.add(Duration(days: 63)).month}/${saillieDate.add(Duration(days: 63)).year}",
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
                          23, UTILS.heightReference(context)),
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
                          30, UTILS.heightReference(context)),
                    ),
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
