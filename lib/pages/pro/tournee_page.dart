import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/geocoding_helper.dart';

// ── Ma tournée — carte des visites du jour + ordre réordonnable. L'heure du
// RDV (date_heure) reste la référence officielle ; ordre_visite est un
// ordre de passage indicatif que le pro peut ajuster pour optimiser son
// trajet, sans modifier les horaires réservés par les clients.

class TourneePage extends StatefulWidget {
  const TourneePage({super.key});

  @override
  State<TourneePage> createState() => _TourneePageState();
}

class _TourneePageState extends State<TourneePage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _bg = Color(0xFFF8F8F6);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _visites = [];
  LatLng? _myPosition;

  @override
  void initState() {
    super.initState();
    _load();
    _loadMyPosition();
  }

  Future<void> _loadMyPosition() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      if (mounted) setState(() => _myPosition = LatLng(pos.latitude, pos.longitude));
    } catch (_) {}
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
          .lte('date_heure', endOfDay.toIso8601String());
      final list = List<Map<String, dynamic>>.from(rows as List);

      final clientUids = list.map((r) => r['client_uid'] as String?).whereType<String>().toSet().toList();
      final animalIds = list.map((r) => r['animal_id']?.toString()).whereType<String>().where((s) => s.isNotEmpty).toSet().toList();

      final results = await Future.wait([
        clientUids.isNotEmpty
            ? _supa.from('user_profiles').select('uid, firstname, lastname, nom').inFilter('uid', clientUids).eq('is_main', true)
            : Future.value(<Map<String, dynamic>>[]),
        animalIds.isNotEmpty
            ? _supa.from('animaux').select('id, nom').inFilter('id', animalIds)
            : Future.value(<Map<String, dynamic>>[]),
      ]);

      final clientNames = <String, String>{};
      for (final c in (results[0] as List)) {
        final nom = (c['nom'] as String?)?.trim();
        final full = nom?.isNotEmpty == true ? nom! : '${c['firstname'] ?? ''} ${c['lastname'] ?? ''}'.trim();
        clientNames[c['uid'] as String] = full.isNotEmpty ? full : 'Client';
      }
      final animalNames = <String, String>{
        for (final a in (results[1] as List)) a['id'].toString(): a['nom']?.toString() ?? '',
      };

      for (final r in list) {
        r['_client_nom'] = clientNames[r['client_uid']] ?? 'Client';
        r['_animal_nom'] = animalNames[r['animal_id']?.toString()] ?? '';
      }

      list.sort((a, b) {
        final oa = a['ordre_visite'] as int?;
        final ob = b['ordre_visite'] as int?;
        if (oa != null && ob != null) return oa.compareTo(ob);
        final da = DateTime.tryParse(a['date_heure']?.toString() ?? '') ?? DateTime(0);
        final db = DateTime.tryParse(b['date_heure']?.toString() ?? '') ?? DateTime(0);
        return da.compareTo(db);
      });

      if (mounted) setState(() { _visites = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _visites.removeAt(oldIndex);
      _visites.insert(newIndex, item);
    });
    try {
      for (var i = 0; i < _visites.length; i++) {
        await _supa.from('rdv').update({'ordre_visite': i}).eq('id', _visites[i]['id']);
      }
    } catch (_) {}
  }

  Future<void> _addAddress(Map<String, dynamic> rdv) async {
    final ctrl = TextEditingController(text: rdv['lieu']?.toString() ?? '');
    final address = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Adresse de la visite', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(fontFamily: 'Galey'),
          decoration: const InputDecoration(hintText: 'Ex : 12 rue des Lilas, 75011 Paris'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (address == null || address.isEmpty) return;
    try {
      final geo = await GeocodingHelper.geocode(address);
      await _supa.from('rdv').update({
        'lieu': address,
        'lieu_lat': geo?.lat,
        'lieu_lng': geo?.lng,
      }).eq('id', rdv['id']);
      await _load();
      if (mounted && geo == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Adresse enregistrée, mais non localisée sur la carte.', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {}
  }

  double? get _totalDistanceKm {
    final geocoded = _visites.where((v) => v['lieu_lat'] != null && v['lieu_lng'] != null).toList();
    if (geocoded.length < 2) return null;
    var total = 0.0;
    for (var i = 0; i < geocoded.length - 1; i++) {
      total += GeocodingHelper.distanceKm(
        (geocoded[i]['lieu_lat'] as num).toDouble(), (geocoded[i]['lieu_lng'] as num).toDouble(),
        (geocoded[i + 1]['lieu_lat'] as num).toDouble(), (geocoded[i + 1]['lieu_lng'] as num).toDouble(),
      );
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final geocoded = _visites.where((v) => v['lieu_lat'] != null && v['lieu_lng'] != null).toList();
    final totalKm = _totalDistanceKm;

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
          : _visites.isEmpty
              ? Center(child: Text('Aucune visite confirmée aujourd\'hui',
                  style: const TextStyle(fontFamily: 'Galey', color: Colors.grey)))
              : Column(children: [
                  SizedBox(
                    height: 240,
                    child: geocoded.isEmpty
                        ? Container(
                            color: const Color(0xFFEEF5EA),
                            alignment: Alignment.center,
                            child: Text('Aucune visite localisée — ajoutez une adresse ci-dessous',
                                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                          )
                        : GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: LatLng((geocoded.first['lieu_lat'] as num).toDouble(), (geocoded.first['lieu_lng'] as num).toDouble()),
                              zoom: 12,
                            ),
                            markers: _buildMarkers(geocoded),
                            polylines: _buildPolyline(geocoded),
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: true,
                          ),
                  ),
                  if (totalKm != null)
                    Container(
                      width: double.infinity,
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text('🚗 ~${totalKm.toStringAsFixed(1)} km au total (à vol d\'oiseau)',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: _teal)),
                    ),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _visites.length,
                      onReorder: _onReorder,
                      itemBuilder: (_, i) => _VisiteTile(
                        key: ValueKey(_visites[i]['id']),
                        index: i,
                        rdv: _visites[i],
                        onAddAddress: () => _addAddress(_visites[i]),
                      ),
                    ),
                  ),
                ]),
    );
  }

  Set<Marker> _buildMarkers(List<Map<String, dynamic>> geocoded) {
    final markers = <Marker>{};
    for (var i = 0; i < geocoded.length; i++) {
      final v = geocoded[i];
      markers.add(Marker(
        markerId: MarkerId(v['id'].toString()),
        position: LatLng((v['lieu_lat'] as num).toDouble(), (v['lieu_lng'] as num).toDouble()),
        icon: BitmapDescriptor.defaultMarkerWithHue(
            i == 0 ? BitmapDescriptor.hueGreen : i == geocoded.length - 1 ? BitmapDescriptor.hueRed : BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(title: '${i + 1}. ${v['_animal_nom']} — ${v['_client_nom']}'),
      ));
    }
    if (_myPosition != null) {
      markers.add(Marker(
        markerId: const MarkerId('ma_position'),
        position: _myPosition!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        infoWindow: const InfoWindow(title: 'Ma position'),
      ));
    }
    return markers;
  }

  Set<Polyline> _buildPolyline(List<Map<String, dynamic>> geocoded) {
    if (geocoded.length < 2) return {};
    return {
      Polyline(
        polylineId: const PolylineId('tournee'),
        points: geocoded.map((v) => LatLng((v['lieu_lat'] as num).toDouble(), (v['lieu_lng'] as num).toDouble())).toList(),
        color: _teal,
        width: 3,
      ),
    };
  }
}

class _VisiteTile extends StatelessWidget {
  final int index;
  final Map<String, dynamic> rdv;
  final VoidCallback onAddAddress;
  static const _teal = Color(0xFF0C5C6C);

  const _VisiteTile({super.key, required this.index, required this.rdv, required this.onAddAddress});

  @override
  Widget build(BuildContext context) {
    final dh = DateTime.tryParse(rdv['date_heure']?.toString() ?? '')?.toLocal();
    final heure = dh != null ? DateFormat('HH:mm').format(dh) : '';
    final lieu = rdv['lieu']?.toString() ?? '';
    final geocoded = rdv['lieu_lat'] != null && rdv['lieu_lng'] != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: _teal.withValues(alpha: 0.1),
          child: Text('${index + 1}', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _teal)),
        ),
        title: Text('${rdv['_animal_nom']} — ${rdv['_client_nom']}',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Row(children: [
          Text(heure, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
          const SizedBox(width: 8),
          if (lieu.isNotEmpty)
            Expanded(child: Text(lieu, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                color: geocoded ? Colors.grey.shade700 : Colors.orange.shade800), overflow: TextOverflow.ellipsis))
          else
            GestureDetector(
              onTap: onAddAddress,
              child: const Text('+ Ajouter une adresse',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _teal, decoration: TextDecoration.underline)),
            ),
        ]),
        trailing: const Icon(Icons.drag_handle, color: Colors.grey),
      ),
    );
  }
}
