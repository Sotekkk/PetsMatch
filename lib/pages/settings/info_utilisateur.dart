import 'package:PetsMatch/pages/particulier/numberadressregistration.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';

class InfoUserSettings extends StatefulWidget {
  const InfoUserSettings({super.key});

  @override
  State<InfoUserSettings> createState() => _InfoUserSettingsState();
}

class _InfoUserSettingsState extends State<InfoUserSettings> {
  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _border = Color(0xFFE4E7E2);

  final TextEditingController _firstnameController = TextEditingController();
  final TextEditingController _lastnameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _elevagePhoneController = TextEditingController();
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
  final TextEditingController _elevagePhoneISOCodeController = TextEditingController();

  List<Country> countries = [];
  Country? selectedCountry;
  Country? selectedElevageCountry;
  String _selectedCountryCode = User_Info.codeISO;
  String _selectedElevageCountryCode = User_Info.codeISOElevage;

  final bool _isPhoneValid = true;
  final bool _isElevagePhoneValid = true;
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
  }

  Future<void> _loadCountries() async {
    final String response = await rootBundle.loadString('assets/CountryCodes.json');
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
    final bool isElevageOrPro = User_Info.isElevage || User_Info.isPro;
    if (isElevageOrPro) {
      if (_elevagePhoneController.text.trim().isEmpty ||
          _villeElevageController.text.trim().isEmpty ||
          _codePostalElevageController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Téléphone, ville et code postal sont obligatoires',
                style: TextStyle(fontFamily: 'Galey')),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    } else {
      if (_phoneController.text.trim().isEmpty ||
          _villeController.text.trim().isEmpty ||
          _codePostalController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Téléphone, ville et code postal sont obligatoires',
                style: TextStyle(fontFamily: 'Galey')),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

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
    User_Info.codeISO = _selectedCountryCode;
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

    final supa = Supabase.instance.client;
    final supaPayload = <String, dynamic>{
      'firstname': _firstnameController.text,
      'lastname': _lastnameController.text,
      'date_of_birth': _dobController.text,
    };
    if (!User_Info.isElevage && !User_Info.isPro) {
      supaPayload['phone_number'] = _phoneController.text;
      supaPayload['ville'] = _villeController.text;
      supaPayload['code_postal'] = _codePostalController.text;
    }
    if (User_Info.isElevage || User_Info.isPro) {
      supaPayload['name_elevage'] = _elevageNameController.text;
      supaPayload['rue_elevage'] = _rueElevageController.text;
      supaPayload['ville_elevage'] = _villeElevageController.text;
      supaPayload['code_postal_elevage'] = _codePostalElevageController.text;
      supaPayload['pays_elevage'] = _paysElevageController.text;
    }
    await supa.from('users').update(supaPayload).eq('uid', User_Info.uid);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informations mises à jour', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Color(0xFF0C5C6C),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Information utilisateur',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _card('Identité', [
              _field('Prénom', _firstnameController),
              _field('Nom', _lastnameController),
              _dateField('Date de naissance', _dobController),
              _readOnlyField('Email', User_Info.email, Icons.email_outlined),
            ]),
            const SizedBox(height: 12),
            _card('Coordonnées', [
              if (!User_Info.isElevage && !User_Info.isPro) ...[
                _phoneField(_phoneController, 'Téléphone', selectedCountry, _isPhoneValid,
                    (Country? c) => setState(() {
                          selectedCountry = c;
                          _selectedCountryCode = c?.dialCode ?? _selectedCountryCode;
                        })),
                const SizedBox(height: 12),
                _field('Rue', _rueController),
                Row(children: [
                  Expanded(flex: 2, child: _fieldRaw('Ville', _villeController)),
                  const SizedBox(width: 8),
                  Expanded(flex: 1, child: _fieldRaw('Code postal', _codePostalController,
                      inputType: TextInputType.number)),
                ]),
                const SizedBox(height: 12),
                _field('Pays', _paysController),
              ],
              if (User_Info.isElevage || User_Info.isPro) ...[
                _field("Nom de l'élevage", _elevageNameController),
                _phoneField(_elevagePhoneController, 'Téléphone élevage', selectedElevageCountry,
                    _isElevagePhoneValid, (Country? c) => setState(() {
                          selectedElevageCountry = c;
                          _selectedElevageCountryCode = c?.dialCode ?? _selectedElevageCountryCode;
                        })),
                const SizedBox(height: 12),
                _field('Rue', _rueElevageController),
                Row(children: [
                  Expanded(flex: 2, child: _fieldRaw('Ville', _villeElevageController)),
                  const SizedBox(width: 8),
                  Expanded(flex: 1, child: _fieldRaw('Code postal', _codePostalElevageController,
                      inputType: TextInputType.number)),
                ]),
                const SizedBox(height: 12),
                _field('Pays', _paysElevageController),
              ],
            ]),
            if (User_Info.isElevage || User_Info.isPro) ...[
              const SizedBox(height: 12),
              _especesCard(),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _updateUserInfo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('Enregistrer les modifications',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Cards & fields ─────────────────────────────────────────────────────────────

  Widget _card(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
            fontSize: 14, color: Color(0xFF1F2A2E))),
        const SizedBox(height: 14),
        ...children,
      ]),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {TextInputType? inputType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        keyboardType: inputType,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _green, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          isDense: true,
        ),
      ),
    );
  }

  Widget _fieldRaw(String label, TextEditingController ctrl,
      {TextInputType? inputType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        keyboardType: inputType,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _green, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          isDense: true,
        ),
      ),
    );
  }

  Widget _readOnlyField(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: value,
        enabled: false,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF9CA3AF)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
          prefixIcon: Icon(icon, size: 18, color: const Color(0xFF9CA3AF)),
          disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          isDense: true,
        ),
      ),
    );
  }

  Widget _dateField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _selectDate(context),
        child: AbsorbPointer(
          child: TextFormField(
            controller: ctrl,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
              suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFF6F767B)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _border)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              isDense: true,
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneField(
      TextEditingController controller,
      String label,
      Country? selectedCountry,
      bool isValid,
      void Function(Country?) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isValid ? _border : Colors.red, width: 1.0),
        ),
        child: Row(
          children: [
            Theme(
              data: Theme.of(context).copyWith(canvasColor: Colors.white),
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: DropdownButton<Country>(
                  value: selectedCountry,
                  icon: const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF6F767B)),
                  underline: const SizedBox(),
                  isDense: true,
                  onChanged: onChanged,
                  items: countries.map<DropdownMenuItem<Country>>((Country country) {
                    return DropdownMenuItem<Country>(
                      value: country,
                      child: Row(children: [
                        Image.asset(
                          'assets/country/${country.code.toLowerCase()}.png',
                          width: 20, height: 14,
                          errorBuilder: (_, __, ___) => const Icon(Icons.flag, size: 16),
                        ),
                        const SizedBox(width: 6),
                        Text(country.dialCode,
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                      ]),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Container(width: 1, height: 28, color: _border),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: label,
                  hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF9CA3AF)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Espèces ───────────────────────────────────────────────────────────────────

  Widget _especesCard() {
    final label = User_Info.isPro
        ? (User_Info.catPro == 'sante' || User_Info.catPro == 'veterinaire'
            ? 'Espèces soignées'
            : User_Info.catPro == 'pension' || User_Info.catPro == 'garde'
                ? 'Espèces gardées'
                : 'Espèces acceptées')
        : 'Espèces élevées';

    return _card(label, [
      Wrap(spacing: 8, runSpacing: 8, children: [
        _speciesChip('Chien', '🐶', _isDog, (v) => setState(() {
          _isDog = v;
          if (!v) _selectedDogBreeds.clear();
        })),
        _speciesChip('Chat', '🐱', _isCat, (v) => setState(() {
          _isCat = v;
          if (!v) _selectedCatBreeds.clear();
        })),
      ]),
      if (_isDog) ...[
        const SizedBox(height: 12),
        _breedSelector('Races de chiens', _allDogBreeds, _selectedDogBreeds,
            (breeds) => setState(() => _selectedDogBreeds = breeds)),
      ],
      if (_isCat) ...[
        const SizedBox(height: 12),
        _breedSelector('Races de chats', _allCatBreeds, _selectedCatBreeds,
            (breeds) => setState(() => _selectedCatBreeds = breeds)),
      ],
    ]);
  }

  Widget _speciesChip(String label, String emoji, bool active, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!active),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEEF5EA) : Colors.transparent,
          border: Border.all(
            color: active ? _green : const Color(0xFFD1D5DB),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
              color: active ? const Color(0xFF1F2A2E) : const Color(0xFF6B7280),
              fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
          if (active) ...[
            const SizedBox(width: 6),
            const Icon(Icons.check_circle, size: 15, color: _green),
          ],
        ]),
      ),
    );
  }

  Widget _breedSelector(String label, List<String> allBreeds, List<String> selected,
      ValueChanged<List<String>> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onTap: () => _openBreedPicker(label: label, allBreeds: allBreeds,
            selected: selected, onChanged: onChanged),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            const Icon(Icons.search, size: 16, color: Color(0xFF6F767B)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selected.isEmpty
                    ? 'Sélectionner des races...'
                    : '${selected.length} race${selected.length > 1 ? 's' : ''} sélectionnée${selected.length > 1 ? 's' : ''}',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF6F767B)),
          ]),
        ),
      ),
      if (selected.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6,
          children: selected.map((breed) => Chip(
            label: Text(breed, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
            backgroundColor: const Color(0xFFEEF5EA),
            side: const BorderSide(color: _green, width: 0.8),
            deleteIconColor: Colors.grey,
            onDeleted: () => onChanged(List.from(selected)..remove(breed)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          )).toList(),
        ),
      ],
    ]);
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
}

// ── Breed picker ─────────────────────────────────────────────────────────────

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
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Expanded(child: Text(widget.label,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500, fontSize: 18))),
                TextButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  child: const Text('Valider',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500,
                          color: Color(0xFF6E9E57), fontSize: 16)),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearch,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Rechercher une race...',
                  hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                ),
              ),
            ),
            if (_selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(spacing: 6, runSpacing: 4,
                  children: _selected.map((b) => Chip(
                    label: Text(b, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                    backgroundColor: const Color(0xFFEEF5EA),
                    side: const BorderSide(color: Color(0xFF6E9E57), width: 0.8),
                    deleteIconColor: Colors.black54,
                    onDeleted: () => setState(() => _selected.remove(b)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  )).toList(),
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
                    title: Text(breed, style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal)),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: Color(0xFF6E9E57), size: 20)
                        : const Icon(Icons.radio_button_unchecked, color: Colors.grey, size: 20),
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
