import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/nature/natural_place_detail_page.dart';
import 'package:PetsMatch/pages/nature/add_natural_place_page.dart';

// ─── Constantes ───────────────────────────────────────────────────────────────

const _teal = Color(0xFF0C5C6C);
const _darkC = Color(0xFF071C22);
const _bgGrad = LinearGradient(
  begin: Alignment.topCenter, end: Alignment.bottomCenter,
  colors: [Color(0xFF071C22), Color(0xFF0C3535), Color(0xFF0C3520)],
  stops: [0.0, 0.5, 1.0],
);

const _catEmoji = {
  'foret':   '🌲',
  'plage':   '🏖️',
  'parc':    '🌿',
  'lac':     '💧',
  'riviere': '🏞️',
};

const _catLabel = {
  'foret':   'Forêt',
  'plage':   'Plage',
  'parc':    'Parc',
  'lac':     'Lac',
  'riviere': 'Rivière',
};

const _catColor = {
  'foret':   Color(0xFF2E7D32),
  'plage':   Color(0xFF1565C0),
  'parc':    Color(0xFF558B2F),
  'lac':     Color(0xFF00838F),
  'riviere': Color(0xFF0277BD),
};

const _catGradient = {
  'foret': [Color(0xFF1B5E20), Color(0xFF388E3C)],
  'plage': [Color(0xFF0D47A1), Color(0xFF0288D1)],
  'parc':  [Color(0xFF33691E), Color(0xFF7CB342)],
  'lac':   [Color(0xFF006064), Color(0xFF00ACC1)],
  'riviere':[Color(0xFF01579B), Color(0xFF039BE5)],
};

double _markerHue(String cat) => switch (cat) {
  'foret'   => BitmapDescriptor.hueGreen,
  'plage'   => BitmapDescriptor.hueBlue,
  'parc'    => BitmapDescriptor.hueCyan,
  'lac'     => BitmapDescriptor.hueAzure,
  'riviere' => BitmapDescriptor.hueAzure,
  _         => BitmapDescriptor.hueGreen,
};

// ─── Page principale ──────────────────────────────────────────────────────────

class NaturalPlacesPage extends StatefulWidget {
  const NaturalPlacesPage({super.key});

  @override
  State<NaturalPlacesPage> createState() => _NaturalPlacesPageState();
}

class _NaturalPlacesPageState extends State<NaturalPlacesPage> {
  final _supa = Supabase.instance.client;

  List<Map<String, dynamic>> _places    = [];
  bool _loading     = true;
  bool _mapView     = false;
  String _catFilter = 'tous';
  bool _alerteEauOnly = false;
  String _search    = '';
  Position? _userPos;
  bool _nearMe      = false;   // filtre « autour de moi »
  double _rayonKm   = 20;      // rayon modifiable (km)
  bool _locatingNearMe = false;

  final _searchCtrl  = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _fetchUserPosition();
    await _loadPlaces();
  }

  Future<void> _fetchUserPosition() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (mounted) setState(() => _userPos = pos);
    } catch (_) {}
  }

  Future<void> _loadPlaces() async {
    setState(() => _loading = true);
    try {
      final uid = User_Info.uid;
      const pageSize = 1000;
      final all = <Map<String, dynamic>>[];
      int from = 0;
      while (true) {
        final query = _supa.from('natural_places').select();
        final filtered = uid.isNotEmpty
            ? query.or('statut.eq.valide,submitted_by_uid.eq.$uid')
            : query.eq('statut', 'valide');
        final page = await filtered.order('nom').range(from, from + pageSize - 1);
        final pageList = List<Map<String, dynamic>>.from(page as List);
        all.addAll(pageList);
        if (pageList.length < pageSize) break;
        from += pageSize;
      }
      if (mounted) {
        setState(() {
          _places = all;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[NaturalPlaces] load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _places;
    if (_catFilter != 'tous') {
      list = list.where((p) => p['categorie'] == _catFilter).toList();
    }
    if (_alerteEauOnly) {
      list = list.where((p) => p['alerte_cyano'] == true).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((p) => (p['nom'] as String? ?? '').toLowerCase().contains(q)).toList();
    }
    if (_userPos != null) {
      list = List.from(list);
      if (_nearMe) {
        list = list.where((p) {
          final lat = (p['lat'] as num?)?.toDouble();
          final lng = (p['lng'] as num?)?.toDouble();
          if (lat == null || lng == null) return false;
          return _distKm(p) <= _rayonKm;
        }).toList();
      }
      list.sort((a, b) {
        final da = _distKm(a);
        final db = _distKm(b);
        return da.compareTo(db);
      });
    }
    return list;
  }

  Future<void> _toggleNearMe() async {
    if (_nearMe) { setState(() => _nearMe = false); return; }
    // On (re)prend la position GPS courante à chaque activation — utile si on
    // s'est déplacé depuis l'ouverture (vacances, etc.).
    setState(() => _locatingNearMe = true);
    await _fetchUserPosition();
    if (mounted) setState(() => _locatingNearMe = false);
    if (_userPos == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Localisation indisponible — autorisez l\'accès à votre position.'),
        ));
      }
      return;
    }
    setState(() => _nearMe = true);
  }

  void _openRayonSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.my_location, size: 18, color: _teal),
              const SizedBox(width: 8),
              const Text('Rayon autour de moi',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 15, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${_rayonKm.toInt()} km',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 15,
                      fontWeight: FontWeight.w700, color: _teal)),
            ]),
            const SizedBox(height: 4),
            Slider(
              value: _rayonKm.clamp(2, 100),
              min: 2, max: 100, divisions: 49,
              activeColor: _teal,
              label: '${_rayonKm.toInt()} km',
              onChanged: (v) {
                setSheet(() => _rayonKm = v);
                setState(() {
                  _rayonKm = v;
                  if (!_nearMe && _userPos != null) _nearMe = true;
                });
              },
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
              Text('2 km', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
              Text('100 km', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
            ]),
          ]),
        ),
      ),
    );
  }

  double _distKm(Map<String, dynamic> p) {
    final pos = _userPos;
    if (pos == null) return 0;
    final lat = (p['lat'] as num?)?.toDouble() ?? 0;
    final lng = (p['lng'] as num?)?.toDouble() ?? 0;
    return Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng) / 1000;
  }

  String _distLabel(Map<String, dynamic> p) {
    final d = _distKm(p);
    if (d < 1) return '< 1 km';
    if (d < 10) return '${d.toStringAsFixed(1)} km';
    return '${d.toInt()} km';
  }

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.isFirst == false;
    return Scaffold(
      backgroundColor: _darkC,
      floatingActionButton: User_Info.uid.isEmpty ? null : FloatingActionButton.extended(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Proposer un lieu', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
        onPressed: () async {
          final added = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const AddNaturalPlacePage()));
          if (added == true) _loadPlaces();
        },
      ),
      body: Stack(children: [
        Positioned.fill(child: Container(decoration: const BoxDecoration(gradient: _bgGrad))),
        SafeArea(child: Column(children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              if (canPop) ...[
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
              ],
              const Expanded(
                child: Text('Lieux Naturels',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 24, color: Colors.white)),
              ),
              GestureDetector(
                onTap: () => setState(() => _mapView = !_mapView),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: Icon(_mapView ? Icons.list_outlined : Icons.map_outlined, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          // ── Recherche ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: _SearchBar(controller: _searchCtrl, onChanged: (v) => setState(() => _search = v)),
          ),
          // ── Filtres catégorie ──
          SizedBox(
            height: 44,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                _CatChip(value: 'tous', label: 'Tous', active: _catFilter == 'tous',
                    onTap: () => setState(() => _catFilter = 'tous')),
                ..._catLabel.entries.map((e) => _CatChip(
                  value: e.key,
                  label: '${_catEmoji[e.key]} ${e.value}',
                  active: _catFilter == e.key,
                  color: _catColor[e.key],
                  onTap: () => setState(() => _catFilter = e.key),
                )),
                _CatChip(
                  value: '_eau', label: '⚠️ Alertes eau',
                  active: _alerteEauOnly, color: const Color(0xFFF59E0B),
                  onTap: () => setState(() => _alerteEauOnly = !_alerteEauOnly),
                ),
              ]),
            ),
          ),
          // ── Barre "Autour de moi" ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Row(children: [
              GestureDetector(
                onTap: _locatingNearMe ? null : _toggleNearMe,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: _nearMe ? const LinearGradient(colors: [_teal, Color(0xFF1E7A8C)]) : null,
                        color: _nearMe ? null : Colors.white.withValues(alpha: 0.10),
                        border: Border.all(color: _nearMe ? Colors.transparent : Colors.white.withValues(alpha: 0.20)),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: _nearMe ? [BoxShadow(color: _teal.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 3))] : null,
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (_locatingNearMe)
                          const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        else
                          const Icon(Icons.my_location, size: 14, color: Colors.white),
                        const SizedBox(width: 5),
                        const Text('Autour de moi', style: TextStyle(
                            fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                            color: Colors.white)),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _openRayonSheet,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('${_rayonKm.toInt()} km', style: const TextStyle(
                            fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                        const Icon(Icons.expand_more, size: 15, color: Colors.white),
                      ]),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (_nearMe && _userPos != null)
                Text('${_filtered.length} lieu(x)', style: TextStyle(
                    fontFamily: 'Galey', fontSize: 11, color: Colors.white.withValues(alpha: 0.6))),
            ]),
          ),
          // ── Contenu ──
          Expanded(
            child: _mapView
                ? _NaturalMapView(places: _filtered, userPos: _userPos, nearMe: _nearMe, rayonKm: _rayonKm, onTapPlace: _openDetail)
                : _buildListView(),
          ),
        ])),
      ]),
    );
  }

  Widget _buildListView() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _teal));
    }

    final filtered = _filtered;

    if (filtered.isEmpty) {
      return const _EmptyState();
    }

    return RefreshIndicator(
      color: _teal,
      onRefresh: _loadPlaces,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: filtered.length,
        itemBuilder: (_, i) => _PlaceCard(
          place: filtered[i],
          distLabel: _userPos != null ? _distLabel(filtered[i]) : null,
          onTap: () => _openDetail(filtered[i]),
        ),
      ),
    );
  }

  void _openDetail(Map<String, dynamic> place) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NaturalPlaceDetailPage(place: place)),
    ).then((_) => _loadPlaces());
  }
}

// ─── Vue carte ────────────────────────────────────────────────────────────────

class _NaturalMapView extends StatefulWidget {
  final List<Map<String, dynamic>> places;
  final Position? userPos;
  final bool nearMe;
  final double rayonKm;
  final void Function(Map<String, dynamic>) onTapPlace;

  const _NaturalMapView({
    required this.places,
    required this.userPos,
    required this.onTapPlace,
    this.nearMe = false,
    this.rayonKm = 20,
  });

  @override
  State<_NaturalMapView> createState() => _NaturalMapViewState();
}

class _NaturalMapViewState extends State<_NaturalMapView> {
  GoogleMapController? _mapController;
  final Map<MarkerId, Marker> _markers = {};
  bool _legendExpanded = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _buildMarkers();
  }

  @override
  void didUpdateWidget(_NaturalMapView old) {
    super.didUpdateWidget(old);
    if (old.places.length != widget.places.length) _buildMarkers();
    // Recentre sur la zone quand on active « autour de moi » ou change le rayon.
    final u = widget.userPos;
    if (u != null && widget.nearMe &&
        (!old.nearMe || old.rayonKm != widget.rayonKm)) {
      final zoom = _zoomForRadiusKm(widget.rayonKm);
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(u.latitude, u.longitude), zoom: zoom),
      ));
    }
  }

  // Zoom approximatif pour qu'un cercle de r km tienne à l'écran.
  double _zoomForRadiusKm(double r) {
    if (r <= 5) return 12;
    if (r <= 10) return 11;
    if (r <= 20) return 10;
    if (r <= 40) return 9;
    if (r <= 70) return 8.2;
    return 7.5;
  }

  void _buildMarkers() {
    final m = <MarkerId, Marker>{};
    for (final p in widget.places) {
      final cyano = p['alerte_cyano'] == true;
      // Alerte cyano : marqueur au point de la zone d'eau si renseigné.
      final lat = ((cyano ? p['alerte_cyano_lat'] : null) as num?)?.toDouble()
          ?? (p['lat'] as num?)?.toDouble();
      final lng = ((cyano ? p['alerte_cyano_lng'] : null) as num?)?.toDouble()
          ?? (p['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final id  = MarkerId(p['id']?.toString() ?? '${lat}_$lng');
      final cat = p['categorie'] as String? ?? '';
      final confirme = (p['alerte_cyano_statut'] as String?) == 'confirme';
      final hue = cyano
          ? (confirme ? BitmapDescriptor.hueRed : BitmapDescriptor.hueOrange)
          : _markerHue(cat);
      m[id] = Marker(
        markerId: id,
        position: LatLng(lat, lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        infoWindow: InfoWindow(
          title: p['nom'] as String? ?? '',
          snippet: cyano
              ? '⚠️ Cyanobactéries — ${confirme ? 'confirmé' : 'suspecté'}'
              : '${_catEmoji[cat] ?? ''} ${_catLabel[cat] ?? cat}',
          onTap: () => widget.onTapPlace(p),
        ),
      );
    }
    setState(() {
      _markers.clear();
      _markers.addAll(m);
    });
  }

  Future<void> _recenterMap() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(pos.latitude, pos.longitude), zoom: 11),
      ));
    } catch (_) {
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialTarget = widget.userPos != null
        ? LatLng(widget.userPos!.latitude, widget.userPos!.longitude)
        : const LatLng(46.603354, 1.888334);

    return Stack(children: [
      GoogleMap(
        initialCameraPosition: CameraPosition(
          target: initialTarget,
          zoom: widget.userPos != null ? 10.5 : 5.5,
        ),
        markers: Set<Marker>.of(_markers.values),
        circles: (widget.nearMe && widget.userPos != null)
            ? {
                Circle(
                  circleId: const CircleId('rayon'),
                  center: LatLng(widget.userPos!.latitude, widget.userPos!.longitude),
                  radius: widget.rayonKm * 1000,
                  fillColor: _teal.withValues(alpha: 0.08),
                  strokeColor: _teal.withValues(alpha: 0.5),
                  strokeWidth: 2,
                ),
              }
            : const <Circle>{},
        onMapCreated: (c) => _mapController = c,
        myLocationEnabled: widget.userPos != null,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: true,
      ),

      // Compteur
      Positioned(
        top: 12, left: 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
          ),
          child: Text('${widget.places.length} lieu(x)',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ),
      ),

      // GPS
      Positioned(
        bottom: 110, right: 12,
        child: FloatingActionButton.small(
          heroTag: 'nature_map_gps',
          backgroundColor: Colors.white,
          onPressed: _locating ? null : _recenterMap,
          child: _locating
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _teal))
              : const Icon(Icons.my_location, color: _teal, size: 20),
        ),
      ),

      // Légende
      Positioned(
        bottom: 110, left: 12,
        child: GestureDetector(
          onTap: () => setState(() => _legendExpanded = !_legendExpanded),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            padding: _legendExpanded
                ? const EdgeInsets.fromLTRB(10, 8, 10, 8)
                : const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: _legendExpanded
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Légende', style: TextStyle(
                          fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 20),
                      Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.grey.shade500),
                    ]),
                    const SizedBox(height: 6),
                    _LegendItem(color: _catColor['foret']!,   label: '🌲 Forêt'),
                    const SizedBox(height: 3),
                    _LegendItem(color: _catColor['plage']!,   label: '🏖️ Plage'),
                    const SizedBox(height: 3),
                    _LegendItem(color: _catColor['parc']!,    label: '🌿 Parc'),
                    const SizedBox(height: 3),
                    _LegendItem(color: _catColor['lac']!,     label: '💧 Lac'),
                    const SizedBox(height: 3),
                    _LegendItem(color: _catColor['riviere']!, label: '🏞️ Rivière'),
                  ])
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.legend_toggle, size: 16, color: _teal),
                    const SizedBox(width: 5),
                    ...[
                      _catColor['foret']!,
                      _catColor['plage']!,
                      _catColor['parc']!,
                      _catColor['lac']!,
                      _catColor['riviere']!,
                    ].map((c) => Container(
                      width: 8, height: 8, margin: const EdgeInsets.only(left: 3),
                      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                    )),
                  ]),
          ),
        ),
      ),
    ]);
  }
}

// ─── Carrousel photos (carte liste) ──────────────────────────────────────────

class _CardPhotoCarousel extends StatefulWidget {
  final List<String> photos;
  final String fallbackEmoji;
  const _CardPhotoCarousel({required this.photos, required this.fallbackEmoji});

  @override
  State<_CardPhotoCarousel> createState() => _CardPhotoCarouselState();
}

class _CardPhotoCarouselState extends State<_CardPhotoCarousel> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photos.length == 1) {
      return CachedNetworkImage(
        imageUrl: widget.photos.first,
        fit: BoxFit.cover,
        placeholder: (_, __) => Center(child: Text(widget.fallbackEmoji, style: const TextStyle(fontSize: 56))),
        errorWidget: (_, __, ___) => Center(child: Text(widget.fallbackEmoji, style: const TextStyle(fontSize: 56))),
      );
    }
    return Stack(children: [
      PageView.builder(
        controller: _controller,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => CachedNetworkImage(
          imageUrl: widget.photos[i],
          fit: BoxFit.cover,
          placeholder: (_, __) => Center(child: Text(widget.fallbackEmoji, style: const TextStyle(fontSize: 56))),
          errorWidget: (_, __, ___) => Center(child: Text(widget.fallbackEmoji, style: const TextStyle(fontSize: 56))),
        ),
      ),
      Positioned(
        bottom: 8, left: 0, right: 0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.photos.length, (i) => Container(
            width: 5, height: 5,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: i == _index ? 0.95 : 0.45),
            ),
          )),
        ),
      ),
    ]);
  }
}

// ─── Card lieu ────────────────────────────────────────────────────────────────

class _PlaceCard extends StatelessWidget {
  final Map<String, dynamic> place;
  final String? distLabel;
  final VoidCallback onTap;

  const _PlaceCard({required this.place, required this.onTap, this.distLabel});

  @override
  Widget build(BuildContext context) {
    final nom   = place['nom'] as String? ?? '';
    final cat   = place['categorie'] as String? ?? '';
    final color = _catColor[cat] ?? _teal;
    final cyano = place['alerte_cyano'] == true;
    final enAttente = place['statut'] == 'en_attente';
    final refuse    = place['statut'] == 'refuse';
    final nbAvis  = place['nb_avis'] as int? ?? 0;
    final noteMoy = (place['note_moyenne'] as num? ?? 0).toStringAsFixed(1);
    final gradColors = _catGradient[cat] ?? [_teal, const Color(0xFF4CAF50)];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 14, offset: const Offset(0, 4)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Photo + overlays ────────────────────────────────────────────
            SizedBox(
              height: 190,
              width: double.infinity,
              child: Stack(fit: StackFit.expand, children: [

                // Fond dégradé catégorie
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradColors,
                    ),
                  ),
                ),

                // Photos (carrousel si plusieurs), sinon emoji centré
                Builder(builder: (_) {
                  final photos = <String>[
                    ...List<String>.from((place['photos'] as List?) ?? const []),
                  ];
                  final photoUrl = place['photo_url'] as String?;
                  if (photoUrl != null && photoUrl.isNotEmpty && !photos.contains(photoUrl)) {
                    photos.insert(0, photoUrl);
                  }
                  if (photos.isEmpty) {
                    return Center(
                      child: Text(_catEmoji[cat] ?? '🌿', style: const TextStyle(fontSize: 56)),
                    );
                  }
                  return _CardPhotoCarousel(photos: photos, fallbackEmoji: _catEmoji[cat] ?? '🌿');
                }),

                // Gradient bas → nom
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.45, 1.0],
                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)],
                      ),
                    ),
                  ),
                ),

                // Badge catégorie — haut gauche
                Positioned(
                  top: 12, left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_catEmoji[cat] ?? ''} ${_catLabel[cat] ?? cat}',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                          fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),

                // Alerte cyano — haut droit
                if (cyano)
                  Positioned(
                    top: 12, right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: (place['alerte_cyano_statut'] as String?) == 'confirme'
                            ? Colors.red.shade700
                            : const Color(0xFFF59E0B),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                          (place['alerte_cyano_statut'] as String?) == 'confirme'
                              ? '⚠️ Cyano confirmé'
                              : '⚠️ Cyano suspecté',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                              fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),

                // Statut modération (mes propositions) — haut droit
                if (enAttente || refuse)
                  Positioned(
                    top: 12, right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: enAttente ? Colors.orange.shade700 : Colors.grey.shade700,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(enAttente ? '⏳ En attente' : '✕ Refusé',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                              fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),

                // Nom + distance — bas
                Positioned(
                  bottom: 12, left: 14, right: 14,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(nom,
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: 'Galey', fontSize: 17,
                                fontWeight: FontWeight.w800, color: Colors.white,
                                shadows: [Shadow(color: Colors.black45, blurRadius: 4)])),
                      ),
                      if (distLabel != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.near_me_outlined, size: 11, color: Colors.white70),
                            const SizedBox(width: 3),
                            Text(distLabel!,
                                style: const TextStyle(fontFamily: 'Galey',
                                    fontSize: 11, color: Colors.white)),
                          ]),
                        ),
                      ],
                    ],
                  ),
                ),
              ]),
            ),

            // ── Infos bas de carte ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Row(children: [
                // Note
                if (nbAvis > 0) ...[
                  const Icon(Icons.star_rounded, size: 15, color: Color(0xFFFDD835)),
                  const SizedBox(width: 3),
                  Text('$noteMoy  ($nbAvis avis)',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                          fontWeight: FontWeight.w600, color: Colors.black87)),
                  const SizedBox(width: 10),
                ],
                // Amenities icônes mini
                ..._amenityIcons(place).map((ic) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(ic, size: 15, color: Colors.grey.shade500),
                )),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey.shade400),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  List<IconData> _amenityIcons(Map<String, dynamic> p) {
    final icons = <IconData>[];
    if (p['has_parking']      == true) icons.add(Icons.local_parking_outlined);
    if (p['has_eau']          == true) icons.add(Icons.water_drop_outlined);
    if (p['has_fontaine']     == true) icons.add(Icons.local_drink_outlined);
    if (p['parcours_ombre']   == true) icons.add(Icons.wb_shade);
    if (p['baignade_possible']== true) icons.add(Icons.pool_outlined);
    if (p['has_poubelle']     == true) icons.add(Icons.delete_outline);
    return icons.take(4).toList();
  }
}


// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.forest_outlined, size: 72, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        const Text('Aucun lieu naturel disponible',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Galey', fontSize: 16,
                fontWeight: FontWeight.w600, color: Colors.black54)),
        const SizedBox(height: 8),
        const Text('Les lieux naturels pet-friendly seront bientôt disponibles près de chez vous.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
      ]),
    ),
  );
}

// ─── Widgets utilitaires ──────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Rechercher un lieu...',
            hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white.withValues(alpha: 0.4)),
            prefixIcon: Icon(Icons.search, color: Colors.white.withValues(alpha: 0.6), size: 20),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.6), size: 18),
                    onPressed: () { controller.clear(); onChanged(''); })
                : null,
            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
    ),
  );
}

class _CatChip extends StatelessWidget {
  final String value, label;
  final bool active;
  final Color? color;
  final VoidCallback onTap;
  const _CatChip({
    required this.value, required this.label, required this.active,
    required this.onTap, this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? _teal;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              gradient: active ? LinearGradient(colors: [c, c.withValues(alpha: 0.7)]) : null,
              color: active ? null : Colors.white.withValues(alpha: 0.10),
              border: Border.all(color: active ? Colors.transparent : Colors.white.withValues(alpha: 0.20)),
              borderRadius: BorderRadius.circular(22),
              boxShadow: active ? [BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 3))] : null,
            ),
            child: Text(label, style: const TextStyle(
                fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                color: Colors.white)),
          ),
        ),
      ),
    );
  }
}


class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.location_on, color: color, size: 14),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 10)),
  ]);
}
