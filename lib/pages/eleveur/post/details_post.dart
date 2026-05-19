import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:PetsMatch/main.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:PetsMatch/pages/eleveur/choice_publication.dart';
import 'package:PetsMatch/pages/eleveur/post/boost.dart';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DetailsPostCreation extends StatefulWidget {
  const DetailsPostCreation({super.key});

  @override
  State<DetailsPostCreation> createState() => _DetailsPostCreationState();
}

class _DetailsPostCreationState extends State<DetailsPostCreation> {
  List<String> _tags = [];
  final List<String> _addedTags = [];
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController titleController = TextEditingController();
  TextEditingController puceController = TextEditingController();
  TextEditingController controllerDateNaissanceCat = TextEditingController();
  TextEditingController numberPorter = TextEditingController();
  final TextEditingController priceController = TextEditingController();

  List<String> _suggestedTags = [];
  List<Map<String, String>> _animals = [];
  String? _selectedAnimal;
  bool _isDogSelected = true;
  bool _isCatSelected = false;
  bool _isMoreThanEightWeeks = false;
  bool _isAdult = false;
  bool _isMale = true;
  bool _isSell = true;
  bool _isSailli = false;
  bool _isRetraite = false;
  bool _isLoof = true;
  bool _isLof = false;
  bool _hasGenealogie = false;
  TextEditingController _genealogieController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchData();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final String response = await rootBundle.loadString('assets/tags.json');
    final List<dynamic> data = json.decode(response);
    setState(() {
      _tags = List<String>.from(data);
    });
  }

  void _fetchData() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      List<Map<String, String>> animals = [];
      String collection = _isDogSelected ? 'dogfiche' : 'catfiche';
      QuerySnapshot snapshot;

      if (_isAdult || _isMoreThanEightWeeks) {
        snapshot = await FirebaseFirestore.instance
            .collection(collection)
            .doc(userId)
            .collection("entries")
            .where('sex', isEqualTo: _isMale ? 'Mâle' : 'Femelle')
            .get();
      } else {
        snapshot = await FirebaseFirestore.instance
            .collection(collection)
            .doc(userId)
            .collection("entries")
            .where('sex', isEqualTo: 'Femelle')
            .get();
      }

      for (var doc in snapshot.docs) {
        animals.add({'name': doc['name'], 'chipNumber': doc['chipNumber']});
      }

      setState(() {
        _animals = animals;
        _selectedAnimal = null; // Reset the selected animal when data changes
        puceController.text = ""; // Clear the text in the TextEditingController
      });
    }
  }

  bool _isFormValid() {
    return _descriptionController.text.isNotEmpty &&
        priceController.text.isNotEmpty;
  }

  void _updateNewPostClass() {
    NewPostClass.desc = _descriptionController.text;
    NewPostClass.tags = _addedTags.map((tag) => {'tag': tag}).toList();
    NewPostClass.isDog = _isDogSelected;
    NewPostClass.isCat = _isCatSelected;
    NewPostClass.moreEightWeeks = _isMoreThanEightWeeks;
    NewPostClass.isAdult = _isAdult;
    NewPostClass.isMale = _isMale;
    NewPostClass.isSell = _isSell;
    NewPostClass.isSailli = _isSailli;
    NewPostClass.isRetraite = _isRetraite;
    NewPostClass.isLoof = _isLoof;
    NewPostClass.isLof = _isLof;
    NewPostClass.title = titleController.text;
    NewPostClass.dateOfBirth = controllerDateNaissanceCat.text;
    NewPostClass.puceNumber = puceController.text;
    NewPostClass.numberPorter = numberPorter.text;
    NewPostClass.price = priceController.text;
    NewPostClass.hasGenealogie = _hasGenealogie;
    NewPostClass.genealogieText = _genealogieController.text.trim();

    NewPostClass.isPro = User_Info.isPro;
  }

  void _onAnimalSelected(String? selectedValue) {
    setState(() {
      _selectedAnimal = selectedValue;
      if (_selectedAnimal != null && _selectedAnimal != 'Autre') {
        final selectedChipNumber = _animals.firstWhere(
            (animal) => animal['chipNumber'] == _selectedAnimal)['chipNumber'];
        puceController.text = selectedChipNumber ?? '';
      } else {
        puceController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color.fromARGB(255, 255, 241, 227),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Center(
          child: Text(
            'DETAILS DU POST',
            style: TextStyle(
              fontFamily: 'Galey',
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (_isFormValid()) {
                _updateNewPostClass();
                Future.microtask(() {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => BoostAdPage()),
                  );
                });
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _descriptionController.text.isEmpty
                          ? 'Veuillez mettre une description'
                          : 'Veuillez indiquer un prix',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text(
              'Suivant',
              style: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w500,
                color: Color.fromARGB(255, 250, 192, 187),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(
                width: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    UTILS.calculWidth(8.0, UTILS.widthReference(context)),
                  ),
                  child: Container(
                    height:
                        UTILS.calculHeight(249, UTILS.heightReference(context)),
                    color: Colors.grey[300],
                    child: _buildMediaSlider(),
                  ),
                ),
              ),
              SizedBox(
                  height:
                      UTILS.calculHeight(23, UTILS.heightReference(context))),
              SizedBox(
                width: UTILS.calculWidth(355, UTILS.widthReference(context)),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        UTILS.calculHeight(200, UTILS.heightReference(context)),
                  ),
                  child: Scrollbar(
                    child: TextField(
                      controller: _descriptionController,
                      keyboardType: TextInputType.multiline,
                      maxLines: null,
                      style: TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        labelText: "Description de l'animal",
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Color.fromARGB(255, 250, 192, 187),
                            width: 2.0,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.black,
                            width: 2.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (User_Info.isElevage) SizedBox(height: 30),
              if (User_Info.isElevage)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Titre',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontFamily: 'Galey',
                        color: Color.fromARGB(193, 30, 30, 30),
                        fontWeight: FontWeight.w500,
                        fontSize: UTILS.calculWidth(
                            20, UTILS.widthReference(context)),
                      )),
                ),
              if (User_Info.isElevage)
                SizedBox(
                    width:
                        UTILS.calculWidth(355, UTILS.widthReference(context)),
                    child: TextField(
                      controller: titleController,
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                        labelText: 'Titre de la publication',
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: Color.fromARGB(255, 250, 192, 187)),
                        ),
                      ),
                    )),
              if (User_Info.isElevage) SizedBox(height: 30),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Prix (€)',
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      fontFamily: 'Galey',
                      color: Color.fromARGB(193, 30, 30, 30),
                      fontWeight: FontWeight.w500,
                      fontSize:
                          UTILS.calculWidth(20, UTILS.widthReference(context)),
                    )),
              ),
              SizedBox(
                width: UTILS.calculWidth(355, UTILS.widthReference(context)),
                child: TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Prix de l\'animal en €',
                    enabledBorder: UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: Color.fromARGB(255, 250, 192, 187)),
                    ),
                  ),
                ),
              ),
              if (User_Info.isElevage) SizedBox(height: 30),
              if (User_Info.isElevage)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Sélectionnez l\'animal',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontFamily: 'Galey',
                        color: Color.fromARGB(193, 30, 30, 30),
                        fontWeight: FontWeight.w500,
                        fontSize: UTILS.calculWidth(
                            20, UTILS.widthReference(context)),
                      )),
                ),
              if (User_Info.isElevage)
                Row(
                  children: [
                    Checkbox(
                      value: _isDogSelected,
                      onChanged: (value) {
                        setState(() {
                          _isDogSelected = value!;
                          _isCatSelected = !value;
                          _fetchData();
                        });
                      },
                      activeColor: Color.fromARGB(255, 250, 192, 187),
                    ),
                    Text('Chien'),
                    Checkbox(
                      value: _isCatSelected,
                      onChanged: (value) {
                        setState(() {
                          _isCatSelected = value!;
                          _isDogSelected = !value;
                          _fetchData();
                        });
                      },
                      activeColor: Color.fromARGB(255, 250, 192, 187),
                    ),
                    Text('Chat'),
                  ],
                ),
              if (User_Info.isElevage) SizedBox(height: 30),
              if (User_Info.isElevage)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Âge de l\'animal',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontFamily: 'Galey',
                        color: Color.fromARGB(193, 30, 30, 30),
                        fontWeight: FontWeight.w500,
                        fontSize: UTILS.calculWidth(
                            20, UTILS.widthReference(context)),
                      )),
                ),
              if (User_Info.isElevage)
                CheckboxListTile(
                  activeColor: Color.fromARGB(255, 250, 192, 187),
                  title: Text("+ 8 semaines"),
                  value: _isMoreThanEightWeeks,
                  onChanged: (value) {
                    setState(() {
                      _isMoreThanEightWeeks = value!;
                      _isAdult = false;
                      _fetchData();
                    });
                  },
                ),
              if (User_Info.isElevage)
                CheckboxListTile(
                  activeColor: Color.fromARGB(255, 250, 192, 187),
                  title: Text("- 8 semaines"),
                  value: !_isMoreThanEightWeeks && !_isAdult,
                  onChanged: (value) {
                    setState(() {
                      _isMoreThanEightWeeks = false;
                      _isAdult = !value!;
                      _fetchData();
                    });
                  },
                ),
              if (User_Info.isElevage)
                CheckboxListTile(
                  activeColor: Color.fromARGB(255, 250, 192, 187),
                  title: Text("Adulte"),
                  value: _isAdult,
                  onChanged: (value) {
                    setState(() {
                      _isAdult = value!;
                      _isMoreThanEightWeeks = false;
                      _fetchData();
                    });
                  },
                ),
              if (User_Info.isElevage) SizedBox(height: 30),
              if (User_Info.isElevage)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Date de naissance',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontFamily: 'Galey',
                        color: Color.fromARGB(193, 30, 30, 30),
                        fontWeight: FontWeight.w500,
                        fontSize: UTILS.calculWidth(
                            20, UTILS.widthReference(context)),
                      )),
                ),
              if (User_Info.isElevage)
                SizedBox(
                    width:
                        UTILS.calculWidth(355, UTILS.widthReference(context)),
                    child: TextFormField(
                      controller: controllerDateNaissanceCat,
                      decoration: InputDecoration(
                        labelText: 'Date de naissance de l\'animal',
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
                        FocusScope.of(context)
                            .requestFocus(FocusNode()); // Prevent keyboard
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
                            controllerDateNaissanceCat.text = formattedDate;
                          });
                        }
                      },
                    )),
              if (User_Info.isElevage) SizedBox(height: 30),
              if (User_Info.isElevage)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Type de publication',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontFamily: 'Galey',
                        color: Color.fromARGB(193, 30, 30, 30),
                        fontWeight: FontWeight.w500,
                        fontSize: UTILS.calculWidth(
                            20, UTILS.widthReference(context)),
                      )),
                ),
              if (User_Info.isElevage)
                Row(
                  children: [
                    Checkbox(
                      value: _isSell,
                      onChanged: (value) {
                        setState(() {
                          _isSell = value!;
                          _isSailli = !value;
                          _isRetraite = !value;
                        });
                      },
                      activeColor: Color.fromARGB(255, 250, 192, 187),
                    ),
                    Text('Vente'),
                    Checkbox(
                      value: _isSailli,
                      onChanged: (value) {
                        setState(() {
                          _isSell = !value!;
                          _isSailli = value;
                          _isRetraite = !value;
                        });
                      },
                      activeColor: Color.fromARGB(255, 250, 192, 187),
                    ),
                    Text('Saillie'),
                    Checkbox(
                      value: _isRetraite,
                      onChanged: (value) {
                        setState(() {
                          _isSell = !value!;
                          _isSailli = !value;
                          _isRetraite = value;
                        });
                      },
                      activeColor: Color.fromARGB(255, 250, 192, 187),
                    ),
                    Text('Retraite'),
                  ],
                ),
              if (User_Info.isElevage) SizedBox(height: 30),
              if (User_Info.isElevage)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Certification',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontFamily: 'Galey',
                        color: Color.fromARGB(193, 30, 30, 30),
                        fontWeight: FontWeight.w500,
                        fontSize: UTILS.calculWidth(
                            20, UTILS.widthReference(context)),
                      )),
                ),
              if (User_Info.isElevage)
                if (User_Info.isElevage)
                  Row(
                    children: [
                      Checkbox(
                        value: _isDogSelected ? _isLof : _isLoof,
                        onChanged: (value) {
                          setState(() {
                            if (_isDogSelected) {
                              _isLof = value!;
                            } else {
                              _isLoof = value!;
                            }
                          });
                        },
                        activeColor: Color.fromARGB(255, 250, 192, 187),
                      ),
                      Text(_isDogSelected ? 'LOF' : 'LOOF'),
                      Checkbox(
                        value: _isDogSelected ? !_isLof : !_isLoof,
                        onChanged: (value) {
                          setState(() {
                            if (_isDogSelected) {
                              _isLof = !value!;
                            } else {
                              _isLoof = !value!;
                            }
                          });
                        },
                        activeColor: Color.fromARGB(255, 250, 192, 187),
                      ),
                      Text(_isDogSelected ? 'Non LOF' : 'Non LOOF'),
                    ],
                  ),
              if (User_Info.isElevage)
                CheckboxListTile(
                  value: _hasGenealogie,
                  onChanged: (value) {
                    setState(() {
                      _hasGenealogie = value ?? false;
                    });
                  },
                  title: Text("Généalogie club de race",
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w500,
                          fontSize: UTILS.calculWidth(
                              16, UTILS.widthReference(context)))),
                  activeColor: Color.fromARGB(255, 250, 192, 187),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              if (_hasGenealogie)
                SizedBox(
                  width: UTILS.calculWidth(355, UTILS.widthReference(context)),
                  child: TextField(
                    controller: _genealogieController,
                    maxLines: null,
                    decoration: InputDecoration(
                      labelText: "Détails sur la généalogie",
                      border: OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: Color.fromARGB(255, 250, 192, 187),
                        ),
                      ),
                    ),
                  ),
                ),
              if (User_Info.isElevage) SizedBox(height: 30),
              if (User_Info.isElevage)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Sexe de l\'animal',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontFamily: 'Galey',
                        color: Color.fromARGB(193, 30, 30, 30),
                        fontWeight: FontWeight.w500,
                        fontSize: UTILS.calculWidth(
                            20, UTILS.widthReference(context)),
                      )),
                ),
              if (User_Info.isElevage)
                Row(
                  children: [
                    Checkbox(
                      value: _isMale,
                      onChanged: (value) {
                        setState(() {
                          _isMale = value!;
                          _fetchData();
                        });
                      },
                      activeColor: Color.fromARGB(255, 250, 192, 187),
                    ),
                    Text('Mâle'),
                    Checkbox(
                      value: !_isMale,
                      onChanged: (value) {
                        setState(() {
                          _isMale = !value!;
                          _fetchData();
                        });
                      },
                      activeColor: Color.fromARGB(255, 250, 192, 187),
                    ),
                    Text('Femelle'),
                  ],
                ),
              if (User_Info.isElevage) SizedBox(height: 30),
              if (User_Info.isElevage)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      "Numéro de puce de ${_isMoreThanEightWeeks || _isAdult ? "l\'animal" : "la mère"}",
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontFamily: 'Galey',
                        color: Color.fromARGB(193, 30, 30, 30),
                        fontWeight: FontWeight.w500,
                        fontSize: UTILS.calculWidth(
                            20, UTILS.widthReference(context)),
                      )),
                ),
              if (User_Info.isElevage)
                SizedBox(
                    width:
                        UTILS.calculWidth(355, UTILS.widthReference(context)),
                    child: TextField(
                      controller: puceController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Numéro de puce',
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: Color.fromARGB(255, 250, 192, 187)),
                        ),
                      ),
                    )),
              if (User_Info.isElevage) SizedBox(height: 30),
              if (User_Info.isElevage)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      'Sélectionnez ${_isMoreThanEightWeeks || _isAdult ? "l\'animal" : "la mère"}',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontFamily: 'Galey',
                        color: Color.fromARGB(193, 30, 30, 30),
                        fontWeight: FontWeight.w500,
                        fontSize: UTILS.calculWidth(
                            20, UTILS.widthReference(context)),
                      )),
                ),
              if (User_Info.isElevage)
                SizedBox(
                  width: UTILS.calculWidth(355, UTILS.widthReference(context)),
                  child: DropdownButtonFormField<String>(
                    dropdownColor: Colors.pink[100],
                    value: _selectedAnimal,
                    decoration: InputDecoration(
                      labelText:
                          'Sélectionnez ${_isMoreThanEightWeeks || _isAdult ? "l\'animal" : "la mère"}',
                      border: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Color.fromARGB(255, 250, 192, 187),
                          width: 2.0,
                        ),
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Color.fromARGB(255, 250, 192, 187),
                        ),
                      ),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: 'none', // Unique value for "Autre"
                        child: Text('Autre'),
                      ),
                      ..._animals.map((animal) {
                        return DropdownMenuItem<String>(
                          value: animal['chipNumber']!.isEmpty
                              ? 'no_chip_${animal['name']}'
                              : animal[
                                  'chipNumber'], // Ensure uniqueness by appending the name
                          child: Text(animal['name']!),
                        );
                      }).toList(),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedAnimal = value;
                        if (value == 'none') {
                          puceController.text =
                              ""; // Clear the chip number field
                        } else if (value!.startsWith('no_chip')) {
                          puceController.text = "Aucune puce enregistrée";
                        } else {
                          // Automatically fill in the chip number
                          final selectedAnimal = _animals.firstWhere(
                            (animal) => animal['chipNumber'] == value,
                            orElse: () => {'name': 'Unknown', 'chipNumber': ''},
                          );
                          puceController.text = selectedAnimal['chipNumber']!;
                        }
                      });
                    },
                  ),
                ),
              if (User_Info.isElevage)
                SizedBox(
                    height:
                        UTILS.calculHeight(30, UTILS.heightReference(context))),
              if (User_Info.isElevage)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Nombre d’animaux dans la portée",
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontFamily: 'Galey',
                        color: Color.fromARGB(193, 30, 30, 30),
                        fontWeight: FontWeight.w500,
                        fontSize: UTILS.calculWidth(
                            20, UTILS.widthReference(context)),
                      )),
                ),
              if (User_Info.isElevage)
                SizedBox(
                    width:
                        UTILS.calculWidth(355, UTILS.widthReference(context)),
                    child: TextField(
                      controller: numberPorter,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Nombre d’animaux dans la portée',
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: Color.fromARGB(255, 250, 192, 187)),
                        ),
                      ),
                    )),
              if (User_Info.isElevage)
                SizedBox(
                    height:
                        UTILS.calculHeight(30, UTILS.heightReference(context))),
              if (User_Info.isElevage)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_isDogSelected ? 'Race du chien' : 'Race du chat',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontFamily: 'Galey',
                        color: Color.fromARGB(193, 30, 30, 30),
                        fontWeight: FontWeight.w500,
                        fontSize: UTILS.calculWidth(
                            20, UTILS.widthReference(context)),
                      )),
                ),
              if (User_Info.isElevage)
                SizedBox(
                    width:
                        UTILS.calculWidth(355, UTILS.widthReference(context)),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            decoration: InputDecoration(
                              enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                      color:
                                          Color.fromARGB(255, 250, 192, 187))),
                              labelText: 'Veuillez ajouter une race',
                            ),
                            onChanged: (value) {
                              setState(() {
                                if (value.isEmpty) {
                                  _suggestedTags.clear();
                                } else {
                                  _suggestedTags = _tags
                                      .where((tag) =>
                                          tag
                                              .toLowerCase()
                                              .contains(value.toLowerCase()) &&
                                          !_addedTags.contains(tag))
                                      .toList();
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    )),
              if (User_Info.isElevage)
                if (_suggestedTags.isNotEmpty && _addedTags.length < 8)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 4.0),
                    color: Color.fromARGB(255, 250, 192, 187),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: 150,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _suggestedTags.length,
                        itemBuilder: (context, index) {
                          return Container(
                            color: Color.fromARGB(255, 250, 192,
                                187), // Set the background color here
                            child: ListTile(
                              title: Text(_suggestedTags[index]),
                              onTap: () {
                                if (_addedTags.length < 1) {
                                  setState(() {
                                    _addedTags.add(_suggestedTags[index]);
                                    _controller.clear();
                                    _suggestedTags.clear();
                                  });
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              if (User_Info.isElevage)
                Wrap(
                  spacing: 8.0,
                  children: _addedTags.map((tag) {
                    return Chip(
                      label: Text(tag),
                      backgroundColor: Color.fromARGB(255, 250, 192, 187),
                      deleteIcon: Icon(Icons.close),
                      onDeleted: () {
                        setState(() {
                          _addedTags.remove(tag);
                        });
                      },
                    );
                  }).toList(),
                ),
              if (User_Info.isElevage) SizedBox(height: 30),
              if (User_Info.isElevage)
                Text('${_addedTags.length}/1', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaSlider() {
    if (NewPostClass.mediaStockage.isEmpty) {
      return Image.asset(
        'assets/page/domainenegan.png',
        fit: BoxFit.cover,
      );
    }

    return CarouselSlider(
      options: CarouselOptions(
        height: UTILS.calculHeight(249, UTILS.heightReference(context)),
        enableInfiniteScroll: false,
        viewportFraction: 1.0,
      ),
      items: NewPostClass.mediaStockage.map((media) {
        final isLocalFile = media['path'].startsWith('file://') ||
            !Uri.parse(media['path']).isAbsolute;

        return GestureDetector(
          onTap: () =>
              _previewMedia(context, NewPostClass.mediaStockage.indexOf(media)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              isLocalFile
                  ? Image.file(
                      File(media['path'].replaceFirst(
                          'file://', '')), // Corrige le chemin local
                      fit: BoxFit.cover,
                    )
                  : Image.network(
                      media['path'],
                      fit: BoxFit.cover,
                    ),
              if (!media['isPhoto'])
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Icon(
                    Icons.play_circle_outline,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              Positioned(
                bottom: 8,
                right: 8,
                child: Icon(
                  Icons.fullscreen,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Future<Uint8List?> _loadVideoThumbnail(String videoPath) async {
    final thumbData = await VideoThumbnail.thumbnailData(
      video: videoPath,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 128,
      quality: 25,
    );
    return thumbData;
  }

  void _previewMedia(BuildContext context, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenMedia(
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}

class FullScreenMedia extends StatefulWidget {
  final int initialIndex;

  const FullScreenMedia({required this.initialIndex});

  @override
  _FullScreenMediaState createState() => _FullScreenMediaState();
}

class _FullScreenMediaState extends State<FullScreenMedia> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          CarouselSlider.builder(
            options: CarouselOptions(
              initialPage: widget.initialIndex,
              enableInfiniteScroll: false,
              viewportFraction: 1.0,
              height: double.infinity,
            ),
            itemCount: NewPostClass.mediaStockage.length,
            itemBuilder: (context, index, realIndex) {
              final media = NewPostClass.mediaStockage[index];
              final isLocalFile = media['path'].startsWith('file://') ||
                  !Uri.parse(media['path']).isAbsolute;

              return isLocalFile
                  ? PhotoView(
                      imageProvider: FileImage(
                        File(media['path'].replaceFirst('file://', '')),
                      ),
                    )
                  : PhotoView(
                      imageProvider: NetworkImage(media['path']),
                    );
            },
          ),
          Positioned(
            top: UTILS.calculHeight(30, UTILS.heightReference(context)),
            left: UTILS.calculWidth(10, UTILS.widthReference(context)),
            child: IconButton(
              icon: Icon(
                Icons.close,
                color: Colors.white,
                size: 30,
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
    );
  }
}
