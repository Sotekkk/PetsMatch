import 'dart:async';
import 'dart:convert';
import 'dart:math' show pi, sin, cos, sqrt, atan2;
import 'package:PetsMatch/pages/chatScreen.dart';
import 'package:PetsMatch/pages/particulier/animal_trouve_form_page.dart';
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/utils/french_geo.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:PetsMatch/main.dart';

// ── Species colors ────────────────────────────────────────────────────────────

const _especeBg = {
  'chien':  Color(0xFFFFF7ED), 'chat':   Color(0xFFFDF4FF),
  'cheval': Color(0xFFF0FDF4), 'lapin':  Color(0xFFFFF0F6),
  'oiseau': Color(0xFFECFEFF), 'nac':    Color(0xFFF5F3FF),
  'ovin':   Color(0xFFFFFBEB), 'caprin': Color(0xFFF7FEE7),
  'porcin': Color(0xFFFFF1F2), 'autre':  Color(0xFFF9FAFB),
};
const _especeText = {
  'chien':  Color(0xFFEA580C), 'chat':   Color(0xFF9333EA),
  'cheval': Color(0xFF16A34A), 'lapin':  Color(0xFFDB2777),
  'oiseau': Color(0xFF0891B2), 'nac':    Color(0xFF7C3AED),
  'ovin':   Color(0xFFD97706), 'caprin': Color(0xFF65A30D),
  'porcin': Color(0xFFE11D48), 'autre':  Color(0xFF6B7280),
};
const _especeBorder = {
  'chien':  Color(0xFFFED7AA), 'chat':   Color(0xFFE9D5FF),
  'cheval': Color(0xFFBBF7D0), 'lapin':  Color(0xFFFBCFE8),
  'oiseau': Color(0xFFA5F3FC), 'nac':    Color(0xFFDDD6FE),
  'ovin':   Color(0xFFFDE68A), 'caprin': Color(0xFFD9F99D),
  'porcin': Color(0xFFFECDD3), 'autre':  Color(0xFFE5E7EB),
};
const _especeEmoji = {
  'chien': '🐕', 'chat': '🐈', 'cheval': '🐴', 'lapin': '🐇',
  'oiseau': '🦜', 'nac': '🦎', 'ovin': '🐑', 'caprin': '🐐',
  'porcin': '🐷', 'autre': '🐾',
};
const _especeHue = {
  'chien':  240.0, 'chat':   300.0, 'cheval': 120.0, 'lapin':  330.0,
  'oiseau': 180.0, 'nac':    270.0, 'ovin':    60.0, 'caprin':  90.0,
  'porcin':   0.0, 'autre':   30.0,
};
const _breedFiles = {
  'chien': 'dog_breeds', 'chat': 'cat_breeds', 'cheval': 'horse_breeds',
  'lapin': 'rabbit_breeds', 'oiseau': 'bird_breeds', 'nac': 'nac_breeds',
  'ovin': 'sheep_breeds', 'caprin': 'goat_breeds', 'porcin': 'pig_breeds',
};

// ─────────────────────────────────────────────────────────────────────────────

class AnimauxPerdusPage extends StatefulWidget {
  final String? initialAlertId;
  const AnimauxPerdusPage({super.key, this.initialAlertId});

  @override
  State<AnimauxPerdusPage> createState() => _AnimauxPerdusPageState();
}

class _AnimauxPerdusPageState extends State<AnimauxPerdusPage> {
  static const _orange = Color(0xFFE65100);
  static const _teal   = Color(0xFF0C5C6C);

  bool _showMap = false;
  List<Map<String, dynamic>> _alertes = [];
  List<Map<String, dynamic>> _trouves = [];
  bool _loading = true;
  GoogleMapController? _mapController;
  bool _locating = false;

  // Filtres
  String _filterType = 'tous';
  String? _filterEspece;
  String _searchLieu = '';
  String _filterRace = '';
  String _filterPays = 'France';
  String _filterRegion = '';
  String _filterDept = '';
  int? _filterDistanceKm;
  double? _userLat, _userLng;
  List<String> _breeds = [];
  List<String> _raceSuggestions = [];
  bool _showRaceSugg = false;
  final _raceFocusNode = FocusNode();
  final _raceCtrl = TextEditingController();
  final _lieuCtrl = TextEditingController();

  // Google Places pour le filtre lieu
  late final GoogleMapsPlaces _places;
  Timer? _locDebounce;
  List<Prediction> _locPredictions = [];
  bool _loadingLoc = false;

  static const _especes = [
    'tous', 'chien', 'chat', 'lapin', 'oiseau', 'nac',
    'cheval', 'ovin', 'caprin', 'porcin', 'autre'
  ];

  static const _regionsByPaysList = <String, List<String>>{
    'France': [
      'Île-de-France', 'Auvergne-Rhône-Alpes', 'Bretagne', 'Normandie',
      'Hauts-de-France', 'Grand Est', 'Pays de la Loire', 'Nouvelle-Aquitaine',
      'Occitanie', 'Provence-Alpes-Côte d\'Azur', 'Bourgogne-Franche-Comté',
      'Centre-Val de Loire', 'Corse', 'Guadeloupe', 'Martinique', 'Guyane',
      'La Réunion', 'Mayotte',
    ],
    'Belgique': ['Bruxelles-Capitale', 'Flandre', 'Wallonie'],
    'Suisse': ['Genève', 'Vaud', 'Zurich', 'Berne', 'Valais', 'Neuchâtel'],
    'Luxembourg': ['Luxembourg'],
  };

  Color get _accentColor => _filterType == 'trouve' ? _teal : _orange;

  int get _activeFilterCount => [
    _filterType != 'tous' ? 1 : 0,
    (_filterEspece != null && _filterEspece != 'tous') ? 1 : 0,
    _filterRace.isNotEmpty ? 1 : 0,
    _searchLieu.isNotEmpty ? 1 : 0,
    _filterDistanceKm != null ? 1 : 0,
    (_filterRegion.isNotEmpty || _filterDept.isNotEmpty) ? 1 : 0,
  ].fold(0, (a, b) => a + b);

  List<Map<String, dynamic>> get _filtered {
    List<Map<String, dynamic>> all = [];
    if (_filterType == 'perdu' || _filterType == 'tous') {
      all.addAll(_alertes.map((a) => {...a, '__type': 'perdu'}));
    }
    if (_filterType == 'trouve' || _filterType == 'tous') {
      all.addAll(_trouves.map((a) => {...a, '__type': 'trouve'}));
    }
    return all.where((a) {
      final type = a['__type'] as String;
      if (_filterEspece != null && _filterEspece != 'tous') {
        if ((a['espece'] as String? ?? '').toLowerCase() != _filterEspece) return false;
      }
      if (_filterRace.isNotEmpty &&
          !(a['race'] as String? ?? '').toLowerCase().contains(_filterRace.toLowerCase())) {
        return false;
      }
      final loc = '${a['ville'] ?? ''} ${a['region'] ?? ''} '
          '${type == 'perdu' ? (a['derniere_localisation'] ?? '') : (a['localisation_adresse'] ?? '')}'
          .toLowerCase();
      if (_filterRegion.isNotEmpty) {
        final depts = FrenchGeo.departmentsInRegion(_filterRegion);
        if (!loc.contains(_filterRegion.toLowerCase()) &&
            !depts.any((d) => loc.contains(d.toLowerCase()))) return false;
      }
      if (_filterDept.isNotEmpty && !loc.contains(_filterDept.toLowerCase())) return false;
      if (_searchLieu.isNotEmpty && !loc.contains(_searchLieu.toLowerCase())) return false;
      if (_filterDistanceKm != null && _userLat != null && _userLng != null) {
        final lat = (a['lat'] as num?)?.toDouble();
        final lng = (a['lng'] as num?)?.toDouble();
        if (lat != null && lng != null &&
            _haversine(_userLat!, _userLng!, lat, lng) > _filterDistanceKm!) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
            sin(dLng / 2) * sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  @override
  void initState() {
    super.initState();
    _places = GoogleMapsPlaces(apiKey: getApiKey());
    _load();
    _loadDefaultVille();
    _fetchUserPosition();
    // Délai pour laisser le onTap des suggestions se déclencher avant de les masquer
    _raceFocusNode.addListener(() {
      if (!_raceFocusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) setState(() => _showRaceSugg = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _raceFocusNode.dispose();
    _raceCtrl.dispose();
    _lieuCtrl.dispose();
    _locDebounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchUserPosition() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.medium));
      if (mounted) {
        setState(() {
          _userLat = pos.latitude;
          _userLng = pos.longitude;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDefaultVille() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('ville, ville_elevage')
          .eq('uid', uid)
          .maybeSingle();
      if (row != null && mounted) {
        final v = (row['ville_elevage'] as String?)?.isNotEmpty == true
            ? row['ville_elevage'] as String
            : (row['ville'] as String?) ?? '';
        if (v.isNotEmpty) {
          _lieuCtrl.text = v;
          setState(() => _searchLieu = v);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadBreeds(String espece) async {
    final file = _breedFiles[espece];
    if (file == null) {
      setState(() => _breeds = []);
      return;
    }
    try {
      final raw = await rootBundle.loadString('assets/$file.json');
      final list = List<String>.from(json.decode(raw) as List);
      if (mounted) setState(() => _breeds = list);
    } catch (_) {
      if (mounted) setState(() => _breeds = []);
    }
  }

  void _onRaceInput(String val) {
    _filterRace = val;
    if (val.isEmpty) {
      setState(() {
        _raceSuggestions = [];
        _showRaceSugg = false;
      });
      return;
    }
    final q = val.toLowerCase();
    final matches = _breeds.where((b) => b.toLowerCase().contains(q)).take(6).toList();
    setState(() {
      _raceSuggestions = matches;
      _showRaceSugg = matches.isNotEmpty;
    });
  }

  // ── Location autocomplete ─────────────────────────────────────────────────

  void _onLocChanged(String val) {
    _locDebounce?.cancel();
    setState(() { _searchLieu = val; _locPredictions = []; });
    if (val.trim().length < 3) return;
    setState(() => _loadingLoc = true);
    _locDebounce = Timer(const Duration(milliseconds: 450), () => _fetchLocPredictions(val));
  }

  Future<void> _fetchLocPredictions(String input) async {
    try {
      final res = await _places.autocomplete(
        input,
        components: [
          Component(Component.country, 'fr'), Component(Component.country, 'be'),
          Component(Component.country, 'ch'), Component(Component.country, 'lu'),
        ],
        language: 'fr',
      );
      if (!mounted) return;
      setState(() { _locPredictions = res.isOkay ? res.predictions : []; _loadingLoc = false; });
    } catch (_) {
      if (mounted) setState(() { _locPredictions = []; _loadingLoc = false; });
    }
  }

  Future<void> _selectLocPrediction(Prediction p) async {
    setState(() { _locPredictions = []; _lieuCtrl.text = p.description ?? ''; _searchLieu = p.description ?? ''; });
    if (p.placeId == null) return;
    try {
      final det = await _places.getDetailsByPlaceId(p.placeId!, language: 'fr');
      if (!mounted || !det.isOkay) return;
      String ville = '', region = '', pays = '';
      for (final c in det.result.addressComponents) {
        if (c.types.contains('locality'))                        ville  = c.longName;
        else if (c.types.contains('administrative_area_level_2') && ville.isEmpty) ville = c.longName;
        if (c.types.contains('administrative_area_level_1'))     region = c.longName;
        if (c.types.contains('country'))                         pays   = c.longName;
      }
      setState(() {
        if (ville.isNotEmpty) { _lieuCtrl.text = ville; _searchLieu = ville; }
        if (pays.isNotEmpty)   _filterPays   = pays;
        if (region.isNotEmpty) _filterRegion = region;
      });
    } catch (_) {}
  }

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        Supabase.instance.client
            .from('alertes_perdus')
            .select()
            .eq('statut', 'perdu')
            .order('created_at', ascending: false),
        Supabase.instance.client
            .from('animaux_trouves')
            .select()
            .order('created_at', ascending: false),
      ]);
      if (mounted) {
        setState(() {
          _alertes = List<Map<String, dynamic>>.from(results[0] as List);
          _trouves = List<Map<String, dynamic>>.from(results[1] as List);
          _loading = false;
        });
        if (widget.initialAlertId != null) {
          final target = _alertes.firstWhere(
            (a) => a['id'] == widget.initialAlertId,
            orElse: () => {},
          );
          if (target.isNotEmpty) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _showAlertDetail(target));
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _retrouveAlerte(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Animal retrouvé ?',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Confirmer que votre animal a été retrouvé ?',
            style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler',
                style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6F767B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6E9E57), foregroundColor: Colors.white),
            child: const Text('Confirmer', style: TextStyle(fontFamily: 'Galey')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await Supabase.instance.client.from('alertes_perdus').update({
      'statut': 'retrouve',
      'date_retrouve': DateTime.now().toIso8601String().substring(0, 10),
    }).eq('id', id);
    _load();
  }

  Future<void> _deleteAlerte(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer l\'alerte ?',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Cette alerte sera supprimée définitivement.',
            style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler',
                style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6F767B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await Supabase.instance.client.from('alertes_perdus').delete().eq('id', id);
    _load();
  }

  Future<void> _deleteTrouve(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer la déclaration ?',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Cette déclaration sera supprimée définitivement.',
            style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler',
                style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6F767B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await Supabase.instance.client.from('animaux_trouves').delete().eq('id', id);
    _load();
  }

  void _showAlertDetail(Map<String, dynamic> a) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AlertDetailSheet(
        alerte: a,
        onShare: () {
          Navigator.pop(context);
          _share(a);
        },
        onContact: () {
          Navigator.pop(context);
          _contact(a, type: 'perdu');
        },
      ),
    );
  }

  void _showTrouveDetail(Map<String, dynamic> a) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TrouveDetailSheet(
        trouve: a,
        onContact: () {
          Navigator.pop(context);
          _contact(a, type: 'trouve');
        },
        onShare: () {
          Navigator.pop(context);
          _shareTrouve(a);
        },
      ),
    );
  }

  void _share(Map<String, dynamic> a) {
    final nom     = (a['nom_animal'] ?? 'Animal') as String;
    final espece  = (a['espece'] ?? '') as String;
    final lieu    = (a['derniere_localisation'] ?? '') as String;
    final dateStr = a['date_perte'] as String?;
    final date    = dateStr != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(dateStr))
        : '';
    final desc    = (a['description'] as String?) ?? '';
    final contact = (a['contact'] as String?) ?? '';
    final numero  = (a['numero_alerte'] as String?) ?? '';

    const url = 'https://petsmatch.fr/animaux-perdus';
    final text = [
      '🚨 ANIMAL PERDU — $nom ($espece)${numero.isNotEmpty ? ' [N° $numero]' : ''}',
      if (lieu.isNotEmpty) '📍 Dernière localisation : $lieu',
      if (date.isNotEmpty) '📅 Disparu le $date',
      if (desc.isNotEmpty) desc,
      if (contact.isNotEmpty) '📞 Contact : $contact',
      '',
      'Si vous l\'avez vu, contactez le propriétaire ou signalez sur PetsMatch 🐾\n$url',
    ].join('\n');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _ShareSheet(text: text, url: url, nom: 'Animal perdu : $nom'),
    );
  }

  void _shareTrouve(Map<String, dynamic> a) {
    final espece  = (a['espece'] ?? 'animal') as String;
    final race    = (a['race'] as String?) ?? '';
    final lieu    = (a['localisation_adresse'] ?? a['ville'] ?? '') as String;
    final dateStr = a['date_trouve'] as String?;
    final date    = dateStr != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(dateStr))
        : '';
    final desc    = (a['description'] as String?) ?? '';

    const url = 'https://petsmatch.fr/animaux-perdus';
    final nom = '${espece[0].toUpperCase()}${espece.substring(1)}'
        '${race.isNotEmpty ? ' ($race)' : ''}';
    final text = [
      '🐾 ANIMAL TROUVÉ — $nom',
      if (lieu.isNotEmpty) '📍 Trouvé à : $lieu',
      if (date.isNotEmpty) '📅 Trouvé le $date',
      if (desc.isNotEmpty) desc,
      '',
      'Cet animal cherche son propriétaire ! Contactez le déclarant sur PetsMatch 🐾\n$url',
    ].join('\n');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareSheet(text: text, url: url, nom: 'Animal trouvé : $nom'),
    );
  }

  Future<void> _contact(Map<String, dynamic> a, {String type = 'perdu'}) async {
    // For trouvé with messaging disabled, show contact info directly
    if (type == 'trouve') {
      final accepte = a['contact_messagerie'] as bool? ?? true;
      if (!accepte) {
        final phone = a['contact_telephone'] as String?;
        final email = a['contact_email'] as String?;
        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => _ContactInfoSheet(phone: phone, email: email),
        );
        return;
      }
    }

    final ownerId = type == 'perdu'
        ? a['uid_proprietaire'] as String?
        : a['user_uid'] as String?;
    if (ownerId == null) return;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;
    if (currentUid == ownerId) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('C\'est votre propre déclaration')));
      return;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      final existing = await firestore
          .collection('conversations')
          .where('participants', arrayContains: currentUid)
          .get();

      String? conversationId;
      for (final doc in existing.docs) {
        final participants =
            List<String>.from(doc.data()['participants'] ?? []);
        if (participants.contains(ownerId)) {
          conversationId = doc.id;
          break;
        }
      }

      bool isNew = false;
      if (conversationId == null) {
        final docRef = await firestore.collection('conversations').add({
          'participants': [currentUid, ownerId],
          'lastMessage': '',
          'timestamp': FieldValue.serverTimestamp(),
          'unreadCount': {currentUid: 0, ownerId: 0},
          'categorie': 'animaux-perdus',
        });
        conversationId = docRef.id;
        isNew = true;
      } else {
        final conv = existing.docs.firstWhere((d) => d.id == conversationId);
        if (conv.data()['categorie'] != 'animaux-perdus') {
          await firestore
              .collection('conversations')
              .doc(conversationId)
              .update({'categorie': 'animaux-perdus'});
        }
      }

      if (!mounted) return;
      final alerteId = a['id'] as String?;
      final nomAnimal = a['nom_animal'] as String?;
      Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              conversationId: conversationId!,
              eleveurId: ownerId,
              alerteId: alerteId,
              nomAnimal: nomAnimal,
              isNewConversation: isNew,
            ),
          ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _showChipSearch() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => ChipSearchSheet(
        onTapAlerte: (a) { Navigator.pop(sheetCtx); _showAlertDetail(a); },
        onTapTrouve: (a) { Navigator.pop(sheetCtx); _showTrouveDetail(a); },
      ),
    );
  }

  Future<void> _recenterMap() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.medium));
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
            target: LatLng(pos.latitude, pos.longitude), zoom: 12),
      ));
    } catch (_) {
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeFilterCount;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _accentColor,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _showMap ? 'Carte — Perdus & Trouvés' : 'Perdus & Trouvés',
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.nfc_outlined, color: Colors.white),
            tooltip: 'Recherche par puce',
            onPressed: _showChipSearch,
          ),
          Stack(clipBehavior: Clip.none, children: [
            IconButton(
              icon: const Icon(Icons.tune_outlined, color: Colors.white),
              tooltip: 'Filtres',
              onPressed: _openFilterSheet,
            ),
            if (active > 0)
              Positioned(
                right: 6, top: 6,
                child: Container(
                  width: 16, height: 16,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: Center(
                    child: Text('$active',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _accentColor)),
                  ),
                ),
              ),
          ]),
          IconButton(
            icon: Icon(_showMap ? Icons.list_alt_outlined : Icons.map_outlined, color: Colors.white),
            tooltip: _showMap ? 'Vue liste' : 'Vue carte',
            onPressed: () => setState(() => _showMap = !_showMap),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _accentColor))
          : _showMap
              ? _buildMap()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _accentColor,
                  child: _buildList(),
                ),
    );
  }

  Future<void> _openFilterSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void applyFilter(VoidCallback fn) { setState(fn); setSheet(() {}); }
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            builder: (_, ctrl) => SingleChildScrollView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Handle
                Center(child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),

                // Type
                const Text('Type', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 8),
                Row(children: [
                  for (final entry in [('perdu', '🚨 Perdus'), ('trouve', '🐾 Trouvés'), ('tous', 'Tous')])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => applyFilter(() => _filterType = entry.$1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: _filterType == entry.$1 ? _accentColor : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(entry.$2,
                              style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
                                  color: _filterType == entry.$1 ? Colors.white : Colors.black87)),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 16),

                // Espèce
                const Text('Espèce', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: _especes.map((e) {
                  final isAll = e == 'tous';
                  final selected = isAll ? (_filterEspece == null || _filterEspece == 'tous') : _filterEspece == e;
                  return GestureDetector(
                    onTap: () => applyFilter(() { _filterEspece = isAll ? null : e; if (!isAll) _loadBreeds(e); }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected ? (_especeText[e] ?? _accentColor) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isAll ? 'Toutes' : '${_especeEmoji[e] ?? ''} ${e[0].toUpperCase()}${e.substring(1)}',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : Colors.black87),
                      ),
                    ),
                  );
                }).toList()),
                const SizedBox(height: 16),

                // Lieu
                const Text('Lieu', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: _lieuCtrl,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Ville, région, lieu…',
                    hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
                    prefixIcon: const Icon(Icons.location_on_outlined, size: 18, color: Colors.grey),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _accentColor)),
                    filled: true, fillColor: const Color(0xFFF8F8F8),
                    suffixIcon: _searchLieu.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => applyFilter(() { _lieuCtrl.clear(); _searchLieu = ''; _filterRegion = ''; _filterPays = ''; }))
                        : null,
                  ),
                  onChanged: (v) => applyFilter(() => _searchLieu = v),
                ),
                const SizedBox(height: 12),

                // Geo dropdowns
                Row(children: [
                  Expanded(child: _GeoDropdown(
                    value: _filterPays.isEmpty ? null : _filterPays,
                    hint: 'Pays',
                    items: const ['France', 'Belgique', 'Suisse', 'Luxembourg'],
                    onChanged: (v) => applyFilter(() { _filterPays = v ?? ''; _filterRegion = ''; _filterDept = ''; }),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _GeoDropdown(
                    value: _filterRegion.isEmpty ? null : _filterRegion,
                    hint: 'Région',
                    items: _filterPays.isNotEmpty ? (_regionsByPaysList[_filterPays] ?? []) : [],
                    onChanged: (v) => applyFilter(() { _filterRegion = v ?? ''; _filterDept = ''; }),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _GeoDropdown(
                    value: _filterDept.isEmpty ? null : _filterDept,
                    hint: 'Dép.',
                    items: _filterRegion.isNotEmpty ? FrenchGeo.departmentsInRegion(_filterRegion) : [],
                    onChanged: (v) => applyFilter(() => _filterDept = v ?? ''),
                  )),
                ]),

                // Distance
                if (_userLat != null) ...[
                  const SizedBox(height: 12),
                  const Text('Rayon', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [null, 5, 10, 25, 50, 100].map((d) {
                    final selected = _filterDistanceKm == d;
                    return GestureDetector(
                      onTap: () => applyFilter(() => _filterDistanceKm = d),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected ? _accentColor : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(d == null ? 'Tous' : '$d km',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                                color: selected ? Colors.white : Colors.black87)),
                      ),
                    );
                  }).toList()),
                ],

                const SizedBox(height: 24),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => applyFilter(() {
                        _filterType = 'tous'; _filterEspece = null; _filterRace = ''; _raceCtrl.clear();
                        _searchLieu = ''; _lieuCtrl.clear(); _filterRegion = ''; _filterPays = 'France'; _filterDept = ''; _filterDistanceKm = null;
                      }),
                      style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.grey.shade300), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('Réinitialiser', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(backgroundColor: _accentColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('Appliquer', style: TextStyle(color: Colors.white, fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActiveFilterChips() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          if (_filterType != 'tous')
            _ActiveFilterChip(
              label: _filterType == 'perdu' ? '🚨 Perdus' : '🐾 Trouvés',
              onRemove: () => setState(() => _filterType = 'tous'),
            ),
          if (_filterEspece != null && _filterEspece != 'tous')
            _ActiveFilterChip(
              label: '${_especeEmoji[_filterEspece] ?? ''} ${_filterEspece![0].toUpperCase()}${_filterEspece!.substring(1)}',
              onRemove: () => setState(() => _filterEspece = null),
            ),
          if (_filterRace.isNotEmpty)
            _ActiveFilterChip(
              label: _filterRace,
              onRemove: () => setState(() { _filterRace = ''; _raceCtrl.clear(); }),
            ),
          if (_searchLieu.isNotEmpty)
            _ActiveFilterChip(
              label: '📍 $_searchLieu',
              onRemove: () => setState(() { _searchLieu = ''; _lieuCtrl.clear(); _filterRegion = ''; _filterPays = ''; }),
            ),
          if (_filterDistanceKm != null)
            _ActiveFilterChip(
              label: '${_filterDistanceKm} km',
              onRemove: () => setState(() => _filterDistanceKm = null),
            ),
        ]),
      ),
    );
  }

  Widget _buildList() {
    final list = _filtered;
    return Column(children: [
      if (_activeFilterCount > 0) _buildActiveFilterChips(),
      Expanded(
        child: list.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.search_off, size: 60, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('Aucun résultat',
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 16,
                          color: Colors.grey.shade500)),
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final item = list[i];
                  final type = item['__type'] as String;
                  final ownerId = type == 'perdu'
                      ? item['uid_proprietaire']
                      : item['uid_declarant'];
                  final isOwn = ownerId == _currentUid;
                  return _AlertCard(
                    alerte: item,
                    type: type,
                    onTap: () => type == 'perdu'
                        ? _showAlertDetail(item)
                        : _showTrouveDetail(item),
                    onShare: type == 'perdu' ? () => _share(item) : () => _shareTrouve(item),
                    onContact: () => _contact(item, type: type),
                    onRetrouve: (type == 'perdu' && isOwn)
                        ? () => _retrouveAlerte(item['id'] as String)
                        : null,
                    onEdit: (type == 'trouve' && isOwn)
                        ? () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => AnimalTrouveFormPage(existing: item)))
                            .then((_) => _load())
                        : null,
                    onDelete: isOwn
                        ? () => type == 'perdu'
                            ? _deleteAlerte(item['id'] as String)
                            : _deleteTrouve(item['id'] as String)
                        : null,
                  );
                },
              ),
      ),
    ]);
  }

  Widget _buildFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Type toggle: Perdus | Trouvés | Tous
        Row(children: [
          _TypeChip(
              label: '🚨 Perdus',
              value: 'perdu',
              current: _filterType,
              color: _orange,
              onTap: () => setState(() => _filterType = 'perdu')),
          const SizedBox(width: 6),
          _TypeChip(
              label: '🐾 Trouvés',
              value: 'trouve',
              current: _filterType,
              color: _teal,
              onTap: () => setState(() => _filterType = 'trouve')),
          const SizedBox(width: 6),
          _TypeChip(
              label: 'Tous',
              value: 'tous',
              current: _filterType,
              color: const Color(0xFF6B7280),
              onTap: () => setState(() => _filterType = 'tous')),
        ]),
        const SizedBox(height: 8),
        // Lieu search avec Google Places
        Stack(clipBehavior: Clip.none, children: [
          SizedBox(
            height: 38,
            child: TextField(
              controller: _lieuCtrl,
              onChanged: _onLocChanged,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Ville, région ou lieu…',
                hintStyle: const TextStyle(
                    fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
                prefixIcon: const Icon(Icons.location_on_outlined, size: 18, color: Colors.grey),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: _accentColor)),
                filled: true,
                fillColor: const Color(0xFFF8F8F8),
                suffixIcon: _loadingLoc
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : _searchLieu.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () => setState(() {
                              _lieuCtrl.clear();
                              _searchLieu = '';
                              _filterRegion = '';
                              _filterPays = '';
                              _locPredictions = [];
                            }))
                        : null,
              ),
            ),
          ),
          if (_locPredictions.isNotEmpty)
            Positioned(
              top: 42,
              left: 0,
              right: 0,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _locPredictions.take(5).map((p) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                    title: Text(p.description ?? '',
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                    onTap: () => _selectLocPrediction(p),
                  )).toList(),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        // Espece chips
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _especes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final e = _especes[i];
              final isAll = e == 'tous';
              final selected = isAll
                  ? (_filterEspece == null || _filterEspece == 'tous')
                  : _filterEspece == e;
              final chipBg =
                  selected ? (_especeText[e] ?? _accentColor) : Colors.grey.shade100;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _filterEspece = isAll ? null : e;
                    _filterRace = '';
                    _raceCtrl.clear();
                    _raceSuggestions = [];
                    _showRaceSugg = false;
                  });
                  if (!isAll) _loadBreeds(e);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                      color: chipBg, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    '${_especeEmoji[e] ?? ''}  ${e[0].toUpperCase()}${e.substring(1)}',
                    style: TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : Colors.black87),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // Pays / Région / Département
        Row(children: [
          Expanded(
            child: _GeoDropdown(
              value: _filterPays.isEmpty ? null : _filterPays,
              hint: 'Pays',
              items: const ['France', 'Belgique', 'Suisse', 'Luxembourg'],
              onChanged: (v) => setState(() {
                _filterPays = v ?? '';
                _filterRegion = '';
                _filterDept = '';
              }),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _GeoDropdown(
              value: _filterRegion.isEmpty ? null : _filterRegion,
              hint: 'Région',
              items: _filterPays.isNotEmpty
                  ? (_regionsByPaysList[_filterPays] ?? [])
                  : const [],
              onChanged: (v) =>
                  setState(() {
                    _filterRegion = v ?? '';
                    _filterDept = '';
                  }),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _GeoDropdown(
              value: _filterDept.isEmpty ? null : _filterDept,
              hint: 'Dép.',
              items: _filterRegion.isNotEmpty
                  ? FrenchGeo.departmentsInRegion(_filterRegion)
                  : const [],
              onChanged: (v) => setState(() => _filterDept = v ?? ''),
            ),
          ),
        ]),
        // Distance filter (shown when GPS position available)
        if (_userLat != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.near_me_outlined, size: 15, color: Colors.grey),
            const SizedBox(width: 6),
            const Text('Rayon :',
                style: TextStyle(
                    fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [null, 5, 10, 25, 50, 100].map((d) {
                    final selected = _filterDistanceKm == d;
                    return GestureDetector(
                      onTap: () => setState(() => _filterDistanceKm = d),
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: selected ? _accentColor : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          d == null ? 'Tous' : '$d km',
                          style: TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: selected ? Colors.white : Colors.black87),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ]),
        ],
        // Reset button
        if (_filterEspece != null || _filterRace.isNotEmpty ||
            _searchLieu.isNotEmpty || _filterPays.isNotEmpty ||
            _filterRegion.isNotEmpty || _filterDept.isNotEmpty ||
            _filterDistanceKm != null) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => setState(() {
                _filterEspece = null;
                _filterRace = '';
                _searchLieu = '';
                _filterPays = '';
                _filterRegion = '';
                _filterDept = '';
                _filterDistanceKm = null;
                _raceCtrl.clear();
                _lieuCtrl.clear();
                _raceSuggestions = [];
                _showRaceSugg = false;
                _locPredictions = [];
              }),
              child: const Text('Réinitialiser les filtres',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 11,
                      color: Color(0xFF6F767B),
                      decoration: TextDecoration.underline)),
            ),
          ),
        ],
        // Race autocomplete (only when espece selected)
        if (_filterEspece != null && _filterEspece != 'tous') ...[
          const SizedBox(height: 8),
          Stack(clipBehavior: Clip.none, children: [
            SizedBox(
              height: 38,
              child: TextField(
                controller: _raceCtrl,
                focusNode: _raceFocusNode,
                onChanged: _onRaceInput,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Race (optionnel)…',
                  hintStyle: const TextStyle(
                      fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
                  prefixIcon:
                      const Icon(Icons.pets, size: 16, color: Colors.grey),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: _accentColor)),
                  filled: true,
                  fillColor: const Color(0xFFF8F8F8),
                  suffixIcon: _filterRace.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _raceCtrl.clear();
                            setState(() {
                              _filterRace = '';
                              _raceSuggestions = [];
                              _showRaceSugg = false;
                            });
                          })
                      : null,
                ),
              ),
            ),
            if (_showRaceSugg)
              Positioned(
                top: 40,
                left: 0,
                right: 0,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _raceSuggestions
                        .map((r) => ListTile(
                              dense: true,
                              title: Text(r,
                                  style: const TextStyle(
                                      fontFamily: 'Galey', fontSize: 13)),
                              onTap: () {
                                _raceCtrl.text = r;
                                setState(() {
                                  _filterRace = r;
                                  _showRaceSugg = false;
                                });
                                _raceFocusNode.unfocus();
                              },
                            ))
                        .toList(),
                  ),
                ),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _buildMap() {
    final list = _filtered;
    final markers = <Marker>{};
    for (final a in list) {
      final type = a['__type'] as String;
      final lat = (a['lat'] as num?)?.toDouble();
      final lng = (a['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final espece = (a['espece'] as String? ?? '').toLowerCase();
      final hue = type == 'trouve'
          ? BitmapDescriptor.hueGreen
          : (_especeHue[espece] ?? BitmapDescriptor.hueOrange);
      final emoji = _especeEmoji[espece] ?? '🐾';
      final nom = type == 'perdu'
          ? (a['nom_animal'] as String? ?? '')
          : '$emoji ${espece.isNotEmpty ? espece[0].toUpperCase() + espece.substring(1) : 'Animal'}';
      final snippetLoc = type == 'perdu'
          ? (a['derniere_localisation'] as String? ?? '')
          : (a['ville'] as String? ?? '');
      markers.add(Marker(
        markerId: MarkerId('${type}_${a['id']}'),
        position: LatLng(lat, lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        infoWindow: InfoWindow(
          title: '${type == 'perdu' ? '🚨' : '🐾'} $nom',
          snippet: [
            espece,
            if ((a['race'] as String?)?.isNotEmpty == true) a['race'] as String,
            if (snippetLoc.isNotEmpty) '📍 $snippetLoc',
          ].join(' · '),
        ),
        onTap: () =>
            type == 'perdu' ? _showAlertDetail(a) : _showTrouveDetail(a),
      ));
    }

    return Stack(children: [
      // ── Carte plein écran ────────────────────────────────────────────────
      GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: LatLng(46.603354, 1.888334),
          zoom: 5.5,
        ),
        markers: markers,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: true,
        onMapCreated: (c) => _mapController = c,
      ),

      // ── Bouton recentrer ─────────────────────────────────────────────────
      Positioned(
        right: 12, bottom: 80,
        child: FloatingActionButton.small(
          heroTag: 'recenter',
          backgroundColor: Colors.white,
          onPressed: _locating ? null : _recenterMap,
          child: _locating
              ? SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _accentColor))
              : Icon(Icons.my_location, color: _accentColor, size: 20),
        ),
      ),

      // ── Légende ──────────────────────────────────────────────────────────
      Positioned(
        left: 12, bottom: 16,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFE65100), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              const Text('Perdu', style: TextStyle(fontFamily: 'Galey', fontSize: 11)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              const Text('Trouvé', style: TextStyle(fontFamily: 'Galey', fontSize: 11)),
            ]),
          ]),
        ),
      ),

      if (markers.isEmpty && list.isNotEmpty)
        Positioned(
          bottom: 16, left: 80, right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Text(
              'Certaines déclarations n\'ont pas de coordonnées GPS.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.orange.shade800),
              textAlign: TextAlign.center,
            ),
          ),
        ),
    ]);
  }
}

// ── Active filter chip (dans la barre de filtres actifs) ──────────────────────

class _ActiveFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _ActiveFilterChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0C5C6C).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF0C5C6C).withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
            fontWeight: FontWeight.w600, color: Color(0xFF0C5C6C))),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onRemove,
          child: const Icon(Icons.close, size: 14, color: Color(0xFF0C5C6C)),
        ),
      ]),
    );
  }
}

// ── Type chip ─────────────────────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  final String label, value, current;
  final Color color;
  final VoidCallback onTap;
  const _TypeChip({
    required this.label,
    required this.value,
    required this.current,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = current == value;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? color : Colors.grey.shade300, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontFamily: 'Galey',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : Colors.grey.shade600),
        ),
      ),
    );
  }
}

// ── Alert Card ────────────────────────────────────────────────────────────────

class _AlertCard extends StatelessWidget {
  final Map<String, dynamic> alerte;
  final String type;
  final VoidCallback onTap;
  final VoidCallback? onShare;
  final VoidCallback onContact;
  final VoidCallback? onRetrouve;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  const _AlertCard({
    required this.alerte,
    required this.type,
    required this.onTap,
    this.onShare,
    required this.onContact,
    this.onRetrouve,
    this.onDelete,
    this.onEdit,
  });

  static const _teal = Color(0xFF0C5C6C);

  void _showOwnerActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          if (onEdit != null)
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F4F6),
                child: Icon(Icons.edit_outlined, color: Color(0xFF0C5C6C)),
              ),
              title: const Text('Modifier la déclaration',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.pop(context);
                onEdit!();
              },
            ),
          if (onRetrouve != null)
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFEEF5EA),
                child: Icon(Icons.check_circle_outline,
                    color: Color(0xFF6E9E57)),
              ),
              title: const Text('Animal retrouvé !',
                  style: TextStyle(
                      fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.pop(context);
                onRetrouve!();
              },
            ),
          if (onDelete != null)
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFFFEBEE),
                child: Icon(Icons.delete_outline, color: Colors.red),
              ),
              title: Text(
                  type == 'perdu'
                      ? 'Supprimer l\'alerte'
                      : 'Supprimer la déclaration',
                  style: const TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                onDelete!();
              },
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPerdu = type == 'perdu';
    final espece = ((alerte['espece'] ?? '') as String).toLowerCase();
    final nom = isPerdu ? (alerte['nom_animal'] ?? '') as String : '';
    final race = (alerte['race'] ?? '') as String;
    final sexe = (alerte['sexe'] as String?) ?? '';
    final lieu = isPerdu
        ? (alerte['derniere_localisation'] ?? alerte['ville'] ?? '') as String
        : (alerte['localisation_adresse'] ?? alerte['ville'] ?? '') as String;

    String? photoUrl;
    if (isPerdu) {
      photoUrl = alerte['photo_url'] as String?;
    } else {
      final photos = alerte['photos'];
      if (photos is List && photos.isNotEmpty) {
        photoUrl = photos.first as String?;
      }
    }

    final dateStr =
        isPerdu ? alerte['date_perte'] as String? : alerte['date_trouve'] as String?;
    final date = dateStr != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(dateStr))
        : '';
    final desc = alerte['description'] as String?;

    final cardBorder = isPerdu
        ? (_especeBorder[espece] ?? Colors.orange.shade200)
        : const Color(0xFF89CDD8);
    final cardText = isPerdu
        ? (_especeText[espece] ?? const Color(0xFFE65100))
        : _teal;
    final cardBg = _especeBg[espece] ?? Colors.white;
    final emoji = _especeEmoji[espece] ?? '🐾';
    final badge = isPerdu ? '$emoji PERDU' : '$emoji TROUVÉ';
    final displayName = nom.isNotEmpty
        ? nom
        : '${espece.isNotEmpty ? espece[0].toUpperCase() + espece.substring(1) : 'Animal'} trouvé';

    return GestureDetector(
      onTap: onTap,
      onLongPress: (onRetrouve != null || onDelete != null)
          ? () => _showOwnerActions(context)
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cardBorder, width: 1.2),
          boxShadow: [
            BoxShadow(
                color: cardBorder.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 3))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 72,
                height: 72,
                child: photoUrl != null && photoUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: photoUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            _placeholder(cardBg, cardText, emoji),
                        errorWidget: (_, __, ___) =>
                            _placeholder(cardBg, cardText, emoji))
                    : _placeholder(cardBg, cardText, emoji),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: cardText,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(badge,
                        style: const TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(displayName,
                        style: const TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Color(0xFF1F2A2E)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(
                  [
                    espece,
                    if (race.isNotEmpty) race,
                    if (sexe.isNotEmpty) sexe
                  ].join(' · '),
                  style: const TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 12,
                      color: Color(0xFF6F767B)),
                ),
                if (lieu.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.location_on_outlined, size: 12, color: cardText),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(lieu,
                          style: const TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 11,
                              color: Color(0xFF6F767B)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ],
                if (date.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${isPerdu ? 'Disparu' : 'Trouvé'} le $date',
                    style: TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 11,
                        color: cardText),
                  ),
                ],
                if (desc != null && desc.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(desc,
                      style: const TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 12,
                          color: Color(0xFF4A5568)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  OutlinedButton.icon(
                    onPressed: onContact,
                    icon: const Icon(Icons.message_outlined, size: 14),
                    label: const Text('Contacter',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _teal,
                      side: const BorderSide(color: _teal),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  if (onShare != null) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: onShare,
                      icon: const Icon(Icons.share, size: 14),
                      label: const Text('Partager',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isPerdu ? Colors.orange.shade700 : _teal,
                        side: BorderSide(
                            color: isPerdu ? Colors.orange.shade300 : const Color(0xFF9ECFDA)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _placeholder(Color bg, Color iconColor, String emoji) => Container(
      color: bg,
      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 30))));
}

// ── Alert Detail Sheet (perdus) ───────────────────────────────────────────────

class _AlertDetailSheet extends StatelessWidget {
  final Map<String, dynamic> alerte;
  final VoidCallback onShare;
  final VoidCallback onContact;

  const _AlertDetailSheet(
      {required this.alerte,
      required this.onShare,
      required this.onContact});

  @override
  Widget build(BuildContext context) {
    final nom      = (alerte['nom_animal'] ?? '') as String;
    final espece   = ((alerte['espece'] ?? '') as String).toLowerCase();
    final race     = (alerte['race'] ?? '') as String;
    final sexe     = (alerte['sexe'] as String?) ?? '';
    final lieu     = (alerte['derniere_localisation'] ?? alerte['ville'] ?? '') as String;
    final desc     = alerte['description'] as String?;
    final contact  = (alerte['contact'] as String?) ?? '';
    final numero   = (alerte['numero_alerte'] as String?) ?? '';
    final photoUrl = alerte['photo_url'] as String?;
    final dateStr  = alerte['date_perte'] as String?;
    final date     = dateStr != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(dateStr))
        : '';
    final cardText = _especeText[espece] ?? const Color(0xFFE65100);
    final cardBg   = _especeBg[espece]   ?? const Color(0xFFFFF7ED);
    final emoji    = _especeEmoji[espece] ?? '🐾';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 90,
                height: 90,
                child: photoUrl != null && photoUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: photoUrl,
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover)
                    : Container(
                        color: cardBg,
                        child: Center(
                            child: Text(emoji,
                                style: const TextStyle(fontSize: 40)))),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: cardText,
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('$emoji PERDU',
                          style: const TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(nom,
                          style: const TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                              color: Color(0xFF1F2A2E)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                      [
                        espece,
                        if (race.isNotEmpty) race,
                        if (sexe.isNotEmpty) sexe
                      ].join(' · '),
                      style: const TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 13,
                          color: Color(0xFF6F767B))),
                  if (date.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Disparu le $date',
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 12,
                            color: cardText)),
                  ],
                ])),
          ]),
          if (lieu.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.location_on_outlined, size: 16, color: cardText),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(lieu,
                      style: const TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 13,
                          color: Color(0xFF4A5568)))),
            ]),
          ],
          if (desc != null && desc.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(desc,
                style: const TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 13,
                    color: Color(0xFF4A5568))),
          ],
          if (contact.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.phone_outlined,
                  size: 14, color: Color(0xFF6F767B)),
              const SizedBox(width: 6),
              Text(contact,
                  style: const TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 13,
                      color: Color(0xFF6F767B))),
            ]),
          ],
          if (numero.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('N° $numero',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 11,
                      color: cardText.withOpacity(0.7),
                      fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onContact,
                icon: const Icon(Icons.message_outlined, size: 16),
                label:
                    const Text('Contacter', style: TextStyle(fontFamily: 'Galey')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0C5C6C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: onShare,
              icon: const Icon(Icons.share, size: 16),
              label:
                  const Text('Partager', style: TextStyle(fontFamily: 'Galey')),
              style: OutlinedButton.styleFrom(
                foregroundColor: cardText,
                side: BorderSide(color: cardText.withOpacity(0.4)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ── Trouvé Detail Sheet ───────────────────────────────────────────────────────

class _TrouveDetailSheet extends StatefulWidget {
  final Map<String, dynamic> trouve;
  final VoidCallback onContact;
  final VoidCallback onShare;
  const _TrouveDetailSheet({required this.trouve, required this.onContact, required this.onShare});

  @override
  State<_TrouveDetailSheet> createState() => _TrouveDetailSheetState();
}

class _TrouveDetailSheetState extends State<_TrouveDetailSheet> {
  static const _teal = Color(0xFF0C5C6C);
  int _photoIndex = 0;

  @override
  Widget build(BuildContext context) {
    final a = widget.trouve;
    final espece = ((a['espece'] ?? '') as String).toLowerCase();
    final race = (a['race'] ?? '') as String;
    final sexe = (a['sexe'] as String?) ?? '';
    final taille = (a['taille'] as String?) ?? '';
    final couleur = (a['couleur'] as String?) ?? '';
    final puce = (a['numero_puce'] as String?) ?? '';
    final etat = (a['etat_sante'] as String?) ?? '';
    final comportement = (a['comportement'] as String?) ?? '';
    final desc = (a['description'] as String?) ?? '';
    final lieu = (a['localisation_adresse'] ?? a['ville'] ?? '') as String;
    final dateStr = a['date_trouve'] as String?;
    final date = dateStr != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(dateStr))
        : '';
    final accepte = a['contact_messagerie'] as bool? ?? true;
    final phone = a['contact_telephone'] as String?;
    final email = a['contact_email'] as String?;

    final photosRaw = a['photos'];
    final photos = photosRaw is List
        ? List<String>.from(photosRaw.map((e) => e.toString()))
        : <String>[];
    final emoji = _especeEmoji[espece] ?? '🐾';
    final cardBg = _especeBg[espece] ?? const Color(0xFFE8F4F6);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            // Photos
            if (photos.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 200,
                  child: photos.length == 1
                      ? CachedNetworkImage(
                          imageUrl: photos.first, fit: BoxFit.cover)
                      : Stack(children: [
                          PageView.builder(
                            itemCount: photos.length,
                            onPageChanged: (i) =>
                                setState(() => _photoIndex = i),
                            itemBuilder: (_, i) => CachedNetworkImage(
                                imageUrl: photos[i], fit: BoxFit.cover),
                          ),
                          Positioned(
                            bottom: 8,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                photos.length,
                                (i) => Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 3),
                                  width: i == _photoIndex ? 16 : 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: i == _photoIndex
                                        ? Colors.white
                                        : Colors.white54,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ]),
                ),
              ),
              const SizedBox(height: 14),
            ] else ...[
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                      color: cardBg, borderRadius: BorderRadius.circular(16)),
                  child: Center(
                      child: Text(emoji,
                          style: const TextStyle(fontSize: 40))),
                ),
              ),
              const SizedBox(height: 14),
            ],
            // Badge + titre
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: _teal,
                    borderRadius: BorderRadius.circular(20)),
                child: Text('$emoji TROUVÉ',
                    style: const TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  espece.isNotEmpty
                      ? '${espece[0].toUpperCase()}${espece.substring(1)}'
                      : 'Animal trouvé',
                  style: const TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: Color(0xFF1F2A2E)),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            // Infos
            Wrap(spacing: 8, runSpacing: 6, children: [
              if (race.isNotEmpty) _InfoChip(race),
              if (sexe.isNotEmpty) _InfoChip(sexe),
              if (taille.isNotEmpty) _InfoChip(taille),
              if (couleur.isNotEmpty) _InfoChip('Couleur : $couleur'),
              if (puce.isNotEmpty) _InfoChip('Puce : $puce'),
            ]),
            if (date.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 14, color: _teal),
                const SizedBox(width: 6),
                Text('Trouvé le $date',
                    style: const TextStyle(
                        fontFamily: 'Galey', fontSize: 13, color: _teal)),
              ]),
            ],
            if (lieu.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.location_on_outlined, size: 14, color: _teal),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(lieu,
                        style: const TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 13,
                            color: Color(0xFF4A5568)))),
              ]),
            ],
            if (etat.isNotEmpty) ...[
              const SizedBox(height: 8),
              _DetailRow(label: 'État de santé', value: etat),
            ],
            if (comportement.isNotEmpty) ...[
              const SizedBox(height: 4),
              _DetailRow(label: 'Comportement', value: comportement),
            ],
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(desc,
                  style: const TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 13,
                      color: Color(0xFF4A5568))),
            ],
            const SizedBox(height: 16),
            // Contact + Share
            if (accepte)
              Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: widget.onContact,
                    icon: const Icon(Icons.message_outlined, size: 16),
                    label: const Text('Contacter', style: TextStyle(fontFamily: 'Galey')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _teal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: widget.onShare,
                  icon: const Icon(Icons.share, size: 16),
                  label: const Text('Partager', style: TextStyle(fontFamily: 'Galey')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _teal,
                    side: const BorderSide(color: Color(0xFF9ECFDA)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ])
            else
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Contact direct',
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: _teal)),
                    if (phone != null && phone.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.phone_outlined,
                            size: 14, color: Color(0xFF6F767B)),
                        const SizedBox(width: 6),
                        Text(phone,
                            style: const TextStyle(
                                fontFamily: 'Galey',
                                fontSize: 13,
                                color: Color(0xFF4A5568))),
                      ]),
                    ],
                    if (email != null && email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.email_outlined,
                            size: 14, color: Color(0xFF6F767B)),
                        const SizedBox(width: 6),
                        Text(email,
                            style: const TextStyle(
                                fontFamily: 'Galey',
                                fontSize: 13,
                                color: Color(0xFF4A5568))),
                      ]),
                    ],
                  ]),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: widget.onShare,
                  icon: const Icon(Icons.share, size: 16),
                  label: const Text('Partager', style: TextStyle(fontFamily: 'Galey')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _teal,
                    side: const BorderSide(color: Color(0xFF9ECFDA)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  const _InfoChip(this.label);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: const Color(0xFFE8F4F6),
            borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: const TextStyle(
                fontFamily: 'Galey',
                fontSize: 12,
                color: Color(0xFF0C5C6C))),
      );
}

class _DetailRow extends StatelessWidget {
  final String label, value;
  const _DetailRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 12,
                    color: Color(0xFF6F767B))),
          ),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 12,
                      color: Color(0xFF1F2A2E)))),
        ],
      );
}

// ── Contact info sheet (for trouvé with messagerie disabled) ──────────────────

class _ContactInfoSheet extends StatelessWidget {
  final String? phone, email;
  const _ContactInfoSheet({this.phone, this.email});

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.of(context).padding.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const Text('Coordonnées du déclarant',
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          const SizedBox(height: 16),
          if (phone != null && phone!.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.phone_outlined, color: Color(0xFF0C5C6C)),
              title: Text(phone!,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
              onTap: () => launchUrl(Uri.parse('tel:$phone')),
            ),
          if (email != null && email!.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.email_outlined, color: Color(0xFF0C5C6C)),
              title: Text(email!,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
              onTap: () => launchUrl(Uri.parse('mailto:$email')),
            ),
          if ((phone == null || phone!.isEmpty) &&
              (email == null || email!.isEmpty))
            const Text('Aucune coordonnée disponible.',
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 13,
                    color: Color(0xFF6F767B))),
        ]),
      );
}

// ─── Share sheet ──────────────────────────────────────────────────────────────

class _ShareSheet extends StatelessWidget {
  final String text, url, nom;
  const _ShareSheet(
      {required this.text, required this.url, required this.nom});

  Future<void> _copy(BuildContext ctx) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (ctx.mounted) {
      Navigator.pop(ctx);
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('Lien copié !'), duration: Duration(seconds: 2)));
    }
  }

  Future<void> _launch(BuildContext ctx, Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (ctx.mounted) Navigator.pop(ctx);
  }

  @override
  Widget build(BuildContext context) {
    final encoded = Uri.encodeComponent(text);
    final waUrl = Uri.parse('https://wa.me/?text=$encoded');
    final smsUrl = Uri.parse('sms:?body=$encoded');
    final emailUrl = Uri.parse(
        'mailto:?subject=${Uri.encodeComponent(nom)}&body=$encoded');
    final safe = MediaQuery.of(context).padding;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, safe.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Text(nom,
            style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Galey',
                fontWeight: FontWeight.w700,
                fontSize: 15),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _ShareBtn(
            icon: const Icon(Icons.link_rounded, color: Colors.white, size: 24),
            bg: const Color(0xFF3A3A4E),
            label: 'Copier le lien',
            onTap: () => _copy(context),
          ),
          _ShareBtn(
            icon: const FaIcon(FontAwesomeIcons.whatsapp,
                color: Colors.white, size: 24),
            bg: const Color(0xFF25D366),
            label: 'WhatsApp',
            onTap: () => _launch(context, waUrl),
          ),
          _ShareBtn(
            icon: const Icon(Icons.sms_outlined, color: Colors.white, size: 24),
            bg: const Color(0xFF4A90E2),
            label: 'SMS',
            onTap: () => _launch(context, smsUrl),
          ),
          _ShareBtn(
            icon: const Icon(Icons.mail_outline_rounded,
                color: Colors.white, size: 24),
            bg: const Color(0xFFEA4335),
            label: 'Email',
            onTap: () => _launch(context, emailUrl),
          ),
        ]),
      ]),
    );
  }
}

class _ShareBtn extends StatelessWidget {
  final Widget icon;
  final Color bg;
  final String label;
  final VoidCallback onTap;
  const _ShareBtn(
      {required this.icon,
      required this.bg,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(16)),
            child: Center(child: icon),
          ),
          const SizedBox(height: 6),
          SizedBox(
              width: 60,
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontFamily: 'Galey'),
                  textAlign: TextAlign.center,
                  maxLines: 2)),
        ]),
      );
}

// ── Dropdown géographique compact ─────────────────────────────────────────────

// ── Chip search sheet (PT06) ──────────────────────────────────────────────────

class ChipSearchSheet extends StatefulWidget {
  final void Function(Map<String, dynamic>)? onTapAlerte;
  final void Function(Map<String, dynamic>)? onTapTrouve;
  const ChipSearchSheet({super.key, this.onTapAlerte, this.onTapTrouve});

  @override
  State<ChipSearchSheet> createState() => _ChipSearchSheetState();
}

class _ChipSearchSheetState extends State<ChipSearchSheet> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;
  final _ctrl = TextEditingController();
  bool _searching = false;
  bool _searched  = false;
  List<Map<String, dynamic>> _results = [];

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() { _searching = true; _results = []; _searched = false; });

    final results = <Map<String, dynamic>>[];

    try {
      final rows = await _supa.from('alertes_perdus').select()
          .ilike('identification', '%$q%')
          .eq('statut', 'perdu').limit(10);
      for (final row in (rows as List)) {
        results.add({...Map<String, dynamic>.from(row as Map), '__type': 'perdu'});
      }
    } catch (_) {}

    try {
      final rows = await _supa.from('animaux_trouves').select()
          .ilike('numero_puce', '%$q%').limit(10);
      for (final row in (rows as List)) {
        results.add({...Map<String, dynamic>.from(row as Map), '__type': 'trouve'});
      }
    } catch (_) {}

    try {
      final rows = await _supa.from('animaux')
          .select('id,nom,espece,race,identification,photo_url,uid_eleveur')
          .ilike('identification', '%$q%').limit(10);
      for (final row in (rows as List)) {
        results.add({...Map<String, dynamic>.from(row as Map), '__type': 'elevage'});
      }
    } catch (_) {}

    setState(() { _results = results; _searched = true; _searching = false; });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text('Recherche par numéro de puce',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
              const SizedBox(height: 3),
              Text('Recherche dans les alertes perdues, déclarations trouvées et élevages.',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F8F8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: TextField(
                      controller: _ctrl,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      autofocus: true,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: '250269802345678',
                        hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.grey),
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.nfc_outlined, size: 18, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal, foregroundColor: Colors.white,
                    minimumSize: const Size(48, 44), padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _searching ? null : _search,
                  child: _searching
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.search, size: 20),
                ),
              ]),
              const SizedBox(height: 12),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: _searching
                ? Center(child: CircularProgressIndicator(color: _teal))
                : !_searched
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.nfc_outlined, size: 52, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text('Entrez un numéro de puce pour rechercher\ndans toutes les déclarations',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                                  color: Colors.grey.shade400),
                              textAlign: TextAlign.center),
                        ]),
                      ))
                    : _results.isEmpty
                        ? Center(child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.search_off, size: 52, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              const Text('Aucun animal trouvé avec ce numéro de puce',
                                  style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                                      color: Colors.grey),
                                  textAlign: TextAlign.center),
                            ]),
                          ))
                        : ListView.builder(
                            controller: scroll,
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
                            itemCount: _results.length,
                            itemBuilder: (_, i) {
                              final r = _results[i];
                              final type = r['__type'] as String;
                              final currentUid = FirebaseAuth.instance.currentUser?.uid;

                              if (type == 'elevage') {
                                final isOwn = r['uid_eleveur'] != null && r['uid_eleveur'] == currentUid;
                                return _ChipResultCard(
                                  result: r,
                                  onTap: isOwn ? () {
                                    Navigator.pop(context);
                                    Navigator.push(context, MaterialPageRoute(
                                        builder: (_) => AnimalFichePage(animalId: r['id'] as String?)));
                                  } : null,
                                  onDeclare: () {
                                    Navigator.pop(context);
                                    Navigator.push(context, MaterialPageRoute(
                                        builder: (_) => AnimalTrouveFormPage(
                                          knownOwnerUid: r['uid_eleveur'] as String?,
                                          initialPuce: r['identification'] as String?,
                                          initialEspece: r['espece'] as String?,
                                        )));
                                  },
                                );
                              }

                              return _ChipResultCard(
                                result: r,
                                onTap: type == 'perdu'
                                    ? () {
                                        if (widget.onTapAlerte != null) {
                                          widget.onTapAlerte!(r);
                                        } else {
                                          Navigator.pop(context);
                                          Navigator.push(context, MaterialPageRoute(builder: (_) => const AnimauxPerdusPage()));
                                        }
                                      }
                                    : () {
                                        if (widget.onTapTrouve != null) {
                                          widget.onTapTrouve!(r);
                                        } else {
                                          Navigator.pop(context);
                                          Navigator.push(context, MaterialPageRoute(builder: (_) => const AnimauxPerdusPage()));
                                        }
                                      },
                              );
                            },
                          ),
          ),
        ]),
      ),
    );
  }
}

class _ChipResultCard extends StatelessWidget {
  final Map<String, dynamic> result;
  final VoidCallback? onTap;
  final VoidCallback? onDeclare;
  const _ChipResultCard({required this.result, this.onTap, this.onDeclare});

  static const _orange = Color(0xFFE65100);
  static const _teal   = Color(0xFF0C5C6C);
  static const _green  = Color(0xFF16A34A);

  @override
  Widget build(BuildContext context) {
    final type = result['__type'] as String;
    final accent = type == 'perdu' ? _orange : type == 'trouve' ? _teal : _green;
    final showBadge = type != 'elevage';
    final badge = type == 'perdu' ? '🚨 PERDU' : '🐾 TROUVÉ';

    String title, subtitle;
    String? photoUrl, chipNum;

    if (type == 'perdu') {
      title    = result['nom_animal'] as String? ?? 'Animal perdu';
      subtitle = '${result['espece'] ?? ''}'
          '${(result['ville'] ?? result['derniere_localisation'] ?? '').toString().isNotEmpty ? ' · ${result['ville'] ?? result['derniere_localisation']}' : ''}';
      photoUrl = result['photo_url'] as String?;
      chipNum  = result['identification'] as String?;
    } else if (type == 'trouve') {
      final esp = result['espece'] as String? ?? 'Animal';
      title    = esp[0].toUpperCase() + esp.substring(1);
      subtitle = result['localisation_ville'] as String? ?? result['ville'] as String? ?? '';
      final photos = result['photos'];
      if (photos is List && photos.isNotEmpty) photoUrl = photos.first as String?;
      chipNum  = result['numero_puce'] as String?;
    } else {
      title    = result['nom'] as String? ?? 'Animal';
      final esp  = result['espece'] as String? ?? '';
      final race = result['race'] as String? ?? '';
      subtitle = [esp, race].where((s) => s.isNotEmpty).join(' · ');
      photoUrl = result['photo_url'] as String?;
      chipNum  = result['identification'] as String?;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(width: 56, height: 56,
                child: photoUrl != null && photoUrl.isNotEmpty
                    ? CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: Colors.grey.shade100),
                        errorWidget: (_, __, ___) => _ChipPhotoPlaceholder(accent))
                    : _ChipPhotoPlaceholder(accent)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (showBadge) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(badge,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 9,
                          fontWeight: FontWeight.w700, color: accent)),
                ),
                const SizedBox(height: 4),
              ],
              Text(title,
                  style: const TextStyle(fontFamily: 'Galey',
                      fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (subtitle.isNotEmpty)
                Text(subtitle,
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                        color: Colors.grey.shade500),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              if (chipNum != null && chipNum.isNotEmpty)
                Text('🔖 $chipNum',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                        color: _teal)),
            ])),
            if (onTap != null)
              Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
          ]),
          if (onDeclare != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.location_on_outlined, size: 16),
                label: const Text('Déclarer trouvé',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _green,
                  side: const BorderSide(color: _green),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: onDeclare,
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _ChipPhotoPlaceholder extends StatelessWidget {
  final Color color;
  const _ChipPhotoPlaceholder(this.color);
  @override
  Widget build(BuildContext context) => Container(
    color: color.withOpacity(0.08),
    child: Icon(Icons.pets, color: color.withOpacity(0.4), size: 28),
  );
}

class _GeoDropdown extends StatelessWidget {
  final String? value;
  final String hint;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  const _GeoDropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: (items.contains(value)) ? value : null,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: Color(0xFFE65100))),
        filled: true,
        fillColor: const Color(0xFFF8F8F8),
      ),
      hint: Text(hint,
          style: const TextStyle(
              fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
      style: const TextStyle(
          fontFamily: 'Galey', fontSize: 12, color: Color(0xFF1F2A2E)),
      items: [
        DropdownMenuItem<String>(
            value: null,
            child: Text(hint,
                style: const TextStyle(
                    fontFamily: 'Galey', fontSize: 11, color: Colors.grey))),
        ...items.map((s) => DropdownMenuItem(
            value: s,
            child: Text(s,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12),
                overflow: TextOverflow.ellipsis))),
      ],
      onChanged: items.isEmpty ? null : onChanged,
    );
  }
}
