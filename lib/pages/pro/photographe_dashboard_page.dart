import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/geocoding_helper.dart';

/// Tableau de bord photographe — agrégats calculés à la volée (pas de table
/// de stats dénormalisée) : nombre de shootings, CA, kilomètres parcourus
/// ce mois-ci, note moyenne (avis_pro, déjà dénormalisée sur user_profiles).
class PhotographeDashboardPage extends StatefulWidget {
  const PhotographeDashboardPage({super.key});

  @override
  State<PhotographeDashboardPage> createState() => _PhotographeDashboardPageState();
}

class _PhotographeDashboardPageState extends State<PhotographeDashboardPage> {
  static const _teal = Color(0xFF90A4AE);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  int _nbShootings = 0;
  double _ca = 0;
  double _kmCeMois = 0;
  double _noteMoyenne = 0;
  int _nbAvis = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final pid = User_Info.activeProfileId;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1).toUtc();

      final results = await Future.wait<dynamic>([
        _supa.from('rdv').select('id').eq('pro_uid', uid).eq('pro_profile_id', pid).eq('statut', 'termine'),
        _supa.from('photographe_factures').select('montant_total').eq('pro_uid', uid).eq('pro_profile_id', pid).eq('statut', 'payee'),
        _supa.from('rdv').select('lat_depart, lng_depart')
            .eq('pro_uid', uid).eq('pro_profile_id', pid).eq('statut', 'termine')
            .gte('date_heure', startOfMonth.toIso8601String())
            .not('lat_depart', 'is', null),
        pid.isNotEmpty
            ? _supa.from('user_profiles').select('lat, lng, note_moyenne, nb_avis').eq('id', pid).maybeSingle()
            : Future<Map<String, dynamic>?>.value(null),
      ]);

      final shootings = results[0] as List;
      final factures = results[1] as List;
      final rdvsMois = results[2] as List;
      final profil = results[3] as Map<String, dynamic>?;

      final ca = factures.fold<double>(0, (s, f) => s + ((f['montant_total'] as num?)?.toDouble() ?? 0));

      double kmTotal = 0;
      final proLat = (profil?['lat'] as num?)?.toDouble();
      final proLng = (profil?['lng'] as num?)?.toDouble();
      if (proLat != null && proLng != null) {
        for (final r in rdvsMois) {
          final lat = (r['lat_depart'] as num?)?.toDouble();
          final lng = (r['lng_depart'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            kmTotal += GeocodingHelper.distanceKm(proLat, proLng, lat, lng);
          }
        }
      }

      if (mounted) setState(() {
        _nbShootings = shootings.length;
        _ca = ca;
        _kmCeMois = kmTotal;
        _noteMoyenne = (profil?['note_moyenne'] as num?)?.toDouble() ?? 0;
        _nbAvis = (profil?['nb_avis'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _statCard(String label, String value, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: _teal, size: 22),
        const SizedBox(height: 10),
        Text(value, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Color(0xFF1F2A2E))),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Tableau de bord', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              onRefresh: _load,
              color: _teal,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(children: [
                    _statCard('Shootings réalisés', '$_nbShootings', Icons.camera_alt_outlined),
                    const SizedBox(width: 12),
                    _statCard('CA encaissé', '${_ca.toStringAsFixed(0)} €', Icons.euro_outlined),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    _statCard('Km ce mois-ci', '${_kmCeMois.toStringAsFixed(0)} km', Icons.directions_car_outlined),
                    const SizedBox(width: 12),
                    _statCard('Note moyenne',
                        _nbAvis > 0 ? '${_noteMoyenne.toStringAsFixed(1)} ★ ($_nbAvis)' : '—',
                        Icons.star_outline),
                  ]),
                ],
              ),
            ),
    );
  }
}
