import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;

const _kTeal = Color(0xFF0C5C6C);

class ProZonePage extends StatefulWidget {
  const ProZonePage({super.key});

  @override
  State<ProZonePage> createState() => _ProZonePageState();
}

class _ProZonePageState extends State<ProZonePage> {
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  GoogleMapController? _mapCtrl;
  LatLng? _centre;
  int _rayonKm = 20;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Charger la zone existante
      final zone = await _supa
          .from('zones_intervention')
          .select()
          .eq('pro_uid', _uid)
          .maybeSingle();

      // Charger lat/lng depuis le profil pro
      final user = await _supa
          .from('users')
          .select('lat, lng, rayon_intervention')
          .eq('uid', _uid)
          .maybeSingle();

      if (mounted) {
        setState(() {
          if (zone != null) {
            _rayonKm   = (zone['rayon_km'] as num?)?.toInt() ?? 20;
            final zLat = (zone['centre_lat'] as num?)?.toDouble();
            final zLng = (zone['centre_lng'] as num?)?.toDouble();
            if (zLat != null && zLng != null) {
              _centre = LatLng(zLat, zLng);
            }
          }
          // Fallback sur lat/lng du profil
          if (_centre == null && user != null) {
            final uLat = (user['lat'] as num?)?.toDouble();
            final uLng = (user['lng'] as num?)?.toDouble();
            if (uLat != null && uLng != null) {
              _centre = LatLng(uLat, uLng);
            }
            if (zone == null) {
              _rayonKm = (user['rayon_intervention'] as num?)?.toInt() ?? 20;
            }
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final centre = _centre;
      // Upsert zones_intervention
      await _supa.from('zones_intervention').upsert({
        'pro_uid':    _uid,
        'rayon_km':   _rayonKm,
        'centre_lat': centre?.latitude,
        'centre_lng': centre?.longitude,
        'updated_at': DateTime.now().toIso8601String(),
        if (User_Info.activeProfileId.isNotEmpty) 'pro_profile_id': User_Info.activeProfileId,
      }, onConflict: 'pro_uid');

      // Sync rayon dans users
      await _supa
          .from('users')
          .update({'rayon_intervention': _rayonKm})
          .eq('uid', _uid);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Zone enregistrée !',
              style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: _kTeal,
        ));
        Navigator.pop(context, _rayonKm);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e',
              style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Set<Circle> get _circles {
    final c = _centre;
    if (c == null) return {};
    return {
      Circle(
        circleId: const CircleId('zone'),
        center: c,
        radius: _rayonKm * 1000.0,
        fillColor: _kTeal.withValues(alpha: 0.12),
        strokeColor: _kTeal,
        strokeWidth: 2,
      ),
    };
  }

  void _onMapTap(LatLng pos) {
    setState(() => _centre = pos);
    _mapCtrl?.animateCamera(CameraUpdate.newLatLng(pos));
  }

  @override
  Widget build(BuildContext context) {
    final hasPos = _centre != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _kTeal,
        foregroundColor: Colors.white,
        title: const Text('Zone d\'intervention',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!_saving)
            TextButton(
              onPressed: _save,
              child: const Text('Enregistrer',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      color: Colors.white, fontSize: 14)),
            )
          else
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kTeal))
          : Column(children: [
              // Info banner
              Container(
                color: _kTeal.withValues(alpha: 0.08),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  const Icon(Icons.info_outline, size: 18, color: _kTeal),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasPos
                          ? 'Touchez la carte pour déplacer le centre. Ajustez le rayon ci-dessous.'
                          : 'Touchez la carte pour définir le centre de votre zone.',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _kTeal),
                    ),
                  ),
                ]),
              ),

              // Carte
              Expanded(
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _centre ?? const LatLng(46.5, 2.5),
                    zoom: _centre != null ? 9 : 6,
                  ),
                  circles: _circles,
                  onMapCreated: (c) => _mapCtrl = c,
                  onTap: _onMapTap,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: false,
                ),
              ),

              // Slider rayon
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.radar, color: _kTeal, size: 20),
                    const SizedBox(width: 8),
                    const Text('Rayon d\'intervention',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                            fontSize: 14, color: Color(0xFF1E2025))),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _kTeal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('$_rayonKm km',
                          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                              fontSize: 14, color: _kTeal)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: _kTeal,
                      thumbColor: _kTeal,
                      inactiveTrackColor: const Color(0xFFDDDDDD),
                      overlayColor: _kTeal.withValues(alpha: 0.15),
                    ),
                    child: Slider(
                      value: _rayonKm.toDouble(),
                      min: 5,
                      max: 200,
                      divisions: 39,
                      onChanged: (v) => setState(() => _rayonKm = v.round()),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('5 km', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
                      Text('100 km', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
                      Text('200 km', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ]),
              ),
            ]),
    );
  }
}
