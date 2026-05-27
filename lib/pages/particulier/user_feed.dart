import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/storage_helper.dart';
import 'package:PetsMatch/utils/french_geo.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:PetsMatch/utils/image_pick.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/particulier/animal_fiche_particulier.dart';
import 'package:PetsMatch/pages/particulier/alerte_perdu_form_page.dart';
import 'package:PetsMatch/pages/settings/info_utilisateur.dart';
import 'package:PetsMatch/pages/settings/main_settings.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/services/alertes_notifications.dart';

class UserParticulierFeed extends StatefulWidget {
  final int initialTab;
  const UserParticulierFeed({super.key, this.initialTab = 0});

  @override
  State<UserParticulierFeed> createState() => _UserParticulierFeedState();
}

class _UserParticulierFeedState extends State<UserParticulierFeed>
    with SingleTickerProviderStateMixin {
  static const _teal = Color(0xFF0C5C6C);

  late TabController _tabController;
  final _supa = Supabase.instance.client;

  // Profile tab
  final _bioCtrl = TextEditingController();
  final _adoptCtrl = TextEditingController();
  final _rueCtrl  = TextEditingController();
  final _cpCtrl   = TextEditingController();
  final _villeCtrl = TextEditingController();
  File? _imageFile;
  bool _isPickerActive = false;
  String _profilePicUrl =
      'https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60';
  bool _bioModified = false;
  bool _adoptModified = false;
  bool _adresseModified = false;
  bool _locating = false;
  bool _editingProfil = false;
  // Address Places search
  late final GoogleMapsPlaces _places;
  final _adresseSearchCtrl = TextEditingController();
  List<Prediction> _adressePredictions = [];
  bool _loadingAdressePredictions = false;
  Timer? _adresseDebounce;
  double? _profileLat;
  double? _profileLng;
  String _initBio = '';
  String _initAdopt = '';

  // Animaux tab
  List<Map<String, dynamic>> _animaux = [];
  bool _loadingAnimaux = false;

  // Perdus tab
  List<Map<String, dynamic>> _alertes = [];
  bool _loadingAlertes = false;

  // Adoption project toggle
  bool _hasAdoptProject = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2));
    _fetchProfile();
    _fetchAnimaux();
    _fetchAlertes();

    _places = GoogleMapsPlaces(apiKey: getApiKey());
    _bioCtrl.addListener(() => setState(() => _bioModified = _bioCtrl.text != _initBio));
    _adoptCtrl.addListener(() => setState(() => _adoptModified = _adoptCtrl.text != _initAdopt));
    _rueCtrl.addListener(_onAdresseChanged);
    _cpCtrl.addListener(_onAdresseChanged);
    _villeCtrl.addListener(_onAdresseChanged);

    _tabController.addListener(() {
      if (_tabController.index != 0 && _editingProfil) {
        setState(() => _editingProfil = false);
      }
      if (_tabController.index == 1) _fetchAnimaux();
      if (_tabController.index == 2) _fetchAlertes();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _bioCtrl.dispose();
    _adoptCtrl.dispose();
    _rueCtrl.dispose();
    _cpCtrl.dispose();
    _villeCtrl.dispose();
    _adresseSearchCtrl.dispose();
    _adresseDebounce?.cancel();
    _places.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(User_Info.uid)
          .get();
      final d = doc.data() ?? {};
      // Remove address listeners to avoid _adresseModified = true during load
      _rueCtrl.removeListener(_onAdresseChanged);
      _cpCtrl.removeListener(_onAdresseChanged);
      _villeCtrl.removeListener(_onAdresseChanged);
      setState(() {
        _profilePicUrl = d['profilePictureUrl'] ?? _profilePicUrl;
        _initBio = d['desc'] ?? '';
        _initAdopt = d['adoptProject'] ?? '';
        _bioCtrl.text = _initBio;
        _adoptCtrl.text = _initAdopt;
        _hasAdoptProject = _initAdopt.isNotEmpty;
        _rueCtrl.text   = d['rue'] ?? User_Info.rue;
        _cpCtrl.text    = d['codePostal'] ?? User_Info.codePostal;
        _villeCtrl.text = d['ville'] ?? User_Info.ville;
        _adresseModified = false;
      });
      _rueCtrl.addListener(_onAdresseChanged);
      _cpCtrl.addListener(_onAdresseChanged);
      _villeCtrl.addListener(_onAdresseChanged);
    } catch (_) {}
  }

  void _onAdresseChanged() {
    setState(() => _adresseModified = true);
  }

  Future<void> _saveAdresse() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final geo = FrenchGeo.fromPostalCode(_cpCtrl.text.trim());
    final dept = geo?.departement ?? '';
    final reg  = geo?.region ?? '';
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'rue':        _rueCtrl.text.trim(),
      'codePostal': _cpCtrl.text.trim(),
      'ville':      _villeCtrl.text.trim(),
      'departement': dept,
      'region':      reg,
      if (_profileLat != null) 'lat': _profileLat,
      if (_profileLng != null) 'lng': _profileLng,
    });
    try {
      await _supa.from('users').upsert({
        'uid':         uid,
        'rue':         _rueCtrl.text.trim(),
        'code_postal': _cpCtrl.text.trim(),
        'ville':       _villeCtrl.text.trim(),
        'departement': dept,
        'region':      reg,
        if (_profileLat != null) 'lat': _profileLat,
        if (_profileLng != null) 'lng': _profileLng,
      }, onConflict: 'uid');
    } catch (_) {}
    User_Info.rue = _rueCtrl.text.trim();
    User_Info.codePostal = _cpCtrl.text.trim();
    User_Info.ville = _villeCtrl.text.trim();
    User_Info.departement = dept;
    User_Info.region = reg;
    setState(() {
      _adresseModified = false;
      _adresseSearchCtrl.clear();
      _adressePredictions = [];
    });
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adresse enregistrée'), backgroundColor: Color(0xFF0C5C6C)));
  }

  void _onAdresseSearchChanged(String val) {
    _adresseDebounce?.cancel();
    if (val.trim().length < 3) {
      setState(() { _adressePredictions = []; _loadingAdressePredictions = false; });
      return;
    }
    setState(() => _loadingAdressePredictions = true);
    _adresseDebounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final res = await _places.autocomplete(val,
            components: [Component(Component.country, 'fr'), Component(Component.country, 'be'),
                         Component(Component.country, 'ch'), Component(Component.country, 'lu')],
            language: 'fr');
        if (!mounted) return;
        setState(() { _adressePredictions = res.isOkay ? res.predictions : []; _loadingAdressePredictions = false; });
      } catch (_) {
        if (mounted) setState(() => _loadingAdressePredictions = false);
      }
    });
  }

  Future<void> _selectAdressePrediction(Prediction p) async {
    setState(() { _adressePredictions = []; _adresseSearchCtrl.text = p.description ?? ''; });
    if (p.placeId == null) return;
    try {
      final det = await _places.getDetailsByPlaceId(p.placeId!, language: 'fr');
      if (!mounted || !det.isOkay) return;
      String num = '', route = '', cp = '', ville = '';
      for (final c in det.result.addressComponents) {
        if (c.types.contains('street_number')) num   = c.longName;
        if (c.types.contains('route'))         route = c.longName;
        if (c.types.contains('postal_code'))   cp    = c.longName;
        if (c.types.contains('locality'))      ville = c.longName;
        else if (c.types.contains('administrative_area_level_2') && ville.isEmpty) ville = c.longName;
      }
      final loc = det.result.geometry?.location;
      setState(() {
        _rueCtrl.text   = [num, route].where((s) => s.isNotEmpty).join(' ');
        _cpCtrl.text    = cp;
        _villeCtrl.text = ville;
        _adresseModified = true;
        if (loc != null) { _profileLat = loc.lat; _profileLng = loc.lng; }
      });
    } catch (_) {}
  }

  Future<void> _geolocateProfil() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      _profileLat = pos.latitude;
      _profileLng = pos.longitude;
      final marks = await geo.placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isEmpty) return;
      final m = marks.first;
      _rueCtrl.text   = m.street ?? '';
      _cpCtrl.text    = m.postalCode ?? '';
      _villeCtrl.text = m.locality ?? m.subLocality ?? '';
      setState(() => _adresseModified = true);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _fetchAnimaux() async {
    final uid = User_Info.uid;
    if (uid.isEmpty) return;
    setState(() => _loadingAnimaux = true);
    try {
      final data = await _supa
          .from('animaux')
          .select()
          .or('uid_eleveur.eq.$uid,uid_proprietaire.eq.$uid')
          .order('created_at', ascending: false);
      setState(() {
        _animaux = List<Map<String, dynamic>>.from(data);
        _loadingAnimaux = false;
      });
    } catch (_) {
      setState(() => _loadingAnimaux = false);
    }
  }

  Future<void> _fetchAlertes() async {
    final uid = User_Info.uid;
    if (uid.isEmpty) return;
    setState(() => _loadingAlertes = true);
    try {
      final data = await _supa
          .from('alertes_perdus')
          .select()
          .eq('uid_proprietaire', uid)
          .order('created_at', ascending: false);
      setState(() {
        _alertes = List<Map<String, dynamic>>.from(data);
        _loadingAlertes = false;
      });
    } catch (_) {
      setState(() => _loadingAlertes = false);
    }
  }

  Future<void> _pickImage() async {
    if (_isPickerActive) return;
    try {
      setState(() => _isPickerActive = true);
      final f = await pickAndCropSquare();
      setState(() {
        _imageFile = f ?? _imageFile;
        _isPickerActive = false;
      });
      if (_imageFile != null) await _uploadProfilePic();
    } catch (_) {
      setState(() => _isPickerActive = false);
    }
  }

  Future<void> _uploadProfilePic() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    final url = await uploadPhoto(_imageFile!, 'profiles/$uid/photo.jpg');
    setState(() => _profilePicUrl = url);
    User_Info.profilePictureUrl = url;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(User_Info.uid)
        .update({'profilePictureUrl': url});
  }

  Future<void> _saveBio() async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(User_Info.uid)
        .update({'desc': _bioCtrl.text});
    setState(() { _bioModified = false; _initBio = _bioCtrl.text; });
  }

  Future<void> _saveAdopt() async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(User_Info.uid)
        .update({'adoptProject': _adoptCtrl.text});
    setState(() { _adoptModified = false; _initAdopt = _adoptCtrl.text; });
  }

  Future<void> _retrouveAlerte(String id) async {
    try {
      await _supa.from('alertes_perdus').update({
        'statut': 'retrouve',
        'date_retrouve': DateTime.now().toIso8601String().substring(0, 10),
      }).eq('id', id);
      setState(() {
        final idx = _alertes.indexWhere((a) => a['id'] == id);
        if (idx >= 0) _alertes[idx] = {..._alertes[idx], 'statut': 'retrouve'};
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _deleteAlerte(String id) async {
    try {
      await _supa.from('alertes_perdus').delete().eq('id', id);
      setState(() => _alertes.removeWhere((a) => a['id'] == id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _editAlerte(Map<String, dynamic> a) async {
    final updated = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => AlertePerduFormPage(
        alerteId: a['id'] as String?,
        animalId: a['animal_id'] as String?,
        photoUrl: a['photo_url'] as String?,
      ),
    ));
    if (updated == true) _fetchAlertes();
  }

  void _showUpdateLocationSheet(Map<String, dynamic> alerte) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _UpdateLocationSheet(
        alerteId: alerte['id'] as String,
        nomAnimal: alerte['nom_animal'] as String? ?? 'Animal',
        espece: alerte['espece'] as String?,
        proprietaireUid: alerte['uid_proprietaire'] as String? ?? User_Info.uid,
        onSaved: () { Navigator.pop(ctx); _fetchAlertes(); },
      ),
    );
  }

  Future<void> _deleteAnimal(String id, String nom) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cet animal ?', style: TextStyle(fontFamily: 'Galey')),
        content: Text('$nom sera supprimé définitivement.',
            style: const TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await _supa.from('animaux').delete().eq('id', id);
      setState(() => _animaux.removeWhere((a) => a['id'] == id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            backgroundColor: _teal,
            automaticallyImplyLeading: true,
            expandedHeight: 100,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: false,
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 4, 50),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Mon Profil',
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          color: Colors.white)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          _editingProfil && _tabController.index == 0
                              ? Icons.done
                              : Icons.edit_outlined,
                          size: 18,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          if (_tabController.index == 0) {
                            setState(() => _editingProfil = !_editingProfil);
                          } else {
                            Navigator.push(context,
                                MaterialPageRoute(builder: (_) => InfoUserSettings()));
                          }
                        },
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 18, color: Colors.white),
                        onSelected: (v) {
                          if (v == 'settings') {
                            Navigator.push(context,
                                MaterialPageRoute(builder: (_) => SettingsMainPage()));
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'settings',
                            child: Row(children: [
                              Icon(Icons.settings, size: 18),
                              SizedBox(width: 8),
                              Text('Paramètres', style: TextStyle(fontFamily: 'Galey')),
                            ]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(
                  fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
              tabs: const [
                Tab(text: 'Mon Profil'),
                Tab(text: 'Mes Animaux'),
                Tab(text: 'Perdus'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildProfilTab(),
            _buildAnimauxTab(),
            _buildPerdusTab(),
          ],
        ),
      ),
    );
  }

  // ── Tab 1: Profil ─────────────────────────────────────────────────────────────

  Widget _buildProfilTab() {
    final especes = <String>{};
    final races = <String>{};
    for (final a in _animaux) {
      if (a['espece'] != null) especes.add(a['espece'] as String);
      if (a['race'] != null && (a['race'] as String).isNotEmpty) races.add(a['race'] as String);
    }

    final ville = _villeCtrl.text.isNotEmpty ? _villeCtrl.text : User_Info.ville;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo + nom
          Center(
            child: _editingProfil
                ? GestureDetector(
                    onTap: _pickImage,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 52,
                          backgroundColor: const Color(0xFFCCE8EE),
                          backgroundImage: _imageFile != null
                              ? FileImage(_imageFile!) as ImageProvider
                              : CachedNetworkImageProvider(_profilePicUrl),
                        ),
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: _teal,
                          child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                        ),
                      ],
                    ),
                  )
                : CircleAvatar(
                    radius: 52,
                    backgroundColor: const Color(0xFFCCE8EE),
                    backgroundImage: _imageFile != null
                        ? FileImage(_imageFile!) as ImageProvider
                        : CachedNetworkImageProvider(_profilePicUrl),
                  ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '${User_Info.firstname} ${User_Info.lastname}',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
          if (ville.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_on, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(ville,
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),

          // Stats animaux
          if (_animaux.isNotEmpty) ...[
            Row(
              children: [
                _StatChip(value: '${_animaux.length}', label: 'Animal${_animaux.length > 1 ? 'x' : ''}', icon: Icons.pets, color: _teal),
                const SizedBox(width: 10),
                _StatChip(value: '${especes.length}', label: 'Espèce${especes.length > 1 ? 's' : ''}', icon: Icons.category_outlined, color: const Color(0xFF6E9E57)),
              ],
            ),
            if (especes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: especes.map((e) => _PillChip(label: _capitalize(e), color: _teal)).toList(),
              ),
            ],
            if (races.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: races.map((r) => _PillChip(label: r, color: const Color(0xFF6E9E57))).toList(),
              ),
            ],
            const SizedBox(height: 24),
          ],

          // ── Adresse ──
          const _SectionTitle('Mon adresse'),
          const SizedBox(height: 10),
          if (_editingProfil) ...[
            // Search bar
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: TextField(
                controller: _adresseSearchCtrl,
                onChanged: _onAdresseSearchChanged,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Rechercher une adresse…',
                  hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: InputBorder.none,
                  prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                  suffixIcon: _loadingAdressePredictions || _locating
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: _teal)))
                      : IconButton(
                          icon: const Icon(Icons.my_location, size: 18, color: _teal),
                          onPressed: _geolocateProfil,
                        ),
                ),
              ),
            ),
            if (_adressePredictions.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 4))],
                ),
                child: Column(
                  children: _adressePredictions.take(5).map((p) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                    title: Text(p.description ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                    onTap: () => _selectAdressePrediction(p),
                  )).toList(),
                ),
              ),
            ],
            const SizedBox(height: 8),
            _adresseField(_rueCtrl, 'Rue', Icons.home_outlined),
            const SizedBox(height: 8),
            Row(children: [
              SizedBox(width: 120, child: _adresseField(_cpCtrl, 'Code postal', Icons.markunread_mailbox_outlined, num: true)),
              const SizedBox(width: 8),
              Expanded(child: _adresseField(_villeCtrl, 'Ville', Icons.location_city_outlined)),
            ]),
            if (_adresseModified) ...[
              const SizedBox(height: 8),
              _SaveBtn(onPressed: _saveAdresse),
            ],
          ] else ...[
            // View mode — read-only address card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on_outlined, color: _teal, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: (_rueCtrl.text.isEmpty && _cpCtrl.text.isEmpty && _villeCtrl.text.isEmpty)
                        ? Text('Adresse non renseignée',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                                color: Colors.grey.shade400, fontStyle: FontStyle.italic))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_rueCtrl.text.isNotEmpty)
                                Text(_rueCtrl.text,
                                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
                              if (_cpCtrl.text.isNotEmpty || _villeCtrl.text.isNotEmpty)
                                Text('${_cpCtrl.text} ${_villeCtrl.text}'.trim(),
                                    style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),

          // ── Bio ──
          const _SectionTitle('À propos de moi'),
          const SizedBox(height: 10),
          if (_editingProfil) ...[
            _TextArea(controller: _bioCtrl, hint: 'Parlez-nous un peu de vous'),
            if (_bioModified) ...[
              const SizedBox(height: 8),
              _SaveBtn(onPressed: _saveBio),
            ],
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: _bioCtrl.text.isNotEmpty
                  ? Text(_bioCtrl.text, style: const TextStyle(fontFamily: 'Galey', fontSize: 14))
                  : Text('Aucune description',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                          color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
            ),
          ],
          const SizedBox(height: 20),

          // ── Projet d'adoption ──
          if (_editingProfil) ...[
            Container(
              decoration: BoxDecoration(
                color: _hasAdoptProject ? const Color(0xFFE8F4F7) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _hasAdoptProject ? _teal : Colors.grey.shade200,
                  width: 1.5,
                ),
              ),
              child: CheckboxListTile(
                value: _hasAdoptProject,
                onChanged: (v) async {
                  setState(() => _hasAdoptProject = v ?? false);
                  if (v == false) {
                    _adoptCtrl.clear();
                    await _saveAdopt();
                  }
                },
                title: const Text("J'ai un projet d'adoption",
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 15)),
                subtitle: _hasAdoptProject
                    ? null
                    : Text("Cocher pour décrire votre projet",
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
                activeColor: _teal,
                checkColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
            if (_hasAdoptProject) ...[
              const SizedBox(height: 10),
              _TextArea(
                controller: _adoptCtrl,
                hint: "Espèce, race, conditions de vie, expérience avec les animaux...",
              ),
              if (_adoptModified) ...[
                const SizedBox(height: 8),
                _SaveBtn(onPressed: _saveAdopt),
              ],
            ],
          ] else if (_hasAdoptProject) ...[
            const _SectionTitle("Projet d'adoption"),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F4F7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _teal.withOpacity(0.3)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.favorite, color: _teal, size: 16),
                    const SizedBox(width: 6),
                    const Text("Projet d'adoption",
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                            fontSize: 14, color: _teal)),
                  ]),
                  if (_adoptCtrl.text.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_adoptCtrl.text, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Tab 2: Mes Animaux ────────────────────────────────────────────────────────

  Widget _buildAnimauxTab() {
    return Stack(
      children: [
        _loadingAnimaux
            ? const Center(child: CircularProgressIndicator(color: _teal))
            : _animaux.isEmpty
                ? _buildEmpty(
                    icon: Icons.pets,
                    message: 'Aucun animal enregistré',
                    sub: 'Appuyez sur + pour ajouter votre premier animal',
                  )
                : RefreshIndicator(
                    onRefresh: _fetchAnimaux,
                    color: _teal,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      itemCount: _animaux.length,
                      itemBuilder: (_, i) => _AnimalCard(
                        data: _animaux[i],
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AnimalFicheParticulierPage(
                                animalId: _animaux[i]['id'],
                                initialData: _animaux[i],
                              ),
                            ),
                          );
                          _fetchAnimaux();
                        },
                        onDelete: () => _deleteAnimal(
                            _animaux[i]['id'], _animaux[i]['nom'] ?? 'cet animal'),
                      ),
                    ),
                  ),
        Positioned(
          right: 16,
          bottom: 90,
          child: FloatingActionButton(
            heroTag: 'add_animal_fab',
            backgroundColor: _teal,
            child: const Icon(Icons.add, color: Colors.white),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AnimalFicheParticulierPage()),
              );
              _fetchAnimaux();
            },
          ),
        ),
      ],
    );
  }

  // ── Tab 3: Perdus ─────────────────────────────────────────────────────────────

  Widget _buildPerdusTab() {
    return Stack(
      children: [
        _loadingAlertes
            ? const Center(child: CircularProgressIndicator(color: _teal))
            : _alertes.isEmpty
                ? _buildEmpty(
                    icon: Icons.location_searching,
                    message: 'Aucune alerte active',
                    sub: 'Déclarez un animal perdu via sa fiche ou le bouton +',
                  )
                : RefreshIndicator(
                    onRefresh: _fetchAlertes,
                    color: _teal,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      itemCount: _alertes.length,
                      itemBuilder: (_, i) => _AlerteCard(
                        data: _alertes[i],
                        onRetrouve: () => _retrouveAlerte(_alertes[i]['id']),
                        onDelete: () => _deleteAlerte(_alertes[i]['id']),
                        onEdit: () => _editAlerte(_alertes[i]),
                        onUpdateLocation: () => _showUpdateLocationSheet(_alertes[i]),
                      ),
                    ),
                  ),
        Positioned(
          right: 16,
          bottom: 90,
          child: FloatingActionButton(
            heroTag: 'add_alerte_fab',
            backgroundColor: Colors.orange.shade700,
            onPressed: _showAnimalPickerForAlerte,
            child: const Icon(Icons.add_location_alt, color: Colors.white),
          ),
        ),
      ],
    );
  }

  void _showAnimalPickerForAlerte() {
    if (_animaux.isEmpty) {
      Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AlertePerduFormPage()))
          .then((_) => _fetchAlertes());
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Quel animal est perdu ?',
                  style: TextStyle(
                      fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 8),
          ..._animaux.map((a) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFE0F0F3),
                  child: a['photo_url'] != null && (a['photo_url'] as String).isNotEmpty
                      ? ClipOval(
                          child: CachedNetworkImage(
                              imageUrl: a['photo_url'] as String,
                              width: 40, height: 40, fit: BoxFit.cover))
                      : Text(
                          (a['nom'] as String? ?? '?').isNotEmpty
                              ? (a['nom'] as String)[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                ),
                title: Text(a['nom'] ?? 'Sans nom',
                    style: const TextStyle(
                        fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                subtitle: a['espece'] != null
                    ? Text(_capitalize(a['espece'] as String),
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 12))
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AlertePerduFormPage(
                        animalId: a['id'] as String?,
                        nom: a['nom'] as String?,
                        espece: a['espece'] as String?,
                        race: a['race'] as String?,
                        sexe: a['sexe'] as String?,
                        couleur: a['couleur'] as String?,
                        photoUrl: a['photo_url'] as String?,
                      ),
                    ),
                  ).then((_) => _fetchAlertes());
                },
              )),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFFFF3E0),
              child: Icon(Icons.add, color: Colors.orange),
            ),
            title: const Text('Autre animal (non enregistré)',
                style: TextStyle(
                    fontFamily: 'Galey', fontWeight: FontWeight.w500)),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AlertePerduFormPage()))
                  .then((_) => _fetchAlertes());
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildEmpty({required IconData icon, required String message, required String sub}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(message,
              style: TextStyle(fontFamily: 'Galey', fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(sub,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400)),
          ),
        ],
      ),
    );
  }
}

// ── Animal card ───────────────────────────────────────────────────────────────

class _AnimalCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _AnimalCard({required this.data, required this.onTap, required this.onDelete});

  String _emoji(String? espece) => switch (espece) {
        'chien' => '🐕',
        'chat' => '🐈',
        'lapin' => '🐇',
        'oiseau' => '🐦',
        'cheval' => '🐎',
        'ovin' => '🐑',
        _ => '🐾',
      };

  @override
  Widget build(BuildContext context) {
    final photoUrl = data['photo_url'] as String?;
    final nom = data['nom'] as String? ?? 'Sans nom';
    final espece = data['espece'] as String?;
    final race = data['race'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: photoUrl != null && photoUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: photoUrl, width: 64, height: 64, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _EmojiAvatar(emoji: _emoji(espece)))
                    : _EmojiAvatar(emoji: _emoji(espece)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nom,
                        style: const TextStyle(
                            fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
                    if (espece != null || race != null)
                      Text(
                        [if (espece != null) _capitalize(espece), if (race != null) race].join(' · '),
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: Colors.grey.shade400, size: 20),
                onSelected: (v) { if (v == 'delete') onDelete(); },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.red)),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmojiAvatar extends StatelessWidget {
  final String emoji;
  const _EmojiAvatar({required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64, height: 64,
      decoration: BoxDecoration(color: const Color(0xFFE0F0F3), borderRadius: BorderRadius.circular(50)),
      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 30))),
    );
  }
}

// ── Alerte card ───────────────────────────────────────────────────────────────

class _AlerteCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onRetrouve;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onUpdateLocation;

  const _AlerteCard({
    required this.data,
    required this.onRetrouve,
    required this.onDelete,
    required this.onEdit,
    required this.onUpdateLocation,
  });

  @override
  Widget build(BuildContext context) {
    final nom     = data['nom_animal'] as String? ?? 'Animal inconnu';
    final espece  = data['espece'] as String?;
    final sexe    = data['sexe'] as String?;
    final loc     = data['derniere_localisation'] as String?;
    final statut  = data['statut'] as String? ?? 'perdu';
    final photoUrl = data['photo_url'] as String?;
    final numero  = data['numero_alerte'] as String?;
    final retrouve = statut == 'retrouve';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: retrouve ? const Color(0xFF6E9E57) : Colors.orange.shade300, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(50),
            child: photoUrl != null && photoUrl.isNotEmpty
                ? CachedNetworkImage(imageUrl: photoUrl, width: 56, height: 56, fit: BoxFit.cover)
                : Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                        color: retrouve ? const Color(0xFFEEF5EA) : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(50)),
                    child: Icon(Icons.pets,
                        color: retrouve ? const Color(0xFF6E9E57) : Colors.orange.shade700, size: 28)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(nom,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: retrouve ? const Color(0xFFEEF5EA) : Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(retrouve ? 'Retrouvé' : 'Perdu',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600,
                          color: retrouve ? const Color(0xFF6E9E57) : Colors.orange.shade700)),
                ),
              ]),
              if (espece != null || sexe != null)
                Text(
                  [if (espece != null) _capitalize(espece),
                   if (sexe != null && sexe.isNotEmpty) _capitalize(sexe)].join(' · '),
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500),
                ),
              if (loc != null && loc.isNotEmpty)
                Row(children: [
                  Icon(Icons.location_on_outlined, size: 12, color: Colors.orange.shade600),
                  const SizedBox(width: 3),
                  Expanded(child: Text(loc,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              if (numero != null && numero.isNotEmpty)
                Text('N° $numero',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.orange.shade400,
                        fontWeight: FontWeight.w600)),
            ]),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.grey.shade400, size: 20),
            onSelected: (v) {
              if (v == 'retrouve') onRetrouve();
              if (v == 'edit') onEdit();
              if (v == 'location') onUpdateLocation();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit',
                child: Row(children: [Icon(Icons.edit_outlined, size: 18, color: Color(0xFF0C5C6C)),
                    SizedBox(width: 8), Text('Modifier l\'alerte', style: TextStyle(fontFamily: 'Galey'))])),
              const PopupMenuItem(value: 'location',
                child: Row(children: [Icon(Icons.my_location, size: 18, color: Color(0xFFE65100)),
                    SizedBox(width: 8), Text('Mettre à jour le lieu', style: TextStyle(fontFamily: 'Galey'))])),
              if (!retrouve)
                const PopupMenuItem(value: 'retrouve',
                  child: Row(children: [Icon(Icons.check_circle_outline, color: Color(0xFF6E9E57), size: 18),
                      SizedBox(width: 8), Text('Marquer retrouvé', style: TextStyle(fontFamily: 'Galey'))])),
              const PopupMenuItem(value: 'delete',
                child: Row(children: [Icon(Icons.delete_outline, color: Colors.red, size: 18),
                    SizedBox(width: 8), Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.red))])),
            ],
          ),
        ]),
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

Widget _adresseField(TextEditingController c, String label, IconData icon, {bool num = false}) =>
    Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]),
      child: TextField(
        controller: c,
        keyboardType: num ? TextInputType.number : TextInputType.text,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey, fontSize: 13),
          prefixIcon: Icon(icon, size: 18, color: Colors.grey),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: InputBorder.none,
        ),
      ),
    );

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
      );
}

class _TextArea extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _TextArea({required this.controller, required this.hint});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))
          ]),
      child: TextFormField(
        controller: controller,
        maxLines: 5,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.grey, fontFamily: 'Galey'),
          contentPadding: const EdgeInsets.all(14),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _SaveBtn extends StatelessWidget {
  final VoidCallback onPressed;
  const _SaveBtn({required this.onPressed});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0C5C6C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 13)),
          onPressed: onPressed,
          child: const Text('Enregistrer',
              style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
        ),
      );
}

class _StatChip extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  const _StatChip({required this.value, required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value,
                    style: TextStyle(
                        fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 16, color: color)),
                Text(label,
                    style: TextStyle(
                        fontFamily: 'Galey', fontSize: 11,
                        color: color.withOpacity(0.8))),
              ],
            ),
          ],
        ),
      );
}

class _PillChip extends StatelessWidget {
  final String label;
  final Color color;
  const _PillChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                fontFamily: 'Galey', fontSize: 12,
                color: color, fontWeight: FontWeight.w500)),
      );
}

// ── Update location bottom sheet ──────────────────────────────────────────────

class _UpdateLocationSheet extends StatefulWidget {
  final String alerteId;
  final String nomAnimal;
  final String? espece;
  final String proprietaireUid;
  final VoidCallback onSaved;

  const _UpdateLocationSheet({
    required this.alerteId,
    required this.nomAnimal,
    required this.proprietaireUid,
    this.espece,
    required this.onSaved,
  });

  @override
  State<_UpdateLocationSheet> createState() => _UpdateLocationSheetState();
}

class _UpdateLocationSheetState extends State<_UpdateLocationSheet> {
  final _supa = Supabase.instance.client;
  late final GoogleMapsPlaces _places;
  Timer? _debounce;

  final _searchCtrl = TextEditingController();
  final _rueCtrl    = TextEditingController();
  final _cpCtrl     = TextEditingController();
  final _villeCtrl  = TextEditingController();

  List<Prediction> _predictions = [];
  bool _loadingPredictions = false;
  bool _locating = false;
  bool _saving = false;
  double? _lat, _lng;

  static const _orange = Color(0xFFE65100);

  @override
  void initState() {
    super.initState();
    _places = GoogleMapsPlaces(apiKey: getApiKey());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _places.dispose();
    _searchCtrl.dispose();
    _rueCtrl.dispose();
    _cpCtrl.dispose();
    _villeCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String val) {
    _lat = null; _lng = null;
    _debounce?.cancel();
    if (val.trim().length < 3) {
      setState(() { _predictions = []; _loadingPredictions = false; });
      return;
    }
    setState(() => _loadingPredictions = true);
    _debounce = Timer(const Duration(milliseconds: 450), () => _fetchPredictions(val));
  }

  Future<void> _fetchPredictions(String input) async {
    try {
      final res = await _places.autocomplete(input,
          components: [Component(Component.country, 'fr'), Component(Component.country, 'be'),
                       Component(Component.country, 'ch'), Component(Component.country, 'lu')],
          language: 'fr');
      if (!mounted) return;
      setState(() { _predictions = res.isOkay ? res.predictions : []; _loadingPredictions = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingPredictions = false);
    }
  }

  Future<void> _selectPrediction(Prediction p) async {
    setState(() { _predictions = []; _searchCtrl.text = p.description ?? ''; });
    if (p.placeId == null) return;
    try {
      final det = await _places.getDetailsByPlaceId(p.placeId!, language: 'fr');
      if (!mounted || !det.isOkay) return;
      String num = '', route = '', cp = '', ville = '';
      for (final c in det.result.addressComponents) {
        if (c.types.contains('street_number')) num   = c.longName;
        if (c.types.contains('route'))         route = c.longName;
        if (c.types.contains('postal_code'))   cp    = c.longName;
        if (c.types.contains('locality'))      ville = c.longName;
        else if (c.types.contains('administrative_area_level_2') && ville.isEmpty) ville = c.longName;
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

  Future<void> _geolocate() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      _lat = pos.latitude; _lng = pos.longitude;
      final marks = await geo.placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isEmpty) return;
      final m = marks.first;
      setState(() {
        _rueCtrl.text   = m.street ?? '';
        _cpCtrl.text    = m.postalCode ?? '';
        _villeCtrl.text = m.locality ?? m.subLocality ?? '';
        _searchCtrl.text = [_rueCtrl.text, _cpCtrl.text, _villeCtrl.text].where((s) => s.isNotEmpty).join(', ');
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    final localisation = [_rueCtrl.text.trim(), _cpCtrl.text.trim(), _villeCtrl.text.trim()]
        .where((s) => s.isNotEmpty).join(', ');
    if (localisation.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez saisir une localisation')));
      return;
    }
    setState(() => _saving = true);
    try {
      await _supa.from('alertes_perdus').update({
        'derniere_localisation': localisation,
        'lat': _lat,
        'lng': _lng,
      }).eq('id', widget.alerteId);
      if (_lat != null && _lng != null) {
        notifyNearbyUsersAboutLostAnimal(
          lat: _lat!,
          lng: _lng!,
          nomAnimal: widget.nomAnimal,
          espece: widget.espece,
          alerteId: widget.alerteId,
          proprietaireUid: widget.proprietaireUid,
        );
      }
      widget.onSaved();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('Mettre à jour la localisation',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          // Search + GPS
          Container(
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200)),
            child: TextField(
              controller: _searchCtrl, onChanged: _onChanged,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Rechercher une adresse…',
                hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: InputBorder.none,
                prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                suffixIcon: (_loadingPredictions || _locating)
                    ? const Padding(padding: EdgeInsets.all(12),
                        child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _orange)))
                    : IconButton(icon: const Icon(Icons.my_location, size: 18, color: _orange), onPressed: _geolocate),
              ),
            ),
          ),
          if (_predictions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 4))]),
              child: Column(children: _predictions.take(5).map((p) => ListTile(
                dense: true,
                leading: const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                title: Text(p.description ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                onTap: () => _selectPrediction(p),
              )).toList()),
            ),
          const SizedBox(height: 10),
          _locField(_rueCtrl, 'Rue / Voie'),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(width: 110, child: _locField(_cpCtrl, 'Code postal', num: true)),
            const SizedBox(width: 8),
            Expanded(child: _locField(_villeCtrl, 'Ville')),
          ]),
          if (_lat != null)
            Padding(padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Icon(Icons.check_circle, size: 13, color: Colors.green.shade600),
                const SizedBox(width: 4),
                Text('GPS enregistré', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.green.shade600)),
              ])),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _orange,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _locField(TextEditingController ctrl, String hint, {bool num = false}) => Container(
    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200)),
    child: TextField(
      controller: ctrl,
      keyboardType: num ? TextInputType.number : null,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
      decoration: InputDecoration(hintText: hint,
          hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: InputBorder.none),
    ),
  );
}
