import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/utils/french_geo.dart';
import 'package:PetsMatch/utils/storage_helper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:PetsMatch/utils/image_pick.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class ProfilEleveurEditPage extends StatefulWidget {
  const ProfilEleveurEditPage({super.key});
  @override
  State<ProfilEleveurEditPage> createState() => _ProfilEleveurEditPageState();
}

class _ProfilEleveurEditPageState extends State<ProfilEleveurEditPage> {
  static const _green = Color(0xFF6E9E57);
  static const _teal  = Color(0xFF0C5C6C);

  // ── Controllers ──────────────────────────────────────────────────────────────
  final _prenomCtrl       = TextEditingController();
  final _nomCtrl          = TextEditingController();
  final _dobCtrl          = TextEditingController();
  final _nomElevageCtrl   = TextEditingController();
  final _telCtrl          = TextEditingController();
  final _descCtrl         = TextEditingController();
  final _addressSearchCtrl = TextEditingController();
  final _rueCtrl          = TextEditingController();
  final _cpCtrl           = TextEditingController();
  final _villeCtrl        = TextEditingController();
  final _paysCtrl         = TextEditingController(text: 'France');

  // ── State ────────────────────────────────────────────────────────────────────
  bool _saving  = false;
  bool _loading = true;
  File?   _photoFile;
  String? _photoUrl;
  File?   _bannerFile;
  String? _bannerUrl;
  DateTime? _acacedDateObtention;
  DateTime? _acacedDateRenewal;

  // Docs admin (éditables)
  final _siretCtrl  = TextEditingController();
  final _acacedCtrl = TextEditingController();
  File?   _siretDocFile;
  String? _siretDocUrl;
  File?   _acacedDocFile;
  String? _acacedDocUrl;

  // ── Places autocomplete ───────────────────────────────────────────────────────
  late final GoogleMapsPlaces _places;
  List<Prediction> _predictions = [];
  Timer? _searchDebounce;
  Timer? _cpDebounce;
  bool   _loadingPredictions = false;
  bool   _locating = false;
  double? _profileLat;
  double? _profileLng;

  // ── Espèces ───────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _especesElevees = [];
  Map<String, List<String>> _allBreeds = {};

  // ── Lifecycle ─────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _places = GoogleMapsPlaces(apiKey: getApiKey());
    _loadData();
    _loadBreeds();
    _cpCtrl.addListener(_onCpChanged);
  }

  @override
  void dispose() {
    for (final c in [_prenomCtrl, _nomCtrl, _dobCtrl, _nomElevageCtrl,
      _telCtrl, _descCtrl, _addressSearchCtrl, _rueCtrl, _cpCtrl, _villeCtrl, _paysCtrl,
      _siretCtrl, _acacedCtrl]) {
      c.dispose();
    }
    _places.dispose();
    _searchDebounce?.cancel();
    _cpDebounce?.cancel();
    super.dispose();
  }

  // ── Load ──────────────────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final d = doc.data() ?? {};

    String? bannerFromFirestore = d['bannerUrl'] as String?;

    // Fallback : si Firestore n'a pas bannerUrl, lire depuis Supabase
    if (bannerFromFirestore == null || bannerFromFirestore.isEmpty) {
      try {
        final row = await Supabase.instance.client
            .from('users').select('banner_url').eq('uid', uid).maybeSingle();
        final url = row?['banner_url'] as String?;
        if (url != null && url.isNotEmpty) bannerFromFirestore = url;
      } catch (_) {}
    }

    setState(() {
      _prenomCtrl.text     = d['firstname']       ?? User_Info.firstname;
      _nomCtrl.text        = d['lastname']         ?? User_Info.lastname;
      _dobCtrl.text        = d['dateofbirth']      ?? User_Info.dateofbirth;
      _nomElevageCtrl.text = d['nameElevage']      ?? User_Info.nameElevage;
      _telCtrl.text        = d['numeroElevage']    ?? User_Info.numeroElevage;
      _descCtrl.text       = d['desc']             ?? User_Info.desc;
      _rueCtrl.text        = d['rueElevage']       ?? User_Info.rueElevage;
      _cpCtrl.text         = d['codePostalElevage'] ?? User_Info.codePostalElevage;
      _villeCtrl.text      = d['villeElevage']     ?? User_Info.villeElevage;
      _paysCtrl.text       = (d['paysElevage'] ?? User_Info.paysElevage).isNotEmpty
          ? (d['paysElevage'] ?? User_Info.paysElevage) : 'France';
      _photoUrl   = d['profilePictureUrlElevage'] ?? User_Info.profilePictureUrlElevage;
      _bannerUrl  = bannerFromFirestore;
      _siretCtrl.text  = d['siret']  ?? User_Info.siret;
      _acacedCtrl.text = d['acaced'] ?? User_Info.acacedNumero;
      _siretDocUrl  = d['kbisUrl']     ?? User_Info.kbisUrl;
      _acacedDocUrl = d['acacedDocUrl'] ?? User_Info.acacedDocUrl;

      if (d['acacedDateObtention'] != null) {
        try { _acacedDateObtention = DateFormat('dd/MM/yyyy').parse(d['acacedDateObtention']); } catch (_) {}
      }
      if (d['acacedDateRenewal'] != null) {
        try { _acacedDateRenewal = DateFormat('dd/MM/yyyy').parse(d['acacedDateRenewal']); } catch (_) {}
      }

      // Espèces — nouveau format ou migration depuis isDog/isCat
      if (d['especesElevees'] != null) {
        _especesElevees = List<Map<String, dynamic>>.from(
            (d['especesElevees'] as List).map((e) => <String, dynamic>{
              'espece': e['espece'] ?? '',
              'races': List<String>.from(e['races'] ?? []),
            }));
      } else {
        if (d['isDog'] == true) _especesElevees.add({'espece': 'chien', 'races': List<String>.from(d['dogBreeds'] ?? [])});
        if (d['isCat'] == true) _especesElevees.add({'espece': 'chat',  'races': List<String>.from(d['catBreeds'] ?? [])});
      }

      _loading = false;
    });
  }

  Future<void> _loadBreeds() async {
    const assets = {
      'chien':  'assets/dog_breeds.json',
      'chat':   'assets/cat_breeds.json',
      'cheval': 'assets/horse_breeds.json',
      'lapin':  'assets/rabbit_breeds.json',
      'oiseau': 'assets/bird_breeds.json',
      'nac':    'assets/nac_breeds.json',
      'ovin':   'assets/sheep_breeds.json',
      'caprin': 'assets/goat_breeds.json',
      'porcin': 'assets/pig_breeds.json',
    };
    final loaded = <String, List<String>>{};
    for (final e in assets.entries) {
      try {
        final raw = await rootBundle.loadString(e.value);
        loaded[e.key] = List<String>.from(json.decode(raw));
      } catch (_) {
        loaded[e.key] = [];
      }
    }
    if (mounted) setState(() => _allBreeds = loaded);
  }

  // ── Address autocomplete ───────────────────────────────────────────────────────
  void _onAddressChanged(String val) {
    _searchDebounce?.cancel();
    if (val.length < 3) { setState(() { _predictions = []; _loadingPredictions = false; }); return; }
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
      if (c.types.contains('route'))         route = c.longName;
      if (c.types.contains('postal_code'))   cp = c.longName;
      if (c.types.contains('locality'))      ville = c.longName;
      else if (c.types.contains('administrative_area_level_2') && ville.isEmpty) ville = c.longName;
      if (c.types.contains('country')) pays = c.longName;
    }

    final loc = det.result.geometry?.location;

    setState(() {
      _rueCtrl.text   = [num, route].where((s) => s.isNotEmpty).join(' ');
      _cpCtrl.text    = cp;
      _villeCtrl.text = ville;
      _paysCtrl.text  = pays;
      if (loc != null) { _profileLat = loc.lat; _profileLng = loc.lng; }
    });
  }

  Future<void> _geolocate() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw Exception('Permission refusée');
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.medium));
      final marks =
          await geo.placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isEmpty) throw Exception('Adresse introuvable');
      final m = marks.first;
      setState(() {
        _rueCtrl.text   = m.street ?? '';
        _cpCtrl.text    = m.postalCode ?? '';
        _villeCtrl.text = m.locality ?? m.subLocality ?? '';
        _paysCtrl.text  = m.country ?? 'France';
        _addressSearchCtrl.text =
            [_rueCtrl.text, _cpCtrl.text, _villeCtrl.text]
                .where((s) => s.isNotEmpty).join(', ');
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Géolocalisation impossible : $e'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _onCpChanged() {
    final cp = _cpCtrl.text.trim();
    if (cp.length != 5 || !RegExp(r'^\d{5}$').hasMatch(cp)) return;
    if (_villeCtrl.text.isNotEmpty) return;
    _cpDebounce?.cancel();
    _cpDebounce = Timer(const Duration(milliseconds: 800), () => _lookupCityFromCp(cp));
  }

  Future<void> _lookupCityFromCp(String cp) async {
    final res = await _places.autocomplete(
      '$cp France',
      components: [Component(Component.country, 'fr')],
      language: 'fr',
      types: ['(cities)'],
    );
    if (!mounted || !res.isOkay || res.predictions.isEmpty) return;
    final firstId = res.predictions.first.placeId;
    if (firstId == null) return;
    final det = await _places.getDetailsByPlaceId(firstId);
    if (!mounted || !det.isOkay) return;
    final city = det.result.addressComponents
        .where((c) => c.types.contains('locality'))
        .firstOrNull?.longName ?? '';
    if (city.isNotEmpty && _villeCtrl.text.isEmpty) setState(() => _villeCtrl.text = city);
  }

  // ── Species helpers ────────────────────────────────────────────────────────────
  bool _hasEspece(String esp) => _especesElevees.any((e) => e['espece'] == esp);

  void _toggleEspece(String esp) {
    setState(() {
      if (_hasEspece(esp)) {
        _especesElevees.removeWhere((e) => e['espece'] == esp);
      } else {
        _especesElevees.add({'espece': esp, 'races': <String>[]});
      }
    });
  }

  List<String> _racesFor(String esp) {
    final entry = _especesElevees.firstWhere((e) => e['espece'] == esp,
        orElse: () => {'espece': esp, 'races': <String>[]});
    return List<String>.from(entry['races'] ?? []);
  }

  void _setRaces(String esp, List<String> races) {
    setState(() {
      final idx = _especesElevees.indexWhere((e) => e['espece'] == esp);
      if (idx >= 0) _especesElevees[idx]['races'] = races;
    });
  }

  // ── Photo ─────────────────────────────────────────────────────────────────────
  Future<void> _pickPhoto() async {
    final f = await pickAndCropSquare();
    if (f != null) setState(() => _photoFile = f);
  }

  // ── Propagate location to existing announcements ──────────────────────────────
  void _syncAnnoncesLocation({
    required String uid,
    required String ville,
    required String pays,
    required String departement,
    required String region,
    required String nomEleveur,
  }) {
    FirebaseFirestore.instance
        .collection('annonces')
        .where('uidEleveur', isEqualTo: uid)
        .get()
        .then((snap) {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {
          'villeEleveur':       ville,
          'paysEleveur':        pays,
          'departementEleveur': departement,
          'regionEleveur':      region,
          if (nomEleveur.isNotEmpty) 'nomEleveur': nomEleveur,
        });
      }
      batch.commit().catchError((_) {});
    }).catchError((_) {});
  }

  // ── Save ──────────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    final missing = <String>[];
    if (_prenomCtrl.text.trim().isEmpty)   missing.add('Prénom');
    if (_nomCtrl.text.trim().isEmpty)      missing.add('Nom');
    if (_dobCtrl.text.trim().isEmpty)      missing.add('Date de naissance');
    if (_nomElevageCtrl.text.trim().isEmpty) missing.add("Nom de l'élevage");
    if (_telCtrl.text.trim().isEmpty)      missing.add('Téléphone');
    if (_rueCtrl.text.trim().isEmpty)      missing.add('Rue / Voie');
    if (_cpCtrl.text.trim().isEmpty)       missing.add('Code postal');
    if (_villeCtrl.text.trim().isEmpty)    missing.add("Ville de l'élevage");
    if (_paysCtrl.text.trim().isEmpty)     missing.add('Pays');
    if (_siretCtrl.text.trim().isEmpty)    missing.add('SIRET');
    if (_siretDocFile == null && (_siretDocUrl == null || _siretDocUrl!.isEmpty))
      missing.add('Justificatif SIRET');
    if (_acacedCtrl.text.trim().isEmpty)   missing.add('N° ACACED');
    if (_acacedDateObtention == null)      missing.add("Date d'obtention ACACED");
    if (_acacedDocFile == null && (_acacedDocUrl == null || _acacedDocUrl!.isEmpty))
      missing.add('Certificat ACACED');

    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Champs obligatoires : ${missing.join(', ')}'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      String? photoUrl = _photoUrl;
      if (_photoFile != null) {
        photoUrl = await uploadPhoto(_photoFile!, 'profiles/$uid/photo.jpg');
      }

      String? bannerUrl = _bannerUrl;
      if (_bannerFile != null) {
        bannerUrl = await uploadPhoto(_bannerFile!, 'profiles/$uid/banner.jpg');
      }

      // Upload document SIRET
      String? siretDocUrl = _siretDocUrl;
      if (_siretDocFile != null) {
        siretDocUrl = await uploadPhoto(_siretDocFile!, 'profiles/$uid/kbis.jpg');
        setState(() => _siretDocUrl = siretDocUrl);
      }
      // Upload document ACACED
      String? acacedDocUrl = _acacedDocUrl;
      if (_acacedDocFile != null) {
        acacedDocUrl = await uploadPhoto(_acacedDocFile!, 'profiles/$uid/acaced.jpg');
        setState(() => _acacedDocUrl = acacedDocUrl);
      }

      final isDog = _hasEspece('chien');
      final isCat = _hasEspece('chat');

      final adresseFull = [_rueCtrl.text.trim(), _cpCtrl.text.trim(), _villeCtrl.text.trim()]
          .where((s) => s.isNotEmpty).join(', ');

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'firstname':          _prenomCtrl.text.trim(),
        'lastname':           _nomCtrl.text.trim(),
        'dateofbirth':        _dobCtrl.text.trim(),
        'nameElevage':        _nomElevageCtrl.text.trim(),
        'numeroElevage':      _telCtrl.text.trim(),
        'desc':               _descCtrl.text.trim(),
        'rueElevage':         _rueCtrl.text.trim(),
        'codePostalElevage':  _cpCtrl.text.trim(),
        'villeElevage':       _villeCtrl.text.trim(),
        'paysElevage':        _paysCtrl.text.trim(),
        'adressElevage':      adresseFull,
        'city':               _villeCtrl.text.trim(),
        if (_profileLat != null) 'lat': _profileLat,
        if (_profileLng != null) 'lng': _profileLng,
        ...() {
          final geo = FrenchGeo.fromPostalCode(_cpCtrl.text.trim());
          return {
            'departementElevage': geo?.departement ?? '',
            'regionElevage': geo?.region ?? '',
          };
        }(),
        'especesElevees':     _especesElevees,
        'isDog':              isDog,
        'isCat':              isCat,
        'dogBreeds':          isDog ? _racesFor('chien') : [],
        'catBreeds':          isCat ? _racesFor('chat')  : [],
        if (photoUrl != null) 'profilePictureUrlElevage': photoUrl,
        if (bannerUrl != null) 'bannerUrl': bannerUrl,
        'siret': _siretCtrl.text.trim(),
        'acaced': _acacedCtrl.text.trim(),
        if (siretDocUrl != null && siretDocUrl.isNotEmpty) 'kbisUrl': siretDocUrl,
        if (acacedDocUrl != null && acacedDocUrl.isNotEmpty) 'acacedDocUrl': acacedDocUrl,
        if (_acacedDateObtention != null)
          'acacedDateObtention': DateFormat('dd/MM/yyyy').format(_acacedDateObtention!),
        if (_acacedDateRenewal != null)
          'acacedDateRenewal': DateFormat('dd/MM/yyyy').format(_acacedDateRenewal!),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Sync User_Info
      User_Info.firstname     = _prenomCtrl.text.trim();
      User_Info.lastname      = _nomCtrl.text.trim();
      User_Info.nameElevage   = _nomElevageCtrl.text.trim();
      User_Info.numeroElevage = _telCtrl.text.trim();
      User_Info.rueElevage    = _rueCtrl.text.trim();
      User_Info.codePostalElevage = _cpCtrl.text.trim();
      User_Info.villeElevage  = _villeCtrl.text.trim();
      User_Info.paysElevage   = _paysCtrl.text.trim();
      final geoSync = FrenchGeo.fromPostalCode(_cpCtrl.text.trim());
      User_Info.departementElevage = geoSync?.departement ?? '';
      User_Info.regionElevage      = geoSync?.region      ?? '';
      User_Info.isDog = isDog;
      User_Info.isCat = isCat;
      User_Info.dogBreeds = isDog ? _racesFor('chien') : [];
      User_Info.catBreeds = isCat ? _racesFor('chat')  : [];
      if (photoUrl != null) User_Info.profilePictureUrlElevage = photoUrl;
      if (bannerUrl != null) setState(() => _bannerUrl = bannerUrl);

      // Sync address + geo to Supabase users table
      try {
        final supa = Supabase.instance.client;
        await supa.from('users').upsert({
          'uid': uid,
          'firstname':           _prenomCtrl.text.trim(),
          'lastname':            _nomCtrl.text.trim(),
          'name_elevage':        _nomElevageCtrl.text.trim(),
          'rue_elevage':         _rueCtrl.text.trim(),
          'code_postal_elevage': _cpCtrl.text.trim(),
          'ville_elevage':       _villeCtrl.text.trim(),
          'pays_elevage':        _paysCtrl.text.trim(),
          'adress_elevage':      adresseFull,
          if (_profileLat != null) 'lat': _profileLat,
          if (_profileLng != null) 'lng': _profileLng,
          if (photoUrl != null) 'profile_picture_url_elevage': photoUrl,
          if (bannerUrl != null) 'banner_url': bannerUrl,
          'siret': _siretCtrl.text.trim(),
          'acaced': _acacedCtrl.text.trim(),
          if (siretDocUrl != null && siretDocUrl.isNotEmpty) 'kbis_url': siretDocUrl,
          if (acacedDocUrl != null && acacedDocUrl.isNotEmpty) 'acaced_doc_url': acacedDocUrl,
        }, onConflict: 'uid');
      } catch (_) {}

      // Propagate location fields to all existing announcements
      _syncAnnoncesLocation(
        uid: uid,
        ville:       _villeCtrl.text.trim(),
        pays:        _paysCtrl.text.trim(),
        departement: geoSync?.departement ?? '',
        region:      geoSync?.region      ?? '',
        nomEleveur:  _nomElevageCtrl.text.trim(),
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── ACACED helpers ────────────────────────────────────────────────────────────
  DateTime? get _acacedExpiration {
    final base = _acacedDateRenewal ?? _acacedDateObtention;
    if (base == null) return null;
    return DateTime(base.year + 10, base.month, base.day);
  }

  Color get _acacedStatusColor {
    final exp = _acacedExpiration;
    if (exp == null) return Colors.grey;
    final now = DateTime.now();
    if (exp.isBefore(now)) return Colors.red;
    if (exp.difference(now).inDays < 180) return Colors.orange;
    return _green;
  }

  String get _acacedStatusLabel {
    final exp = _acacedExpiration;
    if (exp == null) return 'Date d\'obtention non renseignée';
    final now = DateTime.now();
    if (exp.isBefore(now)) return 'ACACED expiré — renouvellement requis';
    final days = exp.difference(now).inDays;
    if (days < 180) return 'Expire dans $days jours (${DateFormat('dd/MM/yyyy').format(exp)})';
    return 'Valide jusqu\'au ${DateFormat('dd/MM/yyyy').format(exp)}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        title: const Text('Mon profil éleveur',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_saving)
            const Center(child: Padding(padding: EdgeInsets.only(right: 16),
                child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))))
          else
            TextButton(
              onPressed: _save,
              child: const Text('Enregistrer',
                  style: TextStyle(color: Colors.white, fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _photoSection(),
                  const SizedBox(height: 16),
                  _card('Identité', [
                    _field('Prénom', _prenomCtrl),
                    _field('Nom', _nomCtrl),
                    _dateRow('Date de naissance', _dobCtrl),
                    _readOnly('Email', User_Info.email, Icons.email_outlined),
                  ]),
                  const SizedBox(height: 12),
                  _card('Élevage', [
                    _field('Nom de l\'élevage *', _nomElevageCtrl),
                    _field('Téléphone élevage', _telCtrl, inputType: TextInputType.phone),
                    _field('Description / présentation', _descCtrl, maxLines: 3),
                  ]),
                  const SizedBox(height: 12),
                  _addressCard(),
                  const SizedBox(height: 12),
                  _especesCard(),
                  const SizedBox(height: 12),
                  _administratifCard(),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  // ── Photos (bannière + profil) ────────────────────────────────────────────────
  Widget _photoSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Bannière
        GestureDetector(
          onTap: _pickBanner,
          child: Stack(children: [
            SizedBox(
              width: double.infinity,
              height: 130,
              child: _bannerFile != null
                  ? Image.file(_bannerFile!, fit: BoxFit.cover)
                  : (_bannerUrl != null
                      ? CachedNetworkImage(imageUrl: _bannerUrl!, fit: BoxFit.cover)
                      : Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF0C5C6C), Color(0xFF6E9E57)],
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Center(child: Icon(Icons.landscape, size: 40, color: Colors.white38)),
                        )),
            ),
            Positioned(
              right: 8, bottom: 8,
              child: CircleAvatar(
                radius: 14, backgroundColor: Colors.black45,
                child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
              ),
            ),
            const Positioned(
              left: 8, bottom: 8,
              child: Text('Bannière', style: TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'Galey')),
            ),
          ]),
        ),
        // Photo profil
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(children: [
            Transform.translate(
              offset: const Offset(0, -24),
              child: GestureDetector(
                onTap: _pickPhoto,
                child: Stack(children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
                    ),
                    child: ClipOval(
                      child: _photoFile != null
                          ? Image.file(_photoFile!, fit: BoxFit.cover)
                          : (_photoUrl != null
                              ? CachedNetworkImage(imageUrl: _photoUrl!, fit: BoxFit.cover)
                              : Container(color: const Color(0xFFEEF5EA),
                                  child: const Icon(Icons.store_outlined, size: 30, color: Color(0xFF6E9E57)))),
                    ),
                  ),
                  Positioned(
                    bottom: 2, right: 2,
                    child: CircleAvatar(radius: 12, backgroundColor: _green,
                        child: const Icon(Icons.camera_alt, size: 12, color: Colors.white)),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Photo de profil\n(visible sur votre fiche)',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
            ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _pickBanner() async {
    final file = await pickAndCropBanner();
    if (file != null) setState(() => _bannerFile = file);
  }

  // ── Adresse ───────────────────────────────────────────────────────────────────
  Widget _addressCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Adresse de l\'élevage',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1F2A2E))),
            TextButton.icon(
              onPressed: _locating ? null : _geolocate,
              icon: _locating
                  ? const SizedBox(width: 13, height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0C5C6C)))
                  : const Icon(Icons.my_location, size: 14, color: Color(0xFF0C5C6C)),
              label: const Text('Ma position',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF0C5C6C))),
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Search field
        TextFormField(
          controller: _addressSearchCtrl,
          onChanged: _onAddressChanged,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Rechercher une adresse…',
            labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
            prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF6E9E57)),
            suffixIcon: _loadingPredictions
                ? const Padding(padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6E9E57))))
                : (_predictions.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => setState(() { _predictions = []; _addressSearchCtrl.clear(); }))
                    : null),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57), width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
        ),

        // Suggestions dropdown
        if (_predictions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 4))],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _predictions.length > 5 ? 5 : _predictions.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 40),
              itemBuilder: (_, i) {
                final p = _predictions[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.location_on_outlined, size: 18, color: Color(0xFF0C5C6C)),
                  title: Text(p.description ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                  onTap: () => _selectPrediction(p),
                );
              },
            ),
          ),

        const SizedBox(height: 12),
        _inlineField('Rue / Voie *', _rueCtrl),
        const SizedBox(height: 10),
        Row(children: [
          SizedBox(width: 110, child: _inlineField('Code postal *', _cpCtrl, inputType: TextInputType.number)),
          const SizedBox(width: 10),
          Expanded(child: _inlineField('Ville *', _villeCtrl)),
        ]),
        const SizedBox(height: 10),
        _inlineField('Pays *', _paysCtrl),
      ]),
    );
  }

  // ── Espèces ───────────────────────────────────────────────────────────────────
  Widget _especesCard() {
    final speciesList = kSpeciesData.where((s) => s.value != 'tous').toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Espèces élevées',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1F2A2E))),
        const SizedBox(height: 12),

        // Species chips
        Wrap(spacing: 8, runSpacing: 8, children: speciesList.map((sp) {
          final active = _hasEspece(sp.value);
          return GestureDetector(
            onTap: () => _toggleEspece(sp.value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: active ? sp.color : Colors.transparent,
                border: Border.all(color: active ? sp.color : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                speciesIcon(sp.value, 13, active ? Colors.white : sp.color),
                const SizedBox(width: 6),
                Text(sp.label, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                    color: active ? Colors.white : Colors.black87,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
              ]),
            ),
          );
        }).toList()),

        // Races per selected species
        ..._especesElevees.map((entry) {
          final espece = entry['espece'] as String;
          final races  = List<String>.from(entry['races'] ?? []);
          final color  = speciesColor(espece);
          final allBreeds = List<String>.from(_allBreeds[espece] ?? []);
          if (!allBreeds.contains('Autre')) allBreeds.add('Autre');
          final hasBreedsDB = allBreeds.isNotEmpty;

          return Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                speciesIcon(espece, 14, color),
                const SizedBox(width: 6),
                Text(speciesLabel(espece),
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                        fontSize: 13, color: color)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _openRacePicker(espece, races, hasBreedsDB, allBreeds),
                  icon: const Icon(Icons.add, size: 14, color: Color(0xFF6E9E57)),
                  label: const Text('Races', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6E9E57))),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                ),
              ]),
              if (races.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: races.map((r) => Chip(
                  label: Text(r, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  backgroundColor: color.withOpacity(0.1),
                  side: BorderSide(color: color.withOpacity(0.3)),
                  deleteIconColor: color,
                  onDeleted: () => _setRaces(espece, races..remove(r)),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                )).toList()),
              ] else
                Text('Aucune race renseignée',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400)),
            ]),
          );
        }),
      ]),
    );
  }

  Future<void> _openRacePicker(String espece, List<String> current,
      bool hasBreedsDB, List<String> allBreeds) async {
    if (hasBreedsDB) {
      final result = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => _BreedPickerSheet(
          label: 'Races — ${speciesLabel(espece)}',
          allBreeds: allBreeds,
          initialSelected: List.from(current),
        ),
      );
      if (result != null) _setRaces(espece, result);
    } else {
      // Free text input for other species
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Ajouter une race — ${speciesLabel(espece)}',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
          content: TextField(controller: ctrl, autofocus: true,
              style: const TextStyle(fontFamily: 'Galey'),
              decoration: const InputDecoration(hintText: 'Nom de la race')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Ajouter', style: TextStyle(color: Color(0xFF6E9E57), fontWeight: FontWeight.w600))),
          ],
        ),
      );
      final text = ctrl.text.trim();
      ctrl.dispose();
      if (ok == true && text.isNotEmpty && !current.contains(text)) {
        _setRaces(espece, [...current, text]);
      }
    }
  }

  Future<void> _pickDoc(bool isSiret) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked != null) {
      final f = File(picked.path);
      setState(() { if (isSiret) _siretDocFile = f; else _acacedDocFile = f; });
    }
  }

  // ── Administratif ─────────────────────────────────────────────────────────────
  Widget _administratifCard() {
    final statusColor = _acacedStatusColor;

    Widget docRow({
      required String label,
      required File? docFile,
      required String? docUrl,
      required VoidCallback onPick,
    }) {
      final hasDoc = docFile != null || (docUrl != null && docUrl.isNotEmpty);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$label *',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF555555))),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onPick,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: hasDoc ? const Color(0xFFEEF5EA) : const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasDoc ? const Color(0xFF6E9E57) : Colors.grey.shade300,
                style: hasDoc ? BorderStyle.solid : BorderStyle.none,
              ),
            ),
            child: Row(children: [
              Icon(
                hasDoc ? Icons.check_circle_outline : Icons.attach_file_outlined,
                size: 16,
                color: hasDoc ? const Color(0xFF6E9E57) : Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(
                docFile != null
                    ? docFile.path.split('/').last
                    : (hasDoc ? 'Document enregistré' : 'Joindre un document (photo ou PDF)'),
                style: TextStyle(
                    fontFamily: 'Galey', fontSize: 12,
                    color: hasDoc ? const Color(0xFF1F2A2E) : Colors.grey),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              )),
              if (hasDoc)
                Text('Changer', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF0C5C6C))),
            ]),
          ),
        ),
      ]);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Informations administratives *',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1F2A2E))),
        const SizedBox(height: 14),

        // SIRET
        _field('SIRET *', _siretCtrl, inputType: TextInputType.number),
        const SizedBox(height: 10),
        docRow(
          label: 'Justificatif SIRET (KBIS)',
          docFile: _siretDocFile,
          docUrl: _siretDocUrl,
          onPick: () => _pickDoc(true),
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),

        // ACACED
        _field('N° ACACED *', _acacedCtrl),
        const SizedBox(height: 10),
        _datePicker(
          label: 'Date d\'obtention ACACED *',
          value: _acacedDateObtention,
          onPicked: (d) => setState(() { _acacedDateObtention = d; _acacedDateRenewal = null; }),
        ),
        const SizedBox(height: 10),
        _datePicker(
          label: 'Date de renouvellement (si applicable)',
          value: _acacedDateRenewal,
          onPicked: (d) => setState(() => _acacedDateRenewal = d),
          clearable: true,
          onClear: () => setState(() => _acacedDateRenewal = null),
        ),
        const SizedBox(height: 10),
        docRow(
          label: 'Certificat ACACED',
          docFile: _acacedDocFile,
          docUrl: _acacedDocUrl,
          onPick: () => _pickDoc(false),
        ),

        // Status ACACED
        if (_acacedExpiration != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: statusColor.withOpacity(0.3)),
            ),
            child: Row(children: [
              Icon(
                _acacedExpiration!.isBefore(DateTime.now()) ? Icons.error_outline : Icons.verified_outlined,
                size: 16, color: statusColor,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(_acacedStatusLabel,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      color: statusColor, fontWeight: FontWeight.w600))),
            ]),
          ),
        ],
      ]),
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────────────────
  Widget _card(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
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
      {int maxLines = 1, TextInputType? inputType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl, maxLines: maxLines, keyboardType: inputType,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57), width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      ),
    );
  }

  Widget _inlineField(String label, TextEditingController ctrl, {TextInputType? inputType}) {
    return TextFormField(
      controller: ctrl, keyboardType: inputType,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
    );
  }

  Widget _readOnly(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE4E7E2)),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: Colors.grey.shade400),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B))),
          Text(value, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E))),
        ])),
        Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade400),
      ]),
    );
  }

  Widget _dateRow(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: DateTime.tryParse(ctrl.text) ?? DateTime.now(),
            firstDate: DateTime(1900), lastDate: DateTime.now(),
            builder: (ctx, child) => Theme(
              data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF6E9E57))),
              child: child!,
            ),
          );
          if (picked != null) ctrl.text = DateFormat('dd/MM/yyyy').format(picked);
        },
        child: AbsorbPointer(
          child: TextFormField(
            controller: ctrl,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
              suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF6E9E57)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57), width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
          ),
        ),
      ),
    );
  }

  Widget _datePicker({
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime> onPicked,
    bool clearable = false,
    VoidCallback? onClear,
  }) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2000), lastDate: DateTime(2060),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF6E9E57))),
            child: child!,
          ),
        );
        if (picked != null) onPicked(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
          suffixIcon: clearable && value != null
              ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: onClear, padding: EdgeInsets.zero)
              : const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF6E9E57)),
        ),
        child: Text(
          value != null ? DateFormat('dd/MM/yyyy').format(value) : 'Sélectionner',
          style: TextStyle(fontFamily: 'Galey', fontSize: 13,
              color: value != null ? const Color(0xFF1F2A2E) : Colors.grey),
        ),
      ),
    );
  }
}

// ─── Breed picker (réutilisable) ──────────────────────────────────────────────

class _BreedPickerSheet extends StatefulWidget {
  final String label;
  final List<String> allBreeds;
  final List<String> initialSelected;
  const _BreedPickerSheet({required this.label, required this.allBreeds, required this.initialSelected});
  @override
  State<_BreedPickerSheet> createState() => _BreedPickerSheetState();
}

class _BreedPickerSheetState extends State<_BreedPickerSheet> {
  late List<String> _selected;
  late List<String> _filtered;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.initialSelected);
    _filtered = List.from(widget.allBreeds);
  }

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  void _onSearch(String q) => setState(() {
    _filtered = q.isEmpty ? widget.allBreeds
        : widget.allBreeds.where((b) => b.toLowerCase().contains(q.toLowerCase())).toList();
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.4,
      builder: (_, scroll) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(
              color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Expanded(child: Text(widget.label,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16))),
              TextButton(
                onPressed: () => Navigator.pop(context, _selected),
                child: const Text('Valider',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                        color: Color(0xFF6E9E57), fontSize: 15)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search, onChanged: _onSearch,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Rechercher…',
                hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 18),
                filled: true, fillColor: Colors.grey.shade100,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              ),
            ),
          ),
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(spacing: 6, runSpacing: 4, children: _selected.map((b) => Chip(
                label: Text(b, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                backgroundColor: const Color(0xFFEEF5EA),
                side: const BorderSide(color: Color(0xFF6E9E57)),
                deleteIconColor: Colors.black54,
                onDeleted: () => setState(() => _selected.remove(b)),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )).toList()),
            ),
          const Divider(height: 1),
          Expanded(child: ListView.builder(
            controller: scroll,
            itemCount: _filtered.length,
            itemBuilder: (_, i) {
              final b = _filtered[i];
              final sel = _selected.contains(b);
              return ListTile(
                dense: true,
                title: Text(b, style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
                trailing: Icon(sel ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: sel ? const Color(0xFF6E9E57) : Colors.grey, size: 20),
                onTap: () => setState(() => sel ? _selected.remove(b) : _selected.add(b)),
              );
            },
          )),
        ]),
      ),
    );
  }
}
