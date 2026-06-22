import 'dart:async';
import 'dart:convert';
import 'package:PetsMatch/main.dart' show getApiKey;
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_feed_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_map_page.dart';
import 'package:PetsMatch/utils/french_geo.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:intl/intl.dart';

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

// ─── Page principale ──────────────────────────────────────────────────────────

class AnnoncesPublicPage extends StatefulWidget {
  final String  typeFilter;    // 'compagnon' | 'saillie'
  final String  initialEspece;
  final String? initialRace;
  final bool    isAssociation;
  const AnnoncesPublicPage({
    super.key,
    this.typeFilter = 'compagnon',
    this.initialEspece = 'tous',
    this.initialRace,
    this.isAssociation = false,
  });

  @override
  State<AnnoncesPublicPage> createState() => _AnnoncesPublicPageState();
}

class _AnnoncesPublicPageState extends State<AnnoncesPublicPage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  String _espece       = 'tous';
  String _searchText   = '';
  String _pays         = '';
  String _region       = '';
  String _departement  = '';
  String _ville        = '';
  String _raceText     = '';

  @override
  void initState() {
    super.initState();
    _espece   = widget.initialEspece;
    _raceText = widget.initialRace ?? '';
    if (_raceText.isNotEmpty) _raceCtrl.text = _raceText;
  }
  double? _prixMin;
  double? _prixMax;

  final _searchCtrl  = TextEditingController();
  final _raceCtrl    = TextEditingController();
  final _villeCtrl   = TextEditingController();
  final _prixMinCtrl = TextEditingController();
  final _prixMaxCtrl = TextEditingController();

  bool get _isSaillie    => widget.typeFilter == 'saillie';
  bool get _isAssociation => widget.isAssociation;

  int get _activeFilterCount {
    int n = 0;
    if (_espece != 'tous') n++;
    if (_pays.isNotEmpty) n++;
    if (_region.isNotEmpty) n++;
    if (_departement.isNotEmpty) n++;
    if (_ville.isNotEmpty) n++;
    if (_raceText.isNotEmpty) n++;
    if (_prixMin != null) n++;
    if (_prixMax != null) n++;
    return n;
  }

  bool _matches(Map<String, dynamic> d) {
    // Filtre profil_source
    final ps = (d['profilSource'] as String?) ?? (d['profil_source'] as String?);
    if (_isAssociation) {
      if (ps != 'association') return false;
    } else {
      if (ps == 'association') return false;
    }
    if (_isSaillie) {
      if ((d['typeVente'] as String?) != 'saillie') return false;
    } else {
      if ((d['typeVente'] as String?) == 'saillie') return false;
    }
    final s = (d['statut'] as String?) ?? '';
    if (s == 'vendu' || s == 'cede' || s == 'expire') return false;
    if (_espece != 'tous' && d['espece'] != _espece) return false;
    if (_raceText.isNotEmpty) {
      final race = ((d['race'] as String?) ?? '').toLowerCase();
      if (!race.contains(_raceText.toLowerCase())) return false;
    }
    if (_pays.isNotEmpty) {
      final stored = ((d['paysEleveur'] as String?) ?? '').toLowerCase();
      if (stored.isNotEmpty && !stored.contains(_pays.toLowerCase())) return false;
    }
    if (_region.isNotEmpty) {
      final stored = ((d['regionEleveur'] as String?) ?? '').toLowerCase();
      if (!stored.contains(_region.toLowerCase())) return false;
    }
    if (_departement.isNotEmpty) {
      final stored = ((d['departementEleveur'] as String?) ?? '').toLowerCase();
      if (!stored.contains(_departement.toLowerCase())) return false;
    }
    if (_ville.isNotEmpty) {
      final stored = ((d['villeEleveur'] as String?) ?? '').toLowerCase();
      if (!stored.contains(_ville.toLowerCase())) return false;
    }
    if (_searchText.isNotEmpty) {
      final q     = _searchText.toLowerCase();
      final race  = ((d['race'] as String?) ?? '').toLowerCase();
      final titre = ((d['titre'] as String?) ?? '').toLowerCase();
      if (!race.contains(q) && !titre.contains(q)) return false;
    }
    if (_prixMin != null || _prixMax != null) {
      final type      = (d['type'] as String?) ?? 'animal';
      final typeVente = (d['typeVente'] as String?) ?? 'vente';
      final prix = type == 'portee'
          ? (d['prixMinPortee'] as num?)?.toDouble()
          : typeVente == 'saillie'
              ? (d['sailliePrix'] as num?)?.toDouble()
              : (d['prix'] as num?)?.toDouble();
      if (prix == null) return false;
      if (_prixMin != null && prix < _prixMin!) return false;
      if (_prixMax != null && prix > _prixMax!) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _raceCtrl.dispose();
    _villeCtrl.dispose();
    _prixMinCtrl.dispose();
    _prixMaxCtrl.dispose();
    super.dispose();
  }

  void _removeFilter(String key) {
    setState(() {
      switch (key) {
        case 'espece':       _espece = 'tous'; break;
        case 'pays':         _pays = ''; _region = ''; _departement = ''; break;
        case 'region':       _region = ''; _departement = ''; break;
        case 'departement':  _departement = ''; break;
        case 'ville':        _ville = ''; _villeCtrl.clear(); break;
        case 'race':         _raceText = ''; _raceCtrl.clear(); break;
        case 'prixMin':      _prixMin = null; _prixMinCtrl.clear(); break;
        case 'prixMax':      _prixMax = null; _prixMaxCtrl.clear(); break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text(
          _isAssociation ? 'Adoptions' : _isSaillie ? 'Saillies' : 'Trouver un compagnon',
          style: const TextStyle(fontFamily: 'Galey',
              fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.play_circle_outline_rounded),
            tooltip: 'Fil d\'actualité',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => AnnoncesFeedPage(isAssociationFeed: _isAssociation))),
          ),
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Voir carte',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => AnnoncesMapPage(
                    typeFilter: widget.typeFilter,
                    espece: _espece,
                    race: _raceText,
                    pays: _pays,
                    region: _region,
                    departement: _departement,
                    ville: _ville))),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(children: [
              Expanded(
                child: _SearchBar(
                  controller: _searchCtrl,
                  hint: _isSaillie ? 'Race, étalon...' : 'Race, titre...',
                  onChanged: (v) => setState(() => _searchText = v),
                ),
              ),
              const SizedBox(width: 8),
              _FilterButton(
                count: _activeFilterCount,
                onTap: () => _openFilterSheet(context),
              ),
            ]),
          ),
        ),
      ),
      body: Column(children: [
        // ── Active filter chips ──────────────────────────────────────────
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
                if (_raceText.isNotEmpty)
                  _ActiveChip(label: _raceText,
                      onRemove: () => _removeFilter('race')),
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
                if (_prixMin != null)
                  _ActiveChip(label: '≥ ${_prixMin!.toStringAsFixed(0)} €',
                      onRemove: () => _removeFilter('prixMin')),
                if (_prixMax != null)
                  _ActiveChip(label: '≤ ${_prixMax!.toStringAsFixed(0)} €',
                      onRemove: () => _removeFilter('prixMax')),
              ]),
            ),
          ),
        // ── Liste ────────────────────────────────────────────────────────
        Expanded(child: _AnnoncesList(
          matches: _matches,
          isSaillie: _isSaillie,
        )),
      ]),
    );
  }

  Future<void> _openFilterSheet(BuildContext context) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _FilterSheet(
        espece: _espece, pays: _pays, region: _region,
        departement: _departement, ville: _ville, race: _raceText,
        prixMin: _prixMin, prixMax: _prixMax,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _espece      = result['espece'] as String;
        _pays        = result['pays'] as String;
        _region      = result['region'] as String;
        _departement = result['departement'] as String;
        _ville       = result['ville'] as String;
        _raceText    = result['race'] as String;
        _prixMin     = result['prixMin'] as double?;
        _prixMax     = result['prixMax'] as double?;
        _villeCtrl.text   = _ville;
        _raceCtrl.text    = _raceText;
        _prixMinCtrl.text = _prixMin != null ? _prixMin!.toStringAsFixed(0) : '';
        _prixMaxCtrl.text = _prixMax != null ? _prixMax!.toStringAsFixed(0) : '';
      });
    }
  }
}

// ─── Feuille de filtres (StatefulWidget propre) ───────────────────────────────

class _FilterSheet extends StatefulWidget {
  final String espece, pays, region, departement, ville, race;
  final double? prixMin, prixMax;
  const _FilterSheet({
    required this.espece, required this.pays, required this.region,
    required this.departement, required this.ville, required this.race,
    required this.prixMin, required this.prixMax,
  });
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  late String _espece;
  late String _pays;
  late String _region;
  late String _departement;

  late final TextEditingController _raceCtrl;
  late final TextEditingController _villeCtrl;
  late final TextEditingController _prixMinCtrl;
  late final TextEditingController _prixMaxCtrl;

  late final GoogleMapsPlaces _places;
  Timer? _debounce;
  List<Prediction> _predictions = [];
  bool _villeLoading = false;
  Map<String, List<String>> _allBreeds = {};

  List<String> get _currentBreeds {
    if (_espece == 'tous') return [];
    final list = List<String>.from(_allBreeds[_espece] ?? []);
    if (list.isNotEmpty && !list.contains('Autre')) list.add('Autre');
    return list;
  }

  @override
  void initState() {
    super.initState();
    _espece      = widget.espece;
    _pays        = widget.pays;
    _region      = widget.region;
    _departement = widget.departement;
    _raceCtrl    = TextEditingController(text: widget.race);
    _villeCtrl   = TextEditingController(text: widget.ville);
    _prixMinCtrl = TextEditingController(
        text: widget.prixMin != null ? widget.prixMin!.toStringAsFixed(0) : '');
    _prixMaxCtrl = TextEditingController(
        text: widget.prixMax != null ? widget.prixMax!.toStringAsFixed(0) : '');
    _places = GoogleMapsPlaces(apiKey: getApiKey());
    _loadBreeds();
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
        loaded[e.key] = List<String>.from(jsonDecode(raw));
      } catch (_) {
        loaded[e.key] = [];
      }
    }
    if (mounted) setState(() => _allBreeds = loaded);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _raceCtrl.dispose();
    _villeCtrl.dispose();
    _prixMinCtrl.dispose();
    _prixMaxCtrl.dispose();
    _places.dispose();
    super.dispose();
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

  void _apply() {
    Navigator.pop(context, {
      'espece':      _espece,
      'pays':        _pays,
      'region':      _region,
      'departement': _departement,
      'ville':       _villeCtrl.text.trim(),
      'race':        _raceCtrl.text.trim(),
      'prixMin':     double.tryParse(_prixMinCtrl.text.trim()),
      'prixMax':     double.tryParse(_prixMaxCtrl.text.trim()),
    });
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  Widget _sLabel(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(fontFamily: 'Galey',
        fontSize: 12, fontWeight: FontWeight.w700,
        color: Color(0xFF6F767B))));

  InputDecoration _fieldDecor(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13,
        color: Color(0xFF9CA3AF)),
    prefixIcon: Icon(icon, color: _teal, size: 18),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _teal)),
    filled: true, fillColor: const Color(0xFFF8F9FA),
  );

  InputDecoration _dropDecor(String hint, IconData icon) =>
      _fieldDecor(hint, icon).copyWith(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4));

  Widget _especeChip(String val, String label) {
    final active = _espece == val;
    return GestureDetector(
      onTap: () => setState(() => _espece = val),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(right: 8, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
          Text(label, style: TextStyle(fontFamily: 'Galey',
              fontSize: 12, fontWeight: FontWeight.w600,
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
            const Text('Filtres', style: TextStyle(fontFamily: 'Galey',
                fontWeight: FontWeight.w700, fontSize: 17)),
            TextButton(
              onPressed: () => setState(() {
                _espece = 'tous'; _pays = ''; _region = '';
                _departement = '';
                _raceCtrl.clear(); _villeCtrl.clear();
                _prixMinCtrl.clear(); _prixMaxCtrl.clear();
                _predictions = [];
              }),
              child: const Text('Réinitialiser',
                  style: TextStyle(fontFamily: 'Galey',
                      fontSize: 13, color: Color(0xFF6F767B))),
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

          // ── Race ──────────────────────────────────────────────────────
          _sLabel('Race'),
          if (_currentBreeds.isEmpty)
            TextField(
              controller: _raceCtrl,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: _fieldDecor('Ex : Labrador, Maine Coon...', Icons.pets_outlined),
            )
          else
            GestureDetector(
              onTap: () async {
                final breeds = List<String>.from(_currentBreeds);
                if (!breeds.contains('Autre')) breeds.add('Autre');
                final selected = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (_) => _AnnonceBreedPicker(breeds: breeds, current: _raceCtrl.text),
                );
                if (selected != null) setState(() => _raceCtrl.text = selected);
              },
              child: AbsorbPointer(
                child: TextField(
                  controller: _raceCtrl,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  decoration: _fieldDecor('Ex : Labrador, Chèvre alpine...', Icons.pets_outlined)
                      .copyWith(suffixIcon: const Icon(Icons.keyboard_arrow_down, size: 18, color: _teal)),
                ),
              ),
            ),
          const SizedBox(height: 14),

          // ── Pays ──────────────────────────────────────────────────────
          _sLabel('Pays'),
          DropdownButtonFormField<String>(
            value: _pays.isEmpty ? null : _pays,
            decoration: _dropDecor('Tous les pays', Icons.public_outlined),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                color: Color(0xFF1F2A2E)),
            hint: const Text('Tous les pays',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                    color: Color(0xFF9CA3AF))),
            items: [
              const DropdownMenuItem<String>(value: null,
                  child: Text('Tous les pays', style: TextStyle(
                      fontFamily: 'Galey', fontSize: 13,
                      color: Color(0xFF9CA3AF)))),
              ..._paysList.map((p) => DropdownMenuItem(value: p,
                  child: Text(p, style: const TextStyle(
                      fontFamily: 'Galey', fontSize: 14)))),
            ],
            onChanged: (v) => setState(() {
              _pays = v ?? ''; _region = ''; _departement = '';
            }),
          ),
          const SizedBox(height: 14),

          // ── Région ────────────────────────────────────────────────────
          _sLabel('Région'),
          DropdownButtonFormField<String>(
            value: (regions.contains(_region)) ? _region : null,
            decoration: _dropDecor(
              _pays.isEmpty ? 'Sélectionnez d\'abord un pays'
                  : 'Toutes les régions',
              Icons.location_on_outlined),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                color: Color(0xFF1F2A2E)),
            hint: Text(
              _pays.isEmpty ? 'Sélectionnez d\'abord un pays'
                  : 'Toutes les régions',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                  color: Color(0xFF9CA3AF))),
            items: regions.isEmpty ? null : [
              const DropdownMenuItem<String>(value: null,
                  child: Text('Toutes les régions', style: TextStyle(
                      fontFamily: 'Galey', fontSize: 13,
                      color: Color(0xFF9CA3AF)))),
              ...regions.map((r) => DropdownMenuItem(value: r,
                  child: Text(r, style: const TextStyle(
                      fontFamily: 'Galey', fontSize: 14)))),
            ],
            onChanged: regions.isEmpty ? null
                : (v) => setState(() {
                    _region = v ?? ''; _departement = '';
                  }),
          ),
          const SizedBox(height: 14),

          // ── Département ───────────────────────────────────────────────
          _sLabel('Département'),
          DropdownButtonFormField<String>(
            value: departments.contains(_departement) ? _departement : null,
            decoration: _dropDecor(
              _region.isEmpty ? 'Sélectionnez d\'abord une région'
                  : 'Tous les départements',
              Icons.map_outlined),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                color: Color(0xFF1F2A2E)),
            hint: Text(
              _region.isEmpty ? 'Sélectionnez d\'abord une région'
                  : 'Tous les départements',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                  color: Color(0xFF9CA3AF))),
            items: departments.isEmpty ? null : [
              const DropdownMenuItem<String>(value: null,
                  child: Text('Tous les départements', style: TextStyle(
                      fontFamily: 'Galey', fontSize: 13,
                      color: Color(0xFF9CA3AF)))),
              ...departments.map((d) => DropdownMenuItem(value: d,
                  child: Text(d, style: const TextStyle(
                      fontFamily: 'Galey', fontSize: 14)))),
            ],
            onChanged: departments.isEmpty ? null
                : (v) => setState(() => _departement = v ?? ''),
          ),
          const SizedBox(height: 14),

          // ── Ville (autocomplete Google Places) ────────────────────────
          _sLabel('Ville'),
          TextField(
            controller: _villeCtrl,
            onChanged: _onVilleChanged,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: _fieldDecor(
                'Ex : Lyon, Rennes...', Icons.location_city_outlined).copyWith(
              suffixIcon: _villeLoading
                  ? const SizedBox(width: 16, height: 16,
                      child: Padding(padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _teal)))
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
                    leading: const Icon(Icons.location_on_outlined,
                        size: 16, color: _teal),
                    title: Text(main, style: const TextStyle(
                        fontFamily: 'Galey', fontSize: 13,
                        fontWeight: FontWeight.w600)),
                    subtitle: sec.isNotEmpty ? Text(sec, style: const TextStyle(
                        fontFamily: 'Galey', fontSize: 11)) : null,
                    onTap: () => _selectPrediction(p),
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 14),

          // ── Budget ────────────────────────────────────────────────────
          _sLabel('Budget (€)'),
          Row(children: [
            Expanded(child: TextField(
              controller: _prixMinCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: _fieldDecor('Min', Icons.euro_outlined),
            )),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('—', style: TextStyle(fontFamily: 'Galey',
                    fontSize: 16, color: Colors.grey.shade400))),
            Expanded(child: TextField(
              controller: _prixMaxCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: _fieldDecor('Max', Icons.euro_outlined),
            )),
          ]),
          const SizedBox(height: 24),

          // ── Appliquer ─────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _apply,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
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

// ─── Barre de recherche ───────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.controller, required this.hint,
      required this.onChanged});

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

// ─── Liste avec StreamBuilder ─────────────────────────────────────────────────

class _AnnoncesList extends StatelessWidget {
  final bool Function(Map<String, dynamic>) matches;
  final bool isSaillie;
  const _AnnoncesList({required this.matches, required this.isSaillie});

  static Timestamp? _ts(dynamic v) {
    if (v == null) return null;
    try { return Timestamp.fromDate(DateTime.parse(v.toString())); } catch (_) { return null; }
  }

  static Map<String, dynamic> _norm(Map<String, dynamic> row) => {
    ...row,
    'uidEleveur':         row['uid_eleveur'],
    'nomEleveur':         row['nom_eleveur'],
    'villeEleveur':       row['ville_eleveur'],
    'paysEleveur':        row['pays_eleveur'],
    'regionEleveur':      row['region_eleveur'],
    'departementEleveur': row['departement_eleveur'],
    'typeVente':          row['type_vente'],
    'sailliePrix':        row['saillie_prix'],
    'prixMinPortee':      row['prix_min_portee'],
    'prixMaxPortee':      row['prix_max_portee'],
    'nombreBebes':        row['nombre_bebes'],
    'animauxPortee':      row['animaux_portee'] ?? [],
    'createdAt':          _ts(row['created_at']),
    'profilSource':       row['profil_source'],
  };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client.from('annonces')
          .stream(primaryKey: ['id'])
          .eq('statut', 'disponible')
          .order('created_at', ascending: false),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator(
              color: Color(0xFF0C5C6C)));
        }
        if (snap.hasError) {
          return Center(child: Text('Erreur : ${snap.error}',
              style: const TextStyle(fontFamily: 'Galey',
                  color: Colors.redAccent)));
        }

        final rows = (snap.data ?? []).map(_norm).where(matches).toList();

        if (rows.isEmpty) {
          return Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(isSaillie
                ? Icons.diversity_1_outlined : Icons.pets_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            Text(isSaillie
                ? 'Aucune saillie disponible'
                : 'Aucune annonce disponible',
                style: TextStyle(fontFamily: 'Galey', fontSize: 16,
                    color: Colors.grey.shade500)),
            const SizedBox(height: 6),
            Text('Essayez de modifier vos filtres',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                    color: Colors.grey.shade400)),
          ]));
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: rows.length,
          itemBuilder: (context, i) => _AnnonceCard(
              id: rows[i]['id'] as String, data: rows[i]),
        );
      },
    );
  }
}

// ─── Card annonce publique ────────────────────────────────────────────────────

class _AnnonceCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  const _AnnonceCard({required this.id, required this.data});

  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  @override
  Widget build(BuildContext context) {
    final espece      = (data['espece'] as String?) ?? '';
    final race        = (data['race'] as String?) ?? '';
    final titre       = (data['titre'] as String?) ?? '';
    final typeVente   = (data['typeVente'] as String?) ?? 'vente';
    final type        = (data['type'] as String?) ?? 'animal';
    final photos      = List<String>.from(data['photos'] ?? []);
    final prix        = (data['prix'] as num?)?.toDouble();
    final sailliePrix = (data['sailliePrix'] as num?)?.toDouble();
    final prixMin     = (data['prixMinPortee'] as num?)?.toDouble();
    final prixMax     = (data['prixMaxPortee'] as num?)?.toDouble();
    final nombreBebes = (data['nombreBebes'] as num?)?.toInt();
    final nomEleveur  = (data['nomEleveur'] as String?) ?? '';
    final villeEleveur = (data['villeEleveur'] as String?) ?? '';
    final createdAt   = data['createdAt'] as Timestamp?;

    final displayTitle = titre.isNotEmpty ? titre
        : race.isNotEmpty ? race : speciesLabel(espece);

    String timeAgo = '';
    if (createdAt != null) {
      final diff = DateTime.now().difference(createdAt.toDate());
      timeAgo = diff.inDays == 0 ? "Aujourd'hui"
          : diff.inDays == 1 ? 'Hier'
          : diff.inDays < 7 ? 'il y a ${diff.inDays} j'
          : DateFormat('dd/MM/yy').format(createdAt.toDate());
    }

    // Build prix display string
    String prixLabel = '';
    Color prixColor = const Color(0xFF1F2A2E);
    if (typeVente == 'vente') {
      if (type == 'portee' && (prixMin != null || prixMax != null)) {
        prixLabel = prixMin != null && prixMax != null
            ? '${prixMin.toInt()} – ${prixMax.toInt()} €'
            : prixMin != null ? 'Dès ${prixMin.toInt()} €'
            : 'Max ${prixMax!.toInt()} €';
      } else if (prix != null && prix > 0) {
        prixLabel = '${prix.toStringAsFixed(0)} €';
      }
    } else if (typeVente == 'adoption') {
      prixLabel = 'Don gratuit';
      prixColor = _green;
    } else if (typeVente == 'saillie') {
      prixLabel = sailliePrix != null && sailliePrix > 0
          ? '💜 ${sailliePrix.toInt()} €'
          : '💜 Saillie';
      prixColor = const Color(0xFF7C3AED);
    } else if (typeVente == 'retraite') {
      prixLabel = prix != null && prix > 0 ? '${prix.toInt()} €' : 'Retraité';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => AnnonceDetailPage(
                annonceId: id, initialData: data))),
        borderRadius: BorderRadius.circular(14),
        child: Row(children: [
          // ── Photo ──────────────────────────────────────────────────────
          ClipRRect(
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                bottomLeft: Radius.circular(14)),
            child: SizedBox(width: 100, height: 120,
              child: photos.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photos.first, fit: BoxFit.cover,
                      placeholder: (_, __) => _placeholder(espece),
                      errorWidget: (_, __, ___) => _placeholder(espece))
                  : _placeholder(espece)),
          ),
          // ── Infos ───────────────────────────────────────────────────────
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
              Row(children: [
                speciesIcon(espece, 12, _teal),
                const SizedBox(width: 4),
                Expanded(child: Text(displayTitle,
                    style: const TextStyle(fontFamily: 'Galey',
                        fontWeight: FontWeight.w700, fontSize: 14,
                        color: Color(0xFF1F2A2E)),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 3),
              Text(
                '${race.isNotEmpty ? race : speciesLabel(espece)}'
                '${type == 'portee' && nombreBebes != null
                    ? ' · $nombreBebes bébés' : ''}',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                    color: Color(0xFF6F767B)),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                if (prixLabel.isNotEmpty)
                  Text(prixLabel, style: TextStyle(
                      fontFamily: 'Galey', fontWeight: FontWeight.w800,
                      fontSize: typeVente == 'vente' ? 15 : 13,
                      color: prixColor)),
                const Spacer(),
                if (timeAgo.isNotEmpty)
                  Text(timeAgo, style: TextStyle(fontFamily: 'Galey',
                      fontSize: 10, color: Colors.grey.shade400)),
              ]),
              const SizedBox(height: 5),
              Row(children: [
                const Icon(Icons.store_outlined, size: 12,
                    color: Color(0xFF6F767B)),
                const SizedBox(width: 4),
                Expanded(child: Text(
                  nomEleveur.isNotEmpty ? nomEleveur : 'Éleveur',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                      color: Color(0xFF6F767B)),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                )),
                if (villeEleveur.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.location_on_outlined, size: 11,
                      color: Colors.grey.shade400),
                  Flexible(child: Text(villeEleveur,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                          color: Colors.grey.shade400),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ]),
            ]),
          )),
          Padding(padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.chevron_right,
                  color: Colors.grey.shade300, size: 20)),
        ]),
      ),
    );
  }

  Widget _placeholder(String espece) => Container(
    color: const Color(0xFFEEF5EA),
    child: Center(child: speciesIcon(espece, 36,
        const Color(0xFF6E9E57).withValues(alpha: 0.35))),
  );
}

// ─── Breed picker for annonce filter ─────────────────────────────────────────

class _AnnonceBreedPicker extends StatefulWidget {
  final List<String> breeds;
  final String current;
  const _AnnonceBreedPicker({required this.breeds, required this.current});
  @override State<_AnnonceBreedPicker> createState() => _AnnonceBreedPickerState();
}

class _AnnonceBreedPickerState extends State<_AnnonceBreedPicker> {
  late List<String> _filtered;
  final _searchCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _filtered = widget.breeds; }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  void _filter(String q) => setState(() {
    _filtered = q.isEmpty
        ? widget.breeds
        : widget.breeds.where((b) => b.toLowerCase().contains(q.toLowerCase())).toList();
  });

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
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Expanded(child: Text('Filtrer par race',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17))),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _filter,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Rechercher une race...',
                hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true, fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final b = _filtered[i];
                final selected = b == widget.current;
                return ListTile(
                  dense: true,
                  title: Text(b, style: TextStyle(
                      fontFamily: 'Galey', fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                      color: selected ? const Color(0xFF0C5C6C) : const Color(0xFF1F2A2E))),
                  trailing: selected ? const Icon(Icons.check, color: Color(0xFF0C5C6C), size: 18) : null,
                  onTap: () => Navigator.pop(context, b),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
