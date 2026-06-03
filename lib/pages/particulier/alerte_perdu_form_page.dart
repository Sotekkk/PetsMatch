import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
import 'package:PetsMatch/services/alertes_notifications.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AlertePerduFormPage extends StatefulWidget {
  final String? alerteId;
  final String? animalId;
  final String? nom;
  final String? espece;
  final String? race;
  final String? sexe;
  final String? couleur;
  final String? photoUrl;
  final String? identification;
  final String? contactUrgence;

  const AlertePerduFormPage({
    super.key,
    this.alerteId,
    this.animalId,
    this.nom,
    this.espece,
    this.race,
    this.sexe,
    this.couleur,
    this.photoUrl,
    this.identification,
    this.contactUrgence,
  });

  @override
  State<AlertePerduFormPage> createState() => _AlertePerduFormPageState();
}

class _AlertePerduFormPageState extends State<AlertePerduFormPage> {
  final _supa = Supabase.instance.client;
  late final GoogleMapsPlaces _places;
  Timer? _searchDebounce;

  final _nomCtrl           = TextEditingController();
  final _identCtrl         = TextEditingController();
  final _raceCtrl          = TextEditingController();
  final _couleurCtrl       = TextEditingController();
  final _addressSearchCtrl = TextEditingController();
  final _rueCtrl           = TextEditingController();
  final _cpCtrl            = TextEditingController();
  final _villeCtrl         = TextEditingController();
  final _paysCtrl          = TextEditingController(text: 'France');
  final _regionCtrl        = TextEditingController();
  final _descCtrl          = TextEditingController();
  final _recompenseCtrl    = TextEditingController();
  final _contactEmailCtrl  = TextEditingController();
  final _contactTelCtrl    = TextEditingController();

  String   _espece       = 'chien';
  String?  _sexe;
  DateTime? _datePerte;
  DateTime? _dateDerniereLoc;
  bool     _contactMessagerie  = true;
  bool     _saving             = false;
  bool     _locating           = false;
  List<Prediction> _predictions = [];
  bool     _loadingPredictions = false;
  double?  _lat;
  double?  _lng;

  File?   _imageFile;
  String? _existingPhotoUrl;
  String  _numeroAlerte = '';

  // Breed autocomplete
  List<String> _breeds = [];
  List<String> _breedSuggestions = [];
  bool         _showBreedSuggestions = false;
  final _raceFocusNode = FocusNode();

  // Animal picker
  List<Map<String, dynamic>> _userAnimaux = [];
  bool _loadingAnimaux = false;

  bool get _isEdit => widget.alerteId != null;

  static const _especes = [
    'chien', 'chat', 'lapin', 'oiseau', 'nac',
    'cheval', 'ovin', 'caprin', 'porcin', 'autre'
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

  static const _orange = Color(0xFFE65100);

  @override
  void initState() {
    super.initState();
    _places = GoogleMapsPlaces(apiKey: getApiKey());
    _existingPhotoUrl = widget.photoUrl;

    _raceFocusNode.addListener(() {
      if (!_raceFocusNode.hasFocus) setState(() => _showBreedSuggestions = false);
    });

    if (_isEdit) {
      _loadExistingAlerte();
    } else {
      _nomCtrl.text     = widget.nom ?? '';
      _identCtrl.text   = widget.identification ?? '';
      _raceCtrl.text    = widget.race ?? '';
      _couleurCtrl.text = widget.couleur ?? '';
      _espece           = widget.espece ?? 'chien';
      _sexe             = widget.sexe;
      _datePerte        = DateTime.now();
      _dateDerniereLoc  = DateTime.now();
      _contactEmailCtrl.text = FirebaseAuth.instance.currentUser?.email ?? '';
      if (widget.contactUrgence?.isNotEmpty == true) {
        _contactTelCtrl.text = widget.contactUrgence!;
      }
      _numeroAlerte = _generateNumero();
      if (widget.animalId != null) _loadAnimalData();
    }

    _loadBreeds(_espece);
    _loadUserAnimaux();
  }

  String _generateNumero() {
    final now  = DateTime.now();
    final rand = (1000 + Random().nextInt(8999)).toString();
    return 'A${DateFormat('yyyyMMdd').format(now)}-$rand';
  }

  // ── Breeds ──────────────────────────────────────────────────────────────────

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

  // ── User animals picker ─────────────────────────────────────────────────────

  Future<void> _loadUserAnimaux() async {
    final uid = User_Info.uid;
    if (uid.isEmpty) return;
    setState(() => _loadingAnimaux = true);
    try {
      final rows = await _supa
          .from('animaux')
          .select('id, nom, espece, race, sexe, couleur, photo_url, identification, contacts_urgence')
          .eq('uid_proprietaire', uid)
          .order('nom');
      if (mounted) setState(() { _userAnimaux = List<Map<String, dynamic>>.from(rows); _loadingAnimaux = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingAnimaux = false);
    }
  }

  void _showAnimalPicker() {
    if (_userAnimaux.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aucun animal enregistré dans vos fiches.')));
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, sc) => Column(children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(
              color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Choisir un animal', style: TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          Expanded(
            child: ListView.builder(
              controller: sc,
              itemCount: _userAnimaux.length,
              itemBuilder: (_, i) {
                final a = _userAnimaux[i];
                return ListTile(
                  leading: CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.orange.shade50,
                    backgroundImage: (a['photo_url'] as String?)?.isNotEmpty == true
                        ? CachedNetworkImageProvider(a['photo_url'] as String) : null,
                    child: (a['photo_url'] as String?)?.isNotEmpty == true
                        ? null : const Icon(Icons.pets, color: _orange, size: 18),
                  ),
                  title: Text(a['nom'] ?? '', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                  subtitle: Text('${a['espece'] ?? ''}${(a['race'] as String?)?.isNotEmpty == true ? ' · ${a['race']}' : ''}',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  onTap: () { Navigator.pop(ctx); _fillFromAnimal(a); },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  void _fillFromAnimal(Map<String, dynamic> d) {
    final newEspece = (d['espece'] as String?) ?? 'chien';
    setState(() {
      _nomCtrl.text     = (d['nom'] as String?) ?? '';
      _identCtrl.text   = (d['identification'] as String?) ?? '';
      _espece           = newEspece;
      _raceCtrl.text    = (d['race'] as String?) ?? '';
      _sexe             = d['sexe'] as String?;
      _couleurCtrl.text = (d['couleur'] as String?) ?? '';
      if ((d['photo_url'] as String?)?.isNotEmpty == true) {
        _existingPhotoUrl = d['photo_url'] as String;
      }
      // Pre-fill contact from emergency contacts
      final contacts = List<Map<String, dynamic>>.from(d['contacts_urgence'] ?? []);
      if (contacts.isNotEmpty) {
        final c = contacts.first;
        _contactTelCtrl.text  = (c['tel'] as String?) ?? '';
        final cEmail = (c['email'] as String?) ?? '';
        if (cEmail.isNotEmpty) _contactEmailCtrl.text = cEmail;
      }
    });
    _loadBreeds(newEspece);
  }

  // ── Load existing alert (edit mode) ─────────────────────────────────────────

  Future<void> _loadExistingAlerte() async {
    try {
      final rows = await _supa.from('alertes_perdus').select().eq('id', widget.alerteId!).limit(1);
      if ((rows as List).isEmpty || !mounted) return;
      final d = rows.first as Map<String, dynamic>;
      final newEspece = (d['espece'] ?? 'chien') as String;
      setState(() {
        _nomCtrl.text     = (d['nom_animal'] ?? '') as String;
        _identCtrl.text   = (d['identification'] ?? '') as String;
        _raceCtrl.text    = (d['race'] ?? '') as String;
        _couleurCtrl.text = (d['couleur'] ?? '') as String;
        _espece           = newEspece;
        _sexe             = d['sexe'] as String?;
        _existingPhotoUrl = d['photo_url'] as String?;
        _descCtrl.text         = (d['description'] ?? '') as String;
        _recompenseCtrl.text   = (d['recompense'] ?? '') as String;
        _contactEmailCtrl.text = (d['contact_email'] ?? d['contact'] ?? '') as String;
        _contactTelCtrl.text   = (d['contact_telephone'] ?? '') as String;
        _contactMessagerie     = (d['contact_messagerie'] ?? true) as bool;
        _paysCtrl.text         = (d['pays'] ?? 'France') as String;
        _regionCtrl.text       = (d['region'] ?? '') as String;
        _numeroAlerte          = (d['numero_alerte'] ?? _generateNumero()) as String;
        _lat              = (d['lat'] as num?)?.toDouble();
        _lng              = (d['lng'] as num?)?.toDouble();

        final loc = (d['derniere_localisation'] ?? '') as String;
        if (loc.isNotEmpty) {
          final parts = loc.split(', ');
          if (parts.length >= 3) {
            _rueCtrl.text   = parts[0];
            _cpCtrl.text    = parts[1];
            _villeCtrl.text = parts[2];
          } else if (parts.length == 2) {
            _cpCtrl.text    = parts[0];
            _villeCtrl.text = parts[1];
          } else {
            _villeCtrl.text = loc;
          }
          _addressSearchCtrl.text = loc;
        }
        if (d['date_perte'] != null) {
          try { _datePerte = DateTime.parse(d['date_perte'] as String); } catch (_) {}
        }
        if (d['date_derniere_localisation'] != null) {
          try { _dateDerniereLoc = DateTime.parse(d['date_derniere_localisation'] as String); } catch (_) {}
        }
        _dateDerniereLoc ??= _datePerte;
      });
      _loadBreeds(newEspece);
    } catch (_) {}
  }

  // ── Load from animal fiche ───────────────────────────────────────────────────

  Future<void> _loadAnimalData() async {
    try {
      final rows = await _supa.from('animaux')
          .select('nom, espece, race, sexe, couleur, photo_url, identification, contacts_urgence')
          .eq('id', widget.animalId!)
          .limit(1);
      if ((rows as List).isEmpty || !mounted) return;
      final d = rows.first as Map<String, dynamic>;
      final newEspece = (d['espece'] ?? _espece) as String;
      setState(() {
        if (_nomCtrl.text.isEmpty)     _nomCtrl.text     = (d['nom'] ?? '') as String;
        if (_identCtrl.text.isEmpty)   _identCtrl.text   = (d['identification'] ?? '') as String;
        if (_raceCtrl.text.isEmpty)    _raceCtrl.text    = (d['race'] ?? '') as String;
        if (_couleurCtrl.text.isEmpty) _couleurCtrl.text = (d['couleur'] ?? '') as String;
        _espece = newEspece;
        _sexe   = (d['sexe'] as String?)?.isNotEmpty == true ? d['sexe'] as String : _sexe;
        if ((_existingPhotoUrl == null || _existingPhotoUrl!.isEmpty) &&
            (d['photo_url'] as String?)?.isNotEmpty == true) {
          _existingPhotoUrl = d['photo_url'] as String;
        }
        // Pre-fill contact from emergency contacts if not already set
        if (_contactTelCtrl.text.isEmpty) {
          final contacts = List<Map<String, dynamic>>.from(d['contacts_urgence'] ?? []);
          if (contacts.isNotEmpty) {
            final c = contacts.first;
            _contactTelCtrl.text = (c['tel'] as String?) ?? '';
            final cEmail = (c['email'] as String?) ?? '';
            if (cEmail.isNotEmpty && _contactEmailCtrl.text.isEmpty) {
              _contactEmailCtrl.text = cEmail;
            }
          }
        }
      });
      _loadBreeds(newEspece);
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _raceFocusNode.dispose();
    _places.dispose();
    for (final c in [_nomCtrl, _identCtrl, _raceCtrl, _couleurCtrl,
                     _addressSearchCtrl, _rueCtrl, _cpCtrl, _villeCtrl,
                     _paysCtrl, _regionCtrl, _descCtrl, _recompenseCtrl,
                     _contactEmailCtrl, _contactTelCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Photo ────────────────────────────────────────────────────────────────────

  Future<void> _pickPhoto() async {
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
          const Text('Choisir une photo',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1F2A2E))),
          const SizedBox(height: 16),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: Colors.orange.shade50,
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.camera_alt_outlined, color: Colors.orange.shade700),
            ),
            title: const Text('Prendre une photo', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            subtitle: const Text('Ouvrir la caméra', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          const SizedBox(height: 10),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: const Color(0xFF0C5C6C).withOpacity(0.07),
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: const Color(0xFF0C5C6C).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.photo_library_outlined, color: Color(0xFF0C5C6C)),
            ),
            title: const Text('Choisir depuis la galerie', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            subtitle: const Text('Sélectionner une photo existante', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final f = await pickAndCropSquare(source: source);
    if (f != null && mounted) setState(() => _imageFile = f);
  }

  Future<String?> _uploadPhoto() async {
    if (_imageFile == null) return _existingPhotoUrl;
    try {
      final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final url = await uploadPhoto(_imageFile!, 'alertes/$name');
      return url;
    } catch (_) { return _existingPhotoUrl; }
  }

  // ── Address search ───────────────────────────────────────────────────────────

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
      String num = '', route = '', cp = '', ville = '', pays = '', region = '';
      for (final c in det.result.addressComponents) {
        if (c.types.contains('street_number'))                   num    = c.longName;
        if (c.types.contains('route'))                           route  = c.longName;
        if (c.types.contains('postal_code'))                     cp     = c.longName;
        if (c.types.contains('locality'))                        ville  = c.longName;
        else if (c.types.contains('administrative_area_level_2') && ville.isEmpty) ville = c.longName;
        if (c.types.contains('administrative_area_level_1'))     region = c.longName;
        if (c.types.contains('country'))                         pays   = c.longName;
      }
      final loc = det.result.geometry?.location;
      setState(() {
        _rueCtrl.text   = [num, route].where((s) => s.isNotEmpty).join(' ');
        _cpCtrl.text    = cp;
        _villeCtrl.text = ville;
        if (pays.isNotEmpty)   _paysCtrl.text   = pays;
        if (region.isNotEmpty) _regionCtrl.text = region;
        if (loc != null) { _lat = loc.lat; _lng = loc.lng; }
      });
    } catch (_) {}
  }

  // ── GPS ──────────────────────────────────────────────────────────────────────

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
        if ((m.country ?? '').isNotEmpty)             _paysCtrl.text   = m.country!;
        if ((m.administrativeArea ?? '').isNotEmpty)  _regionCtrl.text = m.administrativeArea!;
        _addressSearchCtrl.text =
            [_rueCtrl.text, _cpCtrl.text, _villeCtrl.text].where((s) => s.isNotEmpty).join(', ');
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Géolocalisation impossible : $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // ── Submit ───────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final errors = <String>[];
    if (_nomCtrl.text.trim().isEmpty)   errors.add('Nom de l\'animal');
    if (_raceCtrl.text.trim().isEmpty)  errors.add('Race');
    if (_sexe == null)                  errors.add('Sexe');
    if (_datePerte == null)             errors.add('Date de disparition');
    if (_villeCtrl.text.trim().isEmpty) errors.add('Ville');
    final contactEmail = _contactEmailCtrl.text.trim();
    final contactTel   = _contactTelCtrl.text.trim();
    if (contactEmail.isEmpty && contactTel.isEmpty && !_contactMessagerie) {
      errors.add('Au moins un contact requis (email, téléphone ou messagerie)');
    }
    if (contactEmail.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(contactEmail)) {
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
      final photoUrl = await _uploadPhoto();
      final localisation = [_rueCtrl.text.trim(), _cpCtrl.text.trim(), _villeCtrl.text.trim()]
          .where((s) => s.isNotEmpty).join(', ');

      final dateDernLoc = _dateDerniereLoc ?? _datePerte;

      final payload = {
        'uid_proprietaire':        User_Info.uid,
        'animal_id':               widget.animalId,
        'nom_animal':              _nomCtrl.text.trim(),
        'identification':          _identCtrl.text.trim().isEmpty ? null : _identCtrl.text.trim(),
        'espece':                  _espece,
        'race':                    _raceCtrl.text.trim().isEmpty ? null : _raceCtrl.text.trim(),
        'sexe':                    _sexe,
        'couleur':                 _couleurCtrl.text.trim().isEmpty ? null : _couleurCtrl.text.trim(),
        'photo_url':               photoUrl,
        'description':             _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'recompense':              _recompenseCtrl.text.trim().isEmpty ? null : _recompenseCtrl.text.trim(),
        'date_perte':              _datePerte?.toIso8601String().substring(0, 10),
        'date_derniere_localisation': dateDernLoc?.toIso8601String().substring(0, 10),
        'derniere_localisation':   localisation.isEmpty ? null : localisation,
        'pays':                    _paysCtrl.text.trim().isEmpty ? 'France' : _paysCtrl.text.trim(),
        'region':                  _regionCtrl.text.trim().isEmpty ? null : _regionCtrl.text.trim(),
        'lat':                     _lat,
        'lng':                     _lng,
        'contact_email':           contactEmail.isEmpty ? null : contactEmail,
        'contact_telephone':       contactTel.isEmpty ? null : contactTel,
        'contact_messagerie':      _contactMessagerie,
        'numero_alerte':           _numeroAlerte,
        'statut':                  'perdu',
      };

      String? newAlertId;
      if (_isEdit) {
        await _supa.from('alertes_perdus').update(payload).eq('id', widget.alerteId!);
      } else {
        newAlertId = '${DateTime.now().millisecondsSinceEpoch}';
        await _supa.from('alertes_perdus').insert({
          'id': newAlertId,
          ...payload,
        });
      }

      final effectiveAlertId = _isEdit ? widget.alerteId! : newAlertId!;

      if (_lat != null && _lng != null) {
        notifyNearbyUsersAboutLostAnimal(
          lat: _lat!, lng: _lng!,
          nomAnimal: _nomCtrl.text.trim(), espece: _espece,
          alerteId: effectiveAlertId,
          proprietaireUid: User_Info.uid,
        );
      }

      if (!_isEdit) {
        runMatchLostFound(alerteId: effectiveAlertId, type: 'perdu');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_isEdit ? 'Alerte mise à jour ✓' : 'Alerte publiée ✓'),
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
    final photoProvider = _imageFile != null
        ? FileImage(_imageFile!) as ImageProvider
        : (_existingPhotoUrl?.isNotEmpty == true ? NetworkImage(_existingPhotoUrl!) : null);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: Colors.orange.shade700,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(_isEdit ? 'Modifier l\'alerte' : 'Déclarer un animal perdu',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 24, 16,
            24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Numéro alerte
          if (_numeroAlerte.isNotEmpty)
            Align(alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.shade200)),
                child: Text('N° $_numeroAlerte',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                        fontWeight: FontWeight.w600, color: Colors.orange.shade800)),
              ),
            ),
          const SizedBox(height: 12),

          // Bannière info
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200)),
            child: Row(children: [
              Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('Votre alerte sera visible sur la carte publique.',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.orange.shade800))),
            ]),
          ),
          const SizedBox(height: 24),

          // Photo
          Center(child: GestureDetector(
            onTap: _pickPhoto,
            child: Stack(alignment: Alignment.bottomRight, children: [
              CircleAvatar(radius: 52,
                backgroundColor: Colors.orange.shade50,
                backgroundImage: photoProvider,
                child: photoProvider == null
                    ? Icon(Icons.pets, size: 44, color: Colors.orange.shade300) : null),
              CircleAvatar(radius: 16, backgroundColor: Colors.orange.shade700,
                  child: const Icon(Icons.camera_alt, size: 15, color: Colors.white)),
            ]),
          )),
          const SizedBox(height: 6),
          Center(child: Text('Appuyer pour changer la photo',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500))),
          const SizedBox(height: 24),

          // ── Nom + picker ───────────────────────────────────────────────────
          Row(children: [
            const Expanded(child: _FLabel('Nom de l\'animal *')),
            TextButton.icon(
              onPressed: _loadingAnimaux ? null : _showAnimalPicker,
              icon: Icon(Icons.pets, size: 14, color: Colors.orange.shade700),
              label: Text('Mes animaux',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
            ),
          ]),
          const SizedBox(height: 6),
          _FField(controller: _nomCtrl, hint: 'Ex : Rex'),
          const SizedBox(height: 14),

          // ── Identification ─────────────────────────────────────────────────
          const _FLabel('Identification (puce / tatouage)'),
          const SizedBox(height: 6),
          _FField(controller: _identCtrl, hint: 'N° de puce ou tatouage'),
          const SizedBox(height: 18),

          // ── Espèce ─────────────────────────────────────────────────────────
          const _FLabel('Espèce *'),
          const SizedBox(height: 6),
          _DropdownCard(value: _espece, items: _especes, onChanged: (v) {
            setState(() { _espece = v; _raceCtrl.clear(); _breedSuggestions = []; });
            _loadBreeds(v);
          }),
          const SizedBox(height: 18),

          // ── Race (autocomplete) ────────────────────────────────────────────
          const _FLabel('Race *'),
          const SizedBox(height: 6),
          _buildRaceField(),
          const SizedBox(height: 18),

          // ── Sexe ───────────────────────────────────────────────────────────
          const _FLabel('Sexe *'),
          const SizedBox(height: 6),
          _SexeChips(value: _sexe, onChanged: (v) => setState(() => _sexe = v)),
          const SizedBox(height: 18),

          // ── Couleur ────────────────────────────────────────────────────────
          const _FLabel('Couleur / signes particuliers'),
          const SizedBox(height: 6),
          _FField(controller: _couleurCtrl, hint: 'Ex : robe fauve, tache blanche…'),
          const SizedBox(height: 18),

          // ── Date de disparition ────────────────────────────────────────────
          const _FLabel('Date de disparition *'),
          const SizedBox(height: 6),
          _DateField(date: _datePerte, onPicked: (d) => setState(() {
            _datePerte = d;
            if (_dateDerniereLoc == null) _dateDerniereLoc = d;
          })),
          const SizedBox(height: 18),

          // ── Date dernière localisation (edit ou si différente) ─────────────
          const _FLabel('Date de dernière localisation'),
          const SizedBox(height: 4),
          Text('Par défaut = date de disparition. Mettez à jour si vous avez vu l\'animal depuis.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 6),
          _DateField(date: _dateDerniereLoc ?? _datePerte,
              onPicked: (d) => setState(() => _dateDerniereLoc = d)),
          const SizedBox(height: 18),

          // ── Localisation ───────────────────────────────────────────────────
          const _FLabel('Dernière localisation *'),
          const SizedBox(height: 6),
          _buildAddressSearch(),
          const SizedBox(height: 8),
          _FField(controller: _rueCtrl, hint: 'Rue / Voie (optionnel)'),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(width: 110, child: _FField(
                controller: _cpCtrl, hint: 'Code postal', inputType: TextInputType.number)),
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

          // ── Description ────────────────────────────────────────────────────
          const _FLabel('Description'),
          const SizedBox(height: 6),
          _FMultiField(controller: _descCtrl, hint: 'Circonstances de la disparition…'),
          const SizedBox(height: 18),

          // ── Récompense ─────────────────────────────────────────────────────
          const _FLabel('Récompense (optionnel)'),
          const SizedBox(height: 6),
          _FField(controller: _recompenseCtrl, hint: 'Ex : 200 €'),
          const SizedBox(height: 18),

          // ── Contact ────────────────────────────────────────────────────────
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
          _MessagerieToggle(
            value: _contactMessagerie,
            onChanged: (v) => setState(() => _contactMessagerie = v),
          ),
          const SizedBox(height: 32),

          // ── Bouton submit ──────────────────────────────────────────────────
          SizedBox(width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.location_on, color: Colors.white, size: 20),
              label: Text(
                _saving
                    ? (_isEdit ? 'Mise à jour…' : 'Publication…')
                    : (_isEdit ? 'Mettre à jour' : 'Publier l\'alerte'),
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

  // ── Race field with autocomplete ────────────────────────────────────────────

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

  // ── Address search ───────────────────────────────────────────────────────────

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
            hintText: 'Rechercher une adresse ou entrez juste la ville…',
            hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
            suffixIcon: (_loadingPredictions || _locating)
                ? const Padding(padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _orange)))
                : IconButton(
                    icon: const Icon(Icons.my_location, color: _orange, size: 20),
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
                  Expanded(child: Text(p.description ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
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

class _SexeChips extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _SexeChips({required this.value, required this.onChanged});

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
            color: sel ? const Color(0xFFE65100) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(_labels[s]!,
              style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                  fontWeight: FontWeight.w600,
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
        const Text('Messagerie PetsMatch', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
        Text('Permettre aux utilisateurs de vous contacter via l\'app',
            style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
      ])),
      Switch(value: value, onChanged: onChanged, activeColor: const Color(0xFF0C5C6C)),
    ]),
  );
}

class _DateField extends StatelessWidget {
  final DateTime? date;
  final ValueChanged<DateTime> onPicked;
  const _DateField({required this.date, required this.onPicked});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () async {
      final d = await showDatePicker(context: context,
          initialDate: date ?? DateTime.now(),
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
        Text(date != null ? DateFormat('dd/MM/yyyy').format(date!) : 'Sélectionner',
            style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                color: date != null ? Colors.black87 : Colors.grey)),
      ]),
    ),
  );
}
