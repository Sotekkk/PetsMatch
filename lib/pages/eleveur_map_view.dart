import 'package:PetsMatch/pages/main_feed.dart' show UserSelected;
import 'package:PetsMatch/pages/user_detail_page_feed.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ─── Couleurs markers par espèce ─────────────────────────────────────────────

double _markerHue(List<String> especes) {
  if (especes.isEmpty) return BitmapDescriptor.hueRose;
  if (especes.length > 1) {
    final set = especes.toSet();
    if (set.length == 2 && set.contains('chien') && set.contains('chat')) {
      return BitmapDescriptor.hueRose;
    }
    return BitmapDescriptor.hueRed;
  }
  return switch (especes.first) {
    'chien'  => BitmapDescriptor.hueAzure,
    'chat'   => BitmapDescriptor.hueOrange,
    'cheval' => BitmapDescriptor.hueGreen,
    'lapin'  => BitmapDescriptor.hueViolet,
    'oiseau' => BitmapDescriptor.hueCyan,
    'nac'    => BitmapDescriptor.hueYellow,
    'ovin'   => BitmapDescriptor.hueMagenta,
    'caprin' => BitmapDescriptor.hueMagenta,
    'porcin' => BitmapDescriptor.hueMagenta,
    _        => BitmapDescriptor.hueRose,
  };
}


List<String> _especesOf(Map<String, dynamic> data) {
  final ee = data['especesElevees'];
  if (ee is List && ee.isNotEmpty) {
    return ee.map((e) => (e as Map)['espece'] as String).toList();
  }
  final list = <String>[];
  if (data['isDog'] == true) list.add('chien');
  if (data['isCat'] == true) list.add('chat');
  return list;
}

// ─── Widget ───────────────────────────────────────────────────────────────────

class EleveurMapView extends StatefulWidget {
  final String espece;
  final String pays;
  final String region;
  final String departement;
  final String ville;
  final List<String> selectedBreeds;
  final String nameSearch;
  final int activeFilterCount;
  final VoidCallback onFilterTap;

  const EleveurMapView({
    super.key,
    required this.espece,
    required this.pays,
    required this.region,
    required this.departement,
    required this.ville,
    required this.selectedBreeds,
    required this.nameSearch,
    required this.activeFilterCount,
    required this.onFilterTap,
  });

  @override
  State<EleveurMapView> createState() => _EleveurMapViewState();
}

class _EleveurMapViewState extends State<EleveurMapView> {
  GoogleMapController? _mapController;
  final Map<MarkerId, Marker> _markers = {};
  List<Map<String, dynamic>> _eleveurs = [];
  bool _loading = true;
  bool _legendExpanded = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _loadEleveurs();
  }

  Future<void> _loadEleveurs() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('isElevage', isEqualTo: true)
        .where('isValidate', isEqualTo: true)
        .get();

    final result = <Map<String, dynamic>>[];

    for (final doc in snapshot.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['uid'] = doc.id;

      if (data['lat'] == null || data['lng'] == null) {
        final structured = [
          data['villeElevage'] ?? '',
          data['codePostalElevage'] ?? '',
          data['paysElevage'] ?? '',
        ].where((s) => (s as String).isNotEmpty).join(', ');

        final fallback = (data['adressElevage'] ?? '').toString().trim();
        final addressQuery = structured.isNotEmpty ? structured : fallback;

        if (addressQuery.isNotEmpty) {
          try {
            final locs = await locationFromAddress(addressQuery);
            if (locs.isNotEmpty) {
              data['lat'] = locs.first.latitude;
              data['lng'] = locs.first.longitude;
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(doc.id)
                  .update({'lat': data['lat'], 'lng': data['lng']});
            }
          } catch (_) {}
        }
      }

      if (data['lat'] != null && data['lng'] != null) result.add(data);
    }

    if (mounted) {
      setState(() {
        _eleveurs = result;
        _loading = false;
      });
      _updateMarkers();
    }
  }

  List<Map<String, dynamic>> get _filtered {
    return _eleveurs.where((data) {
      // Espèce
      if (widget.espece != 'tous') {
        final ee = data['especesElevees'];
        if (ee is List && ee.isNotEmpty) {
          if (!ee.any((e) => (e as Map)['espece'] == widget.espece)) return false;
        } else {
          if (widget.espece == 'chien' && data['isDog'] != true) return false;
          if (widget.espece == 'chat' && data['isCat'] != true) return false;
          if (widget.espece != 'chien' && widget.espece != 'chat') return false;
        }
      }
      // Races
      if (widget.selectedBreeds.isNotEmpty) {
        final ee = data['especesElevees'];
        final List<String> allRaces;
        if (ee is List) {
          allRaces = [for (final e in ee) ...List<String>.from((e as Map)['races'] ?? [])];
        } else {
          allRaces = [
            ...List<String>.from(data['dogBreeds'] ?? []),
            ...List<String>.from(data['catBreeds'] ?? []),
          ];
        }
        if (!widget.selectedBreeds.any((b) => allRaces.contains(b))) return false;
      }
      // Localisation
      if (widget.pays.isNotEmpty) {
        final s = ((data['paysElevage'] as String?) ?? '').toLowerCase();
        if (s.isNotEmpty && !s.contains(widget.pays.toLowerCase())) return false;
      }
      if (widget.region.isNotEmpty) {
        final s = ((data['regionElevage'] as String?) ?? '').toLowerCase();
        if (!s.contains(widget.region.toLowerCase())) return false;
      }
      if (widget.departement.isNotEmpty) {
        final s = ((data['departementElevage'] as String?) ?? '').toLowerCase();
        if (!s.contains(widget.departement.toLowerCase())) return false;
      }
      if (widget.ville.isNotEmpty) {
        final s = ((data['villeElevage'] as String?) ?? '').toLowerCase();
        if (!s.contains(widget.ville.toLowerCase())) return false;
      }
      // Texte
      if (widget.nameSearch.isNotEmpty) {
        final q    = widget.nameSearch.toLowerCase();
        final name = (data['nameElevage'] ?? '').toString().toLowerCase();
        final desc = (data['descEntreprise'] ?? '').toString().toLowerCase();
        if (!name.contains(q) && !desc.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  void _updateMarkers() {
    final newMarkers = <MarkerId, Marker>{};
    for (final data in _filtered) {
      final lat = (data['lat'] as num).toDouble();
      final lng = (data['lng'] as num).toDouble();
      final uid = data['uid'] as String;
      final id  = MarkerId(uid);
      final hue = _markerHue(_especesOf(data));

      newMarkers[id] = Marker(
        markerId: id,
        position: LatLng(lat, lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        onTap: () => _openProfile(data),
      );
    }
    setState(() {
      _markers
        ..clear()
        ..addAll(newMarkers);
    });
  }

  void _openProfile(Map<String, dynamic> data) {
    final user = UserSelected.fromMap(data, data['uid'] as String);
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => UserDetailPageFeed(user: user)));
  }

  Future<void> _recenterMap() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(target: LatLng(pos.latitude, pos.longitude), zoom: 12)));
    } catch (_) {
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  void didUpdateWidget(EleveurMapView old) {
    super.didUpdateWidget(old);
    if (old.espece != widget.espece ||
        old.pays != widget.pays ||
        old.region != widget.region ||
        old.departement != widget.departement ||
        old.ville != widget.ville ||
        old.nameSearch != widget.nameSearch ||
        old.selectedBreeds.join() != widget.selectedBreeds.join()) {
      _updateMarkers();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(color: Color(0xFFA7C79A)),
          SizedBox(height: 12),
          Text('Géolocalisation des élevages...',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
        ]),
      );
    }

    return Stack(children: [
      GoogleMap(
        initialCameraPosition: const CameraPosition(
            target: LatLng(46.603354, 1.888334), zoom: 5.5),
        markers: Set<Marker>.of(_markers.values),
        onMapCreated: (c) => _mapController = c,
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
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]),
          child: Text('${_filtered.length} élevage(s)',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ),
      ),

      // Bouton filtres (remplace l'ancien bouton races-only)
      Positioned(
        top: 12, right: 12,
        child: GestureDetector(
          onTap: widget.onFilterTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: widget.activeFilterCount > 0
                  ? const Color(0xFF0C5C6C)
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.tune, size: 16,
                  color: widget.activeFilterCount > 0 ? Colors.white : Colors.black87),
              const SizedBox(width: 6),
              Text(
                widget.activeFilterCount > 0
                    ? '${widget.activeFilterCount} filtre(s)'
                    : 'Filtres',
                style: TextStyle(
                    fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w500,
                    color: widget.activeFilterCount > 0 ? Colors.white : Colors.black87),
              ),
            ]),
          ),
        ),
      ),

      // Bouton GPS
      Positioned(
        bottom: 110, right: 12,
        child: FloatingActionButton.small(
          heroTag: 'eleveur_map_gps',
          backgroundColor: Colors.white,
          onPressed: _locating ? null : _recenterMap,
          child: _locating
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0C5C6C)))
              : const Icon(Icons.my_location, color: Color(0xFF0C5C6C), size: 20),
        ),
      ),

      // Légende collapsible
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
                    _LegendItem(color: const Color(0xFF4285F4), label: '🐶 Chien'),
                    const SizedBox(height: 3),
                    _LegendItem(color: const Color(0xFFFF6D00), label: '🐱 Chat'),
                    const SizedBox(height: 3),
                    _LegendItem(color: const Color(0xFF4CAF50), label: '🐴 Cheval'),
                    const SizedBox(height: 3),
                    _LegendItem(color: const Color(0xFF9C27B0), label: '🐰 Lapin'),
                    const SizedBox(height: 3),
                    _LegendItem(color: const Color(0xFF00BCD4), label: '🐦 Oiseau'),
                    const SizedBox(height: 3),
                    _LegendItem(color: const Color(0xFFFDD835), label: '🦔 NAC'),
                    const SizedBox(height: 3),
                    _LegendItem(color: const Color(0xFFE91E63), label: '🐑 Élevage'),
                    const SizedBox(height: 3),
                    _LegendItem(color: const Color(0xFFFF4081), label: '🐶🐱 Chien+Chat'),
                    const SizedBox(height: 3),
                    _LegendItem(color: const Color(0xFFF44336), label: '🔀 Multi-espèce'),
                  ])
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.legend_toggle, size: 16, color: Color(0xFF0C5C6C)),
                    const SizedBox(width: 5),
                    // Petits points couleurs
                    ...[
                      const Color(0xFF4285F4),
                      const Color(0xFFFF6D00),
                      const Color(0xFF4CAF50),
                      const Color(0xFF9C27B0),
                      const Color(0xFF00BCD4),
                    ].map((c) => Container(
                      width: 8, height: 8, margin: const EdgeInsets.only(left: 3),
                      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                    )),
                    const SizedBox(width: 2),
                    Text('...', style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade500,
                        fontFamily: 'Galey')),
                  ]),
          ),
        ),
      ),
    ]);
  }
}

// ─── Légende ─────────────────────────────────────────────────────────────────

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.location_on, color: color, size: 14),
      const SizedBox(width: 4),
      Text(label,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 10)),
    ]);
  }
}

