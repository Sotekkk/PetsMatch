import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../balades_ludiques_shared.dart';

class DefiGpsWidget extends StatefulWidget {
  final double pointLat;
  final double pointLng;
  final int rayonValidationM;
  final Future<void> Function(double lat, double lng, double distanceM) onValidated;

  const DefiGpsWidget({
    super.key,
    required this.pointLat,
    required this.pointLng,
    required this.rayonValidationM,
    required this.onValidated,
  });

  @override
  State<DefiGpsWidget> createState() => _DefiGpsWidgetState();
}

class _DefiGpsWidgetState extends State<DefiGpsWidget> {
  bool _busy = false;
  String? _message;

  Future<void> _check() async {
    setState(() { _busy = true; _message = null; });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _message = 'Activez la localisation pour valider cette étape.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.best));
      final distance = Geolocator.distanceBetween(pos.latitude, pos.longitude, widget.pointLat, widget.pointLng);
      if (distance <= widget.rayonValidationM) {
        await widget.onValidated(pos.latitude, pos.longitude, distance);
      } else {
        setState(() => _message = 'Vous êtes à ${distance.round()} m du point (max ${widget.rayonValidationM} m). Rapprochez-vous !');
      }
    } catch (_) {
      setState(() => _message = 'Impossible de récupérer votre position.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Rendez-vous sur place puis appuyez sur le bouton pour valider votre position.',
          style: TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.4)),
      if (_message != null) Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(_message!, style: const TextStyle(fontFamily: 'Galey', color: Colors.red, fontSize: 12)),
      ),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _busy ? null : _check,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.my_location, color: Colors.white),
          label: const Text('Je suis arrivé(e)', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
          style: ElevatedButton.styleFrom(backgroundColor: kBlOrange, padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ),
    ]);
  }
}
