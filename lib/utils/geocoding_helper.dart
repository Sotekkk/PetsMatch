import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';

/// Géocode une adresse texte libre en coordonnées GPS (géocodage natif
/// device, même package déjà utilisé ailleurs dans l'app — ex.
/// pro_profile_edit.dart). Retourne null si l'adresse n'a pas pu être
/// résolue (adresse vide, "au cabinet", pas de réseau…).
class GeocodingHelper {
  static Future<({double lat, double lng})?> geocode(String address) async {
    final q = address.trim();
    if (q.isEmpty) return null;
    try {
      final locs = await geo.locationFromAddress(q);
      if (locs.isEmpty) return null;
      return (lat: locs.first.latitude, lng: locs.first.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Distance à vol d'oiseau en km.
  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2) / 1000.0;
  }
}
