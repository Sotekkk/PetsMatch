import 'dart:async';
import 'dart:convert';
import 'package:PetsMatch/pages/particulier/numberadressregistration.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_webservice/places.dart';

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

  // Google Places — adresse particulier
  late final GoogleMapsPlaces _places;
  final _addressSearchCtrl = TextEditingController();
  List<Prediction> _predictions = [];
  bool _loadingPredictions = false;
  bool _locating = false;
  Timer? _searchDebounce;
  double? _lat;
  double? _lng;

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

  @override
  void initState() {
    super.initState();
    _places = GoogleMapsPlaces(apiKey: getApiKey());
    _loadUserInfo();
    _loadCountries();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _addressSearchCtrl.dispose();
    super.dispose();
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

        // Charger lat/lng depuis Supabase et pré-remplir le champ de recherche
        try {
          final rows = await Supabase.instance.client
              .from('users')
              .select('lat, lng')
              .eq('uid', user.uid)
              .maybeSingle();
          if (rows != null) {
            _lat = (rows['lat'] as num?)?.toDouble();
            _lng = (rows['lng'] as num?)?.toDouble();
          }
        } catch (_) {}
        // Pré-remplir la barre de recherche avec l'adresse existante
        final addrParts = [User_Info.rue, User_Info.codePostal, User_Info.ville]
            .where((s) => s.isNotEmpty);
        if (addrParts.isNotEmpty) {
          _addressSearchCtrl.text = addrParts.join(', ');
        }
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
      supaPayload['rue']          = _rueController.text;
      supaPayload['ville']        = _villeController.text;
      supaPayload['code_postal']  = _codePostalController.text;
      supaPayload['pays']         = _paysController.text;
      if (_lat != null) supaPayload['lat'] = _lat;
      if (_lng != null) supaPayload['lng'] = _lng;
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

  // ── Google Places autocomplete ─────────────────────────────────────────────

  void _onAddressChanged(String val) {
    _searchDebounce?.cancel();
    if (val.length < 3) {
      setState(() { _predictions = []; _loadingPredictions = false; });
      return;
    }
    setState(() => _loadingPredictions = true);
    _searchDebounce = Timer(const Duration(milliseconds: 400), () => _fetchPredictions(val));
  }

  Future<void> _fetchPredictions(String input) async {
    final res = await _places.autocomplete(
      input,
      components: [Component(Component.country, 'fr')],
      language: 'fr',
    );
    if (!mounted) return;
    setState(() {
      _predictions = res.isOkay ? res.predictions : [];
      _loadingPredictions = false;
    });
  }

  Future<void> _selectPrediction(Prediction p) async {
    _searchDebounce?.cancel();
    setState(() { _predictions = []; _addressSearchCtrl.text = p.description ?? ''; });
    if (p.placeId == null) return;

    final det = await _places.getDetailsByPlaceId(p.placeId!);
    if (!mounted || !det.isOkay) return;

    String num = '', route = '', cp = '', ville = '', pays = 'France';
    for (final c in det.result.addressComponents) {
      if (c.types.contains('street_number')) num = c.longName;
      if (c.types.contains('route')) route = c.longName;
      if (c.types.contains('postal_code')) cp = c.longName;
      if (c.types.contains('locality')) { ville = c.longName; }
      else if (c.types.contains('administrative_area_level_2') && ville.isEmpty) { ville = c.longName; }
      if (c.types.contains('country')) pays = c.longName;
    }
    final loc = det.result.geometry?.location;
    setState(() {
      _rueController.text   = [num, route].where((s) => s.isNotEmpty).join(' ');
      _codePostalController.text = cp;
      _villeController.text = ville;
      _paysController.text  = pays;
      if (loc != null) { _lat = loc.lat; _lng = loc.lng; }
    });
  }

  Future<void> _geolocate() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw Exception('Permission refusée');
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      final marks = await geo.placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isEmpty) throw Exception('Adresse introuvable');
      final m = marks.first;
      setState(() {
        _rueController.text   = m.street ?? '';
        _codePostalController.text = m.postalCode ?? '';
        _villeController.text = m.locality ?? m.subLocality ?? '';
        _paysController.text  = m.country ?? 'France';
        _lat = pos.latitude;
        _lng = pos.longitude;
        _addressSearchCtrl.text = [_rueController.text, _codePostalController.text,
            _villeController.text].where((s) => s.isNotEmpty).join(', ');
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Géolocalisation impossible : $e',
              style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
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
              _field('Prénom *', _firstnameController),
              _field('Nom *', _lastnameController),
              _dateField('Date de naissance', _dobController),
              _readOnlyField('Email', User_Info.email, Icons.email_outlined),
            ]),
            const SizedBox(height: 12),
            _card('Coordonnées', [
              if (!User_Info.isElevage && !User_Info.isPro) ...[
                _phoneField(_phoneController, 'Téléphone *', selectedCountry, _isPhoneValid,
                    (Country? c) => setState(() {
                          selectedCountry = c;
                          _selectedCountryCode = c?.dialCode ?? _selectedCountryCode;
                        })),
                const SizedBox(height: 12),
                // Barre de recherche d'adresse Google Places
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _addressSearchCtrl,
                          onChanged: _onAddressChanged,
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'Rechercher une adresse',
                            prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF6E9E57)),
                            suffixIcon: _loadingPredictions
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(width: 16, height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2,
                                            color: Color(0xFF6E9E57))))
                                : null,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none),
                            filled: true, fillColor: Colors.white,
                            labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                                color: Colors.grey),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: IconButton(
                          onPressed: _locating ? null : _geolocate,
                          tooltip: 'Ma position actuelle',
                          icon: _locating
                              ? const SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2,
                                      color: Color(0xFF6E9E57)))
                              : const Icon(Icons.my_location, color: Color(0xFF6E9E57)),
                        ),
                      ),
                    ],
                  ),
                ),
                // Suggestions Google Places
                if (_predictions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8, offset: const Offset(0, 4))],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _predictions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
                      itemBuilder: (_, i) {
                        final p = _predictions[i];
                        return ListTile(
                          leading: const Icon(Icons.location_on_outlined, size: 18,
                              color: Color(0xFF6E9E57)),
                          title: Text(p.description ?? '',
                              style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                          dense: true,
                          onTap: () => _selectPrediction(p),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                // Champs détaillés remplis automatiquement
                _field('Rue', _rueController),
                Row(children: [
                  Expanded(flex: 2, child: _fieldRaw('Ville *', _villeController)),
                  const SizedBox(width: 8),
                  Expanded(flex: 1, child: _fieldRaw('Code postal *', _codePostalController,
                      inputType: TextInputType.number)),
                ]),
                const SizedBox(height: 12),
                _field('Pays', _paysController),
              ],
              if (User_Info.isElevage || User_Info.isPro) ...[
                _field("Nom de l'élevage", _elevageNameController),
                _phoneField(_elevagePhoneController, 'Téléphone élevage *', selectedElevageCountry,
                    _isElevagePhoneValid, (Country? c) => setState(() {
                          selectedElevageCountry = c;
                          _selectedElevageCountryCode = c?.dialCode ?? _selectedElevageCountryCode;
                        })),
                const SizedBox(height: 12),
                _field('Rue', _rueElevageController),
                Row(children: [
                  Expanded(flex: 2, child: _fieldRaw('Ville *', _villeElevageController)),
                  const SizedBox(width: 8),
                  Expanded(flex: 1, child: _fieldRaw('Code postal *', _codePostalElevageController,
                      inputType: TextInputType.number)),
                ]),
                const SizedBox(height: 12),
                _field('Pays', _paysElevageController),
              ],
            ]),
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
