import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:PetsMatch/utils/storage_helper.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:PetsMatch/utils/image_pick.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:PetsMatch/main.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AnimalTrouveFormPage extends StatefulWidget {
  final String? knownOwnerUid;
  final String? initialPuce;
  final String? initialEspece;
  final Map<String, dynamic>? existing;
  const AnimalTrouveFormPage({super.key, this.knownOwnerUid, this.initialPuce, this.initialEspece, this.existing});

  @override
  State<AnimalTrouveFormPage> createState() => _AnimalTrouveFormPageState();
}

class _AnimalTrouveFormPageState extends State<AnimalTrouveFormPage> {
  static const _teal   = Color(0xFF0C5C6C);
  static const _tealBg = Color(0xFFE8F4F6);

  final _supa = Supabase.instance.client;
  late final GoogleMapsPlaces _places;
  Timer? _searchDebounce;

  final _couleurCtrl        = TextEditingController();
  final _puceCtrl           = TextEditingController();
  final _etatSanteCtrl      = TextEditingController();
  final _comportementCtrl   = TextEditingController();
  final _descCtrl           = TextEditingController();
  final _addressSearchCtrl  = TextEditingController();
  final _rueCtrl            = TextEditingController();
  final _villeCtrl          = TextEditingController();
  final _cpCtrl             = TextEditingController();
  final _paysCtrl           = TextEditingController(text: 'France');
  final _regionCtrl         = TextEditingController();
  final _deptCtrl           = TextEditingController();
  final _raceCtrl           = TextEditingController();
  final _contactEmailCtrl   = TextEditingController();
  final _contactTelCtrl     = TextEditingController();

  String   _espece    = 'chien';
  String?  _sexe;
  String?  _taille;
  DateTime _dateTrouve = DateTime.now();
  bool     _contactMessagerie = true;
  bool     _saving    = false;
  bool     _locating  = false;
  double?  _lat;
  double?  _lng;

  List<Prediction> _predictions = [];
  bool _loadingPredictions = false;

  List<File>   _imageFiles = [];
  List<String> _existingPhotos = [];

  List<String> _breeds = [];
  List<String> _breedSuggestions = [];
  bool         _showBreedSuggestions = false;
  final _raceFocusNode = FocusNode();

  static const _especes = [
    'chien', 'chat', 'lapin', 'oiseau', 'nac',
    'cheval', 'ovin', 'caprin', 'porcin', 'autre',
  ];

  static const _breedFiles = {
    'chien':  'dog_breeds',
    'chat':   'cat_breeds',
    'cheval': 'horse_breeds',
    'lapin':  'rabbit_breeds',
    'oiseau': 'bird_breeds',
    'nac':    'nac_breeds',
    'ovin':   'sheep_breeds',
    'caprin': 'goat_breeds',
    'porcin': 'pig_breeds',
  };

  @override
  void initState() {
    super.initState();
    _places = GoogleMapsPlaces(apiKey: getApiKey());
    _contactEmailCtrl.text = FirebaseAuth.instance.currentUser?.email ?? '';
    _raceFocusNode.addListener(() {
      if (!_raceFocusNode.hasFocus) setState(() => _showBreedSuggestions = false);
    });
    if (widget.existing != null) {
      final e = widget.existing!;
      _espece = (_especes.contains(e['espece']) ? e['espece'] : 'chien') as String;
      _sexe   = e['sexe'] as String?;
      _taille = e['taille'] as String?;
      _contactMessagerie = e['contact_messagerie'] as bool? ?? true;
      _lat    = (e['lat'] as num?)?.toDouble();
      _lng    = (e['lng'] as num?)?.toDouble();
      _raceCtrl.text         = e['race'] ?? '';
      _couleurCtrl.text      = e['couleur'] ?? '';
      _puceCtrl.text         = e['numero_puce'] ?? '';
      _etatSanteCtrl.text    = e['etat_sante'] ?? '';
      _comportementCtrl.text = e['comportement'] ?? '';
      _descCtrl.text         = e['description'] ?? '';
      _villeCtrl.text        = e['localisation_ville'] ?? '';
      _cpCtrl.text           = e['localisation_code_postal'] ?? '';
      _paysCtrl.text         = e['pays'] ?? 'France';
      _regionCtrl.text       = e['region'] ?? '';
      _deptCtrl.text         = e['departement'] ?? '';
      _contactEmailCtrl.text = e['contact_email'] ?? '';
      _contactTelCtrl.text   = e['contact_telephone'] ?? '';
      _existingPhotos        = List<String>.from(e['photos'] ?? []);
      _addressSearchCtrl.text = e['localisation_adresse'] ?? '';
      if (e['date_trouve'] != null) {
        _dateTrouve = DateTime.tryParse(e['date_trouve'] as String) ?? DateTime.now();
      }
    } else {
      if (widget.initialPuce != null) _puceCtrl.text = widget.initialPuce!;
      if (widget.initialEspece != null && _especes.contains(widget.initialEspece)) {
        _espece = widget.initialEspece!;
      }
    }
    _loadBreeds(_espece);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _raceFocusNode.dispose();
    _places.dispose();
    for (final c in [_couleurCtrl, _puceCtrl, _etatSanteCtrl, _comportementCtrl,
                     _descCtrl, _addressSearchCtrl, _rueCtrl, _villeCtrl, _cpCtrl,
                     _paysCtrl, _regionCtrl, _deptCtrl, _raceCtrl, _contactEmailCtrl, _contactTelCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Breeds ───────────────────────────────────────────────────────────────────

  Future<void> _loadBreeds(String espece) async {
    final file = _breedFiles[espece];
    if (file == null) { setState(() { _breeds = []; _breedSuggestions = []; }); return; }
    try {
      final raw  = await rootBundle.loadString('assets/$file.json');
      final list = List<String>.from(json.decode(raw) as List);
      if (mounted) setState(() { _breeds = list; _breedSuggestions = []; });
    } catch (_) {
      if (mounted) setState(() { _breeds = []; _breedSuggestions = []; });
    }
  }

  void _onRaceChanged(String val) {
    if (val.isEmpty) {
      setState(() { _breedSuggestions = []; _showBreedSuggestions = false; });
      return;
    }
    final q = val.toLowerCase();
    final matches = _breeds.where((b) => b.toLowerCase().contains(q)).take(6).toList();
    setState(() { _breedSuggestions = matches; _showBreedSuggestions = matches.isNotEmpty; });
  }

  // ── Photos ────────────────────────────────────────────────────────────────────

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Ajouter une photo',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: _tealBg,
            leading: Container(width: 44, height: 44,
              decoration: BoxDecoration(color: const Color(0xFFB2DDE4), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.camera_alt_outlined, color: _teal)),
            title: const Text('Prendre une photo', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            subtitle: const Text('Ouvrir la caméra', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          const SizedBox(height: 10),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: _tealBg,
            leading: Container(width: 44, height: 44,
              decoration: BoxDecoration(color: const Color(0xFFB2DDE4), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.photo_library_outlined, color: _teal)),
            title: const Text('Choisir depuis la galerie', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            subtitle: const Text('Sélectionner depuis la galerie', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final f = await pickAndCropSquare(source: source);
    if (f != null && mounted) setState(() => _imageFiles.add(f));
  }

  Future<List<String>> _uploadPhotos() async {
    final urls = List<String>.from(_existingPhotos);
    for (final file in _imageFiles) {
      try {
        final name = '${DateTime.now().millisecondsSinceEpoch}_${urls.length}.jpg';
        final url = await uploadPhoto(file, 'animaux_trouves/$name');
        urls.add(url);
      } catch (_) {}
    }
    return urls;
  }

  // ── Address ───────────────────────────────────────────────────────────────────

  void _onAddressChanged(String val) {
    _lat = null; _lng = null;
    _searchDebounce?.cancel();
    if (val.trim().length < 3) {
      setState(() { _predictions = []; _loadingPredictions = false; });
      return;
    }
    setState(() => _loadingPredictions = true);
    _searchDebounce = Timer(const Duration(milliseconds: 450), () => _fetchPredictions(val));
  }

  Future<void> _fetchPredictions(String input) async {
    try {
      final res = await _places.autocomplete(input,
        components: [Component(Component.country, 'fr'), Component(Component.country, 'be'),
                     Component(Component.country, 'ch'), Component(Component.country, 'lu')],
        language: 'fr',
      );
      if (!mounted) return;
      setState(() { _predictions = res.isOkay ? res.predictions : []; _loadingPredictions = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingPredictions = false);
    }
  }

  Future<void> _selectPrediction(Prediction p) async {
    setState(() { _predictions = []; _addressSearchCtrl.text = p.description ?? ''; });
    if (p.placeId == null) return;
    try {
      final det = await _places.getDetailsByPlaceId(p.placeId!, language: 'fr');
      if (!mounted || !det.isOkay) return;
      String num = '', route = '', cp = '', ville = '', pays = '', region = '', dept = '';
      for (final c in det.result.addressComponents) {
        if (c.types.contains('street_number'))            num    = c.longName;
        if (c.types.contains('route'))                    route  = c.longName;
        if (c.types.contains('postal_code'))              cp     = c.longName;
        if (c.types.contains('locality'))                 ville  = c.longName;
        if (c.types.contains('administrative_area_level_2')) dept = c.longName;
        if (c.types.contains('administrative_area_level_1')) region = c.longName;
        if (c.types.contains('country'))                  pays   = c.longName;
      }
      final rue = [num, route].where((s) => s.isNotEmpty).join(' ');
      final adresse = det.result.formattedAddress ?? p.description ?? '';
      final loc = det.result.geometry?.location;
      setState(() {
        _rueCtrl.text   = rue;
        _cpCtrl.text    = cp;
        _villeCtrl.text = ville.isNotEmpty ? ville : dept;
        if (pays.isNotEmpty)   _paysCtrl.text   = pays;
        if (region.isNotEmpty) _regionCtrl.text = region;
        if (dept.isNotEmpty)   _deptCtrl.text   = dept;
        _addressSearchCtrl.text = adresse;
        if (loc != null) { _lat = loc.lat; _lng = loc.lng; }
      });
    } catch (_) {}
  }

  Future<void> _geolocate() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw Exception('Permission refusée');
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      _lat = pos.latitude; _lng = pos.longitude;
      final marks = await geo.placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isEmpty) throw Exception('Adresse introuvable');
      final m = marks.first;
      setState(() {
        _rueCtrl.text   = m.street ?? '';
        _cpCtrl.text    = m.postalCode ?? '';
        _villeCtrl.text = m.locality ?? m.subLocality ?? '';
        if ((m.country ?? '').isNotEmpty)            _paysCtrl.text   = m.country!;
        if ((m.administrativeArea ?? '').isNotEmpty) _regionCtrl.text = m.administrativeArea!;
        _addressSearchCtrl.text =
            [_rueCtrl.text, _cpCtrl.text, _villeCtrl.text].where((s) => s.isNotEmpty).join(', ');
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Géolocalisation impossible : $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // ── Submit ────────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final errors = <String>[];
    if (_espece.isEmpty)                errors.add('Espèce');
    if (_villeCtrl.text.trim().isEmpty) errors.add('Ville de découverte');
    final totalPhotos = _imageFiles.length + _existingPhotos.length;
    if (totalPhotos == 0)               errors.add('Au moins une photo');
    final email = _contactEmailCtrl.text.trim();
    final tel   = _contactTelCtrl.text.trim();
    if (email.isEmpty && tel.isEmpty && !_contactMessagerie) {
      errors.add('Au moins un moyen de contact');
    }
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      errors.add('Email invalide');
    }

    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Champs requis : ${errors.join(' · ')}'),
          backgroundColor: Colors.red, duration: const Duration(seconds: 4)));
      return;
    }

    setState(() => _saving = true);
    try {
      final photos = await _uploadPhotos();
      final payload = {
        'espece':                   _espece,
        'race':                     _raceCtrl.text.trim().isEmpty ? null : _raceCtrl.text.trim(),
        'sexe':                     _sexe,
        'couleur':                  _couleurCtrl.text.trim().isEmpty ? null : _couleurCtrl.text.trim(),
        'taille':                   _taille,
        'numero_puce':              _puceCtrl.text.trim().isEmpty ? null : _puceCtrl.text.trim(),
        'date_trouve':              DateFormat('yyyy-MM-dd').format(_dateTrouve),
        'etat_sante':               _etatSanteCtrl.text.trim().isEmpty ? null : _etatSanteCtrl.text.trim(),
        'comportement':             _comportementCtrl.text.trim().isEmpty ? null : _comportementCtrl.text.trim(),
        'description':              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'localisation_ville':       _villeCtrl.text.trim(),
        'localisation_code_postal': _cpCtrl.text.trim().isEmpty ? null : _cpCtrl.text.trim(),
        'localisation_adresse':     [_rueCtrl.text.trim(), _cpCtrl.text.trim(), _villeCtrl.text.trim()]
            .where((s) => s.isNotEmpty).join(', ').isNotEmpty
            ? [_rueCtrl.text.trim(), _cpCtrl.text.trim(), _villeCtrl.text.trim()]
                .where((s) => s.isNotEmpty).join(', ')
            : null,
        'pays':                     _paysCtrl.text.trim().isEmpty ? 'France' : _paysCtrl.text.trim(),
        'region':                   _regionCtrl.text.trim().isEmpty ? null : _regionCtrl.text.trim(),
        'departement':              _deptCtrl.text.trim().isEmpty ? null : _deptCtrl.text.trim(),
        'lat':                      _lat,
        'lng':                      _lng,
        'photos':                   photos,
        'contact_email':            email.isEmpty ? null : email,
        'contact_telephone':        tel.isEmpty ? null : tel,
        'contact_messagerie':       _contactMessagerie,
      };

      if (widget.existing != null) {
        await _supa.from('animaux_trouves').update(payload).eq('id', widget.existing!['id']);
      } else {
        final inserted = await _supa.from('animaux_trouves').insert({
          ...payload,
          'user_uid': User_Info.uid,
          'statut':   'trouve',
        }).select('id').single();

        // Notify nearby owners of lost animals (fire-and-forget)
        if (_lat != null && _lng != null) {
          try {
            FirebaseFunctions.instanceFor(region: 'europe-west1')
                .httpsCallable('notifyNearFoundAnimal')
                .call({
                  'lat':          _lat,
                  'lng':          _lng,
                  'espece':       _espece,
                  'trouveId':     inserted['id'] ?? '',
                  'declarantUid': User_Info.uid,
                });
          } catch (_) {}
        }

        // Notify the known owner directly if chip was pre-identified (fire-and-forget)
        if (widget.knownOwnerUid != null) {
          try {
            FirebaseFunctions.instanceFor(region: 'europe-west1')
                .httpsCallable('notifyAnimalOwner')
                .call({
                  'ownerUid': widget.knownOwnerUid,
                  'trouveId': inserted['id'] ?? '',
                  'espece':   _espece,
                });
          } catch (_) {}
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(widget.existing != null ? 'Déclaration mise à jour ✓' : 'Déclaration publiée ✓'),
            backgroundColor: const Color(0xFF6E9E57)));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.existing != null ? 'Modifier ma déclaration' : 'Déclarer un animal trouvé',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 24, 16,
            24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Bannière info
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _tealBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF9ECFDA))),
            child: const Row(children: [
              Icon(Icons.info_outline, color: _teal, size: 20),
              SizedBox(width: 10),
              Expanded(child: Text(
                'Votre déclaration sera visible sur la carte publique et rapprochée des alertes d\'animaux perdus.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal))),
            ]),
          ),
          const SizedBox(height: 24),

          // ── Photos ────────────────────────────────────────────────────────────
          const _FLabel('Photos *'),
          const SizedBox(height: 4),
          Text('Ajoutez au moins une photo de l\'animal trouvé.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 10),
          _buildPhotoGrid(),
          const SizedBox(height: 24),

          // ── Espèce ────────────────────────────────────────────────────────────
          const _FLabel('Espèce *'),
          const SizedBox(height: 6),
          _DropdownCard(value: _espece, items: _especes, onChanged: (v) {
            setState(() { _espece = v; _raceCtrl.clear(); _breedSuggestions = []; });
            _loadBreeds(v);
          }),
          const SizedBox(height: 18),

          // ── Race ──────────────────────────────────────────────────────────────
          const _FLabel('Race estimée'),
          const SizedBox(height: 6),
          _buildRaceField(),
          const SizedBox(height: 18),

          // ── Sexe ──────────────────────────────────────────────────────────────
          const _FLabel('Sexe'),
          const SizedBox(height: 6),
          _SexeChips(value: _sexe, onChanged: (v) => setState(() => _sexe = v)),
          const SizedBox(height: 18),

          // ── Taille ────────────────────────────────────────────────────────────
          const _FLabel('Taille'),
          const SizedBox(height: 6),
          _TailleChips(value: _taille, onChanged: (v) => setState(() => _taille = v)),
          const SizedBox(height: 18),

          // ── Couleur ───────────────────────────────────────────────────────────
          const _FLabel('Couleur / signes particuliers'),
          const SizedBox(height: 6),
          _FField(controller: _couleurCtrl, hint: 'Ex : robe fauve, collier rouge…'),
          const SizedBox(height: 18),

          // ── N° de puce ────────────────────────────────────────────────────────
          const _FLabel('Numéro de puce (si visible)'),
          const SizedBox(height: 6),
          _FField(controller: _puceCtrl, hint: 'Ex : 250269802345678',
              inputType: TextInputType.number),
          const SizedBox(height: 18),

          // ── Date de découverte ────────────────────────────────────────────────
          const _FLabel('Date de découverte *'),
          const SizedBox(height: 6),
          _DateField(date: _dateTrouve,
              onPicked: (d) => setState(() => _dateTrouve = d)),
          const SizedBox(height: 18),

          // ── État de santé ─────────────────────────────────────────────────────
          const _FLabel('État de santé'),
          const SizedBox(height: 6),
          _FField(controller: _etatSanteCtrl, hint: 'Ex : bon état, blessé à la patte…'),
          const SizedBox(height: 18),

          // ── Comportement ──────────────────────────────────────────────────────
          const _FLabel('Comportement'),
          const SizedBox(height: 6),
          _FField(controller: _comportementCtrl, hint: 'Ex : calme, craintif, agressif…'),
          const SizedBox(height: 18),

          // ── Localisation ──────────────────────────────────────────────────────
          const _FLabel('Lieu de découverte *'),
          const SizedBox(height: 6),
          _buildAddressSearch(),
          const SizedBox(height: 8),
          _FField(controller: _rueCtrl, hint: 'Rue / voie (optionnel)'),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(width: 110, child: _FField(
                controller: _cpCtrl, hint: 'Code postal',
                inputType: TextInputType.number)),
            const SizedBox(width: 8),
            Expanded(child: _FField(controller: _villeCtrl, hint: 'Ville *')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _FField(controller: _paysCtrl, hint: 'Pays')),
            const SizedBox(width: 8),
            Expanded(child: _FField(controller: _regionCtrl, hint: 'Région')),
          ]),
          if (_lat != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Row(children: [
                Icon(Icons.check_circle, size: 13, color: Colors.green.shade600),
                const SizedBox(width: 4),
                Text('Coordonnées GPS enregistrées',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.green.shade600)),
              ]),
            ),
          const SizedBox(height: 18),

          // ── Description ───────────────────────────────────────────────────────
          const _FLabel('Description complémentaire'),
          const SizedBox(height: 6),
          _FMultiField(controller: _descCtrl,
              hint: 'Circonstances de la découverte, lieu précis…'),
          const SizedBox(height: 18),

          // ── Contact ───────────────────────────────────────────────────────────
          const _FLabel('Contact *'),
          const SizedBox(height: 4),
          Text('Au moins un moyen de contact requis.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 6),
          _FField(controller: _contactEmailCtrl, hint: 'Email',
              inputType: TextInputType.emailAddress),
          const SizedBox(height: 8),
          _FField(controller: _contactTelCtrl, hint: 'Téléphone',
              inputType: TextInputType.phone),
          const SizedBox(height: 8),
          _MessagerieToggle(value: _contactMessagerie,
              onChanged: (v) => setState(() => _contactMessagerie = v)),
          const SizedBox(height: 32),

          // ── Bouton submit ─────────────────────────────────────────────────────
          SizedBox(width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.pets, color: Colors.white, size: 20),
              label: Text(
                _saving ? 'Publication…' : 'Publier la déclaration',
                style: const TextStyle(fontFamily: 'Galey', color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 16),
              ),
              onPressed: _saving ? null : _submit,
            ),
          ),
        ]),
      ),
    );
  }

  // ── Photo grid ────────────────────────────────────────────────────────────────

  Widget _buildPhotoGrid() {
    final allCount = _existingPhotos.length + _imageFiles.length;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      // Existing photos
      ..._existingPhotos.asMap().entries.map((e) => _photoThumb(
        child: Image.network(e.value, fit: BoxFit.cover),
        onRemove: () => setState(() => _existingPhotos.removeAt(e.key)),
      )),
      // New local photos
      ..._imageFiles.asMap().entries.map((e) => _photoThumb(
        child: Image.file(e.value, fit: BoxFit.cover),
        onRemove: () => setState(() => _imageFiles.removeAt(e.key)),
      )),
      // Add button
      if (allCount < 6)
        GestureDetector(
          onTap: _addPhoto,
          child: Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: _tealBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF9ECFDA), width: 1.5),
            ),
            child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_a_photo_outlined, color: _teal, size: 24),
              SizedBox(height: 4),
              Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: _teal)),
            ]),
          ),
        ),
    ]);
  }

  Widget _photoThumb({required Widget child, required VoidCallback onRemove}) {
    return Stack(alignment: Alignment.topRight, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(width: 80, height: 80, child: child),
      ),
      GestureDetector(
        onTap: onRemove,
        child: Container(
          width: 22, height: 22, margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(11)),
          child: const Icon(Icons.close, color: Colors.white, size: 13),
        ),
      ),
    ]);
  }

  // ── Race autocomplete ─────────────────────────────────────────────────────────

  Widget _buildRaceField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]),
        child: TextField(
          controller: _raceCtrl,
          focusNode: _raceFocusNode,
          onChanged: _onRaceChanged,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(
            hintText: _breeds.isEmpty ? 'Ex : Labrador, Européen…' : 'Rechercher une race…',
            hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: InputBorder.none,
            suffixIcon: _raceCtrl.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                    onPressed: () { setState(() { _raceCtrl.clear(); _breedSuggestions = []; _showBreedSuggestions = false; }); })
                : null,
          ),
        ),
      ),
      if (_showBreedSuggestions && _breedSuggestions.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 4))]),
          child: Column(
            children: _breedSuggestions.map((b) => InkWell(
              onTap: () => setState(() {
                _raceCtrl.text = b;
                _breedSuggestions = [];
                _showBreedSuggestions = false;
                _raceFocusNode.unfocus();
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                child: Row(children: [
                  const Icon(Icons.pets, size: 14, color: Colors.grey),
                  const SizedBox(width: 10),
                  Expanded(child: Text(b, style: const TextStyle(fontFamily: 'Galey', fontSize: 13))),
                ]),
              ),
            )).toList(),
          ),
        ),
    ]);
  }

  // ── Address search ────────────────────────────────────────────────────────────

  Widget _buildAddressSearch() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]),
        child: TextField(
          controller: _addressSearchCtrl,
          onChanged: _onAddressChanged,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Rechercher une adresse ou entrez la ville…',
            hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
            suffixIcon: (_loadingPredictions || _locating)
                ? const Padding(padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _teal)))
                : IconButton(
                    icon: const Icon(Icons.my_location, color: _teal, size: 20),
                    tooltip: 'Ma position', onPressed: _geolocate),
          ),
        ),
      ),
      if (_predictions.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 4))]),
          child: Column(
            children: _predictions.take(5).map((p) => InkWell(
              onTap: () => _selectPrediction(p),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 10),
                  Expanded(child: Text(p.description ?? '',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ),
            )).toList(),
          ),
        ),
    ]);
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _TailleChips extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _TailleChips({required this.value, required this.onChanged});

  static const _teal = Color(0xFF0C5C6C);
  static const _labels = {'petit': 'Petit', 'moyen': 'Moyen', 'grand': 'Grand'};

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, children: [
    ...['petit', 'moyen', 'grand'].map((s) {
      final sel = value == s;
      return GestureDetector(
        onTap: () => onChanged(sel ? null : s),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? _teal : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(_labels[s]!,
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
                  color: sel ? Colors.white : Colors.black87)),
        ),
      );
    }),
  ]);
}

class _SexeChips extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _SexeChips({required this.value, required this.onChanged});

  static const _teal = Color(0xFF0C5C6C);
  static const _labels = {'male': 'Mâle', 'femelle': 'Femelle', 'inconnu': 'Inconnu'};

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, children: [
    ...['male', 'femelle', 'inconnu'].map((s) {
      final sel = value == s;
      return GestureDetector(
        onTap: () => onChanged(sel ? null : s),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? _teal : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(_labels[s]!,
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
                  color: sel ? Colors.white : Colors.black87)),
        ),
      );
    }),
  ]);
}

class _FLabel extends StatelessWidget {
  final String text;
  const _FLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14));
}

class _FField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? inputType;
  const _FField({required this.controller, required this.hint, this.inputType});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]),
    child: TextField(
      controller: controller, keyboardType: inputType,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
      decoration: InputDecoration(hintText: hint,
          hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: InputBorder.none),
    ),
  );
}

class _FMultiField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _FMultiField({required this.controller, required this.hint});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]),
    child: TextField(
      controller: controller, maxLines: 4,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
      decoration: InputDecoration(hintText: hint,
          hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
          contentPadding: const EdgeInsets.all(14), border: InputBorder.none),
    ),
  );
}

class _DropdownCard extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  const _DropdownCard({required this.value, required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]),
    child: DropdownButtonFormField<String>(
      value: value,
      decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14), border: InputBorder.none),
      style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.black87),
      items: items.map((s) => DropdownMenuItem(value: s,
          child: Text(s[0].toUpperCase() + s.substring(1),
              style: const TextStyle(fontFamily: 'Galey')))).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    ),
  );
}

class _MessagerieToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _MessagerieToggle({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]),
    child: Row(children: [
      const Icon(Icons.chat_bubble_outline, size: 18, color: Color(0xFF0C5C6C)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Messagerie PetsMatch',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
        Text('Permettre aux utilisateurs de vous contacter via l\'app',
            style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
      ])),
      Switch(value: value, onChanged: onChanged, activeColor: const Color(0xFF0C5C6C)),
    ]),
  );
}

class _DateField extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onPicked;
  const _DateField({required this.date, required this.onPicked});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () async {
      final d = await showDatePicker(context: context,
          initialDate: date,
          firstDate: DateTime(2020), lastDate: DateTime.now());
      if (d != null) onPicked(d);
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]),
      child: Row(children: [
        const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
        const SizedBox(width: 10),
        Text(DateFormat('dd/MM/yyyy').format(date),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
      ]),
    ),
  );
}
