import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class BaladesLudiquesMapView extends StatefulWidget {
  final List<Map<String, dynamic>> balades;
  final void Function(Map<String, dynamic> balade) onTap;
  const BaladesLudiquesMapView({super.key, required this.balades, required this.onTap});

  @override
  State<BaladesLudiquesMapView> createState() => _BaladesLudiquesMapViewState();
}

class _BaladesLudiquesMapViewState extends State<BaladesLudiquesMapView> {
  double _hueForDifficulte(String d) => switch (d) {
        'facile' => BitmapDescriptor.hueGreen,
        'modere' => BitmapDescriptor.hueOrange,
        'difficile' => BitmapDescriptor.hueRed,
        _ => BitmapDescriptor.hueAzure,
      };

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{};
    for (final b in widget.balades) {
      final lat = (b['lat_depart'] as num?)?.toDouble();
      final lng = (b['lng_depart'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      markers.add(Marker(
        markerId: MarkerId(b['id'].toString()),
        position: LatLng(lat, lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(_hueForDifficulte(b['difficulte']?.toString() ?? 'facile')),
        infoWindow: InfoWindow(title: b['titre']?.toString() ?? '', onTap: () => widget.onTap(b)),
        onTap: () => widget.onTap(b),
      ));
    }

    return GoogleMap(
      initialCameraPosition: const CameraPosition(target: LatLng(46.603354, 1.888334), zoom: 5.5),
      markers: markers,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: true,
    );
  }
}
