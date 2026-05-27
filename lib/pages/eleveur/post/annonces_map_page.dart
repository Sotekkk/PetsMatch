import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AnnoncesMapPage extends StatefulWidget {
  final String typeFilter; // 'compagnon' | 'saillie'
  final String espece;
  final String race;
  final String pays;
  final String region;
  final String departement;
  final String ville;
  const AnnoncesMapPage({
    super.key,
    this.typeFilter = 'compagnon',
    this.espece = 'tous',
    this.race = '',
    this.pays = '',
    this.region = '',
    this.departement = '',
    this.ville = '',
  });

  @override
  State<AnnoncesMapPage> createState() => _AnnoncesMapPageState();
}

class _AnnoncesMapPageState extends State<AnnoncesMapPage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  GoogleMapController? _mapController;
  final Map<MarkerId, Marker> _markers = {};
  List<Map<String, dynamic>> _annonces = [];
  bool _loading = true;
  bool _locating = false;
  bool _legendExpanded = false;
  String _status = 'Chargement des annonces...';

  bool get _isSaillie => widget.typeFilter == 'saillie';

  @override
  void initState() {
    super.initState();
    _loadAnnonces();
  }

  static Map<String, dynamic> _norm(Map<String, dynamic> row) => {
    ...row,
    '_id':                row['id']?.toString() ?? '',
    'uidEleveur':         row['uid_eleveur'],
    'nomEleveur':         row['nom_eleveur'],
    'villeEleveur':       row['ville_eleveur'],
    'paysEleveur':        row['pays_eleveur'] ?? 'France',
    'regionEleveur':      row['region_eleveur'] ?? '',
    'departementEleveur': row['departement_eleveur'] ?? '',
    'typeVente':          row['type_vente'],
    'prixMinPortee':      row['prix_min_portee'],
    'prixMaxPortee':      row['prix_max_portee'],
    'nombreBebes':        row['nombre_bebes'],
    'animauxPortee':      row['animaux_portee'] ?? [],
  };

  Future<void> _loadAnnonces() async {
    setState(() => _status = 'Chargement des annonces...');

    final rows = await Supabase.instance.client
        .from('annonces')
        .select()
        .eq('statut', 'disponible');

    final List<Map<String, dynamic>> result = [];
    final geocodeCache = <String, LatLng?>{};
    int done = 0;

    for (final raw in rows) {
      final data = _norm(Map<String, dynamic>.from(raw));

      // Type filter
      final typeVente = (data['typeVente'] as String?) ?? '';
      if (_isSaillie) {
        if (typeVente != 'saillie') continue;
      } else {
        if (typeVente == 'saillie') continue;
      }

      // Inherited filters from list view
      if (widget.espece != 'tous') {
        if ((data['espece'] as String?) != widget.espece) continue;
      }
      if (widget.race.isNotEmpty) {
        final r = ((data['race'] as String?) ?? '').toLowerCase();
        if (!r.contains(widget.race.toLowerCase())) continue;
      }
      if (widget.pays.isNotEmpty) {
        final p = ((data['paysEleveur'] as String?) ?? '').toLowerCase();
        if (p.isNotEmpty && !p.contains(widget.pays.toLowerCase())) continue;
      }
      if (widget.region.isNotEmpty) {
        final r = ((data['regionEleveur'] as String?) ?? '').toLowerCase();
        if (r.isNotEmpty && !r.contains(widget.region.toLowerCase())) continue;
      }
      if (widget.departement.isNotEmpty) {
        final d = ((data['departementEleveur'] as String?) ?? '').toLowerCase();
        if (d.isNotEmpty && !d.contains(widget.departement.toLowerCase())) continue;
      }
      if (widget.ville.isNotEmpty) {
        final v = ((data['villeEleveur'] as String?) ?? '').toLowerCase();
        if (!v.contains(widget.ville.toLowerCase())) continue;
      }

      // Use stored coordinates or geocode
      if (data['lat'] == null || data['lng'] == null) {
        String villeQuery = ((data['villeEleveur'] as String?) ?? '').trim();
        String paysQuery  = ((data['paysEleveur']  as String?) ?? 'France').trim();

        // Fallback: load from breeder profile when villeEleveur is missing
        if (villeQuery.isEmpty) {
          final uid = ((data['uidEleveur'] as String?) ?? '').trim();
          if (uid.isNotEmpty) {
            try {
              final userRow = await Supabase.instance.client
                  .from('users').select().eq('uid', uid).maybeSingle();
              if (userRow != null) {
                final villeElevage = ((userRow['ville_elevage'] as String?) ?? '').trim();
                final cpElevage    = ((userRow['code_postal_elevage'] as String?) ?? '').trim();
                paysQuery = ((userRow['pays_elevage'] as String?) ?? 'France').trim();
                villeQuery = villeElevage.isNotEmpty ? villeElevage : cpElevage;
                // Backfill denormalized field on the annonce so we don't have to do this again
                if (villeQuery.isNotEmpty) {
                  Supabase.instance.client
                      .from('annonces')
                      .update({'ville_eleveur': villeQuery, 'pays_eleveur': paysQuery})
                      .eq('id', data['_id'])
                      .catchError((_) {});
                }
              }
            } catch (_) {}
          }
        }

        if (villeQuery.isNotEmpty) {
          final geoKey = '$villeQuery|$paysQuery';
          if (!geocodeCache.containsKey(geoKey)) {
            done++;
            if (mounted) {
              setState(() => _status = 'Localisation ($done)...');
            }
            final queryStr = paysQuery.toLowerCase() == 'france' || paysQuery.isEmpty
                ? '$villeQuery, France'
                : '$villeQuery, $paysQuery';
            try {
              final locs = await locationFromAddress(queryStr);
              geocodeCache[geoKey] = locs.isNotEmpty
                  ? LatLng(locs.first.latitude, locs.first.longitude)
                  : null;
              if (geocodeCache[geoKey] != null) {
                Supabase.instance.client
                    .from('annonces')
                    .update({
                  'lat': geocodeCache[geoKey]!.latitude,
                  'lng': geocodeCache[geoKey]!.longitude,
                }).eq('id', data['_id']).catchError((_) {});
              }
            } catch (_) {
              geocodeCache[geoKey] = null;
            }
          }
          final pos = geocodeCache[geoKey];
          if (pos != null) {
            data['lat'] = pos.latitude;
            data['lng'] = pos.longitude;
          }
        }
      }

      if (data['lat'] != null && data['lng'] != null) {
        result.add(data);
      }
    }

    if (!mounted) return;
    setState(() {
      _annonces = result;
      _loading = false;
    });
    _buildMarkers();
  }

  void _buildMarkers() {
    // Group by rounded coordinates to cluster nearby pins
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final a in _annonces) {
      final lat = (a['lat'] as num).toDouble();
      final lng = (a['lng'] as num).toDouble();
      final key = '${lat.toStringAsFixed(2)}_${lng.toStringAsFixed(2)}';
      groups.putIfAbsent(key, () => []).add(a);
    }

    final newMarkers = <MarkerId, Marker>{};
    for (final entry in groups.entries) {
      final list = entry.value;
      final first = list.first;
      final lat = (first['lat'] as num).toDouble();
      final lng = (first['lng'] as num).toDouble();
      final id = MarkerId(entry.key);

      newMarkers[id] = Marker(
        markerId: id,
        position: LatLng(lat, lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(
            _isSaillie
                ? BitmapDescriptor.hueRose
                : BitmapDescriptor.hueCyan),
        onTap: () => _showSheet(list),
      );
    }

    setState(() => _markers..clear()..addAll(newMarkers));
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

  void _showSheet(List<Map<String, dynamic>> annonces) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: annonces.length == 1 ? 0.35 : 0.5,
        maxChildSize: 0.85,
        builder: (sheetCtx, ctrl) => Column(children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(children: [
              const Icon(Icons.location_on_outlined, color: _teal, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  (annonces.first['villeEleveur'] as String?)?.isNotEmpty == true
                      ? annonces.first['villeEleveur'] as String : 'Cette zone',
                  style: const TextStyle(fontFamily: 'Galey',
                      fontWeight: FontWeight.w700, fontSize: 14,
                      color: _teal),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${annonces.length} annonce${annonces.length > 1 ? 's' : ''}',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                    color: Colors.grey.shade500)),
            ]),
          ),
          const Divider(height: 1),
          // List
          Expanded(child: ListView.builder(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            itemCount: annonces.length,
            itemBuilder: (_, i) {
              final a = annonces[i];
              return _MapAnnonceCard(
                data: a,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(ctx, MaterialPageRoute(
                      builder: (_) => AnnonceDetailPage(
                          annonceId: a['_id'] as String,
                          initialData: a)));
                },
              );
            },
          )),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text(
          _isSaillie ? 'Carte – Saillies' : 'Carte des annonces',
          style: const TextStyle(fontFamily: 'Galey',
              fontWeight: FontWeight.w700, fontSize: 17)),
        elevation: 0,
        actions: [
          if (!_loading)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '${_annonces.length} annonce${_annonces.length > 1 ? 's' : ''}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                      color: Colors.white70)),
              ),
            ),
        ],
      ),
      body: _loading
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              const CircularProgressIndicator(color: _teal),
              const SizedBox(height: 16),
              Text(_status,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                      color: Color(0xFF6F767B))),
            ]))
          : _annonces.isEmpty
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.map_outlined, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 14),
                  Text('Aucune annonce localisable',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 16,
                          color: Colors.grey.shade500)),
                  const SizedBox(height: 6),
                  Text('Vérifiez que les éleveurs ont renseigné leur ville',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                          color: Colors.grey.shade400),
                      textAlign: TextAlign.center),
                ]))
              : Stack(children: [
                  GoogleMap(
                    onMapCreated: (ctrl) => _mapController = ctrl,
                    initialCameraPosition: const CameraPosition(
                        target: LatLng(46.8, 2.35), zoom: 5.5),
                    markers: Set<Marker>.of(_markers.values),
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: true,
                  ),
                  // GPS centering button
                  Positioned(
                    bottom: 110, right: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'annonces_map_gps',
                      backgroundColor: Colors.white,
                      onPressed: _locating ? null : _recenterMap,
                      child: _locating
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: _teal))
                          : const Icon(Icons.my_location, color: _teal, size: 20),
                    ),
                  ),
                  // Legend
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
                                _AnnonceLegendItem(color: const Color(0xFF00BCD4), label: '🐾 Compagnon / Portée'),
                                const SizedBox(height: 3),
                                _AnnonceLegendItem(color: const Color(0xFFE91E63), label: '💕 Saillie'),
                              ])
                            : Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.legend_toggle, size: 16, color: _teal),
                                const SizedBox(width: 5),
                                Container(width: 8, height: 8,
                                    decoration: const BoxDecoration(color: Color(0xFF00BCD4), shape: BoxShape.circle)),
                                const SizedBox(width: 3),
                                Container(width: 8, height: 8,
                                    decoration: const BoxDecoration(color: Color(0xFFE91E63), shape: BoxShape.circle)),
                              ]),
                      ),
                    ),
                  ),
                ]),
    );
  }
}

// ─── Mini card pour la sheet carte ───────────────────────────────────────────

class _MapAnnonceCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  const _MapAnnonceCard({required this.data, required this.onTap});

  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  @override
  Widget build(BuildContext context) {
    final espece    = (data['espece'] as String?) ?? '';
    final race      = (data['race'] as String?) ?? '';
    final titre     = (data['titre'] as String?) ?? '';
    final typeVente = (data['typeVente'] as String?) ?? 'vente';
    final type      = (data['type'] as String?) ?? 'animal';
    final photos    = List<String>.from(data['photos'] ?? []);
    final prix      = (data['prix'] as num?)?.toDouble();
    final prixMin   = (data['prixMinPortee'] as num?)?.toDouble();
    final prixMax   = (data['prixMaxPortee'] as num?)?.toDouble();
    final displayTitle = titre.isNotEmpty ? titre
        : race.isNotEmpty ? race : speciesLabel(espece);

    String prixLabel = '';
    if (typeVente == 'vente') {
      if (type == 'portee' && (prixMin != null || prixMax != null)) {
        prixLabel = prixMin != null && prixMax != null
            ? '${prixMin.toInt()} – ${prixMax.toInt()} €'
            : prixMin != null ? 'Dès ${prixMin.toInt()} €'
            : 'Max ${prixMax!.toInt()} €';
      } else if (prix != null && prix > 0) {
        prixLabel = '${prix.toInt()} €';
      }
    } else if (typeVente == 'adoption') {
      prixLabel = 'Adoption';
    } else if (typeVente == 'saillie') {
      prixLabel = 'Saillie';
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(children: [
          // Photo
          ClipRRect(
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12)),
            child: SizedBox(width: 70, height: 70,
              child: photos.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photos.first, fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                          color: const Color(0xFFEEF5EA)),
                      errorWidget: (_, __, ___) => Container(
                          color: const Color(0xFFEEF5EA),
                          child: Center(child: speciesIcon(
                              espece, 24, _green))))
                  : Container(color: const Color(0xFFEEF5EA),
                      child: Center(child: speciesIcon(espece, 24, _green)))),
          ),
          // Info
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                speciesIcon(espece, 11, _teal),
                const SizedBox(width: 4),
                Expanded(child: Text(displayTitle,
                    style: const TextStyle(fontFamily: 'Galey',
                        fontWeight: FontWeight.w700, fontSize: 13,
                        color: Color(0xFF1F2A2E)),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
              Text(race.isNotEmpty ? race : speciesLabel(espece),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                      color: Color(0xFF6F767B))),
              if (prixLabel.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(prixLabel, style: TextStyle(
                    fontFamily: 'Galey', fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: typeVente == 'adoption' ? _green : _teal)),
              ],
            ]),
          )),
          const Padding(
            padding: EdgeInsets.only(right: 10),
            child: Icon(Icons.chevron_right, size: 18,
                color: Color(0xFF0C5C6C))),
        ]),
      ),
    );
  }
}

// ─── Legend item ─────────────────────────────────────────────────────────────

class _AnnonceLegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _AnnonceLegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.location_on, color: color, size: 14),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 10)),
    ]);
  }
}
