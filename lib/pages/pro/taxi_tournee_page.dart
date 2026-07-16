import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/geocoding_helper.dart';

// ── Ma tournée (taxi animalier) — courses du jour, chacune avec un point de
// départ ET d'arrivée (contrairement à tournee_page.dart qui gère des
// visites à un seul lieu). Distance à vol d'oiseau (GeocodingHelper), pas
// d'itinéraire routier réel — décision prise pour le MVP de ce module.

class TaxiTourneePage extends StatefulWidget {
  const TaxiTourneePage({super.key});

  @override
  State<TaxiTourneePage> createState() => _TaxiTourneePageState();
}

class _TaxiTourneePageState extends State<TaxiTourneePage> {
  static const _teal = Color(0xFF00838F);
  static const _bg = Color(0xFFF8F8F6);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _courses = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final pid = User_Info.activeProfileId;
    if (uid == null || pid.isEmpty) { setState(() => _loading = false); return; }
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day).toUtc();
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59).toUtc();

      final rows = await _supa.from('rdv').select()
          .eq('pro_uid', uid).eq('pro_profile_id', pid)
          .eq('statut', 'confirme')
          .gte('date_heure', startOfDay.toIso8601String())
          .lte('date_heure', endOfDay.toIso8601String())
          .order('date_heure');
      final list = List<Map<String, dynamic>>.from(rows as List);

      final clientUids = list.map((r) => r['client_uid'] as String?).whereType<String>().toSet().toList();
      final clientNames = <String, String>{};
      if (clientUids.isNotEmpty) {
        final profiles = await _supa.from('user_profiles')
            .select('uid, firstname, lastname, nom').inFilter('uid', clientUids).eq('is_main', true);
        for (final c in profiles as List) {
          final nom = (c['nom'] as String?)?.trim();
          final full = nom?.isNotEmpty == true ? nom! : '${c['firstname'] ?? ''} ${c['lastname'] ?? ''}'.trim();
          clientNames[c['uid'] as String] = full.isNotEmpty ? full : 'Client';
        }
      }
      for (final r in list) {
        r['_client_nom'] = clientNames[r['client_uid']] ?? 'Client';
      }

      if (mounted) setState(() { _courses = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isGeocoded(Map<String, dynamic> c) =>
      c['lat_depart'] != null && c['lng_depart'] != null && c['lat_arrivee'] != null && c['lng_arrivee'] != null;

  double? _distanceKm(Map<String, dynamic> c) {
    if (!_isGeocoded(c)) return null;
    return GeocodingHelper.distanceKm(
      (c['lat_depart'] as num).toDouble(), (c['lng_depart'] as num).toDouble(),
      (c['lat_arrivee'] as num).toDouble(), (c['lng_arrivee'] as num).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final geocoded = _courses.where(_isGeocoded).toList();
    final totalKm = geocoded.fold<double>(0, (sum, c) => sum + (_distanceKm(c) ?? 0));

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Ma tournée', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _courses.isEmpty
              ? const Center(child: Text('Aucune course confirmée aujourd\'hui',
                  style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
              : Column(children: [
                  SizedBox(
                    height: 240,
                    child: geocoded.isEmpty
                        ? Container(
                            color: const Color(0xFFEEF5EA),
                            alignment: Alignment.center,
                            child: Text('Aucune course localisée pour l\'instant',
                                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                          )
                        : GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: LatLng((geocoded.first['lat_depart'] as num).toDouble(),
                                  (geocoded.first['lng_depart'] as num).toDouble()),
                              zoom: 12,
                            ),
                            markers: _buildMarkers(geocoded),
                            polylines: _buildPolylines(geocoded),
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: true,
                          ),
                  ),
                  if (geocoded.isNotEmpty)
                    Container(
                      width: double.infinity,
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text('🚕 ~${totalKm.toStringAsFixed(1)} km au total (à vol d\'oiseau)',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: _teal)),
                    ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _courses.length,
                      itemBuilder: (_, i) => _CourseTile(course: _courses[i], distanceKm: _distanceKm(_courses[i])),
                    ),
                  ),
                ]),
    );
  }

  Set<Marker> _buildMarkers(List<Map<String, dynamic>> geocoded) {
    final markers = <Marker>{};
    for (var i = 0; i < geocoded.length; i++) {
      final c = geocoded[i];
      markers.add(Marker(
        markerId: MarkerId('${c['id']}_depart'),
        position: LatLng((c['lat_depart'] as num).toDouble(), (c['lng_depart'] as num).toDouble()),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: 'Départ — ${c['_client_nom']}', snippet: c['adresse_depart']?.toString()),
      ));
      markers.add(Marker(
        markerId: MarkerId('${c['id']}_arrivee'),
        position: LatLng((c['lat_arrivee'] as num).toDouble(), (c['lng_arrivee'] as num).toDouble()),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: 'Arrivée — ${c['_client_nom']}', snippet: c['adresse_arrivee']?.toString()),
      ));
    }
    return markers;
  }

  Set<Polyline> _buildPolylines(List<Map<String, dynamic>> geocoded) {
    return {
      for (final c in geocoded)
        Polyline(
          polylineId: PolylineId(c['id'].toString()),
          points: [
            LatLng((c['lat_depart'] as num).toDouble(), (c['lng_depart'] as num).toDouble()),
            LatLng((c['lat_arrivee'] as num).toDouble(), (c['lng_arrivee'] as num).toDouble()),
          ],
          color: _teal,
          width: 3,
        ),
    };
  }
}

class _CourseTile extends StatelessWidget {
  final Map<String, dynamic> course;
  final double? distanceKm;
  static const _teal = Color(0xFF00838F);

  const _CourseTile({required this.course, required this.distanceKm});

  @override
  Widget build(BuildContext context) {
    final dh = DateTime.tryParse(course['date_heure']?.toString() ?? '')?.toLocal();
    final heure = dh != null ? DateFormat('HH:mm').format(dh) : '';
    final nbAnimaux = course['nombre_animaux'] as int? ?? 1;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 14, backgroundColor: _teal.withValues(alpha: 0.1),
                child: const Icon(Icons.local_taxi_outlined, size: 14, color: _teal)),
            const SizedBox(width: 8),
            Text(heure, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(width: 8),
            Text(course['_client_nom']?.toString() ?? '',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
            const Spacer(),
            if (distanceKm != null)
              Text('${distanceKm!.toStringAsFixed(1)} km',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: _teal)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.trip_origin, size: 14, color: Colors.green),
            const SizedBox(width: 6),
            Expanded(child: Text(course['adresse_depart']?.toString() ?? '—',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12), overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 3),
          Row(children: [
            const Icon(Icons.location_on_outlined, size: 14, color: Colors.red),
            const SizedBox(width: 6),
            Expanded(child: Text(course['adresse_arrivee']?.toString() ?? '—',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12), overflow: TextOverflow.ellipsis)),
          ]),
          if (nbAnimaux > 1) ...[
            const SizedBox(height: 4),
            Text('$nbAnimaux animaux', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          ],
        ]),
      ),
    );
  }
}
