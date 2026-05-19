// ignore_for_file: prefer_const_constructors

import 'package:PetsMatch/animation/delayed_animation.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/document_elevage.dart';
import 'package:PetsMatch/pages/particulier/numberadressregistration.dart';

import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:flutter/services.dart';
import 'dart:io';

class RegisterElevageInformation extends StatefulWidget {
  const RegisterElevageInformation({super.key});

  @override
  State<RegisterElevageInformation> createState() =>
      _RegisterElevageInformationState();
}

class _RegisterElevageInformationState extends State<RegisterElevageInformation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  TextEditingController controllerNom = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  bool _isImagePickerActive = false;
  String? imageName = "zizi";
  late String imagePath;

  Future<void> _pickImage() async {
    if (_isImagePickerActive) {
      return;
    }

    try {
      setState(() {
        _isImagePickerActive = true;
      });

      final XFile? pickedFile =
          await _picker.pickImage(source: ImageSource.gallery);

      setState(() {
        _imageFile = pickedFile != null ? File(pickedFile.path) : _imageFile;
        imageName = pickedFile?.name;
        _isImagePickerActive = false;
      });
    } catch (e) {
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
    final path = 'files/$imageName';
    final file = _imageFile;

    final ref = FirebaseStorage.instance.ref().child(path);
    var uploadTask = ref.putFile(file!);

    final snapshot = await uploadTask;

    final urlDownload = await snapshot.ref.getDownloadURL();
    User_Info.profilePictureUrlElevage = urlDownload;
  }

  final TextEditingController _phoneController = TextEditingController();
  String _selectedCountryCode = '+33';

  late List<Country> countries = [];
  Country? selectedCountry;

  bool _isNomElevageValid = true;
  bool _isPhoneElevageValid = true;
  bool _isAddressElevageValid = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);

    loadCountries().then((list) {
      setState(() {
        countries = list;
        selectedCountry = countries[0];
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validateAndContinue() {
    setState(() {
      _isNomElevageValid = controllerNom.text.trim().isNotEmpty;
      _isPhoneElevageValid = _phoneController.text.trim().isNotEmpty;
      _isAddressElevageValid = User_Info.adressElevage.trim().isNotEmpty;
    });

    if (_isNomElevageValid && _isPhoneElevageValid && _isAddressElevageValid) {
      User_Info.numeroElevage = _phoneController.text;
      User_Info.nameElevage = controllerNom.text;

      User_Info.codeISOElevage = _selectedCountryCode;
      try {
        uploadFIle();
      } catch (e) {
        print('Erreur lors de l\'upload: $e');
      }
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => RegisterDocumentElevage()),
      );
    } else {
      print("pas possible");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: SingleChildScrollView(
            reverse: true,
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
                      if (User_Info.isElevage)
                        Align(
                          alignment: Alignment(-0.8, 0),
                          child: Text(
                            'Information élevage',
                            style: TextStyle(
                                fontSize: UTILS.calculWidth(
                                    30, UTILS.widthReference(context)),
                                fontFamily: 'Galey',
                                color: const Color.fromARGB(174, 0, 0, 0),
                                fontWeight: FontWeight.w500),
                            textAlign: TextAlign.left,
                          ),
                        ),
                      if (User_Info.isPro)
                        Align(
                          alignment: Alignment(-0.8, 0),
                          child: Text(
                            'Information professionnel',
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
                              'Veuillez entrer vos informations',
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
                          child: Image.asset('assets/page/info_elevage.png')),
                      SizedBox(
                          height: UTILS.calculHeight(
                              9, UTILS.heightReference(context))),
                      SizedBox(
                        height: UTILS.calculHeight(
                            110, UTILS.heightReference(context)),
                        width: UTILS.calculWidth(
                            376, UTILS.widthReference(context)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: _pickImage,
                                  child: Stack(
                                    alignment: Alignment.bottomRight,
                                    children: [
                                      SizedBox(
                                        height: UTILS.calculHeight(
                                            80, UTILS.heightReference(context)),
                                        width: UTILS.calculWidth(
                                            80, UTILS.widthReference(context)),
                                      ),
                                      CircleAvatar(
                                        radius: UTILS.calculWidth(33.5,
                                            UTILS.widthReference(context)),
                                        backgroundColor: Colors.transparent,
                                        backgroundImage: _imageFile != null
                                            ? FileImage(_imageFile!)
                                                as ImageProvider
                                            : NetworkImage(
                                                'https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60'),
                                      ),
                                      if (_imageFile == null)
                                        Positioned(
                                          right: 0,
                                          bottom: 0,
                                          child: GestureDetector(
                                            onTap: () {},
                                            child: CircleAvatar(
                                              radius: UTILS.calculWidth(
                                                  12,
                                                  UTILS
                                                      .widthReference(context)),
                                              backgroundColor:
                                                  const Color.fromARGB(
                                                      255, 255, 178, 173),
                                              child: Icon(Icons.edit,
                                                  size: UTILS.calculWidth(
                                                      18,
                                                      UTILS.widthReference(
                                                          context)),
                                                  color: Colors.black),
                                            ),
                                          ),
                                        ),
                                      if (_imageFile != null)
                                        Positioned(
                                          right: 0,
                                          bottom: 0,
                                          child: GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                _imageFile = null;
                                              });
                                            },
                                            child: CircleAvatar(
                                              radius: UTILS.calculWidth(
                                                  12,
                                                  UTILS
                                                      .widthReference(context)),
                                              backgroundColor:
                                                  const Color.fromARGB(
                                                      255, 255, 178, 173),
                                              child: Icon(Icons.close,
                                                  size: UTILS.calculWidth(
                                                      18,
                                                      UTILS.widthReference(
                                                          context)),
                                                  color: Colors.black),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  height: UTILS.calculHeight(
                                      13, UTILS.heightReference(context)),
                                ),
                              ],
                            ),
                            SizedBox(
                                width: UTILS.calculWidth(
                                    26, UTILS.widthReference(context))),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                      height: UTILS.calculHeight(
                                          20, UTILS.heightReference(context))),
                                  if (User_Info.isElevage)
                                    SizedBox(
                                      height: UTILS.calculHeight(
                                          53, UTILS.heightReference(context)),
                                      width: UTILS.calculWidth(
                                          268, UTILS.widthReference(context)),
                                      child: TextFormField(
                                        controller: controllerNom,
                                        cursorColor: Colors.black,
                                        decoration: InputDecoration(
                                          labelText: 'Nom élevage',
                                          filled: true,
                                          contentPadding: EdgeInsets.symmetric(
                                              vertical: UTILS.calculHeight(
                                                  12.0,
                                                  UTILS.heightReference(
                                                      context)),
                                              horizontal: UTILS.calculWidth(
                                                  15.0,
                                                  UTILS.widthReference(
                                                      context))),
                                          fillColor: Color.fromARGB(
                                              255, 250, 192, 187),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                                UTILS.calculWidth(
                                                    50.0,
                                                    UTILS.widthReference(
                                                        context))),
                                            borderSide: BorderSide(
                                                color: Colors.transparent),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                                UTILS.calculWidth(
                                                    30.0,
                                                    UTILS.widthReference(
                                                        context))),
                                            borderSide: BorderSide(
                                                color: _isNomElevageValid
                                                    ? Colors.transparent
                                                    : Colors.red,
                                                width: UTILS.calculWidth(
                                                    2.0,
                                                    UTILS.widthReference(
                                                        context))),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                                UTILS.calculWidth(
                                                    30.0,
                                                    UTILS.widthReference(
                                                        context))),
                                            borderSide: BorderSide(
                                                color: Color.fromARGB(
                                                    255, 250, 192, 187),
                                                width: UTILS.calculWidth(
                                                    2.0,
                                                    UTILS.widthReference(
                                                        context))),
                                          ),
                                          labelStyle: TextStyle(
                                            fontFamily: 'Galey',
                                            fontWeight: FontWeight.w500,
                                            color: Colors.black,
                                            fontSize: UTILS.calculWidth(17,
                                                UTILS.widthReference(context)),
                                          ),
                                          prefixIcon: Padding(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: UTILS.calculWidth(
                                                    15.0,
                                                    UTILS.widthReference(
                                                        context))),
                                            child: Icon(Icons.person),
                                          ),
                                        ),
                                        keyboardType:
                                            TextInputType.emailAddress,
                                      ),
                                    ),
                                  if (User_Info.isPro)
                                    SizedBox(
                                      height: UTILS.calculHeight(
                                          53, UTILS.heightReference(context)),
                                      width: UTILS.calculWidth(
                                          268, UTILS.widthReference(context)),
                                      child: TextFormField(
                                        controller: controllerNom,
                                        cursorColor: Colors.black,
                                        decoration: InputDecoration(
                                          labelText: 'Nom société',
                                          filled: true,
                                          contentPadding: EdgeInsets.symmetric(
                                              vertical: UTILS.calculHeight(
                                                  12.0,
                                                  UTILS.heightReference(
                                                      context)),
                                              horizontal: UTILS.calculWidth(
                                                  15.0,
                                                  UTILS.widthReference(
                                                      context))),
                                          fillColor: Color.fromARGB(
                                              255, 250, 192, 187),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                                UTILS.calculWidth(
                                                    50.0,
                                                    UTILS.widthReference(
                                                        context))),
                                            borderSide: BorderSide(
                                                color: Colors.transparent),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                                UTILS.calculWidth(
                                                    30.0,
                                                    UTILS.widthReference(
                                                        context))),
                                            borderSide: BorderSide(
                                                color: _isNomElevageValid
                                                    ? Colors.transparent
                                                    : Colors.red,
                                                width: UTILS.calculWidth(
                                                    2.0,
                                                    UTILS.widthReference(
                                                        context))),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                                UTILS.calculWidth(
                                                    30.0,
                                                    UTILS.widthReference(
                                                        context))),
                                            borderSide: BorderSide(
                                                color: Color.fromARGB(
                                                    255, 250, 192, 187),
                                                width: UTILS.calculWidth(
                                                    2.0,
                                                    UTILS.widthReference(
                                                        context))),
                                          ),
                                          labelStyle: TextStyle(
                                            fontFamily: 'Galey',
                                            fontWeight: FontWeight.w500,
                                            color: Colors.black,
                                            fontSize: UTILS.calculWidth(17,
                                                UTILS.widthReference(context)),
                                          ),
                                          prefixIcon: Padding(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: UTILS.calculWidth(
                                                    15.0,
                                                    UTILS.widthReference(
                                                        context))),
                                            child: Icon(Icons.person),
                                          ),
                                        ),
                                        keyboardType:
                                            TextInputType.emailAddress,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: UTILS.calculWidth(
                            372, UTILS.widthReference(context)),
                        height: UTILS.calculHeight(
                            53, UTILS.heightReference(context)),
                        padding: EdgeInsets.symmetric(
                            horizontal: UTILS.calculWidth(
                                20, UTILS.widthReference(context))),
                        decoration: BoxDecoration(
                          color: Color.fromARGB(255, 250, 192, 187),
                          borderRadius: BorderRadius.circular(UTILS.calculWidth(
                              30.0, UTILS.widthReference(context))),
                        ),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            canvasColor: Color.fromARGB(255, 250, 192, 187),
                          ),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                flex: 1,
                                child: DropdownButton<Country>(
                                  value: selectedCountry,
                                  icon: Icon(Icons.arrow_drop_down),
                                  underline: Container(),
                                  onChanged: (Country? newValue) {
                                    setState(() {
                                      selectedCountry = newValue!;
                                      _selectedCountryCode =
                                          selectedCountry?.dialCode as String;
                                    });
                                  },
                                  items: countries
                                      .map<DropdownMenuItem<Country>>(
                                          (Country country) {
                                    return DropdownMenuItem<Country>(
                                      value: country,
                                      child: Row(
                                        children: <Widget>[
                                          Image.asset(
                                              'assets/country/${country.code.toLowerCase()}.png',
                                              width: UTILS.calculWidth(
                                                  20,
                                                  UTILS
                                                      .widthReference(context)),
                                              height: UTILS.calculHeight(
                                                  20,
                                                  UTILS.heightReference(
                                                      context)), errorBuilder:
                                                  (BuildContext context,
                                                      Object exception,
                                                      StackTrace? stackTrace) {
                                            return Icon(Icons.flag);
                                          }),
                                          SizedBox(
                                              width: UTILS.calculWidth(
                                                  5,
                                                  UTILS.widthReference(
                                                      context))),
                                          Text(country.dialCode),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                              SizedBox(
                                  width: UTILS.calculWidth(
                                      20, UTILS.widthReference(context))),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    hintText: 'Numéro de téléphone',
                                  ),
                                  onChanged: (value) {
                                    print(
                                        "Numéro modifié : ${selectedCountry?.dialCode}$value");
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                          height: UTILS.calculHeight(
                              30, UTILS.heightReference(context))),
                      PlacesSearchWidgetElevage(
                        isValid: _isAddressElevageValid,
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
                              14.6, UTILS.heightReference(context))),
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

class PlacesSearchWidgetElevage extends StatefulWidget {
  final bool isValid;

  PlacesSearchWidgetElevage({required this.isValid});

  @override
  _PlacesSearchWidgetElevageState createState() =>
      _PlacesSearchWidgetElevageState();
}

class _PlacesSearchWidgetElevageState extends State<PlacesSearchWidgetElevage> {
  TextEditingController _controller = TextEditingController();
  GoogleMapsPlaces _places = GoogleMapsPlaces(apiKey: getApiKey());
  List<Prediction> _suggestions = [];
  double _containerHeight = 50;
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSearchChanged);
  }

  _onSearchChanged() {
    final text = _controller.text;
    if (text == _lastText) return; // ignore cursor/selection changes
    _lastText = text;

    if (text.isEmpty) {
      setState(() {
        _suggestions = [];
        _containerHeight = 50;
      });
    } else {
      _getSuggestions(text);
    }
  }

  Future<void> _getSuggestions(String input) async {
    final response = await _places.autocomplete(input);
    if (!mounted) return;
    if (response.isOkay) {
      setState(() {
        _suggestions = response.predictions;
        _containerHeight = 200;
      });
    } else {
      print('Failed to fetch suggestions');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedContainer(
        duration: Duration(milliseconds: 500),
        width: UTILS.calculWidth(372, UTILS.widthReference(context)),
        height: _suggestions.isNotEmpty
            ? UTILS.calculHeight(196, UTILS.heightReference(context))
            : UTILS.calculHeight(57, UTILS.heightReference(context)),
        decoration: BoxDecoration(
          color: Color.fromARGB(255, 250, 192, 187),
          borderRadius: BorderRadius.circular(
              UTILS.calculWidth(30.0, UTILS.widthReference(context))),
          border: Border.all(
            color: widget.isValid ? Colors.transparent : Colors.red,
            width: UTILS.calculWidth(2.0, UTILS.widthReference(context)),
          ),
        ),
        child: Column(
          children: [
            TextFormField(
              cursorColor: Colors.black,
              controller: _controller,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                hintText: 'Entrez l\'adresse',
                prefixIcon: Icon(Icons.place),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _suggestions.length > 3 ? 3 : _suggestions.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.place),
                    title: Text(_suggestions[index].description ??
                        'Adresse non disponible'),
                    onTap: () {
                      final description = _suggestions[index].description ?? '';
                      _lastText = description;
                      _controller.text = description;
                      User_Info.adressElevage = description;
                      FocusScope.of(context).unfocus();
                      setState(() {
                        _suggestions = [];
                        _containerHeight = 50;
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _places.dispose();
    super.dispose();
  }
}
