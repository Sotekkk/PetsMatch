import 'dart:async';
import 'dart:convert';
import 'package:PetsMatch/main.dart' show getApiKey;
import 'package:PetsMatch/widgets/verification_badge.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/pages/eleveur_map_view.dart';
import 'package:PetsMatch/pages/user_detail_page_feed.dart';
import 'package:PetsMatch/pages/main_feed.dart';
import 'package:PetsMatch/utils/french_geo.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_webservice/places.dart';

// ─── Données géographiques ────────────────────────────────────────────────────

const _paysList = ['France', 'Belgique', 'Suisse', 'Luxembourg'];

const _regionsByPays = <String, List<String>>{
  'France': [
    'Île-de-France',
    'Auvergne-Rhône-Alpes',
    'Bretagne',
    'Normandie',
    'Hauts-de-France',
    'Grand Est',
    'Pays de la Loire',
    'Nouvelle-Aquitaine',
    'Occitanie',
    'Provence-Alpes-Côte d\'Azur',
    'Bourgogne-Franche-Comté',
    'Centre-Val de Loire',
    'Corse',
    'Guadeloupe',
    'Martinique',
    'Guyane',
    'La Réunion',
    'Mayotte',
  ],
  'Belgique': ['Bruxelles-Capitale', 'Flandre', 'Wallonie'],
  'Suisse': ['Genève', 'Vaud', 'Zurich', 'Berne', 'Valais', 'Neuchâtel'],
  'Luxembourg': ['Luxembourg'],
};

// ─── Mapping espèce → fichier JSON ───────────────────────────────────────────

const _breedAssets = <String, String>{
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

// ─── Page principale ──────────────────────────────────────────────────────────

class EleveurListPage extends StatefulWidget {
  const EleveurListPage({super.key});
  @override
  State<EleveurListPage> createState() => _EleveurListPageState();
}

class _EleveurListPageState extends State<EleveurListPage> {
  static const _teal = Color(0xFF0C5C6C);

  String _search       = '';
  String _espece       = 'tous';
  String _pays         = '';
  String _region       = '';
  String _departement  = '';
  String _ville        = '';
  List<String> _selectedBreeds = [];
  bool _mapView = false;

  final _searchCtrl = TextEditingController();
  final Map<String, List<String>> _allBreeds = {};

  @override
  void initState() {
    super.initState();
    _loadBreeds();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBreeds() async {
    final loaded = <String, List<String>>{};
    for (final entry in _breedAssets.entries) {
      try {
        final json = await rootBundle.loadString(entry.value);
        loaded[entry.key] = List<String>.from(jsonDecode(json));
      } catch (_) {
        loaded[entry.key] = [];
      }
    }
    if (mounted) setState(() => _allBreeds.addAll(loaded));
  }

  int get _activeFilterCount {
    int n = 0;
    if (_espece != 'tous') n++;
    if (_selectedBreeds.isNotEmpty) n++;
    if (_pays.isNotEmpty) n++;
    if (_region.isNotEmpty) n++;
    if (_departement.isNotEmpty) n++;
    if (_ville.isNotEmpty) n++;
    return n;
  }

  bool _matches(Map<String, dynamic> data) {
    // Espèce
    if (_espece != 'tous') {
      final especesElevees = data['especesElevees'];
      if (especesElevees is List && especesElevees.isNotEmpty) {
        if (!especesElevees.any((e) => (e as Map)['espece'] == _espece)) return false;
      } else {
        if (_espece == 'chien' && data['isDog'] != true) { return false; }
        else if (_espece == 'chat' && data['isCat'] != true) { return false; }
        else if (_espece != 'chien' && _espece != 'chat') { return false; }
      }
    }
    // Races
    if (_selectedBreeds.isNotEmpty) {
      final especesElevees = data['especesElevees'];
      List<String> allRaces;
      if (especesElevees is List) {
        allRaces = [
          for (final e in especesElevees)
            ...List<String>.from((e as Map)['races'] ?? []),
        ];
      } else {
        allRaces = [
          ...List<String>.from(data['dogBreeds'] ?? []),
          ...List<String>.from(data['catBreeds'] ?? []),
        ];
      }
      if (!_selectedBreeds.any((b) => allRaces.contains(b))) return false;
    }
    // Localisation
    if (_pays.isNotEmpty) {
      final stored = ((data['paysElevage'] as String?) ?? '').toLowerCase();
      if (stored.isNotEmpty && !stored.contains(_pays.toLowerCase())) return false;
    }
    if (_region.isNotEmpty) {
      final stored = ((data['regionElevage'] as String?) ?? '').toLowerCase();
      if (!stored.contains(_region.toLowerCase())) return false;
    }
    if (_departement.isNotEmpty) {
      final stored = ((data['departementElevage'] as String?) ?? '').toLowerCase();
      if (!stored.contains(_departement.toLowerCase())) return false;
    }
    if (_ville.isNotEmpty) {
      final stored = ((data['villeElevage'] as String?) ?? '').toLowerCase();
      if (!stored.contains(_ville.toLowerCase())) return false;
    }
    // Recherche texte
    if (_search.isNotEmpty) {
      final q    = _search.toLowerCase();
      final name = (data['nameElevage'] ?? '').toString().toLowerCase();
      final desc = (data['descEntreprise'] ?? '').toString().toLowerCase();
      if (!name.contains(q) && !desc.contains(q)) return false;
    }
    return true;
  }

  void _removeFilter(String key) {
    setState(() {
      switch (key) {
        case 'espece':      _espece = 'tous'; _selectedBreeds = []; break;
        case 'breeds':      _selectedBreeds = []; break;
        case 'pays':        _pays = ''; _region = ''; _departement = ''; break;
        case 'region':      _region = ''; _departement = ''; break;
        case 'departement': _departement = ''; break;
        case 'ville':       _ville = ''; break;
      }
    });
  }

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _EleveurFilterSheet(
        espece: _espece,
        pays: _pays, region: _region, departement: _departement, ville: _ville,
        selectedBreeds: List<String>.from(_selectedBreeds),
        allBreeds: _allBreeds,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _espece         = result['espece'] as String;
        _pays           = result['pays'] as String;
        _region         = result['region'] as String;
        _departement    = result['departement'] as String;
        _ville          = result['ville'] as String;
        _selectedBreeds = result['breeds'] as List<String>;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Élevages',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_mapView ? Icons.list_outlined : Icons.map_outlined),
            tooltip: _mapView ? 'Vue liste' : 'Vue carte',
            onPressed: () => setState(() => _mapView = !_mapView),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(children: [
              Expanded(
                child: _SearchBarWidget(
                  controller: _searchCtrl,
                  hint: 'Rechercher un élevage...',
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 8),
              _FilterButton(count: _activeFilterCount, onTap: _openFilterSheet),
            ]),
          ),
        ),
      ),
      body: Column(children: [
        // ── Filtres actifs ──────────────────────────────────────────────────
        if (_activeFilterCount > 0)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                if (_espece != 'tous')
                  _ActiveChip(label: speciesLabel(_espece),
                      onRemove: () => _removeFilter('espece')),
                if (_selectedBreeds.isNotEmpty)
                  _ActiveChip(label: '${_selectedBreeds.length} race(s)',
                      onRemove: () => _removeFilter('breeds')),
                if (_pays.isNotEmpty)
                  _ActiveChip(label: '🌍 $_pays',
                      onRemove: () => _removeFilter('pays')),
                if (_region.isNotEmpty)
                  _ActiveChip(label: '📍 $_region',
                      onRemove: () => _removeFilter('region')),
                if (_departement.isNotEmpty)
                  _ActiveChip(label: _departement,
                      onRemove: () => _removeFilter('departement')),
                if (_ville.isNotEmpty)
                  _ActiveChip(label: '🏘 $_ville',
                      onRemove: () => _removeFilter('ville')),
              ]),
            ),
          ),
        // ── Contenu ─────────────────────────────────────────────────────────
        Expanded(
          child: _mapView
              ? EleveurMapView(
                  espece: _espece,
                  pays: _pays,
                  region: _region,
                  departement: _departement,
                  ville: _ville,
                  selectedBreeds: _selectedBreeds,
                  nameSearch: _search,
                  activeFilterCount: _activeFilterCount,
                  onFilterTap: _openFilterSheet,
                )
              : StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('isElevage', isEqualTo: true)
                      .where('isValidate', isEqualTo: true)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(color: _teal));
                    }
                    if (!snap.hasData || snap.data!.docs.isEmpty) {
                      return const _EmptyState();
                    }

                    final docs = snap.data!.docs
                        .where((d) => _matches(d.data() as Map<String, dynamic>))
                        .toList();

                    if (docs.isEmpty) {
                      return const _EmptyState(
                          message: 'Aucun résultat pour ces filtres.');
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final data = docs[i].data() as Map<String, dynamic>;
                        final uid  = docs[i].id;
                        return _EleveurCard(data: data, uid: uid);
                      },
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// ─── Feuille de filtres ───────────────────────────────────────────────────────

class _EleveurFilterSheet extends StatefulWidget {
  final String espece, pays, region, departement, ville;
  final List<String> selectedBreeds;
  final Map<String, List<String>> allBreeds;

  const _EleveurFilterSheet({
    required this.espece,
    required this.pays, required this.region,
    required this.departement, required this.ville,
    required this.selectedBreeds,
    required this.allBreeds,
  });

  @override
  State<_EleveurFilterSheet> createState() => _EleveurFilterSheetState();
}

class _EleveurFilterSheetState extends State<_EleveurFilterSheet> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  late String _espece;
  late String _pays;
  late String _region;
  late String _departement;
  late List<String> _selectedBreeds;

  late final TextEditingController _villeCtrl;
  late final GoogleMapsPlaces _places;
  Timer? _debounce;
  List<Prediction> _predictions = [];
  bool _villeLoading = false;

  @override
  void initState() {
    super.initState();
    _espece         = widget.espece;
    _pays           = widget.pays;
    _region         = widget.region;
    _departement    = widget.departement;
    _selectedBreeds = List<String>.from(widget.selectedBreeds);
    _villeCtrl      = TextEditingController(text: widget.ville);
    _places         = GoogleMapsPlaces(apiKey: getApiKey());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _villeCtrl.dispose();
    _places.dispose();
    super.dispose();
  }

  List<String> get _currentBreeds {
    if (_espece == 'tous') {
      final seen = <String>{};
      return [
        for (final list in widget.allBreeds.values)
          for (final b in list)
            if (seen.add(b)) b,
      ];
    }
    return widget.allBreeds[_espece] ?? [];
  }

  void _onVilleChanged(String val) {
    _debounce?.cancel();
    if (val.trim().length < 3) {
      setState(() { _predictions = []; _villeLoading = false; });
      return;
    }
    setState(() => _villeLoading = true);
    _debounce = Timer(const Duration(milliseconds: 450), () => _fetchVille(val));
  }

  Future<void> _fetchVille(String input) async {
    final countryCode = _pays == 'Belgique' ? 'be'
        : _pays == 'Suisse' ? 'ch'
        : _pays == 'Luxembourg' ? 'lu'
        : 'fr';
    try {
      final res = await _places.autocomplete(
        input,
        components: [Component(Component.country, countryCode)],
        language: 'fr',
        types: ['(cities)'],
      );
      if (!mounted) return;
      setState(() {
        _predictions = res.isOkay ? res.predictions : [];
        _villeLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _villeLoading = false);
    }
  }

  void _selectPrediction(Prediction p) {
    final city = p.structuredFormatting?.mainText
        ?? p.description?.split(',').first.trim()
        ?? '';
    _villeCtrl.text = city;
    setState(() => _predictions = []);
  }

  void _openBreedsModal() async {
    final breeds = _currentBreeds;
    if (breeds.isEmpty) return;
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _BreedFilterSheet(
        allBreeds: breeds,
        selected: List<String>.from(_selectedBreeds),
      ),
    );
    if (result != null) setState(() => _selectedBreeds = result);
  }

  void _apply() {
    Navigator.pop(context, {
      'espece':      _espece,
      'pays':        _pays,
      'region':      _region,
      'departement': _departement,
      'ville':       _villeCtrl.text.trim(),
      'breeds':      _selectedBreeds,
    });
  }

  Widget _sLabel(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(
        fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700,
        color: Color(0xFF6F767B))));

  InputDecoration _dropDecor(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF9CA3AF)),
    prefixIcon: Icon(icon, color: _teal, size: 18),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _teal)),
    filled: true, fillColor: const Color(0xFFF8F9FA),
  );

  InputDecoration _fieldDecor(String hint, IconData icon) => _dropDecor(hint, icon).copyWith(
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12));

  Widget _especeChip(String val, String label) {
    final active = _espece == val;
    return GestureDetector(
      onTap: () => setState(() {
        _espece = val;
        _selectedBreeds = [];
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(right: 8, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? _teal : Colors.transparent,
          border: Border.all(color: active ? _teal : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (val == 'tous')
            Icon(Icons.apps_outlined, size: 13,
                color: active ? Colors.white : Colors.grey.shade600)
          else
            speciesIcon(val, 13, active ? Colors.white : _green),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(
              fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
              color: active ? Colors.white : Colors.black87)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final regions     = _pays.isNotEmpty ? (_regionsByPays[_pays] ?? []) : <String>[];
    final departments = _region.isNotEmpty
        ? FrenchGeo.departmentsInRegion(_region) : <String>[];
    final hasBreeds   = _currentBreeds.isNotEmpty;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 28),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Handle
          Center(child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)))),
          // Header
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Filtres', style: TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
            TextButton(
              onPressed: () => setState(() {
                _espece = 'tous'; _pays = ''; _region = ''; _departement = '';
                _selectedBreeds = []; _villeCtrl.clear(); _predictions = [];
              }),
              child: const Text('Réinitialiser', style: TextStyle(
                  fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
            ),
          ]),
          const SizedBox(height: 16),

          // ── Espèce ────────────────────────────────────────────────────
          _sLabel('Espèce'),
          Wrap(children: [
            ('tous', 'Tous'),
            ...kSpeciesData
                .where((s) => s.value != 'tous')
                .map((s) => (s.value, s.label)),
          ].map((e) => _especeChip(e.$1, e.$2)).toList()),
          const SizedBox(height: 10),

          // ── Races ─────────────────────────────────────────────────────
          if (hasBreeds) ...[
            _sLabel('Races'),
            GestureDetector(
              onTap: _openBreedsModal,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _selectedBreeds.isNotEmpty
                      ? _teal : const Color(0xFFE5E7EB)),
                ),
                child: Row(children: [
                  Icon(Icons.tune_outlined, size: 16,
                      color: _selectedBreeds.isNotEmpty ? _teal : Colors.grey.shade500),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    _selectedBreeds.isEmpty
                        ? 'Sélectionner des races...'
                        : '${_selectedBreeds.length} race(s) sélectionnée(s)',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                        color: _selectedBreeds.isEmpty
                            ? const Color(0xFF9CA3AF) : _teal),
                  )),
                  if (_selectedBreeds.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(() => _selectedBreeds = []),
                      child: const Icon(Icons.close, size: 16, color: _teal),
                    ),
                ]),
              ),
            ),
            if (_selectedBreeds.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4,
                  children: _selectedBreeds.map((b) => Chip(
                    label: Text(b, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                    backgroundColor: const Color(0xFFA7C79A),
                    deleteIconColor: Colors.black54,
                    onDeleted: () => setState(() => _selectedBreeds.remove(b)),
                  )).toList()),
            ],
            const SizedBox(height: 14),
          ],

          // ── Pays ──────────────────────────────────────────────────────
          _sLabel('Pays'),
          DropdownButtonFormField<String>(
            value: _pays.isEmpty ? null : _pays,
            decoration: _dropDecor('Tous les pays', Icons.public_outlined),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                color: Color(0xFF1F2A2E)),
            hint: const Text('Tous les pays', style: TextStyle(
                fontFamily: 'Galey', fontSize: 13, color: Color(0xFF9CA3AF))),
            items: [
              const DropdownMenuItem<String>(value: null,
                  child: Text('Tous les pays', style: TextStyle(
                      fontFamily: 'Galey', fontSize: 13, color: Color(0xFF9CA3AF)))),
              ..._paysList.map((p) => DropdownMenuItem(value: p,
                  child: Text(p, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)))),
            ],
            onChanged: (v) => setState(() {
              _pays = v ?? ''; _region = ''; _departement = '';
            }),
          ),
          const SizedBox(height: 14),

          // ── Région ────────────────────────────────────────────────────
          _sLabel('Région'),
          DropdownButtonFormField<String>(
            value: regions.contains(_region) ? _region : null,
            decoration: _dropDecor(
              _pays.isEmpty ? 'Sélectionnez d\'abord un pays' : 'Toutes les régions',
              Icons.location_on_outlined),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                color: Color(0xFF1F2A2E)),
            hint: Text(
              _pays.isEmpty ? 'Sélectionnez d\'abord un pays' : 'Toutes les régions',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                  color: Color(0xFF9CA3AF))),
            items: regions.isEmpty ? null : [
              const DropdownMenuItem<String>(value: null,
                  child: Text('Toutes les régions', style: TextStyle(
                      fontFamily: 'Galey', fontSize: 13, color: Color(0xFF9CA3AF)))),
              ...regions.map((r) => DropdownMenuItem(value: r,
                  child: Text(r, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)))),
            ],
            onChanged: regions.isEmpty ? null
                : (v) => setState(() { _region = v ?? ''; _departement = ''; }),
          ),
          const SizedBox(height: 14),

          // ── Département ───────────────────────────────────────────────
          _sLabel('Département'),
          DropdownButtonFormField<String>(
            value: departments.contains(_departement) ? _departement : null,
            decoration: _dropDecor(
              _region.isEmpty ? 'Sélectionnez d\'abord une région' : 'Tous les départements',
              Icons.map_outlined),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                color: Color(0xFF1F2A2E)),
            hint: Text(
              _region.isEmpty ? 'Sélectionnez d\'abord une région' : 'Tous les départements',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                  color: Color(0xFF9CA3AF))),
            items: departments.isEmpty ? null : [
              const DropdownMenuItem<String>(value: null,
                  child: Text('Tous les départements', style: TextStyle(
                      fontFamily: 'Galey', fontSize: 13, color: Color(0xFF9CA3AF)))),
              ...departments.map((d) => DropdownMenuItem(value: d,
                  child: Text(d, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)))),
            ],
            onChanged: departments.isEmpty ? null
                : (v) => setState(() => _departement = v ?? ''),
          ),
          const SizedBox(height: 14),

          // ── Ville ─────────────────────────────────────────────────────
          _sLabel('Ville'),
          TextField(
            controller: _villeCtrl,
            onChanged: _onVilleChanged,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: _fieldDecor('Ex : Lyon, Rennes...', Icons.location_city_outlined).copyWith(
              suffixIcon: _villeLoading
                  ? const SizedBox(width: 16, height: 16,
                      child: Padding(padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2, color: _teal)))
                  : _villeCtrl.text.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _villeCtrl.clear();
                            setState(() => _predictions = []);
                          })
                      : null,
            ),
          ),
          if (_predictions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE5E7EB)),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Column(
                children: _predictions.take(5).map((p) {
                  final main = p.structuredFormatting?.mainText ?? '';
                  final sec  = p.structuredFormatting?.secondaryText ?? '';
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined, size: 16, color: _teal),
                    title: Text(main, style: const TextStyle(
                        fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: sec.isNotEmpty
                        ? Text(sec, style: const TextStyle(fontFamily: 'Galey', fontSize: 11))
                        : null,
                    onTap: () => _selectPrediction(p),
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 24),

          // ── Appliquer ─────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _apply,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Appliquer les filtres',
                  style: TextStyle(fontFamily: 'Galey',
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Card éleveur ─────────────────────────────────────────────────────────────

class _EleveurCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String uid;
  const _EleveurCard({required this.data, required this.uid});

  @override
  Widget build(BuildContext context) {
    final nameElevage = (data['nameElevage'] ?? 'Élevage') as String;
    final desc    = (data['descEntreprise'] ?? '') as String;
    final ppUrl   = (data['profilePictureUrlElevage'] ?? '') as String;
    final bannerUrl = (data['bannerUrl'] ?? '') as String;
    final adress  = FrenchGeo.formatLocation(data).isNotEmpty
        ? FrenchGeo.formatLocation(data)
        : (data['adressElevage'] ?? '').toString().trim();

    // Espèces depuis le nouveau format ou fallback
    final especesElevees = data['especesElevees'];
    final List<({String espece, List<String> races})> speciesList;
    if (especesElevees is List && especesElevees.isNotEmpty) {
      speciesList = [
        for (final e in especesElevees)
          (
            espece: ((e as Map)['espece'] as String?) ?? '',
            races:  List<String>.from(e['races'] ?? []),
          ),
      ].where((s) => s.espece.isNotEmpty).toList();
    } else {
      speciesList = [
        if (data['isDog'] == true)
          (espece: 'chien', races: List<String>.from(data['dogBreeds'] ?? [])),
        if (data['isCat'] == true)
          (espece: 'chat', races: List<String>.from(data['catBreeds'] ?? [])),
      ];
    }

    return GestureDetector(
      onTap: () {
        final user = UserSelected.fromMap(data, uid);
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => UserDetailPageFeed(user: user)));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Bannière
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Stack(
              children: [
                bannerUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: bannerUrl,
                        height: 130, width: double.infinity, fit: BoxFit.cover,
                        placeholder: (_, __) => const _PlaceholderBanner(),
                        errorWidget: (_, __, ___) => const _PlaceholderBanner())
                    : ppUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: ppUrl,
                            height: 130, width: double.infinity, fit: BoxFit.cover,
                            placeholder: (_, __) => const _PlaceholderBanner(),
                            errorWidget: (_, __, ___) => const _PlaceholderBanner())
                        : const _PlaceholderBanner(),
                if (bannerUrl.isNotEmpty && ppUrl.isNotEmpty)
                  Positioned(
                    bottom: 8,
                    left: 12,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4)],
                      ),
                      child: ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: ppUrl, fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFFEEF5EA)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Nom + badge vérifié
              Row(children: [
                Expanded(
                  child: Text(nameElevage,
                      style: const TextStyle(fontFamily: 'Galey',
                          fontWeight: FontWeight.w600, fontSize: 16)),
                ),
                VerificationBadge(
                  level: getVerificationLevel(
                    isValidate: data['isValidate'] == true,
                    siret: data['siret']?.toString(),
                    isPremium: data['isPremium'] == true,
                  ),
                ),
              ]),

              // Espèces + races
              if (speciesList.isNotEmpty) ...[
                const SizedBox(height: 7),
                Wrap(spacing: 6, runSpacing: 4,
                    children: [
                      for (final s in speciesList) ...[
                        _SpeciesTag(espece: s.espece),
                        ...s.races.take(2).map((r) => _BreedTag(label: r)),
                        if (s.races.length > 2)
                          _BreedTag(label: '+${s.races.length - 2}'),
                      ],
                    ]),
              ],

              // Localisation
              if (adress.isNotEmpty) ...[
                const SizedBox(height: 5),
                Row(children: [
                  const Icon(Icons.location_on, size: 13, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(child: Text(adress,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      overflow: TextOverflow.ellipsis)),
                ]),
              ],

              // Animaux disponibles
              _AvailableAnimaux(uid: uid),

              // Description
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(desc,
                    style: const TextStyle(fontSize: 13, color: Colors.black87,
                        fontFamily: 'Galey'),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─── Animaux disponibles (async) ──────────────────────────────────────────────

class _AvailableAnimaux extends StatefulWidget {
  final String uid;
  const _AvailableAnimaux({required this.uid});
  @override
  State<_AvailableAnimaux> createState() => _AvailableAnimauxState();
}

class _AvailableAnimauxState extends State<_AvailableAnimaux> {
  List<Map<String, dynamic>>? _active;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snap = await FirebaseFirestore.instance
        .collection('annonces')
        .where('uidEleveur', isEqualTo: widget.uid)
        .get();
    if (!mounted) return;
    final active = snap.docs
        .map((d) => d.data())
        .where((d) {
          final s = (d['statut'] as String?) ?? '';
          return s == 'disponible' || s == 'reserve';
        })
        .toList();
    setState(() => _active = active);
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    if (active == null || active.isEmpty) return const SizedBox();

    // Grouper par race (ou label espèce si pas de race)
    final groups = <String, int>{};
    for (final d in active) {
      final espece = (d['espece'] as String?) ?? '';
      final race   = (d['race'] as String?) ?? '';
      final key    = race.isNotEmpty ? race : speciesLabel(espece);
      if (key.isNotEmpty) groups[key] = (groups[key] ?? 0) + 1;
    }
    if (groups.isEmpty) return const SizedBox();

    final parts = groups.entries
        .take(3)
        .map((e) => '${e.value} ${e.key}')
        .join(' · ');
    final extra = groups.length > 3 ? ' +${groups.length - 3}' : '';

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        const Icon(Icons.check_circle_outline, size: 13,
            color: Color(0xFF6E9E57)),
        const SizedBox(width: 4),
        Expanded(child: Text(
          '$parts$extra disponible(s)',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
              color: Color(0xFF6E9E57)),
          maxLines: 1, overflow: TextOverflow.ellipsis,
        )),
      ]),
    );
  }
}

// ─── Widgets utilitaires ──────────────────────────────────────────────────────

class _SpeciesTag extends StatelessWidget {
  final String espece;
  const _SpeciesTag({required this.espece});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFA7C79A).withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFA7C79A)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        speciesIcon(espece, 11, const Color(0xFF6E9E57)),
        const SizedBox(width: 4),
        Text(speciesLabel(espece),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                fontWeight: FontWeight.w500, color: Colors.black87)),
      ]),
    );
  }
}

class _BreedTag extends StatelessWidget {
  final String label;
  const _BreedTag({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Text(label, style: const TextStyle(
        fontFamily: 'Galey', fontSize: 10, color: Colors.black54)),
  );
}

class _PlaceholderBanner extends StatelessWidget {
  const _PlaceholderBanner();
  @override
  Widget build(BuildContext context) => Container(
    height: 130, width: double.infinity,
    color: const Color(0xFFA7C79A).withValues(alpha: 0.3),
    child: const Icon(Icons.pets, size: 48, color: Color(0xFFA7C79A)),
  );
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({this.message = 'Aucun élevage vérifié pour le moment.'});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.pets, size: 60, color: Colors.grey[300]),
      const SizedBox(height: 12),
      Text(message, style: const TextStyle(color: Colors.grey, fontFamily: 'Galey')),
    ]),
  );
}

// ─── Barre de recherche ───────────────────────────────────────────────────────

class _SearchBarWidget extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  const _SearchBarWidget({
      required this.controller, required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
        color: Color(0xFF1F2A2E)),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13,
          color: Colors.white54),
      prefixIcon: const Icon(Icons.search, color: Colors.white70, size: 20),
      suffixIcon: controller.text.isNotEmpty
          ? IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 18),
              onPressed: () { controller.clear(); onChanged(''); })
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.18),
    ),
  );
}

// ─── Bouton filtre avec badge ─────────────────────────────────────────────────

class _FilterButton extends StatelessWidget {
  final VoidCallback onTap;
  final int count;
  const _FilterButton({required this.onTap, required this.count});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Stack(clipBehavior: Clip.none, children: [
      Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.tune_outlined, color: Colors.white, size: 20)),
      if (count > 0)
        Positioned(top: -4, right: -4,
          child: Container(
            width: 18, height: 18,
            decoration: const BoxDecoration(
                color: Color(0xFF6E9E57), shape: BoxShape.circle),
            child: Center(child: Text('$count',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 10,
                    fontWeight: FontWeight.w700, color: Colors.white))))),
    ]),
  );
}

// ─── Chip filtre actif ────────────────────────────────────────────────────────

class _ActiveChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _ActiveChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 8),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
        color: const Color(0xFF0C5C6C).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: const Color(0xFF0C5C6C).withValues(alpha: 0.25))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
          fontWeight: FontWeight.w600, color: Color(0xFF0C5C6C))),
      const SizedBox(width: 6),
      GestureDetector(onTap: onRemove,
          child: const Icon(Icons.close, size: 14, color: Color(0xFF0C5C6C))),
    ]),
  );
}

// ─── Sélecteur de races (modal) ───────────────────────────────────────────────

class _BreedFilterSheet extends StatefulWidget {
  final List<String> allBreeds;
  final List<String> selected;
  const _BreedFilterSheet({required this.allBreeds, required this.selected});
  @override
  State<_BreedFilterSheet> createState() => _BreedFilterSheetState();
}

class _BreedFilterSheetState extends State<_BreedFilterSheet> {
  late List<String> _selected;
  late List<String> _filtered;
  final TextEditingController _search = TextEditingController();

  List<String> get _allWithOther {
    final list = List<String>.from(widget.allBreeds);
    if (!list.contains('Autre')) list.add('Autre');
    return list;
  }

  @override
  void initState() {
    super.initState();
    _selected = List<String>.from(widget.selected);
    _filtered = _allWithOther;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, scroll) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Expanded(
                child: Text('Filtrer par race', style: TextStyle(
                    fontFamily: 'Galey', fontWeight: FontWeight.w500, fontSize: 18)),
              ),
              if (_selected.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _selected.clear()),
                  child: const Text('Effacer', style: TextStyle(color: Colors.grey)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context, _selected),
                child: const Text('Appliquer', style: TextStyle(
                    fontFamily: 'Galey', fontWeight: FontWeight.w500,
                    color: Color(0xFF6E9E57), fontSize: 15)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _search,
              onChanged: (q) => setState(() {
                _filtered = _allWithOther
                    .where((b) => b.toLowerCase().contains(q.toLowerCase()))
                    .toList();
              }),
              decoration: InputDecoration(
                hintText: 'Rechercher une race...',
                hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(spacing: 6, runSpacing: 4,
                  children: _selected.map((b) => Chip(
                    label: Text(b, style: const TextStyle(
                        fontFamily: 'Galey', fontSize: 12)),
                    backgroundColor: const Color(0xFFA7C79A),
                    deleteIconColor: Colors.black54,
                    onDeleted: () => setState(() => _selected.remove(b)),
                  )).toList()),
            ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final breed = _filtered[i];
                final sel   = _selected.contains(breed);
                return ListTile(
                  dense: true,
                  title: Text(breed, style: TextStyle(
                      fontFamily: 'Galey', fontSize: 14,
                      fontWeight: sel ? FontWeight.w500 : FontWeight.normal)),
                  trailing: Icon(sel ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: sel ? const Color(0xFF6E9E57) : Colors.grey, size: 20),
                  onTap: () => setState(() {
                    sel ? _selected.remove(breed) : _selected.add(breed);
                  }),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
