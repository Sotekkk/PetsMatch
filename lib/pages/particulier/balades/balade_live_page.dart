import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/particulier/balades/balade_recap_page.dart';
import 'package:PetsMatch/pages/particulier/balades/balade_utils.dart';

/// Suivi GPS en direct d'une balade (remplace le formulaire manuel Phase 1,
/// enregistrer_balade_page.dart) : trace le parcours, accumule distance et
/// durée, prend des photos, continue écran verrouillé/appli en arrière-plan
/// via le service de premier plan Android (geolocator_android) et le mode
/// "location" en arrière-plan iOS.
///
/// ⚠️ Limite honnête (documentée par geolocator lui-même) : ceci réduit
/// fortement le risque que l'OS tue l'appli en arrière-plan, mais ne
/// l'empêche pas totalement (Android peut quand même la tuer sous
/// optimisation batterie agressive) — et si l'utilisateur balaie l'appli
/// hors des apps récentes, le suivi s'arrête (nécessiterait une architecture
/// de service natif dédiée, hors scope ici).
class BaladeLivePage extends StatefulWidget {
  final String animalId;
  /// Nom affiché — « Luna » ou « Luna et Rocky » pour plusieurs animaux.
  final String animalNom;
  final String espece;
  /// Autres animaux de la balade (id, nom, espece) en plus de [animalId].
  final List<Map<String, dynamic>> autresAnimaux;

  const BaladeLivePage({
    super.key,
    required this.animalId,
    required this.animalNom,
    required this.espece,
    this.autresAnimaux = const [],
  });

  @override
  State<BaladeLivePage> createState() => _BaladeLivePageState();
}

class _BaladeLivePageState extends State<BaladeLivePage> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;

  GoogleMapController? _mapCtrl;
  StreamSubscription<Position>? _posSub;
  Timer? _ticker;

  bool _checkingPermission = true;
  String? _permissionError;
  bool _started = false;
  bool _paused = false;
  bool _finishing = false;

  String? _baladeId;
  DateTime? _startedAt;
  DateTime? _pauseStartedAt;
  Duration _pausedTotal = Duration.zero;

  Position? _lastPosition;
  final List<LatLng> _routePoints = [];
  final List<Map<String, dynamic>> _routeRaw = [];
  double _distanceM = 0;
  final List<File> _photos = [];

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (!mounted) return;
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      setState(() {
        _checkingPermission = false;
        _permissionError = "Autorisez l'accès à la position pour tracer la balade.";
      });
      return;
    }
    // Position "toujours" (nécessaire écran verrouillé) demandée à part, ici,
    // au moment où l'utilisateur comprend pourquoi — jamais au lancement de
    // l'appli. Pas bloquant si refusée : la balade se trace quand même tant
    // que l'appli reste au premier plan.
    try {
      await Permission.locationAlways.request();
    } catch (_) {}
    if (mounted) setState(() => _checkingPermission = false);
  }

  Duration get _elapsed {
    if (_startedAt == null) return Duration.zero;
    final end = DateTime.now();
    var total = end.difference(_startedAt!) - _pausedTotal;
    if (_paused && _pauseStartedAt != null) {
      total -= end.difference(_pauseStartedAt!);
    }
    return total.isNegative ? Duration.zero : total;
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get _distanceLabel => _distanceM >= 1000
      ? '${(_distanceM / 1000).toStringAsFixed(2)} km'
      : '${_distanceM.toStringAsFixed(0)} m';

  Future<void> _start() async {
    final uid = User_Info.uid;
    if (uid.isEmpty) return;
    try {
      final row = await _supa.from('balades_perso').insert({
        'uid': uid,
        if (User_Info.activeProfileId.isNotEmpty) 'profile_id': User_Info.activeProfileId,
        'animal_id': widget.animalId,
        // Tous les animaux de la balade (principal en tête).
        'animal_ids': [widget.animalId, ...widget.autresAnimaux.map((a) => a['id'].toString())],
        'statut': 'en_cours',
      }).select().single();
      _baladeId = row['id']?.toString();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Impossible de démarrer la balade.", style: TextStyle(fontFamily: 'Galey')),
        ));
      }
      return;
    }

    _startedAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
      intervalDuration: const Duration(seconds: 4),
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: 'Balade en cours — ${widget.animalNom}',
        notificationText: 'PetsMatch trace votre parcours en direct',
        notificationChannelName: 'Balades',
        setOngoing: true,
      ),
    );
    final appleSettings = AppleSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
      allowBackgroundLocationUpdates: true,
    );

    _posSub = Geolocator.getPositionStream(
      locationSettings: Platform.isIOS ? appleSettings : settings,
    ).listen(_onPosition, onError: (_) {});

    if (mounted) setState(() => _started = true);
  }

  void _onPosition(Position pos) {
    // Filtre léger anti-bruit GPS : point peu précis, on l'ignore pour
    // l'accumulation de distance (mais la carte peut quand même s'y centrer).
    final point = LatLng(pos.latitude, pos.longitude);
    _mapCtrl?.animateCamera(CameraUpdate.newLatLng(point));

    if (!_paused && pos.accuracy <= 30) {
      if (_lastPosition != null) {
        final seg = Geolocator.distanceBetween(
          _lastPosition!.latitude, _lastPosition!.longitude,
          pos.latitude, pos.longitude,
        );
        // Ignore un saut aberrant (rebond GPS) : > 80 m en moins de 4 s.
        if (seg > 0 && seg < 80) _distanceM += seg;
      }
      _lastPosition = pos;
      _routePoints.add(point);
      _routeRaw.add({'lat': pos.latitude, 'lng': pos.longitude, 't': DateTime.now().toIso8601String()});
    }
    if (mounted) setState(() {});
  }

  void _togglePause() {
    setState(() {
      if (_paused) {
        _pausedTotal += DateTime.now().difference(_pauseStartedAt!);
        _pauseStartedAt = null;
        _paused = false;
      } else {
        _paused = true;
        _pauseStartedAt = DateTime.now();
      }
    });
  }

  Future<void> _takePhoto() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 1440);
      if (x == null) return;
      if (mounted) setState(() => _photos.add(File(x.path)));
    } catch (_) {}
  }

  /// Balade lancée par erreur : arrête le suivi et efface la balade — aucune
  /// XP, flamme ni post (ils ne sont créés qu'au récap de fin).
  Future<void> _abandonner() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Abandonner la balade ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Elle sera supprimée sans être enregistrée (pas d\'XP ni de publication).',
            style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Continuer la balade', style: TextStyle(fontFamily: 'Galey'))),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            child: const Text('Abandonner', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _finishing = true);
    await _posSub?.cancel();
    _ticker?.cancel();
    await abandonnerBalade(_baladeId);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _stop() async {
    final choix = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Terminer la balade ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Text('$_distanceLabel parcourus en ${_fmtDuration(_elapsed)}.',
            style: const TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'supprimer'),
            child: Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.red.shade600)),
          ),
          TextButton(onPressed: () => Navigator.pop(context, 'continuer'), child: const Text('Continuer', style: TextStyle(fontFamily: 'Galey'))),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'terminer'),
            style: FilledButton.styleFrom(backgroundColor: _teal),
            child: const Text('Terminer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (choix == 'supprimer') {
      await _abandonner();
      return;
    }
    if (choix != 'terminer') return;

    setState(() => _finishing = true);
    await _posSub?.cancel();
    _ticker?.cancel();
    final duree = _elapsed;

    // Upload photos (compressées, bucket "social" — déjà utilisé par le fil
    // Pets Social, pas de bucket dédié à créer pour ce volume).
    final photoUrls = <String>[];
    final uid = User_Info.uid;
    for (var i = 0; i < _photos.length; i++) {
      try {
        final compressed = await FlutterImageCompress.compressWithFile(
          _photos[i].path, quality: 78, minWidth: 1280, minHeight: 1280, keepExif: false,
        );
        final bytes = compressed ?? await _photos[i].readAsBytes();
        // Même forme de chemin que les uploads de post (uid en 1er segment) —
        // les policies RLS du bucket "social" s'appuient dessus.
        final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        await _supa.storage.from('social').uploadBinary(
              path, bytes,
              fileOptions: const FileOptions(contentType: 'image/jpg', upsert: false),
            );
        photoUrls.add(_supa.storage.from('social').getPublicUrl(path));
      } catch (_) {}
    }

    Map<String, dynamic>? savedRow;
    try {
      savedRow = await _supa.from('balades_perso').update({
        'statut': 'terminee',
        // toUtc() : sans fuseau, l'heure locale était stockée comme UTC (+2 h).
        'ended_at': DateTime.now().toUtc().toIso8601String(),
        'distance_m': _distanceM,
        'duree_s': duree.inSeconds,
        'route': _routeRaw,
        'photos': photoUrls,
      }).eq('id', _baladeId as Object).select().single();
    } catch (_) {}

    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => BaladeRecapPage(
        baladeId: _baladeId,
        animalId: widget.animalId,
        animalNom: widget.animalNom,
        espece: widget.espece,
        autresAnimaux: widget.autresAnimaux,
        distanceM: _distanceM,
        dureeSecondes: duree.inSeconds,
        routePoints: _routePoints,
        photoUrls: photoUrls.isNotEmpty ? photoUrls : (savedRow?['photos'] as List?)?.cast<String>() ?? const [],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingPermission) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: _teal)));
    }
    if (_permissionError != null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: _teal, foregroundColor: Colors.white,
            title: const Text('Balade', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.location_off_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(_permissionError!, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Galey')),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Geolocator.openAppSettings(),
                style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white),
                child: const Text('Ouvrir les réglages', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      );
    }

    // Balade en cours : un retour (flèche ou bouton du téléphone) propose de
    // l'abandonner au lieu de laisser une balade « en cours » fantôme.
    return PopScope(
      canPop: !_started || _finishing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _started && !_finishing) _abandonner();
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: const CameraPosition(target: LatLng(48.8566, 2.3522), zoom: 16),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          polylines: {
            Polyline(polylineId: const PolylineId('route'), points: _routePoints, color: _teal, width: 5),
          },
          onMapCreated: (c) => _mapCtrl = c,
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.maybePop(context)),
              ),
              const Spacer(),
              if (_photos.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                  child: Text('📷 ${_photos.length}', style: const TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Balade avec ${widget.animalNom}',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 14),
              if (_started)
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _stat(_distanceLabel, 'Distance'),
                  _stat(_fmtDuration(_elapsed), 'Durée'),
                  _stat(baladeVitesseLabel(_distanceM, _elapsed.inSeconds), 'Vitesse moy.'),
                ]),
              const SizedBox(height: 18),
              if (!_started)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                    label: const Text('Démarrer la balade', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: _teal, padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  ),
                )
              else
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _finishing ? null : _takePhoto,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Photo', style: TextStyle(fontFamily: 'Galey')),
                      style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal),
                          padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _finishing ? null : _togglePause,
                      icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                      label: Text(_paused ? 'Reprendre' : 'Pause', style: const TextStyle(fontFamily: 'Galey')),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.orange.shade800, side: BorderSide(color: Colors.orange.shade800),
                          padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _finishing ? null : _stop,
                      icon: _finishing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.stop_rounded, color: Colors.white),
                      label: const Text('Stop', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    ),
                  ),
                ]),
            ]),
          ),
        ),
      ]),
      ),
    );
  }

  Widget _stat(String value, String label) => Column(children: [
        Text(value, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 22, color: _teal)),
        Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
      ]);
}
