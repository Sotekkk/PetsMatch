import 'package:PetsMatch/animation/delayed_animation.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/particulier/securityregister.dart';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_webservice/places.dart';

import 'dart:io';

class Country {
  final String name;
  final String dialCode;
  final String code;

  Country({required this.name, required this.dialCode, required this.code});

  factory Country.fromJson(Map<String, dynamic> json) {
    return Country(
      name: json['name'] as String,
      dialCode: json['dial_code'] as String,
      code: json['code'] as String,
    );
  }
}

Future<List<Country>> loadCountries() async {
  final String response =
      await rootBundle.loadString('assets/CountryCodes.json');
  final data = await json.decode(response) as List;
  return data.map((item) => Country.fromJson(item)).toList();
}

class RegisterPhoneAdressInformationPage extends StatefulWidget {
  const RegisterPhoneAdressInformationPage({super.key});

  @override
  State<RegisterPhoneAdressInformationPage> createState() =>
      _RegisterPhoneAdressInformationPageState();
}

class _RegisterPhoneAdressInformationPageState
    extends State<RegisterPhoneAdressInformationPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  String _selectedCountryCode = '+33'; // France par défaut

  late List<Country> countries = [];
  Country? selectedCountry;

  bool _isPhoneValid = true;
  bool _isAddressValid = true;

  @override
  void initState() {
    super.initState();
    loadCountries().then((list) {
      setState(() {
        countries = list;
        selectedCountry = countries[0];
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _validateAndContinue() {
    setState(() {
      _isPhoneValid = _phoneController.text.trim().isNotEmpty;
      _isAddressValid = _addressController.text.trim().isNotEmpty;
    });

    if (_isPhoneValid && _isAddressValid) {
      User_Info.phone_number = _phoneController.text;
      User_Info.codeISO = _selectedCountryCode;
      User_Info.adress = _addressController.text;

      if (User_Info.phone_number.isNotEmpty &&
          User_Info.phone_number != "0000000000" &&
          User_Info.adress.isNotEmpty &&
          User_Info.adress != "none") {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => RegisterSecurity()),
        );
      } else {
        print("pas possible");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        resizeToAvoidBottomInset: true,
        body: SingleChildScrollView(
            reverse: true,
            child: Center(
                child: Column(children: [
                      SizedBox(
                          width: UTILS.widthReference(context),
                          height: UTILS.calculHeight(
                              104,
                              UTILS.heightReference(
                                  context)), // Hauteur fixe pour le Stack
                          child: Stack(children: [
                            Image.asset(
                              'assets/deco/arrondi_rose_2.png',
                              fit: BoxFit.cover,
                              width: UTILS.calculWidth(
                                  211, UTILS.widthReference(context)),
                              height: UTILS.calculHeight(
                                  104,
                                  UTILS.heightReference(
                                      context)), // Hauteur fixe pour le Stack
                            ),
                            Positioned(
                              top: UTILS.calculHeight(
                                  53, UTILS.heightReference(context)),
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
                              color: Color.fromARGB(174, 0, 0, 0),
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
                                  color: Color.fromARGB(174, 0, 0, 0),
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
                              'assets/page/register_with_number.png')),
                      SizedBox(
                          height: UTILS.calculHeight(
                              37, UTILS.heightReference(context))),
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
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: _isPhoneValid ? Colors.transparent : Colors.red,
                            width: 2.0,
                          ),
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
                                      _selectedCountryCode = selectedCountry?.dialCode as String;
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
                                                  19,
                                                  UTILS
                                                      .widthReference(context)),
                                              height: UTILS.calculHeight(
                                                  20,
                                                  UTILS.heightReference(
                                                      context)),
                                              errorBuilder:
                                                  (BuildContext context,
                                                      Object exception,
                                                      StackTrace? stackTrace) {
                                            return Icon(Icons.flag);
                                          }),
                                          SizedBox(
                                              width: UTILS.calculWidth(
                                                  10,
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
                                      18, UTILS.widthReference(context))),
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
                                    print("Numéro modifié : ${selectedCountry?.dialCode}$value");
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                          height: UTILS.calculHeight(
                              14, UTILS.heightReference(context))),
                      PlacesSearchWidget(controller: _addressController, isValid: _isAddressValid),
                      SizedBox(
                          height: UTILS.calculHeight(
                              123, UTILS.heightReference(context))),
                      Align(
                        alignment:
                            Alignment.center, // Alignez le bouton à droite
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
                                    color: Color.fromARGB(255, 0, 0,
                                        0), // Mettez ici la couleur de votre choix
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
                          height: UTILS.calculHeight(
                              66, UTILS.heightReference(context)),
                          width: UTILS.calculWidth(
                              367, UTILS.widthReference(context)),
                          child: ElevatedButton(
                            onPressed: _validateAndContinue,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Color.fromARGB(255, 250, 192,
                                    187)), // Couleur de fond du bouton
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
                            // Personnaliser le style du bouton
                          )),
                      SizedBox(
                          height: UTILS.calculHeight(
                              9.5, UTILS.heightReference(context))),
                      Image.asset(
                        'assets/deco/arrondi_green_deco_2.png',
                        fit: BoxFit.cover,
                        width: UTILS.calculWidth(
                            233, UTILS.widthReference(context)),
                        height: UTILS.calculHeight(
                            52,
                            UTILS.heightReference(
                                context)), // Hauteur fixe pour l'image
                      ), // Espac
                    ]))));
  }
}

class PlacesSearchWidget extends StatefulWidget {
  final TextEditingController controller;
  final bool isValid;

  PlacesSearchWidget({required this.controller, required this.isValid});

  @override
  _PlacesSearchWidgetState createState() => _PlacesSearchWidgetState();
}

class _PlacesSearchWidgetState extends State<PlacesSearchWidget> {
  GoogleMapsPlaces _places = GoogleMapsPlaces(apiKey: getApiKey());
  List<Prediction> _suggestions = [];
  double _containerHeight = 50;
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onSearchChanged);
  }

  _onSearchChanged() {
    final text = widget.controller.text;
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
        duration: Duration(milliseconds: 500), // Durée de l'animation pour la transition de hauteur
        width: UTILS.calculWidth(372, UTILS.widthReference(context)),
        height: _suggestions.isNotEmpty ? UTILS.calculHeight(200, UTILS.heightReference(context)) : 55,
        decoration: BoxDecoration(
          color: Color.fromARGB(255, 250, 192, 187),
          borderRadius: BorderRadius.circular(30.0),
          border: Border.all(
            color: widget.isValid ? Colors.transparent : Colors.red,
            width: 2.0,
          ),
        ),
        child: Column(
          children: [
            TextFormField(
              cursorColor: Colors.black,
              controller: widget.controller,
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
                    title: Text(_suggestions[index].description ?? 'Adresse non disponible'),
                    onTap: () {
                      final description = _suggestions[index].description ?? '';
                      _lastText = description;
                      widget.controller.text = description;
                      User_Info.adress = description;
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
    widget.controller.removeListener(_onSearchChanged);
    _places.dispose();
    super.dispose();
  }
}
