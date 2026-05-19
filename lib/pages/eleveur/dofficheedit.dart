import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

class DogFicheEdit extends StatefulWidget {
  final Map<String, dynamic> dogData;

  const DogFicheEdit({Key? key, required this.dogData}) : super(key: key);

  @override
  _DogFicheEditState createState() => _DogFicheEditState();
}

class _DogFicheEditState extends State<DogFicheEdit> {
  File? _image;
  String? _profilePictureUrl;
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
  TextEditingController _controller = TextEditingController();
  TextEditingController controllerDateNaissanceDog = TextEditingController();
  List<TextEditingController> _maleNameControllers = [];
  List<TextEditingController> vaccinControllers = [];

  List<String> _allBreeds = [];
  List<String> _suggestedBreeds = []; // Pour stocker les suggestions filtrées
  TextEditingController _breedController = TextEditingController();
  bool _viensDeVotreElevage = true;
  String? _errorMessage;
  bool _loading = false;
  late Future<List<String>> dogBreedsFuture;
  String sexAnimal = "Mâle";
  String raceAnimal = "Aucun";
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
    'Cotation': {'name': 'Aucun document', 'path': ''},
    'Pedigree': {'name': 'Aucun document', 'path': ''},
    'Vaccin': {'name': 'Aucun document', 'path': ''},
  };

  @override
  void initState() {
    super.initState();
    _descriptionController.text = widget.dogData['description'] ?? '';
    _nameController.text = widget.dogData['name'] ?? '';
    _colorController.text = widget.dogData['color'] ?? '';
    _fatherNameController.text = widget.dogData['fatherName'] ?? '';
    _motherNameController.text = widget.dogData['motherName'] ?? '';
    _fatherDNAController.text = widget.dogData['fatherDNA'] ?? '';
    _motherDNAController.text = widget.dogData['motherDNA'] ?? '';
    sexAnimal = widget.dogData['sex'] ?? 'Aucun';
    raceAnimal = widget.dogData['race'] ?? 'Aucun';
    _breedController.text = widget.dogData['race'] ?? '';

    _chipNumberController.text = widget.dogData['chipNumber'] ?? '';
    _coatTypeController.text = widget.dogData['coatType'] ?? '';
    _birthWeightController.text = widget.dogData['birthWeight'] ?? '';
    controllerDateNaissanceDog.text = widget.dogData['dateOfBirth'] ?? '';
    _controller.text = widget.dogData['breeding'] ?? '';
    _viensDeVotreElevage = widget.dogData['breeding'] == '';
    // Initialiser un contrôleur pour chaque entrée dans saillies, seulement si saillies n'est pas vide

    vaccines = widget.dogData['vaccines'] != null
        ? List<Map<String, dynamic>>.from(widget.dogData['vaccines'])
        : [];

    if (vaccines.isNotEmpty) {
      for (var vaccines in vaccines) {
        vaccinControllers
            .add(TextEditingController(text: vaccines['name'] ?? ''));
      }
    }

    vermifuges = widget.dogData['vermifuges'] != null
        ? List<Map<String, dynamic>>.from(widget.dogData['vermifuges'])
        : [];

    chaleurs = widget.dogData['chaleurs'] != null
        ? List<DateTime>.from((widget.dogData['chaleurs'] as List<dynamic>)
            .map((date) => DateTime.parse(date)))
        : [];

    saillies = widget.dogData['saillies'] != null
        ? List<Map<String, dynamic>>.from(widget.dogData['saillies'])
        : [];
    if (saillies.isNotEmpty) {
      for (var saillie in saillies) {
        _maleNameControllers
            .add(TextEditingController(text: saillie['maleName'] ?? ''));
      }
    }
    if (widget.dogData['documents'] is Map) {
      (widget.dogData['documents'] as Map<String, dynamic>)
          .forEach((key, value) {
        if (value is String) {
          documentElevage[key] = {'name': value, 'path': ''};
        } else if (value is Map<String, dynamic>) {
          documentElevage[key] = {
            'name': value['name'] ?? 'Aucun document',
            'path': value['path'] ?? ''
          };
        }
      });
    }

    if (widget.dogData['profilePicture'] != 'Aucune photo de profil') {
      _profilePictureUrl = widget.dogData['profilePicture'];
    }

    dogBreedsFuture = loadDogBreeds();
    dogBreedsFuture.then((breeds) {
      setState(() {
        _allBreeds = breeds;
      });
    });
  }

  Future<List<String>> loadDogBreeds() async {
    final String response =
        await rootBundle.loadString('assets/dog_breeds.json');
    final data = json.decode(response) as List;
    List<String> breeds = List<String>.from(data);
    breeds.insert(0, 'Aucun'); // Ajouter la valeur par défaut
    return breeds;
  }

  @override
  void dispose() {
    _maleNameControllers.forEach((controller) => controller.dispose());
    vaccinControllers.forEach((controller) => controller.dispose());
    super.dispose();
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

  void _handleCheckboxChange(bool? value) {
    setState(() {
      _viensDeVotreElevage = !_viensDeVotreElevage;
      if (_viensDeVotreElevage) {
        _controller.text = ""; // Texte par défaut
      } else {
        _controller
            .clear(); // Efface le texte pour permettre à l'utilisateur d'entrer un nouveau texte
      }
    });
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
      final docId = widget.dogData['id'];

      Map<String, dynamic> dogData = {
        'description': _descriptionController.text,
        'name': _nameController.text,
        'dateOfBirth': controllerDateNaissanceDog.text,
        'race': raceAnimal,
        'sex': sexAnimal,
        'color': _colorController.text,
        'fatherName': _fatherNameController.text,
        'motherName': _motherNameController.text,
        'motherDNA': _motherDNAController.text,
        'chipNumber': _chipNumberController.text,
        'coatType': _coatTypeController.text,
        'birthWeight': _birthWeightController.text,
        'breeding': _viensDeVotreElevage ? '' : _controller.text,
        'profilePicture':
            widget.dogData['profilePicture'] ?? 'Aucune photo de profil',
        'documents': widget.dogData['documents'] ?? {},
        'vaccines': vaccines,
        'vermifuges': vermifuges,
        'chaleurs': chaleurs.map((date) => date.toIso8601String()).toList(),
        'saillies': saillies,
      };

      if (_image != null) {
        String profilePictureUrl =
            await _uploadFile(_image!, docId, 'pictureDogProfile');
        dogData['profilePicture'] = profilePictureUrl;
      }

      for (String category in documentElevage.keys) {
        if (documentElevage[category]!['path']!.isNotEmpty) {
          File file = File(documentElevage[category]!['path']!);
          String downloadUrl = await _uploadFile(
              file, docId, documentElevage[category]!['name']!);
          dogData['documents'][category] = downloadUrl;
        } else {
          dogData['documents'][category] =
              widget.dogData['documents'][category] ?? 'Aucun document';
        }
      }

      await docRef.collection('entries').doc(docId).update(dogData);

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
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

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

  Widget _buildDocumentRow(
      String category, String documentName, String documentPath) {
    if (documentName == 'Aucun document') {
      return SizedBox.shrink();
    }

    return SizedBox(
      height: UTILS.calculHeight(50, UTILS.heightReference(context)),
      child: Card(
        color: Colors.transparent,
        margin: EdgeInsets.symmetric(
          horizontal: UTILS.calculWidth(30, UTILS.widthReference(context)),
          vertical: 0,
        ),
        shadowColor: Color.fromARGB(0, 255, 255, 255),
        surfaceTintColor: Colors.transparent,
        child: ListTile(
          title: Center(
            child: Text(
              documentName,
              style: TextStyle(
                fontFamily: 'Galey',
                color: Color.fromARGB(255, 0, 0, 0),
                fontWeight: FontWeight.w500,
                fontSize: UTILS.calculWidth(13, UTILS.widthReference(context)),
              ),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (documentName.isNotEmpty)
                IconButton(
                  icon: Icon(
                    Icons.visibility,
                    color: Colors.blue,
                    size: UTILS.calculWidth(20, UTILS.widthReference(context)),
                  ),
                  onPressed: () {
                    if (documentName.isNotEmpty) {
                      launch(documentName);
                    }
                  },
                ),
              IconButton(
                icon: Icon(
                  Icons.delete,
                  color: Colors.red,
                  size: UTILS.calculWidth(20, UTILS.widthReference(context)),
                ),
                onPressed: () {
                  setState(() {
                    documentElevage[category] = {
                      'name': 'Aucun document',
                      'path': ''
                    };
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addVaccine() {
    setState(() {
      vaccines.add({'name': '', 'date': null, 'reminderDate': null});
      vaccinControllers.add(
          TextEditingController(text: '')); // Ajouter un nouveau contrôleur
    });
  }

  void _removeVaccine(int index) {
    setState(() {
      vaccines.removeAt(index);
      vaccinControllers[index].dispose(); // Libérer le contrôleur
      vaccinControllers.removeAt(index); // Supprimer le contrôleur
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
      _maleNameControllers.add(
          TextEditingController(text: '')); // Ajouter un nouveau contrôleur
    });
  }

  void _removeSaillie(int index) {
    setState(() {
      if (index < saillies.length) {
        saillies.removeAt(index);
        _maleNameControllers[index].dispose(); // Libérer le contrôleur
        _maleNameControllers.removeAt(index); // Supprimer le contrôleur
      }
    });
  }

  Future<void> _selectDate(
      BuildContext context, Function(DateTime) onConfirm) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      onConfirm(picked);
    }
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
                                  child: _image == null &&
                                          _profilePictureUrl == null
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
                                          child: _image != null
                                              ? Image.file(
                                                  _image!,
                                                  width: UTILS.calculWidth(
                                                      157,
                                                      UTILS.widthReference(
                                                          context)),
                                                  height: UTILS.calculHeight(
                                                      249,
                                                      UTILS.heightReference(
                                                          context)),
                                                  fit: BoxFit.cover,
                                                )
                                              : Image.network(
                                                  _profilePictureUrl!,
                                                  width: UTILS.calculWidth(
                                                      157,
                                                      UTILS.widthReference(
                                                          context)),
                                                  height: UTILS.calculHeight(
                                                      249,
                                                      UTILS.heightReference(
                                                          context)),
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
                    SizedBox(
                        height: UTILS.calculHeight(
                            23, UTILS.heightReference(context))),
                    ExpansionTile(
                      title: Text(
                        'Information du chien',
                        style: TextStyle(
                            fontSize: UTILS.calculWidth(
                                30, UTILS.widthReference(context)),
                            fontFamily: 'Galey',
                            color: const Color.fromARGB(174, 0, 0, 0),
                            fontWeight: FontWeight.w500),
                        textAlign: TextAlign.left,
                      ),
                      children: [
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
                              labelText: 'Race du chien',
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
                                    .where((breed) => breed
                                        .toLowerCase()
                                        .contains(value.toLowerCase()))
                                    .toList();
                              });
                            },
                          ),
                        ),
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
                                          horizontal: 16.0),
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
                              value: sexAnimal,
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
                            height: UTILS.calculHeight(
                                23, UTILS.heightReference(context))),
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
                      ],
                    ),
                    SizedBox(
                        height: UTILS.calculHeight(
                            23, UTILS.heightReference(context))),
                    ExpansionTile(
                      title: Text(
                        'Père',
                        style: TextStyle(
                            fontSize: UTILS.calculWidth(
                                30, UTILS.widthReference(context)),
                            fontFamily: 'Galey',
                            color: const Color.fromARGB(174, 0, 0, 0),
                            fontWeight: FontWeight.w500),
                        textAlign: TextAlign.left,
                      ),
                      children: [
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
                        _buildDocumentRow(
                          'ADN du pere',
                          documentElevage['ADN du pere']!['name']!,
                          documentElevage['ADN du pere']!['path']!,
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
                        _buildDocumentRow(
                          'Pedigree pere',
                          documentElevage['Pedigree pere']!['name']!,
                          documentElevage['Pedigree pere']!['path']!,
                        ),
                      ],
                    ),
                    SizedBox(
                        height: UTILS.calculHeight(
                            23, UTILS.heightReference(context))),
                    ExpansionTile(
                      title: Text(
                        'Mère',
                        style: TextStyle(
                            fontSize: UTILS.calculWidth(
                                30, UTILS.widthReference(context)),
                            fontFamily: 'Galey',
                            color: const Color.fromARGB(174, 0, 0, 0),
                            fontWeight: FontWeight.w500),
                        textAlign: TextAlign.left,
                      ),
                      children: [
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
                        _buildDocumentRow(
                          'ADN de la mere',
                          documentElevage['ADN de la mere']!['name']!,
                          documentElevage['ADN de la mere']!['path']!,
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
                        _buildDocumentRow(
                          'Pedigree mere',
                          documentElevage['Pedigree mere']!['name']!,
                          documentElevage['Pedigree mere']!['path']!,
                        ),
                      ],
                    ),
                    SizedBox(
                        height: UTILS.calculHeight(
                            23, UTILS.heightReference(context))),
                    ExpansionTile(
                      initiallyExpanded: isSanteExpanded,
                      title: Text(
                        'Santé',
                        style: TextStyle(
                          fontSize: UTILS.calculWidth(
                              30, UTILS.widthReference(context)),
                          fontFamily: 'Galey',
                          color: const Color.fromARGB(174, 0, 0, 0),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onExpansionChanged: (bool expanded) {
                        setState(() => isSanteExpanded = expanded);
                      },
                      children: [
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
                                          ? (vermifuge['date'] is Timestamp)
                                              ? "${(vermifuge['date'] as Timestamp).toDate().day}/${(vermifuge['date'] as Timestamp).toDate().month}/${(vermifuge['date'] as Timestamp).toDate().year}"
                                              : "${(vermifuge['date'] as DateTime).day}/${(vermifuge['date'] as DateTime).month}/${(vermifuge['date'] as DateTime).year}"
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
                                          ? (vermifuge['reminderDate']
                                                  is Timestamp)
                                              ? "${(vermifuge['reminderDate'] as Timestamp).toDate().day}/${(vermifuge['reminderDate'] as Timestamp).toDate().month}/${(vermifuge['reminderDate'] as Timestamp).toDate().year}"
                                              : "${(vermifuge['reminderDate'] as DateTime).day}/${(vermifuge['reminderDate'] as DateTime).month}/${(vermifuge['reminderDate'] as DateTime).year}"
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
                    SizedBox(
                        height: UTILS.calculHeight(
                            23, UTILS.heightReference(context))),
                    if (sexAnimal == "Femelle")
                      ExpansionTile(
                        initiallyExpanded: isReproductionExpanded,
                        title: Text(
                          'Reproduction',
                          style: TextStyle(
                            fontSize: UTILS.calculWidth(
                                30, UTILS.widthReference(context)),
                            fontFamily: 'Galey',
                            color: const Color.fromARGB(174, 0, 0, 0),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        onExpansionChanged: (bool expanded) {
                          setState(() => isReproductionExpanded = expanded);
                        },
                        children: [
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
                            dynamic chaleur = entry
                                .value; // Le type dynamique pour supporter plusieurs types

                            DateTime? chaleurDate;

                            if (chaleur is Timestamp) {
                              chaleurDate = chaleur.toDate();
                            } else if (chaleur is DateTime) {
                              chaleurDate = chaleur;
                            } else if (chaleur is String) {
                              chaleurDate = DateTime.tryParse(chaleur);
                            }

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
                                            text: chaleurDate != null
                                                ? "${chaleurDate.day}/${chaleurDate.month}/${chaleurDate.year}"
                                                : '',
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

                            // Vérifier que l'index est valide et que les contrôleurs existent bien pour chaque saillie
                            if (index < _maleNameControllers.length) {
                              return Padding(
                                padding: EdgeInsets.symmetric(vertical: 10.0),
                                child: Column(
                                  children: [
                                    // TextField pour le nom du mâle
                                    SizedBox(
                                      width: UTILS.calculWidth(
                                          355, UTILS.widthReference(context)),
                                      child: TextField(
                                        controller: _maleNameControllers[
                                            index], // Utilisation du contrôleur spécifique
                                        decoration: InputDecoration(
                                          labelText: 'Nom du mâle',
                                          enabledBorder: UnderlineInputBorder(
                                            borderSide: BorderSide(
                                              color: Color.fromARGB(
                                                  255, 250, 192, 187),
                                            ),
                                          ),
                                        ),
                                        onChanged: (value) {
                                          setState(() {
                                            saillie['maleName'] =
                                                value; // Mise à jour du saillie spécifique
                                          });
                                        },
                                      ),
                                    ),
                                    SizedBox(height: 10),

                                    // TextField pour la date de la saillie (affiche la date formatée)
                                    SizedBox(
                                      width: UTILS.calculWidth(
                                          355, UTILS.widthReference(context)),
                                      child: TextField(
                                        decoration: InputDecoration(
                                          labelText: 'Date de la saillie',
                                          enabledBorder: UnderlineInputBorder(
                                            borderSide: BorderSide(
                                              color: Color.fromARGB(
                                                  255, 250, 192, 187),
                                            ),
                                          ),
                                        ),
                                        readOnly:
                                            true, // Champ en lecture seule
                                        controller: TextEditingController(
                                          text: saillie['date'] != null
                                              ? (saillie['date'] is Timestamp)
                                                  ? "${(saillie['date'] as Timestamp).toDate().day}/${(saillie['date'] as Timestamp).toDate().month}/${(saillie['date'] as Timestamp).toDate().year}"
                                                  : "${(saillie['date'] as DateTime).day}/${(saillie['date'] as DateTime).month}/${(saillie['date'] as DateTime).year}"
                                              : '',
                                        ),
                                        onTap: () {
                                          _selectDate(context, (date) {
                                            setState(() {
                                              saillie['date'] =
                                                  date; // Mise à jour de la date de la saillie
                                            });
                                          });
                                        },
                                      ),
                                    ),
                                    SizedBox(height: 3),

                                    // Icône pour supprimer la saillie
                                    IconButton(
                                      icon: Icon(Icons.delete,
                                          color:
                                              Colors.red), // Icône de poubelle
                                      onPressed: () {
                                        _removeSaillie(
                                            index); // Suppression de la saillie
                                      },
                                    ),
                                    if (saillie['date'] != null)
                                      Padding(
                                        padding: EdgeInsets.only(top: 10.0),
                                        child: Builder(
                                          builder: (context) {
                                            // Vérification du type de saillie['date']
                                            DateTime date;

                                            if (saillie['date'] is Timestamp) {
                                              // Si c'est un Timestamp, on le convertit en DateTime
                                              date =
                                                  (saillie['date'] as Timestamp)
                                                      .toDate();
                                            } else if (saillie['date']
                                                is DateTime) {
                                              // Si c'est déjà un DateTime, on l'utilise directement
                                              date =
                                                  saillie['date'] as DateTime;
                                            } else {
                                              // Si le type est invalide, on retourne un widget vide ou une autre gestion d'erreur
                                              return Text(
                                                "Date invalide",
                                                style: TextStyle(
                                                  color: Colors.red,
                                                  fontSize: 14,
                                                ),
                                              );
                                            }

                                            // Ajout de 63 jours pour calculer la date estimée
                                            final DateTime estimatedDate =
                                                date.add(Duration(days: 61));

                                            // Affichage formaté
                                            return Text(
                                              "Estimation de la date de mise bas : ${estimatedDate.day}/${estimatedDate.month}/${estimatedDate.year}",
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            );
                                          },
                                        ),
                                      ),

                                    //Divider, // Ligne de sé
                                  ],
                                ),
                              );
                            } else {
                              return SizedBox
                                  .shrink(); // Si l'index est hors de portée, ne rien afficher
                            }
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
                            30, UTILS.heightReference(context))),
                    SizedBox(
                      height: UTILS.calculHeight(
                          61, UTILS.heightReference(context)),
                      width:
                          UTILS.calculWidth(325, UTILS.widthReference(context)),
                      child: ElevatedButton(
                        onPressed: _saveData,
                        child: Text(
                          'Enregistrer',
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
