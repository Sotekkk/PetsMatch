import 'package:PetsMatch/pages/particulier/numberadressregistration.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:PetsMatch/utils.dart';
import 'package:PetsMatch/main.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';

class InfoUserSettings extends StatefulWidget {
  const InfoUserSettings({super.key});

  @override
  State<InfoUserSettings> createState() => _InfoUserSettingsState();
}

class _InfoUserSettingsState extends State<InfoUserSettings> {
  final TextEditingController _firstnameController = TextEditingController();
  final TextEditingController _lastnameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _elevagePhoneController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _rueController = TextEditingController();
  final TextEditingController _villeController = TextEditingController();
  final TextEditingController _codePostalController = TextEditingController();
  final TextEditingController _paysController = TextEditingController();
  final TextEditingController _rueElevageController = TextEditingController();
  final TextEditingController _villeElevageController = TextEditingController();
  final TextEditingController _codePostalElevageController = TextEditingController();
  final TextEditingController _paysElevageController = TextEditingController();
  final TextEditingController _elevageNameController = TextEditingController();
  final TextEditingController _phoneISOCodeController = TextEditingController();
  final TextEditingController _elevagePhoneISOCodeController =
      TextEditingController();


  List<Country> countries = [];
  Country? selectedCountry;
  Country? selectedElevageCountry;
  String _selectedCountryCode = User_Info.codeISO; // France par défaut
  String _selectedElevageCountryCode =
      User_Info.codeISOElevage; // France par défaut

  bool _isPhoneValid = true;
  bool _isElevagePhoneValid = true;
  bool _isDog = false;
  bool _isCat = false;
  List<String> _selectedDogBreeds = [];
  List<String> _selectedCatBreeds = [];
  List<String> _allDogBreeds = [];
  List<String> _allCatBreeds = [];

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadCountries();
    _loadBreeds();
  }

  Future<void> _loadBreeds() async {
    final dogJson = await rootBundle.loadString('assets/dog_breeds.json');
    final catJson = await rootBundle.loadString('assets/cat_breeds.json');
    setState(() {
      _allDogBreeds = List<String>.from(json.decode(dogJson));
      _allCatBreeds = List<String>.from(json.decode(catJson));
    });
  }

  Future<void> _loadUserInfo() async {
      var user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      var userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      User_Info.updateUserInfo(userDoc.data() as Map<String, dynamic>);
       _firstnameController.text = User_Info.firstname;
    _lastnameController.text = User_Info.lastname;
    _dobController.text = User_Info.dateofbirth;
    _phoneISOCodeController.text = User_Info.codeISO;
    if (User_Info.isElevage || User_Info.isPro) {
      _elevageNameController.text = User_Info.nameElevage;
      _elevagePhoneISOCodeController.text = User_Info.codeISOElevage;
      _elevagePhoneController.text = User_Info.numeroElevage;
      _rueElevageController.text = User_Info.rueElevage;
      _villeElevageController.text = User_Info.villeElevage;
      _codePostalElevageController.text = User_Info.codePostalElevage;
      _paysElevageController.text = User_Info.paysElevage.isNotEmpty ? User_Info.paysElevage : 'France';
      _phoneController.text = User_Info.numeroElevage;
      _isDog = User_Info.isDog;
      _isCat = User_Info.isCat;
      _selectedDogBreeds = List<String>.from(User_Info.dogBreeds);
      _selectedCatBreeds = List<String>.from(User_Info.catBreeds);
    }
    if (!User_Info.isElevage && !User_Info.isPro) {
      _phoneController.text = User_Info.phone_number;
      _rueController.text = User_Info.rue;
      _villeController.text = User_Info.ville;
      _codePostalController.text = User_Info.codePostal;
      _paysController.text = User_Info.pays.isNotEmpty ? User_Info.pays : 'France';
    }
    }
    // Remplir les contrôleurs avec les informations utilisateur existantes
   
  }

  Future<void> _loadCountries() async {
    final String response =
        await rootBundle.loadString('assets/CountryCodes.json');
    final data = await json.decode(response) as List;
    countries = data.map((item) => Country.fromJson(item)).toList();
    setState(() {
      selectedCountry = countries.firstWhere(
          (country) => country.dialCode == _selectedCountryCode,
          orElse: () => countries.first);
      selectedElevageCountry = countries.firstWhere(
          (country) => country.dialCode == _selectedElevageCountryCode,
          orElse: () => countries.first);
    });
  }

  void _updateUserInfo() async {
    // Mettre à jour les informations dans Firebase
    await FirebaseFirestore.instance
        .collection('users')
        .doc(User_Info.uid)
        .update({
      'firstname': _firstnameController.text,
      'lastname': _lastnameController.text,
      'dateofbirth': _dobController.text,
      if (!User_Info.isElevage && !User_Info.isPro)
        'phone_number': _phoneController.text,
      if (User_Info.isElevage || User_Info.isPro)
        'numeroElevage': _phoneController.text,
      'codeISO': _selectedCountryCode,
      if (!User_Info.isElevage && !User_Info.isPro) 'rue': _rueController.text,
      if (!User_Info.isElevage && !User_Info.isPro) 'ville': _villeController.text,
      if (!User_Info.isElevage && !User_Info.isPro) 'codePostal': _codePostalController.text,
      if (!User_Info.isElevage && !User_Info.isPro) 'pays': _paysController.text,
      if (User_Info.isElevage || User_Info.isPro)
        'nameElevage': _elevageNameController.text,
      if (User_Info.isElevage || User_Info.isPro)
        'numeroElevage': _elevagePhoneController.text,
      if (User_Info.isElevage || User_Info.isPro) 'rueElevage': _rueElevageController.text,
      if (User_Info.isElevage || User_Info.isPro) 'villeElevage': _villeElevageController.text,
      if (User_Info.isElevage || User_Info.isPro) 'codePostalElevage': _codePostalElevageController.text,
      if (User_Info.isElevage || User_Info.isPro) 'paysElevage': _paysElevageController.text,
      if (User_Info.isElevage || User_Info.isPro)
        'codeISOElevage': _selectedElevageCountryCode,
      if (User_Info.isElevage || User_Info.isPro) 'isDog': _isDog,
      if (User_Info.isElevage || User_Info.isPro) 'isCat': _isCat,
      if (User_Info.isElevage || User_Info.isPro) 'dogBreeds': _selectedDogBreeds,
      if (User_Info.isElevage || User_Info.isPro) 'catBreeds': _selectedCatBreeds,
      'isElevage': User_Info.isElevage,
    });

    // Mettre à jour les informations dans User_Info
    User_Info.firstname = _firstnameController.text;
    User_Info.lastname = _lastnameController.text;
    User_Info.dateofbirth = _dobController.text;
    if (!User_Info.isElevage && !User_Info.isPro) {
      User_Info.phone_number = _phoneController.text;
      User_Info.rue = _rueController.text;
      User_Info.ville = _villeController.text;
      User_Info.codePostal = _codePostalController.text;
      User_Info.pays = _paysController.text;
    }
    User_Info.codeISO = _selectedCountryCode as String;
    if (User_Info.isElevage || User_Info.isPro) {
      User_Info.nameElevage = _elevageNameController.text;
      User_Info.numeroElevage = _elevagePhoneController.text;
      User_Info.rueElevage = _rueElevageController.text;
      User_Info.villeElevage = _villeElevageController.text;
      User_Info.codePostalElevage = _codePostalElevageController.text;
      User_Info.paysElevage = _paysElevageController.text;
      User_Info.codeISOElevage = _selectedElevageCountryCode;
      User_Info.isDog = _isDog;
      User_Info.isCat = _isCat;
      User_Info.dogBreeds = List<String>.from(_selectedDogBreeds);
      User_Info.catBreeds = List<String>.from(_selectedCatBreeds);
    }

    // Afficher un message de confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Information utilisateur mise à jour')),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _dobController.text = "${picked.toLocal()}".split(' ')[0];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            children: [
              SizedBox(
                width: UTILS.widthReference(context),
                height: UTILS.calculHeight(
                  105,
                  UTILS.heightReference(context),
                ),
                child: Stack(
                  children: [
                    Image.asset(
                      'assets/deco/arrondi_rose_2.png',
                      fit: BoxFit.cover,
                      width:
                          UTILS.calculWidth(211, UTILS.widthReference(context)),
                      height: UTILS.calculHeight(
                        104,
                        UTILS.heightReference(context),
                      ),
                    ),
                    Positioned(
                      top: UTILS.calculHeight(
                          42, UTILS.heightReference(context)),
                      left:
                          UTILS.calculWidth(10, UTILS.widthReference(context)),
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
                          'Information utilisateur',
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
                  height:
                      UTILS.calculHeight(30, UTILS.heightReference(context))),
              _buildStyledTextField(
                  _firstnameController, 'Prénom', Icons.person),
              SizedBox(
                  height:
                      UTILS.calculHeight(15, UTILS.heightReference(context))),
              _buildStyledTextField(_lastnameController, 'Nom', Icons.person),
              SizedBox(
                  height:
                      UTILS.calculHeight(15, UTILS.heightReference(context))),
              _buildDateField(_dobController, 'Date de naissance'),
              SizedBox(
                  height:
                      UTILS.calculHeight(15, UTILS.heightReference(context))),
              _buildStyledTextFieldZeub(),
              if (!User_Info.isElevage && !User_Info.isPro)
                SizedBox(
                    height:
                        UTILS.calculHeight(15, UTILS.heightReference(context))),
              if (!User_Info.isElevage && !User_Info.isPro)
                _buildPhoneField(_phoneController, 'Téléphone', selectedCountry,
                    _isPhoneValid, (Country? country) {
                  setState(() {
                    selectedCountry = country;
                    _selectedCountryCode = selectedCountry?.dialCode as String;
                  });
                }),
              SizedBox(
                  height:
                      UTILS.calculHeight(15, UTILS.heightReference(context))),
              if (User_Info.isElevage || User_Info.isPro)
                _buildStyledTextField(_elevageNameController,
                    'Nom de l\'élevage', Icons.business),
              if (User_Info.isElevage || User_Info.isPro)
                SizedBox(
                    height:
                        UTILS.calculHeight(15, UTILS.heightReference(context))),
              if (User_Info.isElevage || User_Info.isPro)
                _buildPhoneField(
                    _elevagePhoneController,
                    'Numéro Élevage',
                    selectedElevageCountry,
                    _isElevagePhoneValid, (Country? country) {
                  setState(() {
                    selectedElevageCountry = country;
                    _selectedElevageCountryCode =
                        selectedElevageCountry?.dialCode as String;
                  });
                }),
              if (User_Info.isElevage || User_Info.isPro)
                SizedBox(
                    height:
                        UTILS.calculHeight(15, UTILS.heightReference(context))),
              if (!User_Info.isElevage && !User_Info.isPro) ...[
                _buildStyledTextField(_rueController, 'Rue', Icons.home),
                SizedBox(height: UTILS.calculHeight(15, UTILS.heightReference(context))),
                Row(
                  children: [
                    SizedBox(width: UTILS.calculWidth(16, UTILS.widthReference(context))),
                    Expanded(
                      flex: 2,
                      child: _buildStyledTextFieldRaw(_villeController, 'Ville', Icons.location_city),
                    ),
                    SizedBox(width: UTILS.calculWidth(8, UTILS.widthReference(context))),
                    Expanded(
                      flex: 1,
                      child: _buildStyledTextFieldRaw(_codePostalController, 'Code postal', Icons.markunread_mailbox),
                    ),
                    SizedBox(width: UTILS.calculWidth(16, UTILS.widthReference(context))),
                  ],
                ),
                SizedBox(height: UTILS.calculHeight(15, UTILS.heightReference(context))),
                _buildStyledTextField(_paysController, 'Pays', Icons.flag),
              ],
              if (User_Info.isElevage || User_Info.isPro) ...[
                _buildStyledTextField(_rueElevageController, 'Rue', Icons.home),
                SizedBox(height: UTILS.calculHeight(15, UTILS.heightReference(context))),
                Row(
                  children: [
                    SizedBox(width: UTILS.calculWidth(16, UTILS.widthReference(context))),
                    Expanded(
                      flex: 2,
                      child: _buildStyledTextFieldRaw(_villeElevageController, 'Ville', Icons.location_city),
                    ),
                    SizedBox(width: UTILS.calculWidth(8, UTILS.widthReference(context))),
                    Expanded(
                      flex: 1,
                      child: _buildStyledTextFieldRaw(_codePostalElevageController, 'Code postal', Icons.markunread_mailbox),
                    ),
                    SizedBox(width: UTILS.calculWidth(16, UTILS.widthReference(context))),
                  ],
                ),
                SizedBox(height: UTILS.calculHeight(15, UTILS.heightReference(context))),
                _buildStyledTextField(_paysElevageController, 'Pays', Icons.flag),
              ],
              if (User_Info.isElevage || User_Info.isPro) ...[
                SizedBox(
                    height: UTILS.calculHeight(
                        15, UTILS.heightReference(context))),
                SizedBox(
                  width: UTILS.calculWidth(367, UTILS.widthReference(context)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 8),
                        child: Text(
                          'Espèces élevées',
                          style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            fontSize: UTILS.calculWidth(
                                15, UTILS.widthReference(context)),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          _buildSpeciesToggle(
                            label: 'Chien',
                            emoji: '🐶',
                            value: _isDog,
                            onChanged: (v) => setState(() {
                              _isDog = v;
                              if (!v) _selectedDogBreeds.clear();
                            }),
                          ),
                          const SizedBox(width: 12),
                          _buildSpeciesToggle(
                            label: 'Chat',
                            emoji: '🐱',
                            value: _isCat,
                            onChanged: (v) => setState(() {
                              _isCat = v;
                              if (!v) _selectedCatBreeds.clear();
                            }),
                          ),
                        ],
                      ),
                      if (_isDog) ...[
                        const SizedBox(height: 12),
                        _buildBreedSelector(
                          label: 'Races de chiens',
                          allBreeds: _allDogBreeds,
                          selected: _selectedDogBreeds,
                          onChanged: (breeds) =>
                              setState(() => _selectedDogBreeds = breeds),
                        ),
                      ],
                      if (_isCat) ...[
                        const SizedBox(height: 12),
                        _buildBreedSelector(
                          label: 'Races de chats',
                          allBreeds: _allCatBreeds,
                          selected: _selectedCatBreeds,
                          onChanged: (breeds) =>
                              setState(() => _selectedCatBreeds = breeds),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              SizedBox(
                  height:
                      UTILS.calculHeight(20, UTILS.heightReference(context))),
              SizedBox(
                  height:
                      UTILS.calculHeight(61, UTILS.heightReference(context)),
                  width: UTILS.calculWidth(325, UTILS.widthReference(context)),
                  child: ElevatedButton(
                    onPressed: _updateUserInfo,
                    child: Text(
                      'MODIFIER',
                      style: TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w500,
                        color: Color.fromARGB(255, 0, 0, 0),
                        fontSize: UTILS.calculWidth(
                            17, UTILS.widthReference(context)),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromARGB(
                          255, 255, 192, 187), // Couleur de fond du bouton
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStyledTextField(
      TextEditingController controller, String label, IconData icon) {
    return SizedBox(
      height: UTILS.calculHeight(53, UTILS.heightReference(context)),
      width: UTILS.calculWidth(367, UTILS.widthReference(context)),
      child: TextFormField(
        cursorColor: Colors.black,
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          contentPadding: EdgeInsets.symmetric(
            vertical: UTILS.calculHeight(12.0, UTILS.heightReference(context)),
            horizontal: UTILS.calculWidth(15.0, UTILS.widthReference(context)),
          ),
          fillColor: Color.fromARGB(255, 250, 192, 187),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(
                UTILS.calculWidth(50.0, UTILS.widthReference(context))),
            borderSide: BorderSide(color: Colors.transparent),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(
                UTILS.calculWidth(30.0, UTILS.widthReference(context))),
            borderSide: BorderSide(color: Colors.transparent),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(
                UTILS.calculWidth(30.0, UTILS.widthReference(context))),
            borderSide: BorderSide(
                color: Color.fromARGB(255, 250, 192, 187),
                width: UTILS.calculWidth(2.0, UTILS.widthReference(context))),
          ),
          labelStyle: TextStyle(
            fontFamily: 'Galey',
            fontWeight: FontWeight.w500,
            color: Colors.black,
            fontSize: UTILS.calculWidth(17, UTILS.widthReference(context)),
          ),
          prefixIcon: Padding(
            padding: EdgeInsets.symmetric(
                horizontal:
                    UTILS.calculWidth(15.0, UTILS.widthReference(context))),
            child: Icon(icon),
          ),
        ),
      ),
    );
  }

  Widget _buildStyledTextFieldZeub() {
    return SizedBox(
      height: UTILS.calculHeight(53, UTILS.heightReference(context)),
      width: UTILS.calculWidth(367, UTILS.widthReference(context)),
      child: TextFormField(
        initialValue: User_Info.email,
        enabled: false,
        cursorColor: Colors.black,
        decoration: InputDecoration(
          labelText: 'Email',
          filled: true,
          contentPadding: EdgeInsets.symmetric(
            vertical: UTILS.calculHeight(12.0, UTILS.heightReference(context)),
            horizontal: UTILS.calculWidth(15.0, UTILS.widthReference(context)),
          ),
          fillColor: Color.fromARGB(255, 250, 192, 187),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(
                UTILS.calculWidth(50.0, UTILS.widthReference(context))),
            borderSide: BorderSide(color: Colors.transparent),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(
                UTILS.calculWidth(30.0, UTILS.widthReference(context))),
            borderSide: BorderSide(color: Colors.transparent),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(
                UTILS.calculWidth(30.0, UTILS.widthReference(context))),
            borderSide: BorderSide(
                color: Color.fromARGB(255, 250, 192, 187),
                width: UTILS.calculWidth(2.0, UTILS.widthReference(context))),
          ),
          labelStyle: TextStyle(
            fontFamily: 'Galey',
            fontWeight: FontWeight.w500,
            color: Colors.black,
            fontSize: UTILS.calculWidth(17, UTILS.widthReference(context)),
          ),
          prefixIcon: Padding(
            padding: EdgeInsets.symmetric(
                horizontal:
                    UTILS.calculWidth(15.0, UTILS.widthReference(context))),
            child: Icon(Icons.email),
          ),
        ),
      ),
    );
  }

  Widget _buildDateField(TextEditingController controller, String label) {
    return GestureDetector(
      onTap: () => _selectDate(context),
      child: AbsorbPointer(
        child: _buildStyledTextField(controller, label, Icons.calendar_today),
      ),
    );
  }

  Widget _buildPhoneField(
      TextEditingController controller,
      String label,
      Country? selectedCountry,
      bool isValid,
      void Function(Country?) onChanged) {
    return Container(
      width: UTILS.calculWidth(372, UTILS.widthReference(context)),
      height: UTILS.calculHeight(53, UTILS.heightReference(context)),
      padding: EdgeInsets.symmetric(
          horizontal: UTILS.calculWidth(20, UTILS.widthReference(context))),
      decoration: BoxDecoration(
        color: Color.fromARGB(255, 250, 192, 187),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: isValid ? Colors.transparent : Colors.red,
          width: 2.0,
        ),
      ),
      child: Theme(
        data: Theme.of(context)
            .copyWith(canvasColor: Color.fromARGB(255, 250, 192, 187)),
        child: Row(
          children: <Widget>[
            Expanded(
              flex: 1,
              child: DropdownButton<Country>(
                value: selectedCountry,
                icon: Icon(Icons.arrow_drop_down),
                underline: Container(),
                onChanged: onChanged,
                items:
                    countries.map<DropdownMenuItem<Country>>((Country country) {
                  return DropdownMenuItem<Country>(
                    value: country,
                    child: Row(
                      children: <Widget>[
                        Image.asset(
                          'assets/country/${country.code.toLowerCase()}.png',
                          width: UTILS.calculWidth(
                              19, UTILS.widthReference(context)),
                          height: UTILS.calculHeight(
                              20, UTILS.heightReference(context)),
                          errorBuilder: (BuildContext context, Object exception,
                              StackTrace? stackTrace) {
                            return Icon(Icons.flag);
                          },
                        ),
                        SizedBox(
                            width: UTILS.calculWidth(
                                10, UTILS.widthReference(context))),
                        Text(country.dialCode),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            SizedBox(
                width: UTILS.calculWidth(18, UTILS.widthReference(context))),
            Expanded(
              flex: 2,
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: label,
                ),
                onChanged: (value) {
                  print("Numéro modifié : ${selectedCountry?.dialCode}$value");
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreedSelector({
    required String label,
    required List<String> allBreeds,
    required List<String> selected,
    required ValueChanged<List<String>> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () => _openBreedPicker(
            label: label,
            allBreeds: allBreeds,
            selected: selected,
            onChanged: onChanged,
          ),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 250, 192, 187),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    selected.isEmpty
                        ? 'Sélectionner des races...'
                        : '${selected.length} race${selected.length > 1 ? 's' : ''} sélectionnée${selected.length > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w500,
                      fontSize: UTILS.calculWidth(
                          14, UTILS.widthReference(context)),
                    ),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ),
        ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: selected
                .map(
                  (breed) => Chip(
                    label: Text(
                      breed,
                      style: const TextStyle(
                          fontFamily: 'Galey', fontSize: 12),
                    ),
                    backgroundColor: Colors.white,
                    side: const BorderSide(
                        color: Color.fromARGB(255, 250, 192, 187)),
                    deleteIconColor: Colors.grey,
                    onDeleted: () {
                      final updated = List<String>.from(selected)
                        ..remove(breed);
                      onChanged(updated);
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Future<void> _openBreedPicker({
    required String label,
    required List<String> allBreeds,
    required List<String> selected,
    required ValueChanged<List<String>> onChanged,
  }) async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _BreedPickerSheet(
        label: label,
        allBreeds: allBreeds,
        initialSelected: List<String>.from(selected),
      ),
    );
    if (result != null) onChanged(result);
  }

  Widget _buildStyledTextFieldRaw(
      TextEditingController controller, String label, IconData icon) {
    return TextFormField(
      cursorColor: Colors.black,
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        contentPadding: EdgeInsets.symmetric(
          vertical: UTILS.calculHeight(12.0, UTILS.heightReference(context)),
          horizontal: UTILS.calculWidth(12.0, UTILS.widthReference(context)),
        ),
        fillColor: const Color.fromARGB(255, 250, 192, 187),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
              UTILS.calculWidth(30.0, UTILS.widthReference(context))),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
              UTILS.calculWidth(30.0, UTILS.widthReference(context))),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
              UTILS.calculWidth(30.0, UTILS.widthReference(context))),
          borderSide: BorderSide(
              color: const Color.fromARGB(255, 250, 192, 187),
              width: UTILS.calculWidth(2.0, UTILS.widthReference(context))),
        ),
        labelStyle: TextStyle(
          fontFamily: 'Galey',
          fontWeight: FontWeight.w500,
          color: Colors.black,
          fontSize: UTILS.calculWidth(14, UTILS.widthReference(context)),
        ),
        prefixIcon: Icon(icon, size: 18),
      ),
    );
  }

  Widget _buildSpeciesToggle({
    required String label,
    required String emoji,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: value
              ? const Color.fromARGB(255, 250, 192, 187)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: value
                ? const Color.fromARGB(255, 250, 192, 187)
                : Colors.grey.shade300,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w500,
                fontSize: UTILS.calculWidth(14, UTILS.widthReference(context)),
                color: value ? Colors.black87 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              value ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
              color: value ? Colors.black54 : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

}

class _BreedPickerSheet extends StatefulWidget {
  final String label;
  final List<String> allBreeds;
  final List<String> initialSelected;

  const _BreedPickerSheet({
    required this.label,
    required this.allBreeds,
    required this.initialSelected,
  });

  @override
  State<_BreedPickerSheet> createState() => _BreedPickerSheetState();
}

class _BreedPickerSheetState extends State<_BreedPickerSheet> {
  late List<String> _selected;
  late List<String> _filtered;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = List<String>.from(widget.initialSelected);
    _filtered = List<String>.from(widget.allBreeds);
  }

  void _onSearch(String query) {
    setState(() {
      _filtered = widget.allBreeds
          .where((b) => b.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, scrollController) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.label,
                      style: const TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w500,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text(
                      'Valider',
                      style: TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w500,
                        color: Color.fromARGB(255, 200, 100, 80),
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText: 'Rechercher une race...',
                  hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (_selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _selected
                      .map(
                        (b) => Chip(
                          label: Text(b,
                              style: const TextStyle(
                                  fontFamily: 'Galey', fontSize: 12)),
                          backgroundColor: const Color.fromARGB(
                              255, 250, 192, 187),
                          deleteIconColor: Colors.black54,
                          onDeleted: () =>
                              setState(() => _selected.remove(b)),
                        ),
                      )
                      .toList(),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _filtered.length,
                itemBuilder: (_, index) {
                  final breed = _filtered[index];
                  final isSelected = _selected.contains(breed);
                  return ListTile(
                    dense: true,
                    title: Text(
                      breed,
                      style: TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle,
                            color: Color.fromARGB(255, 200, 100, 80),
                            size: 20)
                        : const Icon(Icons.radio_button_unchecked,
                            color: Colors.grey, size: 20),
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selected.remove(breed);
                        } else {
                          _selected.add(breed);
                        }
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
}
