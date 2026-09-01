import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Petite carte pour poser / glisser un point unique.
/// Extrait de `add_natural_place_page.dart` (`_MapPicker`) pour être réutilisé
/// (ajout d'un lieu, signalement d'une zone d'eau cyanobactéries, …).
class MapPointPicker extends StatelessWidget {
  final LatLng position;
  final void Function(LatLng) onChanged;
  final double height;
  final double zoom;

  const MapPointPicker({
    super.key,
    required this.position,
    required this.onChanged,
    this.height = 220,
    this.zoom = 13,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: height,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: position, zoom: zoom),
          onTap: onChanged,
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
          },
          markers: {
            Marker(
              markerId: const MarkerId('picked'),
              position: position,
              draggable: true,
              onDragEnd: onChanged,
            ),
          },
          myLocationButtonEnabled: false,
          zoomControlsEnabled: true,
        ),
      ),
    );
  }
}
