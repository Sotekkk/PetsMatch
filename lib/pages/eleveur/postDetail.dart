import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/utils.dart';
import 'package:carousel_slider/carousel_slider.dart';

class PostDetailPage extends StatefulWidget {
  final Map<String, dynamic> post;

  PostDetailPage({required this.post});

  @override
  _PostDetailPageState createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  TextEditingController _descriptionController = TextEditingController();
  TextEditingController _titleController = TextEditingController();
  bool _isEditingDescription = false;
  bool _isEditingTitle = false;
  bool _isExpanded = false;
  String? nameElevage;
  String? profilePictureUrlElevage;
  bool isOwner = false;

  @override
  void initState() {
    super.initState();
    _descriptionController.text = widget.post['desc'] ?? '';
    _titleController.text =
        widget.post['title'] ?? 'Aucun titre à la publication';
    _checkOwnership();
    _fetchElevageInfo();
  }

  Future<void> _checkOwnership() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid == widget.post['uidEleveur']) {
      setState(() {
        isOwner = true;
      });
    }
  }

  Future<void> _fetchElevageInfo() async {
    final uidEleveur = widget.post['uidEleveur'];
    if (uidEleveur != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uidEleveur)
          .get();
      if (doc.exists) {
        setState(() {
          nameElevage = doc.data()?['nameElevage'];
          profilePictureUrlElevage = doc.data()?['profilePictureUrlElevage'];
        });
      }
    }
  }

  Future<void> _updatePost() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid == widget.post['uidEleveur']) {
      await FirebaseFirestore.instance
          .collection('post')
          .doc(widget.post['id'])
          .update({
        'desc': _descriptionController.text,
        'title': _titleController.text,
      });
    } else {
      print('Vous ne pouvez pas modifier ce post.');
    }
  }

  String buildAnimalDetails() {
    String animalType = widget.post['isCat'] == true
        ? "Chat"
        : widget.post['isDog'] == true
            ? "Chien"
            : "Aucune information enregistrée";

    String race = widget.post['tag'] != null && widget.post['tag'].isNotEmpty
        ? widget.post['tag'][0]
        : "Aucune information enregistrée";

    String ageCategory;
    if (widget.post['isAdult'] == true) {
      ageCategory = "Adulte";
    } else if (widget.post['moreEightWeeks'] == true) {
      ageCategory = "+ de 8 semaines";
    } else if (widget.post['isAdult'] == false &&
        widget.post['moreEightWeeks'] == false) {
      ageCategory = "- de 8 semaines";
    } else {
      ageCategory = "Aucune information enregistrée";
    }

    String dateOfBirth =
        widget.post['dateOfBirth'] ?? "Aucune information enregistrée";

    String typeVente;
    if (widget.post['isRetraite'] == true) {
      typeVente = "Retraite";
    } else if (widget.post['isSailli'] == true) {
      typeVente = "Saillie";
    } else if (widget.post['isSell'] == true) {
      typeVente = "Vente";
    } else {
      typeVente = "Aucune information enregistrée";
    }

    String vaccinationStatus =
        widget.post['isVaccined'] == true ? "Vacciné" : "Non vacciné";

    String lofLoofStatus;
    if (widget.post['isCat'] == true) {
      lofLoofStatus = widget.post['isLoof'] == true ? "Loof" : "Non Loof";
    } else if (widget.post['isDog'] == true) {
      lofLoofStatus = widget.post['isLof'] == true ? "Lof" : "Non Lof";
    } else {
      lofLoofStatus = "Aucune information enregistrée";
    }

// Généalogie club de race
    if (widget.post['hasGenealogie'] == true) {
      String genealogieText = widget.post['genealogieText'] ?? '';
      if (genealogieText.trim().isNotEmpty) {
        lofLoofStatus += "\nGénéalogie club de race : ${genealogieText.trim()}";
      } else {
        lofLoofStatus += "\nGénéalogie club de race : Oui";
      }
    }

    String puceNumber;
    if (widget.post['isAdult'] == false &&
        widget.post['moreEightWeeks'] == false) {
      puceNumber =
          "Puce de la mère: ${widget.post['puceMotherNumber'] ?? "Aucune information enregistrée"}";
    } else {
      puceNumber =
          "Puce de l'animal: ${widget.post['puceNumber'] ?? "Aucune information enregistrée"}";
    }

    String price = widget.post['price'] != null &&
            widget.post['price'].toString().isNotEmpty
        ? "${widget.post['price']} €"
        : "Aucun prix ajouté";

    return "Type d'animal : $animalType\n"
        "Prix : $price\n"
        "Race : $race\n"
        "Âge : $ageCategory\n"
        "Date de naissance : $dateOfBirth\n"
        "Type de vente : $typeVente\n"
        "Vaccination : $vaccinationStatus\n"
        "Statut : $lofLoofStatus\n"
        "$puceNumber";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: CarouselSlider.builder(
              itemCount: widget.post['mediaStockage'].length,
              itemBuilder: (context, index, realIndex) {
                return Container(
                  color: Colors.black,
                  child: Center(
                    child: Image.network(
                      widget.post['mediaStockage'][index]['path'],
                      fit: BoxFit.contain,
                      width: double.infinity,
                    ),
                  ),
                );
              },
              options: CarouselOptions(
                height: double.infinity,
                viewportFraction: 1.0,
                enableInfiniteScroll: false,
              ),
            ),
          ),
          Positioned(
            top: 40,
            left: 10,
            child: IconButton(
              icon: Icon(Icons.close, color: Colors.red, size: 30),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ),
          Positioned(
            bottom: 0, // Commence à partir du bas de l'écran
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.8), // Noir en bas
                    Colors.transparent, // Transparent en haut
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section du titre de la publication
                  Row(
                    children: [
                      Expanded(
                        child: isOwner
                            ? TextField(
                                controller: _titleController,
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: UTILS.calculHeight(
                                        18, UTILS.heightReference(context))),
                                decoration: InputDecoration(
                                  hintText: 'Titre de la publication',
                                  hintStyle: TextStyle(color: Colors.white),
                                  border: _isEditingTitle
                                      ? OutlineInputBorder()
                                      : InputBorder
                                          .none, // Afficher les contours uniquement en mode édition
                                ),
                                maxLines: 1,
                              )
                            : GestureDetector(
                                onLongPress: isOwner
                                    ? () {
                                        setState(() {
                                          _isEditingTitle = true;
                                        });
                                      }
                                    : null,
                                child: Text(
                                  _titleController.text,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: UTILS.calculHeight(
                                        18, UTILS.heightReference(context)),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                      ),
                      if (isOwner)
                        IconButton(
                          icon: Icon(Icons.edit, color: Colors.white),
                          onPressed: () {
                            setState(() {
                              _isEditingTitle = true;
                            });
                          },
                        ),
                    ],
                  ),
                  SizedBox(
                      height: UTILS.calculHeight(
                          10, UTILS.heightReference(context))),

                  // Section de l'éleveur
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.black,
                        backgroundImage: (profilePictureUrlElevage != null &&
                                profilePictureUrlElevage !=
                                    'https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60')
                            ? NetworkImage(profilePictureUrlElevage!)
                            : AssetImage('assets/logo/default_pp.png')
                                as ImageProvider,
                      ),
                      SizedBox(
                          width: UTILS.calculWidth(
                              10, UTILS.widthReference(context))),
                      Text(
                        nameElevage ?? 'Nom de l\'élevage',
                        style: TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w500,
                          fontSize: UTILS.calculHeight(
                              18, UTILS.heightReference(context)),
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                      height: UTILS.calculHeight(
                          10, UTILS.heightReference(context))),

                  // Bouton En savoir plus
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isExpanded = !_isExpanded;
                      });
                    },
                    child: Text(
                      _isExpanded ? 'Réduire...' : 'En savoir plus...',
                      style: TextStyle(
                        color: Color(0xFF6E9E57),
                        fontSize: UTILS.calculWidth(
                            14, UTILS.widthReference(context)),
                      ),
                    ),
                  ),

                  // Détails supplémentaires
                  if (_isExpanded)
                    Container(
                      constraints: BoxConstraints(
                        maxHeight: UTILS.calculHeight(
                            450, UTILS.heightReference(context)),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal:
                            UTILS.calculWidth(4, UTILS.widthReference(context)),
                        vertical: UTILS.calculHeight(
                            8, UTILS.heightReference(context)),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              buildAnimalDetails(),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: UTILS.calculWidth(
                                    16, UTILS.widthReference(context)),
                              ),
                            ),
                            SizedBox(
                                height: UTILS.calculHeight(
                                    10, UTILS.heightReference(context))),
                            Row(
                              children: [
                                Expanded(
                                  child: isOwner
                                      ? TextField(
                                          controller: _descriptionController,
                                          style: TextStyle(color: Colors.white),
                                          decoration: InputDecoration(
                                            hintText: 'Description',
                                            hintStyle:
                                                TextStyle(color: Colors.white),
                                            border: _isEditingDescription
                                                ? OutlineInputBorder()
                                                : InputBorder.none,
                                          ),
                                          maxLines: null,
                                        )
                                      : GestureDetector(
                                          onLongPress: isOwner
                                              ? () {
                                                  setState(() {
                                                    _isEditingDescription =
                                                        true;
                                                  });
                                                }
                                              : null,
                                          child: Text(
                                            _descriptionController.text,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: UTILS.calculWidth(
                                                  16,
                                                  UTILS
                                                      .widthReference(context)),
                                            ),
                                          ),
                                        ),
                                ),
                                if (isOwner)
                                  IconButton(
                                    icon: Icon(Icons.edit, color: Colors.white),
                                    onPressed: () {
                                      setState(() {
                                        _isEditingDescription = true;
                                      });
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Bouton d'enregistrement
                  if ((_isEditingDescription || _isEditingTitle) && isOwner)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            Colors.black, // Couleur de fond du bouton
                      ),
                      onPressed: () {
                        setState(() {
                          _isEditingDescription = false;
                          _isEditingTitle = false;
                        });
                        _updatePost();
                      },
                      child: Text('Enregistrer'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
