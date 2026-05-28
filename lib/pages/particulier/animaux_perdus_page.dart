import 'package:PetsMatch/utils/french_geo.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:PetsMatch/pages/chatScreen.dart';

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

class _AnimauxPerdusPageState extends State<AnimauxPerdusPage>
    with SingleTickerProviderStateMixin {
  static const _orange = Color(0xFFE65100);

  late TabController _tabController;
  List<Map<String, dynamic>> _alertes = [];
  bool _loading = true;
  GoogleMapController? _mapController;
  bool _locating = false;

  // Filtres
  String? _filterEspece;
  String _searchLieu = '';
  String _filterRace = '';
  String _filterPays = '';
  String _filterRegion = '';
  String _filterDept = '';
  List<String> _breeds = [];
  List<String> _raceSuggestions = [];
  bool _showRaceSugg = false;
  final _raceFocusNode = FocusNode();
  final _raceCtrl = TextEditingController();
  final _lieuCtrl = TextEditingController();

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

  List<Map<String, dynamic>> get _filtered {
    return _alertes.where((a) {
      if (_filterEspece != null && _filterEspece != 'tous') {
        if ((a['espece'] as String? ?? '').toLowerCase() != _filterEspece) return false;
      }
      if (_filterRace.isNotEmpty) {
        final race = (a['race'] as String? ?? '').toLowerCase();
        if (!race.contains(_filterRace.toLowerCase())) return false;
      }
      if (_filterRegion.isNotEmpty) {
        final depts = FrenchGeo.departmentsInRegion(_filterRegion);
        final loc = '${a['ville'] ?? ''} ${a['derniere_localisation'] ?? ''}'.toLowerCase();
        final matchesDept = depts.any((d) => loc.contains(d.toLowerCase()));
        if (!matchesDept && !loc.contains(_filterRegion.toLowerCase())) return false;
      }
      if (_filterDept.isNotEmpty) {
        final loc = '${a['ville'] ?? ''} ${a['derniere_localisation'] ?? ''}'.toLowerCase();
        if (!loc.contains(_filterDept.toLowerCase())) return false;
      }
      if (_searchLieu.isNotEmpty) {
        final loc = '${a['derniere_localisation'] ?? ''} ${a['ville'] ?? ''}'.toLowerCase();
        if (!loc.contains(_searchLieu.toLowerCase())) return false;
      }
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
    _loadDefaultVille();
    _raceFocusNode.addListener(() {
      if (!_raceFocusNode.hasFocus) setState(() => _showRaceSugg = false);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _mapController?.dispose();
    _raceFocusNode.dispose();
    _raceCtrl.dispose();
    _lieuCtrl.dispose();
    super.dispose();
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
    if (file == null) { setState(() => _breeds = []); return; }
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
    if (val.isEmpty) { setState(() { _raceSuggestions = []; _showRaceSugg = false; }); return; }
    final q = val.toLowerCase();
    final matches = _breeds.where((b) => b.toLowerCase().contains(q)).take(6).toList();
    setState(() { _raceSuggestions = matches; _showRaceSugg = matches.isNotEmpty; });
  }

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await Supabase.instance.client
          .from('alertes_perdus')
          .select()
          .eq('statut', 'perdu')
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _alertes = List<Map<String, dynamic>>.from(rows as List);
          _loading = false;
        });
        if (widget.initialAlertId != null) {
          final target = _alertes.firstWhere(
            (a) => a['id'] == widget.initialAlertId,
            orElse: () => {},
          );
          if (target.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _showAlertDetail(target));
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAlertDetail(Map<String, dynamic> a) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AlertDetailSheet(
        alerte: a,
        onShare: () { Navigator.pop(context); _share(a); },
        onContact: () { Navigator.pop(context); _contact(a); },
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
      builder: (_) => _ShareSheet(text: text, url: url, nom: 'Animal perdu : $nom'),
    );
  }

  Future<void> _contact(Map<String, dynamic> a) async {
    final ownerId = a['uid_proprietaire'] as String?;
    if (ownerId == null) return;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;
    if (currentUid == ownerId) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('C\'est votre propre alerte')));
      return;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      // Find existing conversation
      final existing = await firestore
          .collection('conversations')
          .where('participants', arrayContains: currentUid)
          .get();

      String? conversationId;
      for (final doc in existing.docs) {
        final participants = List<String>.from(doc.data()['participants'] ?? []);
        if (participants.contains(ownerId)) {
          conversationId = doc.id;
          break;
        }
      }

      // Create if not found, or tag existing without category
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
        // Always tag the conversation as animaux-perdus when coming from this context
        final conv = existing.docs.firstWhere((d) => d.id == conversationId);
        if (conv.data()['categorie'] != 'animaux-perdus') {
          await firestore.collection('conversations').doc(conversationId).update({'categorie': 'animaux-perdus'});
        }
      }

      if (!mounted) return;
      final alerteId = a['id'] as String? ?? a['alerte_id'] as String?;
      final nomAnimal = a['nom_animal'] as String?;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: conversationId!,
          eleveurId: ownerId,
          alerteId: alerteId,
          nomAnimal: nomAnimal,
          isNewConversation: isNew,
        ),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
    }
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _orange,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Animaux perdus',
            style: TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt_outlined), text: 'Liste'),
            Tab(icon: Icon(Icons.map_outlined), text: 'Carte'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _orange))
          : TabBarView(
              controller: _tabController,
              children: [
                RefreshIndicator(
                  onRefresh: _load,
                  color: _orange,
                  child: _buildList(),
                ),
                _buildMap(),
              ],
            ),
    );
  }

  Widget _buildList() {
    final list = _filtered;
    return Column(children: [
      _buildFilters(),
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
                  final isOwn = list[i]['uid_proprietaire'] == _currentUid;
                  return _AlertCard(
                    alerte: list[i],
                    onTap: () => _showAlertDetail(list[i]),
                    onShare: () => _share(list[i]),
                    onContact: () => _contact(list[i]),
                    onRetrouve: isOwn ? () => _retrouveAlerte(list[i]['id'] as String) : null,
                    onDelete: isOwn ? () => _deleteAlerte(list[i]['id'] as String) : null,
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
        // Lieu search
        SizedBox(
          height: 38,
          child: TextField(
            controller: _lieuCtrl,
            onChanged: (v) => setState(() => _searchLieu = v),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Ville ou lieu…',
              hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
              prefixIcon: const Icon(Icons.location_on_outlined, size: 18, color: Colors.grey),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: _orange)),
              filled: true,
              fillColor: const Color(0xFFF8F8F8),
            ),
          ),
        ),
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
              final chipBg = selected
                  ? (_especeText[e] ?? _orange)
                  : Colors.grey.shade100;
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
                  decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    '${_especeEmoji[e] ?? ''}  ${e[0].toUpperCase()}${e.substring(1)}',
                    style: TextStyle(
                        fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
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
                _filterPays = v ?? ''; _filterRegion = ''; _filterDept = '';
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
              onChanged: (v) => setState(() { _filterRegion = v ?? ''; _filterDept = ''; }),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _GeoDropdown(
              value: _filterDept.isEmpty ? null : _filterDept,
              hint: 'Département',
              items: _filterRegion.isNotEmpty
                  ? FrenchGeo.departmentsInRegion(_filterRegion)
                  : const [],
              onChanged: (v) => setState(() => _filterDept = v ?? ''),
            ),
          ),
        ]),
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
                  hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
                  prefixIcon: const Icon(Icons.pets, size: 16, color: Colors.grey),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: _orange)),
                  filled: true,
                  fillColor: const Color(0xFFF8F8F8),
                  suffixIcon: _filterRace.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () {
                          _raceCtrl.clear(); setState(() { _filterRace = ''; _raceSuggestions = []; _showRaceSugg = false; });
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
                    children: _raceSuggestions.map((r) => ListTile(
                      dense: true,
                      title: Text(r, style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                      onTap: () {
                        _raceCtrl.text = r;
                        setState(() { _filterRace = r; _showRaceSugg = false; });
                        _raceFocusNode.unfocus();
                      },
                    )).toList(),
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
      final lat = (a['lat'] as num?)?.toDouble();
      final lng = (a['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final espece = (a['espece'] as String? ?? '').toLowerCase();
      final hue = _especeHue[espece] ?? BitmapDescriptor.hueOrange;
      markers.add(Marker(
        markerId: MarkerId(a['id'].toString()),
        position: LatLng(lat, lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        infoWindow: InfoWindow(
          title: '${_especeEmoji[espece] ?? '🐾'} ${a['nom_animal']}',
          snippet: '${a['espece'] ?? ''}'
              '${a['race'] != null && (a['race'] as String).isNotEmpty ? ' · ${a['race']}' : ''}'
              '${a['derniere_localisation'] != null && (a['derniere_localisation'] as String).isNotEmpty ? '\n📍 ${a['derniere_localisation']}' : ''}',
        ),
        onTap: () => _showAlertDetail(a),
      ));
    }

    return Column(children: [
      _buildFilters(),
      Expanded(
        child: Stack(children: [
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
          // Recenter button
          Positioned(
            right: 12,
            bottom: 100,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              backgroundColor: Colors.white,
              onPressed: _locating ? null : _recenterMap,
              child: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _orange))
                  : const Icon(Icons.my_location, color: _orange, size: 20),
            ),
          ),
          // No coords warning if markers is empty but there are alerts
          if (markers.isEmpty && list.isNotEmpty)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Text(
                  'Certaines alertes n\'ont pas de coordonnées GPS et n\'apparaissent pas sur la carte.',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 12,
                      color: Colors.orange.shade800),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ]),
      ),
    ]);
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _AlertCard extends StatelessWidget {
  final Map<String, dynamic> alerte;
  final VoidCallback onTap;
  final VoidCallback onShare;
  final VoidCallback onContact;
  final VoidCallback? onRetrouve;
  final VoidCallback? onDelete;

  const _AlertCard({
    required this.alerte,
    required this.onTap,
    required this.onShare,
    required this.onContact,
    this.onRetrouve,
    this.onDelete,
  });

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
            width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
                color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          if (onRetrouve != null)
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFEEF5EA),
                child: Icon(Icons.check_circle_outline, color: Color(0xFF6E9E57)),
              ),
              title: const Text('Animal retrouvé !',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              onTap: () { Navigator.pop(context); onRetrouve!(); },
            ),
          if (onDelete != null)
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFFFEBEE),
                child: Icon(Icons.delete_outline, color: Colors.red),
              ),
              title: const Text('Supprimer l\'alerte',
                  style: TextStyle(
                      fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.red)),
              onTap: () { Navigator.pop(context); onDelete!(); },
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nom      = (alerte['nom_animal'] ?? '') as String;
    final espece   = ((alerte['espece'] ?? '') as String).toLowerCase();
    final sexe     = (alerte['sexe'] as String?) ?? '';
    final race     = (alerte['race'] ?? '') as String;
    final lieu     = (alerte['derniere_localisation'] ?? alerte['ville'] ?? '') as String;
    final photoUrl = alerte['photo_url'] as String?;
    final desc     = alerte['description'] as String?;
    final contact  = (alerte['contact'] as String?) ?? '';
    final numero   = (alerte['numero_alerte'] as String?) ?? '';
    final dateStr  = alerte['date_perte'] as String?;
    final date     = dateStr != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(dateStr))
        : '';

    final cardBg     = _especeBg[espece]     ?? Colors.white;
    final cardBorder = _especeBorder[espece] ?? Colors.orange.shade200;
    final cardText   = _especeText[espece]   ?? const Color(0xFFE65100);
    final emoji      = _especeEmoji[espece]  ?? '🐾';

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
          BoxShadow(color: cardBorder.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 72,
              height: 72,
              child: photoUrl != null && photoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photoUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _placeholder(cardBg, cardText, emoji),
                      errorWidget: (_, __, ___) => _placeholder(cardBg, cardText, emoji))
                  : _placeholder(cardBg, cardText, emoji),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: cardText,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('$emoji PERDU',
                      style: const TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(nom,
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
                [espece, if (race.isNotEmpty) race, if (sexe.isNotEmpty) sexe].join(' · '),
                style: const TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 12,
                    color: Color(0xFF6F767B)),
              ),
              if (lieu.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.location_on_outlined,
                      size: 12, color: cardText),
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
                Text('Disparu le $date',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: cardText)),
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
              if (contact.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.phone_outlined,
                      size: 12, color: Color(0xFF6F767B)),
                  const SizedBox(width: 4),
                  Text(contact,
                      style: const TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 11,
                          color: Color(0xFF6F767B))),
                ]),
              ],
              if (numero.isNotEmpty)
                Text('N° $numero',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                        color: cardText.withOpacity(0.7), fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                OutlinedButton.icon(
                  onPressed: onContact,
                  icon: const Icon(Icons.message_outlined, size: 14),
                  label: const Text('Contacter',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0C5C6C),
                    side: const BorderSide(color: Color(0xFF0C5C6C)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.share, size: 14),
                  label: const Text('Partager',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade700,
                    side: BorderSide(color: Colors.orange.shade300),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ]),
            ]),
          ),
        ]),
      ),
      ),  // Container
    );  // GestureDetector
  }

  Widget _placeholder(Color bg, Color iconColor, String emoji) => Container(
        color: bg,
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 30))),
      );
}

class _AlertDetailSheet extends StatelessWidget {
  final Map<String, dynamic> alerte;
  final VoidCallback onShare;
  final VoidCallback onContact;

  const _AlertDetailSheet({required this.alerte, required this.onShare, required this.onContact});

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
    final date     = dateStr != null ? DateFormat('dd/MM/yyyy').format(DateTime.parse(dateStr)) : '';
    final cardText = _especeText[espece] ?? const Color(0xFFE65100);
    final cardBg   = _especeBg[espece]   ?? const Color(0xFFFFF7ED);
    final emoji    = _especeEmoji[espece] ?? '🐾';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
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
                    ? CachedNetworkImage(imageUrl: photoUrl, width: 90, height: 90, fit: BoxFit.cover)
                    : Container(color: cardBg, child: Center(child: Text(emoji, style: const TextStyle(fontSize: 40)))),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: cardText, borderRadius: BorderRadius.circular(20)),
                  child: Text('$emoji PERDU', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(nom, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17, color: Color(0xFF1F2A2E)), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
              const SizedBox(height: 4),
              Text([espece, if (race.isNotEmpty) race, if (sexe.isNotEmpty) sexe].join(' · '),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
              if (date.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Disparu le $date', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: cardText)),
              ],
            ])),
          ]),
          if (lieu.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.location_on_outlined, size: 16, color: cardText),
              const SizedBox(width: 6),
              Expanded(child: Text(lieu, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF4A5568)))),
            ]),
          ],
          if (desc != null && desc.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(desc, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF4A5568))),
          ],
          if (contact.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.phone_outlined, size: 14, color: Color(0xFF6F767B)),
              const SizedBox(width: 6),
              Text(contact, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
            ]),
          ],
          if (numero.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('N° $numero', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: cardText.withOpacity(0.7), fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onContact,
                icon: const Icon(Icons.message_outlined, size: 16),
                label: const Text('Contacter', style: TextStyle(fontFamily: 'Galey')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0C5C6C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: onShare,
              icon: const Icon(Icons.share, size: 16),
              label: const Text('Partager', style: TextStyle(fontFamily: 'Galey')),
              style: OutlinedButton.styleFrom(
                foregroundColor: cardText,
                side: BorderSide(color: cardText.withOpacity(0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ─── Share sheet ──────────────────────────────────────────────────────────────

class _ShareSheet extends StatelessWidget {
  final String text, url, nom;
  const _ShareSheet({required this.text, required this.url, required this.nom});

  Future<void> _copy(BuildContext ctx) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (ctx.mounted) {
      Navigator.pop(ctx);
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Lien copié !'), duration: Duration(seconds: 2)));
    }
  }

  Future<void> _launch(BuildContext ctx, Uri uri) async {
    try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
    if (ctx.mounted) Navigator.pop(ctx);
  }

  @override
  Widget build(BuildContext context) {
    final encoded  = Uri.encodeComponent(text);
    final waUrl    = Uri.parse('https://wa.me/?text=$encoded');
    final smsUrl   = Uri.parse('sms:?body=$encoded');
    final emailUrl = Uri.parse('mailto:?subject=${Uri.encodeComponent(nom)}&body=$encoded');
    final safe     = MediaQuery.of(context).padding;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, safe.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Text(nom,
          style: const TextStyle(color: Colors.white, fontFamily: 'Galey',
              fontWeight: FontWeight.w700, fontSize: 15),
          maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _ShareBtn(
            icon: const Icon(Icons.link_rounded, color: Colors.white, size: 24),
            bg: const Color(0xFF3A3A4E),
            label: 'Copier le lien',
            onTap: () => _copy(context),
          ),
          _ShareBtn(
            icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white, size: 24),
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
            icon: const Icon(Icons.mail_outline_rounded, color: Colors.white, size: 24),
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
  const _ShareBtn({required this.icon, required this.bg, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 56, height: 56,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Center(child: icon),
      ),
      const SizedBox(height: 6),
      SizedBox(width: 60,
        child: Text(label,
          style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'Galey'),
          textAlign: TextAlign.center, maxLines: 2)),
    ]),
  );
}

// ── Dropdown géographique compact ─────────────────────────────────────────────

class _GeoDropdown extends StatelessWidget {
  final String? value;
  final String hint;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  const _GeoDropdown({
    required this.value, required this.hint,
    required this.items, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: (items.contains(value)) ? value : null,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE65100))),
        filled: true, fillColor: const Color(0xFFF8F8F8),
      ),
      hint: Text(hint, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
      style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF1F2A2E)),
      items: [
        DropdownMenuItem<String>(value: null,
            child: Text(hint, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey))),
        ...items.map((s) => DropdownMenuItem(value: s,
            child: Text(s, style: const TextStyle(fontFamily: 'Galey', fontSize: 12),
                overflow: TextOverflow.ellipsis))),
      ],
      onChanged: items.isEmpty ? null : onChanged,
    );
  }
}
