import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';

class FilterPage extends StatefulWidget {
  final bool filterIsDog;
  final bool filterIsCat;
  final bool filterIsPuppy;
  final bool filterIsAdult;
  final bool filterIsSell;
  final bool filterIsSailli;
  final bool filterIsRetraite;
  final bool filterIsLoof;
  final bool filterIsLof;
  final bool filterIsVaccined;
  final bool filterIsMale;
  final bool filterIsFemale;
  final List<String> filterTags;
  final List<String> tags;
  final Function refreshPosts;
  final Function(Map<String, bool>, List<String>) onApplyFilters;

  FilterPage({
    required this.filterIsDog,
    required this.filterIsCat,
    required this.filterIsPuppy,
    required this.filterIsAdult,
    required this.filterIsSell,
    required this.filterIsSailli,
    required this.filterIsRetraite,
    required this.filterIsLoof,
    required this.filterIsLof,
    required this.filterIsVaccined,
    required this.filterIsMale,
    required this.filterIsFemale,
    required this.filterTags,
    required this.tags,
    required this.refreshPosts,
    required this.onApplyFilters,
  });

  @override
  _FilterPageState createState() => _FilterPageState();
}

class _FilterPageState extends State<FilterPage> {
  late bool filterIsDog;
  late bool filterIsCat;
  late bool filterIsPuppy;
  late bool filterIsAdult;
  late bool filterIsSell;
  late bool filterIsSailli;
  late bool filterIsRetraite;
  late bool filterIsLoof;
  late bool filterIsLof;
  late bool filterIsVaccined;
  late bool filterIsMale;
  late bool filterIsFemale;
  late List<String> filterTags;
  final TextEditingController _tagController = TextEditingController();
  List<String> _suggestedTags = [];

  @override
  void initState() {
    super.initState();
    filterIsDog = widget.filterIsDog;
    filterIsCat = widget.filterIsCat;
    filterIsPuppy = widget.filterIsPuppy;
    filterIsAdult = widget.filterIsAdult;
    filterIsSell = widget.filterIsSell;
    filterIsSailli = widget.filterIsSailli;
    filterIsRetraite = widget.filterIsRetraite;
    filterIsLoof = widget.filterIsLoof;
    filterIsLof = widget.filterIsLof;
    filterIsVaccined = widget.filterIsVaccined;
    filterIsMale = widget.filterIsMale;
    filterIsFemale = widget.filterIsFemale;
    filterTags = List<String>.from(widget.filterTags);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      body: SingleChildScrollView(
        child: Container(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
                   SizedBox(
          width: UTILS.widthReference(context),
          height: UTILS.calculHeight(105,
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
                top: UTILS.calculHeight(42, UTILS.heightReference(context)),
                left: UTILS.calculWidth(10, UTILS.widthReference(context)),
                child: IconButton(
                  icon: Icon(Icons.arrow_back,
                      color: Colors.black), // Icône de la flèche noire
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                )),
            Positioned(
              top: UTILS.calculHeight(53, UTILS.heightReference(context)),
              left: 0,
              right:
                  0, // Assurez-vous que left et right sont définis à 0 pour permettre au texte de centrer exactement
              child: Align(
                alignment: Alignment.center,
                child: Text(
                  'FILTRE',
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
              SizedBox(height: 20),
              Align(
                alignment: Alignment.center,
                child: Text(
                  'Type d\'animal',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SwitchListTile(
                title: Text('Chien'),
                value: filterIsDog,
                activeTrackColor: Color(0xFFA7C79A),
                activeColor: Color.fromARGB(255, 255, 255, 255),
                inactiveThumbColor: Color.fromARGB(255, 255, 255, 255),
                inactiveTrackColor: const Color.fromARGB(137, 0, 0, 0),
                onChanged: (bool value) {
                  setState(() {
                    filterIsDog = value;
                  });
                },
              ),
              SwitchListTile(
                title: Text('Chat'),
                value: filterIsCat,
                activeTrackColor: Color(0xFFA7C79A),
                activeColor: Color.fromARGB(255, 255, 255, 255),
                inactiveThumbColor: Color.fromARGB(255, 255, 255, 255),
                inactiveTrackColor: const Color.fromARGB(137, 0, 0, 0),
                onChanged: (bool value) {
                  setState(() {
                    filterIsCat = value;
                  });
                },
              ),
              SizedBox(height: 20),
              Align(
                alignment: Alignment.center,
                child: Text(
                  'Certification',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (filterIsDog || !filterIsCat)
                SwitchListTile(
                  title: Text('LOF'),
                  value: filterIsLof,
                  activeTrackColor: Color(0xFFA7C79A),
                  activeColor: Color.fromARGB(255, 255, 255, 255),
                  inactiveThumbColor: Color.fromARGB(255, 255, 255, 255),
                  inactiveTrackColor: const Color.fromARGB(137, 0, 0, 0),
                  onChanged: (bool value) {
                    setState(() {
                      filterIsLof = value;
                    });
                  },
                ),
              if (filterIsCat || !filterIsDog)
                SwitchListTile(
                  title: Text('LOOF'),
                  value: filterIsLoof,
                  activeTrackColor: Color(0xFFA7C79A),
                  activeColor: Color.fromARGB(255, 255, 255, 255),
                  inactiveThumbColor: Color.fromARGB(255, 255, 255, 255),
                  inactiveTrackColor: const Color.fromARGB(137, 0, 0, 0),
                  onChanged: (bool value) {
                    setState(() {
                      filterIsLoof = value;
                    });
                  },
                ),
              SwitchListTile(
                title: Text('Vacciné'),
                value: filterIsVaccined,
                activeTrackColor: Color(0xFFA7C79A),
                activeColor: Color.fromARGB(255, 255, 255, 255),
                inactiveThumbColor: Color.fromARGB(255, 255, 255, 255),
                inactiveTrackColor: const Color.fromARGB(137, 0, 0, 0),
                onChanged: (bool value) {
                  setState(() {
                    filterIsVaccined = value;
                  });
                },
              ),
              SizedBox(height: 20),
              Align(
                alignment: Alignment.center,
                child: Text(
                  'Âge de l\'animal',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SwitchListTile(
                title: Text('Chiot'),
                value: filterIsPuppy,
                activeTrackColor: Color(0xFFA7C79A),
                activeColor: Color.fromARGB(255, 255, 255, 255),
                inactiveThumbColor: Color.fromARGB(255, 255, 255, 255),
                inactiveTrackColor: const Color.fromARGB(137, 0, 0, 0),
                onChanged: (bool value) {
                  setState(() {
                    filterIsPuppy = value;
                    filterIsAdult = !value;
                  });
                },
              ),
              SwitchListTile(
                title: Text('Adulte'),
                value: filterIsAdult,
                activeTrackColor: Color(0xFFA7C79A),
                activeColor: Color.fromARGB(255, 255, 255, 255),
                inactiveThumbColor: Color.fromARGB(255, 255, 255, 255),
                inactiveTrackColor: const Color.fromARGB(137, 0, 0, 0),
                onChanged: (bool value) {
                  setState(() {
                    filterIsAdult = value;
                    filterIsPuppy = !value;
                  });
                },
              ),
              SizedBox(height: 20),
              Align(
                alignment: Alignment.center,
                child: Text(
                  'Type de publication',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SwitchListTile(
                title: Text('Vente'),
                value: filterIsSell,
                activeTrackColor: Color(0xFFA7C79A),
                activeColor: Color.fromARGB(255, 255, 255, 255),
                inactiveThumbColor: Color.fromARGB(255, 255, 255, 255),
                inactiveTrackColor: const Color.fromARGB(137, 0, 0, 0),
                onChanged: (bool value) {
                  setState(() {
                    filterIsSell = value;
                  });
                },
              ),
              SwitchListTile(
                title: Text('Saillie'),
                value: filterIsSailli,
                activeTrackColor: Color(0xFFA7C79A),
                activeColor: Color.fromARGB(255, 255, 255, 255),
                inactiveThumbColor: Color.fromARGB(255, 255, 255, 255),
                inactiveTrackColor: const Color.fromARGB(137, 0, 0, 0),
                onChanged: (bool value) {
                  setState(() {
                    filterIsSailli = value;
                  });
                },
              ),
              SwitchListTile(
                title: Text('Retraite'),
                value: filterIsRetraite,
                activeTrackColor: Color(0xFFA7C79A),
                activeColor: Color.fromARGB(255, 255, 255, 255),
                inactiveThumbColor: Color.fromARGB(255, 255, 255, 255),
                inactiveTrackColor: const Color.fromARGB(137, 0, 0, 0),
                onChanged: (bool value) {
                  setState(() {
                    filterIsRetraite = value;
                  });
                },
              ),
              SizedBox(height: 20),
              Align(
                alignment: Alignment.center,
                child: Text(
                  'Sexe',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SwitchListTile(
                title: Text('Mâle'),
                value: filterIsMale,
                activeTrackColor: Color(0xFFA7C79A),
                activeColor: Color.fromARGB(255, 255, 255, 255),
                inactiveThumbColor: Color.fromARGB(255, 255, 255, 255),
                inactiveTrackColor: const Color.fromARGB(137, 0, 0, 0),
                onChanged: (bool value) {
                  setState(() {
                    filterIsMale = value;
                  });
                },
              ),
              SwitchListTile(
                title: Text('Femelle'),
                value: filterIsFemale,
                activeTrackColor: Color(0xFFA7C79A),
                activeColor: Color.fromARGB(255, 255, 255, 255),
                inactiveThumbColor: Color.fromARGB(255, 255, 255, 255),
                inactiveTrackColor: const Color.fromARGB(137, 0, 0, 0),
                onChanged: (bool value) {
                  setState(() {
                    filterIsFemale = value;
                  });
                },
              ),
              SizedBox(height: 20),
              Text(
                'Tags',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
               SizedBox(
                width: UTILS.calculWidth(
                    355, UTILS.widthReference(context)),
                      child: TextField(
                controller: _tagController,
                decoration: InputDecoration(
                  labelText: 'Rechercher une race',
                ),
                onChanged: (value) {
                  setState(() {
                    _suggestedTags = widget.tags
                        .where((tag) =>
                            tag.toLowerCase().contains(value.toLowerCase()))
                        .toList();
                  });
                },
              )),
              if (_suggestedTags.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 4.0),
                  color: Color(0xFFA7C79A),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: 150,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _suggestedTags.length,
                      itemBuilder: (context, index) {
                        return Container(
                          color: Color(0xFFA7C79A),
                          child: ListTile(
                            title: Text(_suggestedTags[index]),
                            onTap: () {
                              setState(() {
                                if (!filterTags
                                    .contains(_suggestedTags[index])) {
                                  filterTags.add(_suggestedTags[index]);
                                }
                                _tagController.clear();
                                _suggestedTags.clear();
                              });
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ),
              Wrap(
                spacing: 8.0,
                children: filterTags.map((tag) {
                  return Chip(
                    label: Text(tag),
                    backgroundColor: Color(0xFFA7C79A),
                    deleteIcon: Icon(Icons.close),
                    onDeleted: () {
                      setState(() {
                        filterTags.remove(tag);
                      });
                    },
                  );
                }).toList(),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color.fromARGB(
                      255, 255, 192, 187), // Couleur de fond du bouton
                ),
                onPressed: () {
                  widget.onApplyFilters(
                    {
                      'filterIsDog': filterIsDog,
                      'filterIsCat': filterIsCat,
                      'filterIsPuppy': filterIsPuppy,
                      'filterIsAdult': filterIsAdult,
                      'filterIsSell': filterIsSell,
                      'filterIsSailli': filterIsSailli,
                      'filterIsRetraite': filterIsRetraite,
                      'filterIsLoof': filterIsLoof,
                      'filterIsLof': filterIsLof,
                      'filterIsVaccined': filterIsVaccined,
                      'filterIsMale': filterIsMale,
                      'filterIsFemale': filterIsFemale,
                    },
                    filterTags,
                  );
                  Navigator.pop(context);
                  widget.refreshPosts();
                },
                child: Text('Appliquer les filtres'),
              ),
              SizedBox(height: 5),
              TextButton(
                onPressed: () {
                  widget.onApplyFilters(
                    {
                      'filterIsDog': false,
                      'filterIsCat': false,
                      'filterIsPuppy': false,
                      'filterIsAdult': false,
                      'filterIsSell': false,
                      'filterIsSailli': false,
                      'filterIsRetraite': false,
                      'filterIsLoof': false,
                      'filterIsLof': false,
                      'filterIsVaccined': false,
                      'filterIsMale': false,
                      'filterIsFemale': false,
                    },
                    filterTags = [],
                  );
                  Navigator.pop(context);
                  widget.refreshPosts();
                },
                child: Text('Réinitialiser les filtres'),
              ),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
