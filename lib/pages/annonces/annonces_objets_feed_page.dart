import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/data/annonce_objet_categories.dart';
import 'package:PetsMatch/pages/chatScreen.dart';
import 'package:PetsMatch/utils/french_geo.dart';
import 'package:PetsMatch/utils/messaging_helper.dart';
import 'package:PetsMatch/pages/particulier/create_annonce_objet_page.dart';

const _teal  = Color(0xFF0C5C6C);
const _green = Color(0xFF6E9E57);
const _orange = Color(0xFFFF8A00);

const _kTris = <String, String>{
  'recent': 'Plus récentes',
  'prix_asc': 'Prix croissant',
  'prix_desc': 'Prix décroissant',
};

/// Communes d'un code postal (API open data geo.api.gouv.fr).
Future<List<String>> fetchCommunes(String cp) async {
  if (cp.length != 5) return const [];
  try {
    final uri = Uri.https('geo.api.gouv.fr', '/communes',
        {'codePostal': cp, 'fields': 'nom', 'format': 'json'});
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    return (jsonDecode(res.body) as List)
        .map((e) => (e['nom'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  } catch (_) {
    return const [];
  }
}

/// Fil public des petites annonces « objets & matériel » liées aux animaux —
/// style « petites annonces » : recherche mot-clé, catégories, filtres
/// région / département / ville, géolocalisation, tri. Ouvert à tous.
class AnnoncesObjetsFeedPage extends StatefulWidget {
  const AnnoncesObjetsFeedPage({super.key});
  @override
  State<AnnoncesObjetsFeedPage> createState() => _AnnoncesObjetsFeedPageState();
}

class _AnnoncesObjetsFeedPageState extends State<AnnoncesObjetsFeedPage> {
  final _supa = Supabase.instance.client;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _locating = false;

  // Filtres
  String _cat = 'tous';
  String _kw = '';
  String? _region;
  String? _departement;
  String _ville = '';        // commune sélectionnée
  String _cpFilter = '';     // code postal saisi dans les filtres
  List<String> _communes = [];
  bool _loadingCommunes = false;
  String _tri = 'recent';

  int get _activeFilters =>
      (_region != null ? 1 : 0) +
      (_departement != null ? 1 : 0) +
      (_ville.isNotEmpty ? 1 : 0) +
      (_cpFilter.isNotEmpty ? 1 : 0) +
      (_tri != 'recent' ? 1 : 0);

  Future<void> _loadCommunesFilter(String cp, void Function(void Function()) setSheet) async {
    setSheet(() { _loadingCommunes = true; _cpFilter = cp; });
    final geo = FrenchGeo.fromPostalCode(cp);
    final list = await fetchCommunes(cp);
    setSheet(() {
      _communes = list;
      _loadingCommunes = false;
      if (geo != null) { _region = geo.region; _departement = geo.departement; }
      if (!list.contains(_ville)) _ville = list.length == 1 ? list.first : '';
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() => _kw = v.trim());
      _load();
    });
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      var q = _supa.from('annonces_objets').select().eq('statut', 'disponible');
      if (_cat != 'tous') q = q.eq('categorie', _cat);
      if (_kw.isNotEmpty) {
        final safe = _kw.replaceAll('%', '').replaceAll(',', ' ');
        q = q.or('titre.ilike.%$safe%,description.ilike.%$safe%');
      }
      if (_region != null) q = q.eq('region', _region!);
      if (_departement != null) q = q.eq('departement', _departement!);
      if (_cpFilter.length == 5) q = q.eq('code_postal', _cpFilter);
      if (_ville.isNotEmpty) q = q.ilike('ville', '%$_ville%');

      final PostgrestList data;
      if (_tri == 'prix_asc') {
        data = await q.order('prix', ascending: true, nullsFirst: false).limit(200);
      } else if (_tri == 'prix_desc') {
        data = await q.order('prix', ascending: false, nullsFirst: false).limit(200);
      } else {
        data = await q.order('created_at', ascending: false).limit(200);
      }

      var rows = List<Map<String, dynamic>>.from(data);
      if (_tri == 'recent') {
        rows = [
          ...rows.where((r) => annonceObjetBoostActif(r['boost_until'])),
          ...rows.where((r) => !annonceObjetBoostActif(r['boost_until'])),
        ];
      }
      if (mounted) setState(() { _rows = rows; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _autourDeMoi() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _snack('Autorisez la localisation pour utiliser « Autour de moi ».');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      );
      final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      final cp = marks.isNotEmpty ? (marks.first.postalCode ?? '') : '';
      final geo = FrenchGeo.fromPostalCode(cp);
      if (geo == null) {
        _snack('Localisation introuvable.');
        return;
      }
      setState(() {
        _region = geo.region;
        _departement = geo.departement;
      });
      _load();
      _snack('📍 ${geo.departement}');
    } catch (_) {
      _snack('Impossible de récupérer votre position.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m, style: const TextStyle(fontFamily: 'Galey'))),
      );

  Future<void> _openFilters() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        final kwCtrl = TextEditingController(text: _kw);
        final cpCtrl = TextEditingController(text: _cpFilter);
        return StatefulBuilder(
        builder: (ctx, setSheet) {
          final depts = _region != null
              ? FrenchGeo.departmentsInRegion(_region!)
              : const <String>[];
          return SingleChildScrollView(
            child: Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
                  color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                const Text('Filtres', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() {
                      _kw = ''; _cat = 'tous';
                      _region = null; _departement = null;
                      _ville = ''; _cpFilter = ''; _communes = [];
                      _tri = 'recent';
                    });
                    _load();
                    Navigator.pop(ctx);
                  },
                  child: const Text('Tout effacer', style: TextStyle(fontFamily: 'Galey')),
                ),
              ]),
              const SizedBox(height: 12),

              _sheetLabel('Mots-clés'),
              TextField(
                controller: kwCtrl,
                decoration: _sheetDec('Ex : cage lapin, foin, harnais…').copyWith(
                  prefixIcon: const Icon(Icons.search, size: 18),
                ),
              ),
              const SizedBox(height: 12),

              _sheetLabel('Catégorie'),
              DropdownButtonFormField<String>(
                initialValue: _cat,
                isExpanded: true,
                decoration: _sheetDec('Toutes les catégories'),
                items: [
                  const DropdownMenuItem(value: 'tous', child: Text('Toutes les catégories')),
                  for (final c in kAnnonceObjetCategories)
                    DropdownMenuItem(value: c.slug, child: Text('${c.emoji}  ${c.label}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setSheet(() => _cat = v ?? 'tous'),
              ),
              const SizedBox(height: 16),

              OutlinedButton.icon(
                onPressed: _locating ? null : () { Navigator.pop(ctx); _autourDeMoi(); },
                icon: _locating
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location, size: 16),
                label: const Text('Autour de moi', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal)),
              ),
              const SizedBox(height: 14),

              _sheetLabel('Code postal'),
              TextField(
                controller: cpCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                decoration: _sheetDec('5 chiffres — puis choisissez la commune'),
                onChanged: (v) {
                  final cp = v.trim();
                  if (cp.length == 5) {
                    _loadCommunesFilter(cp, setSheet);
                  } else {
                    setSheet(() { _communes = []; _cpFilter = ''; _ville = ''; });
                  }
                },
              ),
              const SizedBox(height: 12),

              _sheetLabel('Commune'),
              if (_loadingCommunes)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Row(children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Recherche des communes…', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5)),
                  ]),
                )
              else if (_communes.isEmpty)
                Text(
                  cpCtrl.text.trim().length == 5
                      ? 'Aucune commune pour ce code postal.'
                      : 'Saisissez le code postal pour choisir une commune.',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _communes.contains(_ville) ? _ville : null,
                  isExpanded: true,
                  decoration: _sheetDec('Toutes les communes du code postal'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Toutes les communes')),
                    for (final c in _communes) DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setSheet(() => _ville = v ?? ''),
                ),
              const SizedBox(height: 12),

              _sheetLabel('Ou par région / département'),
              DropdownButtonFormField<String>(
                initialValue: _region,
                isExpanded: true,
                decoration: _sheetDec('Toutes les régions'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Toutes les régions')),
                  for (final r in FrenchGeo.regions) DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setSheet(() { _region = v; _departement = null; }),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _departement,
                isExpanded: true,
                decoration: _sheetDec(_region == null ? 'Département — choisissez une région' : 'Tous les départements'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tous les départements')),
                  for (final d in depts) DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: _region == null ? null : (v) => setSheet(() => _departement = v),
              ),
              const SizedBox(height: 12),

              _sheetLabel('Trier par'),
              Wrap(spacing: 8, children: [
                for (final e in _kTris.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _tri == e.key,
                    onSelected: (_) => setSheet(() => _tri = e.key),
                    selectedColor: _teal.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                        fontFamily: 'Galey',
                        color: _tri == e.key ? _teal : Colors.grey.shade700,
                        fontWeight: FontWeight.w600),
                  ),
              ]),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity, height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    final kw = kwCtrl.text.trim();
                    _searchCtrl.text = kw;
                    setState(() => _kw = kw);
                    Navigator.pop(ctx);
                    _load();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Voir les résultats',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ]),
          ),
          );
        },
      );
      },
    );
  }

  Widget _sheetLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1F2A2E))),
      );

  InputDecoration _sheetDec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade400, fontSize: 13),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _teal, width: 1.5)),
      );

  @override
  Widget build(BuildContext context) {
    final locLabel = _ville.isNotEmpty ? _ville : (_departement ?? _region);
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F4),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Petites annonces — matériel',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _teal,
        onPressed: () async {
          final ok = await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CreateAnnonceObjetPage()));
          if (ok == true) _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Publier', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        // ── Recherche + bouton filtres ─────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) { setState(() => _kw = v.trim()); _load(); },
                decoration: InputDecoration(
                  hintText: 'Rechercher (cage, foin, harnais…)',
                  hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade400, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () { _searchCtrl.clear(); setState(() => _kw = ''); _load(); },
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF1F3F2),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Stack(children: [
              IconButton.filledTonal(
                onPressed: _openFilters,
                icon: const Icon(Icons.tune, size: 20),
                style: IconButton.styleFrom(backgroundColor: _teal.withValues(alpha: 0.10), foregroundColor: _teal),
              ),
              if (_activeFilters > 0)
                Positioned(
                  right: 2, top: 2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: _orange, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text('$_activeFilters',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                  ),
                ),
            ]),
          ]),
        ),
        // ── Catégories ─────────────────────────────────────────────
        Container(
          color: Colors.white,
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            children: [
              _catChip('tous', 'Tout', '🔎'),
              for (final c in kAnnonceObjetCategories) _catChip(c.slug, c.label, c.emoji),
            ],
          ),
        ),
        // ── Barre localisation active ──────────────────────────────
        if (locLabel != null)
          Container(
            width: double.infinity,
            color: _teal.withValues(alpha: 0.06),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(children: [
              const Icon(Icons.place_outlined, size: 15, color: _teal),
              const SizedBox(width: 6),
              Expanded(child: Text('Localisation : $locLabel',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _teal, fontWeight: FontWeight.w600))),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _region = null; _departement = null;
                    _ville = ''; _cpFilter = ''; _communes = [];
                  });
                  _load();
                },
                child: const Icon(Icons.close, size: 16, color: _teal),
              ),
            ]),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _teal))
              : _rows.isEmpty
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('🔎', style: TextStyle(fontSize: 40)),
                        const SizedBox(height: 10),
                        Text(
                          _kw.isNotEmpty || _activeFilters > 0 || _cat != 'tous'
                              ? 'Aucune annonce ne correspond à votre recherche.'
                              : 'Aucune annonce pour le moment.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                        ),
                      ]),
                    ))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12,
                          childAspectRatio: 0.70,
                        ),
                        itemCount: _rows.length,
                        itemBuilder: (_, i) => _card(_rows[i]),
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _catChip(String slug, String label, String emoji) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text('$emoji $label'),
          selected: _cat == slug,
          onSelected: (_) { setState(() => _cat = slug); _load(); },
          selectedColor: _teal.withValues(alpha: 0.15),
          labelStyle: TextStyle(
              fontFamily: 'Galey', fontSize: 12,
              color: _cat == slug ? _teal : Colors.grey.shade700,
              fontWeight: FontWeight.w600),
        ),
      );

  Widget _card(Map<String, dynamic> r) {
    final photos = List<String>.from(r['photos'] ?? const []);
    final boosted = annonceObjetBoostActif(r['boost_until']);
    final loc = [r['ville'], r['departement']]
        .where((s) => (s ?? '').toString().isNotEmpty).join(', ');
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => AnnonceObjetDetailPage(data: r))),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: AspectRatio(
                aspectRatio: 1.1,
                child: photos.isNotEmpty
                    ? CachedNetworkImage(imageUrl: photos.first, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _ph())
                    : _ph(),
              ),
            ),
            if (boosted)
              Positioned(top: 6, left: 6, child: _tag('⚡ Boostée', _orange)),
            Positioned(
              bottom: 6, left: 6,
              child: _tag(annonceObjetCategorieEmoji(r['categorie'] as String?), Colors.black54),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((r['titre'] ?? '').toString(),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1F2A2E))),
              const SizedBox(height: 4),
              Text(annonceObjetPrixLabel(r),
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _teal)),
              if (loc.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('📍 $loc',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _ph() => Container(
        color: const Color(0xFFEEF3F0),
        child: const Center(child: Text('📦', style: TextStyle(fontSize: 34))),
      );

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: const TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class AnnonceObjetDetailPage extends StatefulWidget {
  final Map<String, dynamic> data;
  const AnnonceObjetDetailPage({super.key, required this.data});
  @override
  State<AnnonceObjetDetailPage> createState() => _AnnonceObjetDetailPageState();
}

class _AnnonceObjetDetailPageState extends State<AnnonceObjetDetailPage> {
  final _supa = Supabase.instance.client;
  int _photo = 0;
  bool _contacting = false;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get _isOwner {
    final d = widget.data;
    final pid = (d['profile_id'] ?? '').toString();
    return d['uid'] == _myUid &&
        (pid.isEmpty || User_Info.activeProfileId.isEmpty || pid == User_Info.activeProfileId);
  }

  @override
  void initState() {
    super.initState();
    final id = widget.data['id'];
    if (id != null && !_isOwner) {
      _supa.from('annonces_objets').select('vues').eq('id', id).maybeSingle().then((row) {
        if (row != null) {
          _supa.from('annonces_objets')
              .update({'vues': ((row['vues'] as int?) ?? 0) + 1}).eq('id', id);
        }
      }).catchError((_) {});
    }
  }

  Future<void> _contact() async {
    final d = widget.data;
    final ownerUid = d['uid'] as String?;
    if (ownerUid == null || ownerUid.isEmpty) return;
    if (_myUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Connectez-vous pour contacter le vendeur.', style: TextStyle(fontFamily: 'Galey'))));
      return;
    }
    setState(() => _contacting = true);
    _supa.from('annonces_objets').select('contacts').eq('id', d['id']).maybeSingle().then((row) {
      if (row != null) {
        _supa.from('annonces_objets')
            .update({'contacts': ((row['contacts'] as int?) ?? 0) + 1}).eq('id', d['id']);
      }
    }).catchError((_) {});
    try {
      final convId = await MessagingHelper.openOrCreateConversation(
        otherUid: ownerUid,
        categorie: 'annonces-materiel',
        myProfileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null,
      );
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatScreen(conversationId: convId, eleveurId: ownerUid),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _contacting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final photos = List<String>.from(d['photos'] ?? const []);
    final created = DateTime.tryParse(d['created_at']?.toString() ?? '');
    final loc = [d['ville'], d['code_postal'], d['departement'], d['region']]
        .where((s) => (s ?? '').toString().isNotEmpty).join(' · ');
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F4),
      appBar: AppBar(
        backgroundColor: _teal, foregroundColor: Colors.white,
        title: Text((d['titre'] ?? 'Annonce').toString(),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          if (_isOwner)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final ok = await Navigator.push(context, MaterialPageRoute(
                    builder: (_) => CreateAnnonceObjetPage(
                        annonceId: d['id'] as String?, initialData: d)));
                if (ok == true && mounted) Navigator.pop(context, true);
              },
            ),
        ],
      ),
      body: ListView(children: [
        if (photos.isNotEmpty)
          Column(children: [
            SizedBox(
              height: 280,
              child: PageView.builder(
                itemCount: photos.length,
                onPageChanged: (i) => setState(() => _photo = i),
                itemBuilder: (_, i) => CachedNetworkImage(
                    imageUrl: photos[i], fit: BoxFit.cover, width: double.infinity),
              ),
            ),
            if (photos.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < photos.length; i++)
                    Container(
                      width: i == _photo ? 16 : 6, height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == _photo ? _teal : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ]),
              ),
          ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              _chip('${annonceObjetCategorieEmoji(d['categorie'] as String?)} '
                  '${annonceObjetCategorieLabel(d['categorie'] as String?)}', _teal),
              _chip(kAnnonceObjetTransactions[d['type_transaction']] ?? 'Vente', _green),
              if (d['etat'] != null)
                _chip(kAnnonceObjetEtats[d['etat']] ?? d['etat'].toString(), Colors.blueGrey),
            ]),
            const SizedBox(height: 12),
            Text((d['titre'] ?? '').toString(),
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 20, color: Color(0xFF1F2A2E))),
            const SizedBox(height: 6),
            Text(annonceObjetPrixLabel(d),
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 18, color: _teal)),
            const SizedBox(height: 12),
            if ((d['description'] ?? '').toString().isNotEmpty)
              Text(d['description'].toString(),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.5, color: Color(0xFF2C3A40))),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.place_outlined, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Expanded(child: Text(loc,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600))),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.person_outline, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Text((d['nom_vendeur'] ?? 'Particulier').toString(),
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
              if (created != null) ...[
                const Spacer(),
                Text(DateFormat('dd/MM/yyyy').format(created),
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400)),
              ],
            ]),
            const SizedBox(height: 24),
            if (!_isOwner)
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton.icon(
                  onPressed: _contacting ? null : _contact,
                  icon: const Icon(Icons.chat_outlined, size: 18),
                  label: Text(_contacting ? 'Ouverture…' : 'Contacter le vendeur',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: c)),
      );
}
