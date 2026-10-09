// Retards en cascade d'une journée, par praticien : un RDV terminé après
// l'heure prévue (rdv.termine_at) ou encore en cours décale les suivants.
// Ostéopathe / santé : le trajet entre deux RDV (domicile ↔ domicile ou
// cabinet) s'ajoute — même estimation que la réservation (vol d'oiseau à
// 30 km/h, cf. rdv_booking_page.dart), sans la marge de planification ; sans
// coordonnées connues des deux côtés, aucun trajet n'est supposé.
// Même calcul que la Cloud Function sendRetardsAutomatiques
// (functions/retards_auto.js) et le site (website/src/lib/retards-rdv.ts).

import 'dart:math' as math;

const _oubliMin = 120; // RDV non clôturé 2 h après sa fin : clôture oubliée
const kVitesseTrajetKmh = 30;

double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180, dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Position d'un RDV : adresse d'intervention géocodée, sinon le cabinet
/// (RDV sans adresse d'intervention), sinon inconnue.
({double lat, double lng})? positionRdv(Map<String, dynamic> r, ({double lat, double lng})? cabinet) {
  final lat = (r['lieu_lat'] as num?)?.toDouble(), lng = (r['lieu_lng'] as num?)?.toDouble();
  if (lat != null && lng != null) return (lat: lat, lng: lng);
  final exterieur = (r['lieu']?.toString().trim() ?? '').isNotEmpty && r['salle_id'] == null;
  return exterieur ? null : cabinet;
}

/// Minutes de trajet estimées entre deux RDV (0 si une position manque).
int trajetEntreRdv(Map<String, dynamic> a, Map<String, dynamic> b, ({double lat, double lng})? cabinet) {
  final pa = positionRdv(a, cabinet), pb = positionRdv(b, cabinet);
  if (pa == null || pb == null) return 0;
  return (_distanceKm(pa.lat, pa.lng, pb.lat, pb.lng) / kVitesseTrajetKmh * 60).ceil();
}

/// rdv id → retard estimé (minutes) des RDV à venir aujourd'hui.
/// [cabinet] : coordonnées du cabinet ; non nul = trajets pris en compte.
Map<String, int> retardsEnCascade(List<Map<String, dynamic>> rdvs,
    {DateTime? maintenant, ({double lat, double lng})? cabinet, bool avecTrajets = false}) {
  final now = maintenant ?? DateTime.now();
  final debutJour = DateTime(now.year, now.month, now.day);
  final finJour = debutJour.add(const Duration(days: 1));
  final groupes = <String, List<Map<String, dynamic>>>{};
  for (final r in rdvs) {
    if (r['statut'] != 'confirme' && r['statut'] != 'termine') continue;
    final dh = DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal();
    if (dh == null || dh.isBefore(debutJour) || !dh.isBefore(finJour)) continue;
    groupes.putIfAbsent(r['instructeur_profile_id']?.toString() ?? '', () => []).add(r);
  }
  final out = <String, int>{};
  for (final liste in groupes.values) {
    liste.sort((a, b) => a['date_heure'].toString().compareTo(b['date_heure'].toString()));
    DateTime? curseur;
    Map<String, dynamic>? precedent;
    for (final r in liste) {
      final debut = DateTime.parse(r['date_heure'].toString()).toLocal();
      final duree = Duration(minutes: (r['duree_minutes'] as num?)?.toInt() ?? 30);
      final finPrevue = debut.add(duree);
      // Heure à laquelle on peut être sur place : fin du précédent + trajet.
      final arrivee = curseur?.add(Duration(
          minutes: avecTrajets && precedent != null ? trajetEntreRdv(precedent, r, cabinet) : 0));
      precedent = r;
      if (r['statut'] == 'termine') {
        curseur = DateTime.tryParse(r['termine_at']?.toString() ?? '')?.toLocal() ?? finPrevue;
        continue;
      }
      if (!debut.isAfter(now)) {
        final debutReel = arrivee != null && arrivee.isAfter(debut) ? arrivee : debut;
        var fin = debutReel.add(duree);
        if (fin.isBefore(now)) fin = now;
        if (now.difference(finPrevue).inMinutes > _oubliMin) fin = finPrevue;
        curseur = fin;
        continue;
      }
      final debutEstime = arrivee != null && arrivee.isAfter(debut) ? arrivee : debut;
      final retard = debutEstime.difference(debut).inMinutes;
      if (retard > 0) out[r['id'].toString()] = retard;
      curseur = debutEstime.add(duree);
    }
  }
  return out;
}
