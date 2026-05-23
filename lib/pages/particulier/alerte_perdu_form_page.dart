import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:PetsMatch/utils/image_pick.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/services/alertes_notifications.dart';

class AlertePerduFormPage extends StatefulWidget {
  /// Provided for edit mode — pass the existing alert ID.
  final String? alerteId;

  // Pre-filled from animal fiche
  final String? animalId;
  final String? nom;
  final String? espece;
  final String? race;
  final String? sexe;
  final String? couleur;
  final String? photoUrl;

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
  });

  @override
  State<AlertePerduFormPage> createState() => _AlertePerduFormPageState();
}

class _AlertePerduFormPageState extends State<AlertePerduFormPage> {
  final _supa = Supabase.instance.client;
  late final GoogleMapsPlaces _places;
  Timer? _searchDebounce;
  final _nomCtrl          = TextEditingController();
  final _raceCtrl         = TextEditingController();
  final _couleurCtrl      = TextEditingController();
  final _addressSearchCtrl = TextEditingController();
  final _rueCtrl          = TextEditingController();
  final _cpCtrl           = TextEditingController();
  final _villeCtrl        = TextEditingController();
  final _descCtrl         = TextEditingController();
  final _contactCtrl      = TextEditingController();

  String _espece = 'chien';
  String? _sexe;   // null = non renseigné
  DateTime? _datePerte;
  bool _saving = false;
  bool _locating = false;
  List<Prediction> _predictions = [];
  bool _loadingPredictions = false;
  double? _lat;
  double? _lng;

  File? _imageFile;
  String? _existingPhotoUrl;
  String _numeroAlerte = '';

  bool get _isEdit => widget.alerteId != null;

  static const _especes = [
    'chien', 'chat', 'lapin', 'oiseau', 'nac',
    'cheval', 'ovin', 'caprin', 'porcin', 'autre'
  ];

  static const _sexeOptions = ['male', 'femelle', 'inconnu'];
  static const _orange = Color(0xFFE65100);

  @override
  void initState() {
    super.initState();
    _places = GoogleMapsPlaces(apiKey: getApiKey());
    _existingPhotoUrl = widget.photoUrl;

    if (_isEdit) {
      _loadExistingAlerte();
    } else {
      // Pre-fill from params
      _nomCtrl.text    = widget.nom ?? '';
      _raceCtrl.text   = widget.race ?? '';
      _couleurCtrl.text = widget.couleur ?? '';
      _espece          = widget.espece ?? 'chien';
      _sexe            = widget.sexe;
      _datePerte       = DateTime.now();
      _contactCtrl.text = FirebaseAuth.instance.currentUser?.email ?? '';
      _numeroAlerte    = _generateNumero();
      if (widget.animalId != null) _loadAnimalData();
    }
  }

  String _generateNumero() {
    final now = DateTime.now();
    final rand = (1000 + Random().nextInt(8999)).toString();
    return 'A${DateFormat('yyyyMMdd').format(now)}-$rand';
  }

  Future<void> _loadExistingAlerte() async {
    try {
      final rows = await _supa.from('alertes_perdus')
          .select()
          .eq('id', widget.alerteId!)
          .limit(1);
      if ((rows as List).isEmpty || !mounted) return;
      final d = rows.first as Map<String, dynamic>;
      setState(() {
        _nomCtrl.text     = (d['nom_animal'] ?? '') as String;
        _raceCtrl.text    = (d['race'] ?? '') as String;
        _couleurCtrl.text = (d['couleur'] ?? '') as String;
        _espece           = (d['espece'] ?? 'chien') as String;
        _sexe             = d['sexe'] as String?;
        _existingPhotoUrl = d['photo_url'] as String?;
        _descCtrl.text    = (d['description'] ?? '') as String;
        _contactCtrl.text = (d['contact'] ?? '') as String;
        _numeroAlerte     = (d['numero_alerte'] ?? _generateNumero()) as String;
        _lat              = (d['lat'] as num?)?.toDouble();
        _lng              = (d['lng'] as num?)?.toDouble();

        // Populate address fields from derniere_localisation
        final loc = (d['derniere_localisation'] ?? '') as String;
        if (loc.isNotEmpty) {
          final parts = loc.split(', ');
          if (parts.length >= 3) {
            _rueCtrl.text   = parts[0];
            _cpCtrl.text    = parts[1];
            _villeCtrl.text = parts[2];
          } else {
            _villeCtrl.text = loc;
          }
          _addressSearchCtrl.text = loc;
        }

        if (d['date_perte'] != null) {
          try { _datePerte = DateTime.parse(d['date_perte'] as String); } catch (_) {}
        }
      });
    } catch (_) {}
  }

  Future<void> _loadAnimalData() async {
    try {
      final rows = await _supa.from('animaux')
          .select('nom, espece, race, sexe, couleur, photo_url')
          .eq('id', widget.animalId!)
          .limit(1);
      if ((rows as List).isEmpty || !mounted) return;
      final d = rows.first as Map<String, dynamic>;
      setState(() {
        if (_nomCtrl.text.isEmpty)     _nomCtrl.text     = (d['nom'] ?? '') as String;
        if (_raceCtrl.text.isEmpty)    _raceCtrl.text    = (d['race'] ?? '') as String;
        if (_couleurCtrl.text.isEmpty) _couleurCtrl.text = (d['couleur'] ?? '') as String;
        _espece = (d['espece'] ?? _espece) as String;
        _sexe   = (d['sexe'] as String?)?.isNotEmpty == true ? d['sexe'] as String : _sexe;
        if (_existingPhotoUrl == null || _existingPhotoUrl!.isEmpty) {
          _existingPhotoUrl = d['photo_url'] as String?;
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _places.dispose();
    for (final c in [_nomCtrl, _raceCtrl, _couleurCtrl, _addressSearchCtrl,
                     _rueCtrl, _cpCtrl, _villeCtrl, _descCtrl, _contactCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Photo picker ────────────────────────────────────────────────────────────

  Future<void> _pickPhoto() async {
    final f = await pickAndCropSquare();
    if (f != null && mounted) setState(() => _imageFile = f);
  }

  Future<String?> _uploadPhoto() async {
    if (_imageFile == null) return _existingPhotoUrl;
    try {
      final name = 'alertes/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref().child(name);
      await ref.putFile(_imageFile!);
      return await ref.getDownloadURL();
    } catch (_) { return _existingPhotoUrl; }
  }

  // ── Address search ──────────────────────────────────────────────────────────

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
      final res = await _places.autocomplete(
        input,
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
      String num = '', route = '', cp = '', ville = '';
      for (final c in det.result.addressComponents) {
        if (c.types.contains('street_number')) num   = c.longName;
        if (c.types.contains('route'))         route = c.longName;
        if (c.types.contains('postal_code'))   cp    = c.longName;
        if (c.types.contains('locality') ||
            c.types.contains('administrative_area_level_2')) ville = c.longName;
      }
      final loc = det.result.geometry?.location;
      setState(() {
        _rueCtrl.text   = [num, route].where((s) => s.isNotEmpty).join(' ');
        _cpCtrl.text    = cp;
        _villeCtrl.text = ville;
        if (loc != null) { _lat = loc.lat; _lng = loc.lng; }
      });
    } catch (_) {}
  }

  // ── GPS ─────────────────────────────────────────────────────────────────────

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
        _villeCtrl.text = m.locality ?? m.subAdministrativeArea ?? '';
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

  // ── Submit ──────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final nom = _nomCtrl.text.trim();
    if (nom.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Le nom est requis'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _saving = true);
    try {
      final photoUrl = await _uploadPhoto();
      final localisation = [_rueCtrl.text.trim(), _cpCtrl.text.trim(), _villeCtrl.text.trim()]
          .where((s) => s.isNotEmpty).join(', ');
      final payload = {
        'uid_proprietaire': User_Info.uid,
        'animal_id': widget.animalId,
        'nom_animal': nom,
        'espece': _espece,
        'race': _raceCtrl.text.trim().isEmpty ? null : _raceCtrl.text.trim(),
        'sexe': _sexe,
        'couleur': _couleurCtrl.text.trim().isEmpty ? null : _couleurCtrl.text.trim(),
        'photo_url': photoUrl,
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'date_perte': _datePerte?.toIso8601String().substring(0, 10),
        'derniere_localisation': localisation.isEmpty ? null : localisation,
        'lat': _lat,
        'lng': _lng,
        'contact': _contactCtrl.text.trim().isEmpty ? null : _contactCtrl.text.trim(),
        'numero_alerte': _numeroAlerte,
        'statut': 'perdu',
      };

      if (_isEdit) {
        await _supa.from('alertes_perdus').update(payload).eq('id', widget.alerteId!);
      } else {
        await _supa.from('alertes_perdus').insert({
          'id': '${DateTime.now().millisecondsSinceEpoch}',
          ...payload,
        });
      }

      // Notify users within 20km if we have GPS coordinates
      if (_lat != null && _lng != null) {
        notifyNearbyUsersAboutLostAnimal(
          lat: _lat!,
          lng: _lng!,
          nomAnimal: nom,
          espece: _espece,
          alerteId: _isEdit ? widget.alerteId! : '${DateTime.now().millisecondsSinceEpoch}',
          proprietaireUid: User_Info.uid,
        );
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

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final photoProvider = _imageFile != null
        ? FileImage(_imageFile!) as ImageProvider
        : (_existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty
            ? NetworkImage(_existingPhotoUrl!)
            : null);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: Colors.orange.shade700,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(_isEdit ? 'Modifier l\'alerte' : 'Déclarer un animal perdu',
            style: const TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Numero alerte chip
          if (_numeroAlerte.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.shade200)),
                child: Text('N° $_numeroAlerte',
                    style: TextStyle(
                        fontFamily: 'Galey', fontSize: 11,
                        fontWeight: FontWeight.w600, color: Colors.orange.shade800)),
              ),
            ),
          const SizedBox(height: 12),

          // Info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Votre alerte sera visible sur la carte publique.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.orange.shade800)),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          // Photo
          Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: Stack(alignment: Alignment.bottomRight, children: [
                CircleAvatar(
                  radius: 52,
                  backgroundColor: Colors.orange.shade50,
                  backgroundImage: photoProvider,
                  child: photoProvider == null
                      ? Icon(Icons.pets, size: 44, color: Colors.orange.shade300)
                      : null,
                ),
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.orange.shade700,
                  child: const Icon(Icons.camera_alt, size: 15, color: Colors.white),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text('Appuyer pour changer la photo',
                style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          ),
          const SizedBox(height: 24),

          _FLabel('Nom de l\'animal *'),
          const SizedBox(height: 6),
          _FField(controller: _nomCtrl, hint: 'Ex : Rex'),
          const SizedBox(height: 18),

          _FLabel('Espèce'),
          const SizedBox(height: 6),
          _DropdownCard(value: _espece, items: _especes, onChanged: (v) => setState(() => _espece = v)),
          const SizedBox(height: 18),

          _FLabel('Race'),
          const SizedBox(height: 6),
          _FField(controller: _raceCtrl, hint: 'Ex : Labrador, Européen…'),
          const SizedBox(height: 18),

          _FLabel('Sexe'),
          const SizedBox(height: 6),
          _SexeChips(value: _sexe, onChanged: (v) => setState(() => _sexe = v)),
          const SizedBox(height: 18),

          _FLabel('Couleur / signes particuliers'),
          const SizedBox(height: 6),
          _FField(controller: _couleurCtrl, hint: 'Ex : robe fauve, tache blanche sur le front…'),
          const SizedBox(height: 18),

          _FLabel('Date de disparition'),
          const SizedBox(height: 6),
          _DateField(date: _datePerte, onPicked: (d) => setState(() => _datePerte = d)),
          const SizedBox(height: 18),

          // ── Localisation ──
          _FLabel('Dernière localisation'),
          const SizedBox(height: 6),
          _buildAddressSearch(),
          const SizedBox(height: 8),
          _FField(controller: _rueCtrl, hint: 'Rue / Voie'),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(width: 110, child: _FField(controller: _cpCtrl, hint: 'Code postal', inputType: TextInputType.number)),
            const SizedBox(width: 8),
            Expanded(child: _FField(controller: _villeCtrl, hint: 'Ville')),
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

          _FLabel('Description'),
          const SizedBox(height: 6),
          _FMultiField(controller: _descCtrl, hint: 'Circonstances de la disparition…'),
          const SizedBox(height: 18),

          _FLabel('Contact'),
          const SizedBox(height: 6),
          _FField(controller: _contactCtrl, hint: 'Email ou téléphone'),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
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
                _saving ? (_isEdit ? 'Mise à jour…' : 'Publication…') : (_isEdit ? 'Mettre à jour' : 'Publier l\'alerte'),
                style: const TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
              ),
              onPressed: _saving ? null : _submit,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildAddressSearch() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: TextField(
          controller: _addressSearchCtrl,
          onChanged: _onAddressChanged,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Rechercher une adresse…',
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
                    tooltip: 'Ma position',
                    onPressed: _geolocate,
                  ),
          ),
        ),
      ),
      if (_predictions.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 4))],
          ),
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

// ── Widgets ───────────────────────────────────────────────────────────────────

class _SexeChips extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _SexeChips({required this.value, required this.onChanged});

  static const _labels = {'male': 'Mâle', 'femelle': 'Femelle', 'inconnu': 'Inconnu'};

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      ...['male', 'femelle', 'inconnu'].map((s) {
        final sel = value == s;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => onChanged(sel ? null : s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? const Color(0xFFE65100) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(_labels[s]!,
                  style: TextStyle(
                      fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : Colors.black87)),
            ),
          ),
        );
      }),
    ]);
  }
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
          decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14), border: InputBorder.none),
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.black87),
          items: items.map((s) => DropdownMenuItem(value: s,
              child: Text(s[0].toUpperCase() + s.substring(1), style: const TextStyle(fontFamily: 'Galey')))).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
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
              initialDate: date ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
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
