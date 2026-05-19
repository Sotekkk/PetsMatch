import 'dart:convert';
import 'package:PetsMatch/pages/main_feed.dart' show UserSelected;
import 'package:PetsMatch/pages/user_detail_page_feed.dart';
import 'package:PetsMatch/utils/french_geo.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class EleveurMapView extends StatefulWidget {
  final String speciesFilter;
  final String nameSearch;
  final String locationSearch;

  const EleveurMapView({
    super.key,
    required this.speciesFilter,
    required this.nameSearch,
    required this.locationSearch,
  });

  @override
  State<EleveurMapView> createState() => _EleveurMapViewState();
}

class _EleveurMapViewState extends State<EleveurMapView> {
  GoogleMapController? _mapController;
  final Map<MarkerId, Marker> _markers = {};
  List<Map<String, dynamic>> _eleveurs = [];
  bool _loading = true;

  List<String> _allDogBreeds = [];
  List<String> _allCatBreeds = [];
  List<String> _selectedBreeds = [];

  @override
  void initState() {
    super.initState();
    _loadBreeds();
    _loadEleveurs();
  }

  Future<void> _loadBreeds() async {
    final dogJson = await rootBundle.loadString('assets/dog_breeds.json');
    final catJson = await rootBundle.loadString('assets/cat_breeds.json');
    setState(() {
      _allDogBreeds = List<String>.from(jsonDecode(dogJson));
      _allCatBreeds = List<String>.from(jsonDecode(catJson));
    });
  }

  Future<void> _loadEleveurs() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('isElevage', isEqualTo: true)
        .where('isValidate', isEqualTo: true)
        .get();

    final List<Map<String, dynamic>> result = [];

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

      if (data['lat'] != null && data['lng'] != null) {
        result.add(data);
      }
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
      if (widget.speciesFilter == 'chien' && data['isDog'] != true) return false;
      if (widget.speciesFilter == 'chat' && data['isCat'] != true) return false;

      if (_selectedBreeds.isNotEmpty) {
        final all = [
          ...List<String>.from(data['dogBreeds'] ?? []),
          ...List<String>.from(data['catBreeds'] ?? []),
        ];
        if (!_selectedBreeds.any((b) => all.contains(b))) return false;
      }

      if (widget.nameSearch.isNotEmpty) {
        final name = (data['nameElevage'] ?? '').toString().toLowerCase();
        final desc = (data['descEntreprise'] ?? '').toString().toLowerCase();
        if (!name.contains(widget.nameSearch) && !desc.contains(widget.nameSearch)) {
          return false;
        }
      }

      if (widget.locationSearch.isNotEmpty) {
        final q = widget.locationSearch.toLowerCase();
        final ville = (data['villeElevage'] ?? '').toString().toLowerCase();
        final cp = (data['codePostalElevage'] ?? '').toString().toLowerCase();
        if (!ville.contains(q) && !cp.contains(q)) return false;
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
      final id = MarkerId(uid);

      final isDog = data['isDog'] == true;
      final isCat = data['isCat'] == true;

      final hue = (isDog && isCat)
          ? BitmapDescriptor.hueRose
          : isDog
              ? BitmapDescriptor.hueAzure
              : isCat
                  ? BitmapDescriptor.hueOrange
                  : BitmapDescriptor.hueRose;

      newMarkers[id] = Marker(
        markerId: id,
        position: LatLng(lat, lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        onTap: () => _showSheet(data),
      );
    }
    setState(() {
      _markers
        ..clear()
        ..addAll(newMarkers);
    });
  }

  void _showSheet(Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EleveurSheet(data: data, uid: data['uid'] as String),
    );
  }

  List<String> get _breedsForFilter {
    if (widget.speciesFilter == 'chien') return _allDogBreeds;
    if (widget.speciesFilter == 'chat') return _allCatBreeds;
    return [..._allDogBreeds, ..._allCatBreeds];
  }

  @override
  void didUpdateWidget(EleveurMapView old) {
    super.didUpdateWidget(old);
    if (old.speciesFilter != widget.speciesFilter ||
        old.nameSearch != widget.nameSearch ||
        old.locationSearch != widget.locationSearch) {
      _updateMarkers();
    }
  }

  Future<void> _openBreedFilter() async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _BreedFilterSheet(
        allBreeds: _breedsForFilter,
        selected: List<String>.from(_selectedBreeds),
      ),
    );
    if (result != null) {
      setState(() => _selectedBreeds = result);
      _updateMarkers();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
                color: Color.fromARGB(255, 250, 192, 187)),
            SizedBox(height: 12),
            Text(
              'Géolocalisation des élevages...',
              style: TextStyle(
                  fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: const CameraPosition(
            target: LatLng(46.603354, 1.888334),
            zoom: 5.5,
          ),
          markers: Set<Marker>.of(_markers.values),
          onMapCreated: (c) => _mapController = c,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: true,
        ),

        // Compteur
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 4)
              ],
            ),
            child: Text(
              '${_filtered.length} élevage(s)',
              style: const TextStyle(
                  fontFamily: 'Galey',
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ),

        // Bouton filtre races
        Positioned(
          top: 12,
          right: 12,
          child: GestureDetector(
            onTap: _openBreedFilter,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _selectedBreeds.isEmpty
                    ? Colors.white
                    : const Color.fromARGB(255, 250, 192, 187),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 4)
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.tune, size: 16, color: Colors.black87),
                  const SizedBox(width: 6),
                  Text(
                    _selectedBreeds.isEmpty
                        ? 'Races'
                        : '${_selectedBreeds.length} race(s)',
                    style: const TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Légende
        Positioned(
          bottom: 110,
          left: 12,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 4)
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LegendItem(
                    color: const Color(0xFF4285F4), label: '🐶 Chien'),
                const SizedBox(height: 4),
                _LegendItem(
                    color: const Color(0xFFFF6D00), label: '🐱 Chat'),
                const SizedBox(height: 4),
                _LegendItem(
                    color: const Color(0xFFE91E63), label: '🐶🐱 Les deux'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_on, color: color, size: 16),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 11)),
      ],
    );
  }
}

class _EleveurSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  final String uid;

  const _EleveurSheet({required this.data, required this.uid});

  @override
  Widget build(BuildContext context) {
    final name = data['nameElevage'] ?? 'Élevage';
    final desc = data['descEntreprise'] ?? '';
    final ppUrl = data['profilePictureUrlElevage'] ?? '';
    final isDog = data['isDog'] == true;
    final isCat = data['isCat'] == true;
    final dogBreeds = List<String>.from(data['dogBreeds'] ?? []);
    final catBreeds = List<String>.from(data['catBreeds'] ?? []);

    final location = FrenchGeo.formatLocation(data).isNotEmpty
        ? FrenchGeo.formatLocation(data)
        : (data['adressElevage'] ?? '').toString().trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (ppUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    ppUrl,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const _PlaceholderAvatar(),
                  ),
                )
              else
                const _PlaceholderAvatar(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF2E7D32).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified,
                                  color: Color(0xFF2E7D32), size: 11),
                              SizedBox(width: 3),
                              Text('PRO Vérifié',
                                  style: TextStyle(
                                      color: Color(0xFF2E7D32),
                                      fontFamily: 'Galey',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              size: 12, color: Colors.grey),
                          const SizedBox(width: 3),
                          Text(location,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          if (isDog || isCat) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (isDog) _Tag(label: '🐶 Chien'),
                if (isCat) _Tag(label: '🐱 Chat'),
                ...dogBreeds.take(2).map((r) => _Tag(label: r, subtle: true)),
                ...catBreeds.take(2).map((r) => _Tag(label: r, subtle: true)),
                if (dogBreeds.length + catBreeds.length > 4)
                  _Tag(
                      label:
                          '+${dogBreeds.length + catBreeds.length - 4}',
                      subtle: true),
              ],
            ),
          ],

          if (desc.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              desc,
              style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  fontFamily: 'Galey'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                final user = UserSelected.fromMap(data, uid);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserDetailPageFeed(user: user),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    const Color.fromARGB(255, 250, 192, 187),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                'Voir le profil',
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w500,
                    color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderAvatar extends StatelessWidget {
  const _PlaceholderAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 250, 192, 187).withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.pets,
          size: 28, color: Color.fromARGB(255, 250, 192, 187)),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final bool subtle;
  const _Tag({required this.label, this.subtle = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: subtle
            ? Colors.grey.shade100
            : const Color.fromARGB(255, 250, 192, 187).withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: subtle
              ? Colors.grey.shade300
              : const Color.fromARGB(255, 250, 192, 187),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Galey',
          fontSize: 11,
          color: subtle ? Colors.black54 : Colors.black87,
        ),
      ),
    );
  }
}

class _BreedFilterSheet extends StatefulWidget {
  final List<String> allBreeds;
  final List<String> selected;

  const _BreedFilterSheet({
    required this.allBreeds,
    required this.selected,
  });

  @override
  State<_BreedFilterSheet> createState() => _BreedFilterSheetState();
}

class _BreedFilterSheetState extends State<_BreedFilterSheet> {
  late List<String> _selected;
  late List<String> _filtered;
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = List<String>.from(widget.selected);
    _filtered = List<String>.from(widget.allBreeds);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, scroll) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Filtrer par race',
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            fontSize: 18)),
                  ),
                  if (_selected.isNotEmpty)
                    TextButton(
                      onPressed: () =>
                          setState(() => _selected.clear()),
                      child: const Text('Effacer',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, _selected),
                    child: const Text('Appliquer',
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            color: Color.fromARGB(255, 200, 100, 80),
                            fontSize: 15)),
                  ),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _search,
                onChanged: (q) => setState(() {
                  _filtered = widget.allBreeds
                      .where((b) =>
                          b.toLowerCase().contains(q.toLowerCase()))
                      .toList();
                }),
                decoration: InputDecoration(
                  hintText: 'Rechercher une race...',
                  hintStyle: const TextStyle(
                      fontFamily: 'Galey', fontSize: 14),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (_selected.isNotEmpty) ...[
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _selected
                      .map((b) => Chip(
                            label: Text(b,
                                style: const TextStyle(
                                    fontFamily: 'Galey',
                                    fontSize: 12)),
                            backgroundColor: const Color.fromARGB(
                                255, 250, 192, 187),
                            deleteIconColor: Colors.black54,
                            onDeleted: () =>
                                setState(() => _selected.remove(b)),
                          ))
                      .toList(),
                ),
              ),
            ],
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final breed = _filtered[i];
                  final sel = _selected.contains(breed);
                  return ListTile(
                    dense: true,
                    title: Text(breed,
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 14,
                            fontWeight: sel
                                ? FontWeight.w500
                                : FontWeight.normal)),
                    trailing: Icon(
                        sel
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: sel
                            ? const Color.fromARGB(255, 200, 100, 80)
                            : Colors.grey,
                        size: 20),
                    onTap: () => setState(() {
                      sel
                          ? _selected.remove(breed)
                          : _selected.add(breed);
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
