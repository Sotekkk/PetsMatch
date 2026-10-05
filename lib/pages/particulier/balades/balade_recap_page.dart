import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/services/gamification_service.dart';
import 'package:PetsMatch/pages/particulier/social_feed_page.dart' show openCreatePostSheet;
import 'package:PetsMatch/pages/particulier/stories/story_create_page.dart';
import 'package:PetsMatch/pages/particulier/balades/balade_utils.dart';

/// Récap de fin de balade : enregistre XP/palier/flamme (GamificationService)
/// puis propose un partage explicite (Story ou Post) qui déclenche la 2e
/// flamme (share_streak_*). Rien n'est publié sur Pets Social sans ce choix
/// (plus de post automatique depuis le 29/09/2026).
class BaladeRecapPage extends StatefulWidget {
  final String? baladeId;
  final String animalId;
  final String animalNom;
  final String espece;
  final double distanceM;
  final int dureeSecondes;
  final List<LatLng> routePoints;
  final List<String> photoUrls;
  // true = simple consultation d'une balade déjà enregistrée (historique) :
  // n'appelle PAS GamificationService.recordBalade, sinon l'XP/flamme/post
  // automatique seraient recréés à chaque ouverture de l'historique.
  final bool alreadySaved;
  final int? existingXpEarned;
  /// Autres animaux de la balade (id, nom, espece) : XP / flamme pour chacun
  /// et tous tagués au partage.
  final List<Map<String, dynamic>> autresAnimaux;

  const BaladeRecapPage({
    super.key,
    required this.baladeId,
    required this.animalId,
    required this.animalNom,
    required this.espece,
    required this.distanceM,
    required this.dureeSecondes,
    required this.routePoints,
    required this.photoUrls,
    this.alreadySaved = false,
    this.existingXpEarned,
    this.autresAnimaux = const [],
  });

  @override
  State<BaladeRecapPage> createState() => _BaladeRecapPageState();
}

class _BaladeRecapPageState extends State<BaladeRecapPage> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;
  final _shareCardKey = GlobalKey();

  bool _saving = true;
  BaladeResult? _result;
  bool _shared = false;
  bool _sharing = false;

  // Vue du parcours sur la carte-récap : synthétique (tracé stylisé) ou
  // vraie carte. La GoogleMap est une platform view que RepaintBoundary ne
  // sait pas capturer → on en prend un instantané (takeSnapshot) affiché à
  // sa place, c'est lui qui part dans la Story/le Post.
  bool _vueCarte = false;
  GoogleMapController? _mapCtrl;
  Uint8List? _mapSnapshot;
  bool _withPhotos = true;
  bool _deleting = false;
  // Passage de palier : publication sur Pets Social au choix (plus automatique).
  bool _evolutionPosting = false;
  bool _evolutionPosted = false;

  Future<void> _partagerEvolution() async {
    final r = _result;
    if (r == null || _evolutionPosting || _evolutionPosted) return;
    setState(() => _evolutionPosting = true);
    try {
      await GamificationService.instance.publishEvolutionPost(
        uid: User_Info.uid,
        profileId: User_Info.activeProfileId,
        animalId: widget.animalId,
        animalNom: widget.animalNom,
        newTier: r.newTier,
      );
      if (mounted) setState(() { _evolutionPosting = false; _evolutionPosted = true; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _evolutionPosting = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Publication impossible, réessayez.', style: TextStyle(fontFamily: 'Galey'))));
    }
  }

  /// Supprime la balade (XP, post automatique, photos compris — voir
  /// supprimerBalade) puis ferme le récap ; renvoie true à l'historique
  /// pour qu'il se recharge.
  Future<void> _supprimer() async {
    final id = widget.baladeId;
    if (id == null || _deleting) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer cette balade ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('L\'XP gagnée et les photos de la balade seront retirées (ainsi que sa publication automatique pour les anciennes balades). '
            'Les posts ou stories que vous avez partagés vous-même restent en ligne.',
            style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await supprimerBalade(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Balade supprimée', style: TextStyle(fontFamily: 'Galey'))));
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Suppression impossible, réessayez.', style: TextStyle(fontFamily: 'Galey'))));
    }
  }

  bool get _canShowMap => widget.routePoints.length >= 2;
  bool get _hasPhotos => widget.photoUrls.isNotEmpty;

  String get _distanceLabel => widget.distanceM >= 1000
      ? '${(widget.distanceM / 1000).toStringAsFixed(2)} km'
      : '${widget.distanceM.toStringAsFixed(0)} m';

  String get _dureeLabel {
    final d = Duration(seconds: widget.dureeSecondes);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '$m min';
  }

  @override
  void initState() {
    super.initState();
    if (widget.alreadySaved) {
      _shared = true; // historique : pas de nouvelle 2e flamme à chaque consultation
      _saving = false;
    } else {
      _save();
    }
  }

  Future<void> _save() async {
    try {
      final result = await GamificationService.instance.recordBalade(
        uid: User_Info.uid,
        profileId: User_Info.activeProfileId,
        animalId: widget.animalId,
        espece: widget.espece,
        distanceKm: widget.distanceM > 0 ? widget.distanceM / 1000 : null,
        dureeMinutes: widget.dureeSecondes > 0 ? (widget.dureeSecondes / 60).round() : null,
      );
      // Chaque autre animal de la balade gagne aussi son XP / sa flamme.
      for (final a in widget.autresAnimaux) {
        try {
          await GamificationService.instance.recordBalade(
            uid: User_Info.uid,
            profileId: User_Info.activeProfileId,
            animalId: a['id'].toString(),
            espece: a['espece']?.toString() ?? widget.espece,
            distanceKm: widget.distanceM > 0 ? widget.distanceM / 1000 : null,
            dureeMinutes: widget.dureeSecondes > 0 ? (widget.dureeSecondes / 60).round() : null,
          );
        } catch (_) {}
      }
      if (widget.baladeId != null) {
        try {
          await _supa.from('balades_perso').update({'xp_earned': result.xpEarned}).eq('id', widget.baladeId as Object);
        } catch (_) {}
      }
      if (mounted) setState(() { _result = result; _saving = false; });
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  LatLngBounds _routeBounds() {
    final pts = widget.routePoints;
    var minLat = pts.first.latitude, maxLat = pts.first.latitude;
    var minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    // Parcours quasi immobile : évite des bornes nulles (zoom infini).
    const eps = 0.0008;
    if (maxLat - minLat < eps) { minLat -= eps; maxLat += eps; }
    if (maxLng - minLng < eps) { minLng -= eps; maxLng += eps; }
    return LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
  }

  Future<void> _onMapCreated(GoogleMapController c) async {
    _mapCtrl = c;
    // Laisse la vue se dimensionner avant de cadrer, puis les tuiles charger.
    await Future.delayed(const Duration(milliseconds: 350));
    try { await c.moveCamera(CameraUpdate.newLatLngBounds(_routeBounds(), 28)); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 1200));
    await _takeMapSnapshot();
  }

  Future<void> _takeMapSnapshot() async {
    final c = _mapCtrl;
    if (c == null) return;
    try {
      final bytes = await c.takeSnapshot();
      if (bytes != null && mounted) setState(() => _mapSnapshot = bytes);
    } catch (_) {}
  }

  Widget _routeView() {
    if (!_vueCarte || !_canShowMap) {
      return SizedBox(height: 140, width: double.infinity,
          child: CustomPaint(painter: _RoutePainter(widget.routePoints)));
    }
    final snap = _mapSnapshot;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 200,
        width: double.infinity,
        child: snap != null
            ? Image.memory(snap, fit: BoxFit.cover, gaplessPlayback: true)
            : GoogleMap(
                initialCameraPosition: CameraPosition(target: widget.routePoints.first, zoom: 15),
                onMapCreated: _onMapCreated,
                polylines: {
                  Polyline(polylineId: const PolylineId('route'), points: widget.routePoints,
                      color: _teal, width: 5),
                },
                markers: {
                  Marker(markerId: const MarkerId('start'), position: widget.routePoints.first,
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)),
                  Marker(markerId: const MarkerId('end'), position: widget.routePoints.last),
                },
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
                scrollGesturesEnabled: false,
                zoomGesturesEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
              ),
      ),
    );
  }

  /// Photos de la balade (cache local, déjà téléchargées pour l'affichage)
  /// jointes au Post après la carte-récap — 10 images max par post.
  Future<List<File>> _photoFiles() async {
    final out = <File>[];
    for (final url in widget.photoUrls.take(9)) {
      try {
        out.add(await DefaultCacheManager().getSingleFile(url));
      } catch (_) {}
    }
    return out;
  }

  /// Capture la carte-récap (widget Flutter pur — la GoogleMap y est
  /// remplacée par son instantané) en fichier image temporaire, pour Story/Post.
  Future<File?> _captureShareCard() async {
    if (_vueCarte && _canShowMap && _mapSnapshot == null) {
      await _takeMapSnapshot();
      if (_mapSnapshot == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('La carte est encore en chargement, réessaie dans un instant.',
                  style: TextStyle(fontFamily: 'Galey'))));
        }
        return null;
      }
    }
    // Les vignettes photo doivent être peintes avant la capture.
    if (_withPhotos && _hasPhotos) {
      for (final url in widget.photoUrls.take(3)) {
        if (!mounted) return null;
        try { await precacheImage(CachedNetworkImageProvider(url), context); } catch (_) {}
      }
      await WidgetsBinding.instance.endOfFrame;
    }
    try {
      final boundary = _shareCardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return null;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/balade_share_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<void> _markShared({required bool story, required bool post}) async {
    if (_shared) return; // 2e flamme une seule fois par balade, même si Story ET Post
    _shared = true;
    try {
      final pid = User_Info.activeProfileId;
      if (pid.isNotEmpty) await GamificationService.instance.applyShareStreak(pid);
      if (widget.baladeId != null) {
        await _supa.from('balades_perso').update({
          if (story) 'partage_story': true,
          if (post) 'partage_post': true,
        }).eq('id', widget.baladeId as Object);
      }
    } catch (_) {}
  }

  Future<void> _shareStory() async {
    setState(() => _sharing = true);
    final file = await _captureShareCard();
    if (!mounted) return;
    setState(() => _sharing = false);
    if (file == null) return;
    final uid = User_Info.uid;
    final pid = User_Info.activeProfileId;
    if (uid.isEmpty || pid.isEmpty) return;
    final posted = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => StoryCreatePage(
        myUid: uid,
        authorProfileId: pid,
        initialMediaFile: file,
        initialLegende: '🚶 Balade avec ${widget.animalNom} — $_distanceLabel',
      ),
    ));
    if (posted == true) await _markShared(story: true, post: false);
  }

  Future<void> _sharePost() async {
    setState(() => _sharing = true);
    final file = await _captureShareCard();
    if (!mounted) return;
    setState(() => _sharing = false);
    if (file == null) return;
    final uid = User_Info.uid;
    if (uid.isEmpty) return;
    setState(() => _sharing = true);
    final photos = _withPhotos ? await _photoFiles() : <File>[];
    if (!mounted) return;
    setState(() => _sharing = false);
    final posted = await openCreatePostSheet(
      context,
      myUid: uid,
      initialText: '🚶 Balade avec ${widget.animalNom} — $_distanceLabel en $_dureeLabel',
      initialImages: [file, ...photos],
      initialTaggedAnimalIds: {widget.animalId, ...widget.autresAnimaux.map((a) => a['id'].toString())},
    );
    if (posted == true) await _markShared(story: false, post: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: const Text('Balade terminée', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          // Après l'enregistrement (XP connue) — sinon on supprimerait avant
          // que recordBalade ait fini d'écrire XP/post.
          if (widget.baladeId != null && !_saving)
            IconButton(
              tooltip: 'Supprimer la balade',
              onPressed: _deleting ? null : _supprimer,
              icon: _deleting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: _saving
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                if (_canShowMap) ...[
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, icon: Icon(Icons.gesture, size: 18),
                            label: Text('Synthétique', style: TextStyle(fontFamily: 'Galey'))),
                        ButtonSegment(value: true, icon: Icon(Icons.map_outlined, size: 18),
                            label: Text('Carte', style: TextStyle(fontFamily: 'Galey'))),
                      ],
                      selected: {_vueCarte},
                      onSelectionChanged: (s) => setState(() => _vueCarte = s.first),
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: _teal, selectedForegroundColor: Colors.white,
                        foregroundColor: _teal,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                RepaintBoundary(key: _shareCardKey, child: _ShareCard(
                  animalNom: widget.animalNom,
                  distanceLabel: _distanceLabel,
                  dureeLabel: _dureeLabel,
                  vitesseLabel: baladeVitesseLabel(widget.distanceM, widget.dureeSecondes),
                  routeView: _routeView(),
                  photoUrls: _withPhotos ? widget.photoUrls : const [],
                )),
                if (_hasPhotos)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _withPhotos,
                    activeThumbColor: _teal,
                    onChanged: (v) => setState(() => _withPhotos = v),
                    title: const Text('Ajouter mes photos',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text('Sur la carte-récap et jointes au post',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                  ),
                const SizedBox(height: 16),
                if (_result != null)
                  _xpCard()
                else if (widget.existingXpEarned != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: const Color(0xFFEAF2F4), borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      const Text('⭐', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Text('+${widget.existingXpEarned} XP gagnés', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                    ]),
                  ),
                const SizedBox(height: 24),
                const Align(alignment: Alignment.centerLeft, child: Text('Partager la balade',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15))),
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerLeft, child: Text('🔥 Gagne une 2e flamme en partageant',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade600))),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _sharing ? null : _shareStory,
                      icon: const Icon(Icons.auto_stories_outlined),
                      label: const Text('Story', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal),
                          padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _sharing ? null : _sharePost,
                      icon: const Icon(Icons.dynamic_feed_outlined),
                      label: const Text('Post', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal),
                          padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                    child: Text('Terminer', style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade600)),
                  ),
                ),
              ]),
            ),
    );
  }

  Widget _xpCard() {
    final r = _result!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFEAF2F4), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('⭐', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text('+${r.xpEarned} XP', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
          if (r.tierEvolved) ...[
            const SizedBox(width: 8),
            Text('✨ Palier ${GamificationService.tierLabel(r.newTier)} !', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _teal)),
          ],
        ]),
        if (r.tierEvolved) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: _evolutionPosted
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('✓ Évolution partagée sur Pets Social',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _teal, fontWeight: FontWeight.w600)),
                  )
                : TextButton.icon(
                    onPressed: _evolutionPosting ? null : _partagerEvolution,
                    style: TextButton.styleFrom(foregroundColor: _teal, padding: EdgeInsets.zero),
                    icon: _evolutionPosting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _teal))
                        : const Icon(Icons.dynamic_feed_outlined, size: 16),
                    label: const Text('Partager l\'évolution sur Pets Social',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
          ),
        ],
        if (r.streakCount > 0) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Text('🔥', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text('${r.streakCount} jour${r.streakCount > 1 ? 's' : ''} de suite', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700)),
          ]),
        ],
      ]),
    );
  }

}

/// Carte-récap — utilisée à l'écran ET capturée en image pour le partage
/// Story/Post. `routeView` = tracé synthétique ou instantané de la carte.
class _ShareCard extends StatelessWidget {
  final String animalNom;
  final String distanceLabel;
  final String dureeLabel;
  final String vitesseLabel;
  final Widget routeView;
  final List<String> photoUrls;

  const _ShareCard({
    required this.animalNom,
    required this.distanceLabel,
    required this.dureeLabel,
    required this.vitesseLabel,
    required this.routeView,
    required this.photoUrls,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF0C5C6C), Color(0xFF14879E)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: [
        Row(children: [
          const Text('🐾', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Expanded(child: Text('Balade avec $animalNom',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17, color: Colors.white))),
        ]),
        const SizedBox(height: 14),
        routeView,
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _stat(distanceLabel, 'Distance'),
          _stat(dureeLabel, 'Durée'),
          _stat(vitesseLabel, 'Vitesse moy.'),
        ]),
        if (photoUrls.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(children: [
            for (int i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: i < photoUrls.length ? _thumb(i) : const SizedBox(),
                ),
              ),
            ],
          ]),
        ],
      ]),
    );
  }

  Widget _thumb(int i) {
    final extra = photoUrls.length - 3;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(fit: StackFit.expand, children: [
        CachedNetworkImage(imageUrl: photoUrls[i], fit: BoxFit.cover),
        if (i == 2 && extra > 0)
          Container(
            color: Colors.black45,
            alignment: Alignment.center,
            child: Text('+$extra', style: const TextStyle(fontFamily: 'Galey',
                fontWeight: FontWeight.w800, fontSize: 20, color: Colors.white)),
          ),
      ]),
    );
  }

  Widget _stat(String value, String label) => Column(children: [
        Text(value, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 20, color: Colors.white)),
        Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white70)),
      ]);
}

/// Trace stylisée du parcours normalisée dans le rectangle disponible — pas
/// de fond de carte (évite la capture ratée des platform views GoogleMap).
class _RoutePainter extends CustomPainter {
  final List<LatLng> points;
  _RoutePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.white.withValues(alpha: 0.12);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)), bg);

    if (points.length < 2) {
      final dot = Paint()..color = Colors.white;
      canvas.drawCircle(size.center(Offset.zero), 6, dot);
      return;
    }

    var minLat = points.first.latitude, maxLat = points.first.latitude;
    var minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final latSpan = (maxLat - minLat).abs().clamp(0.0001, 999).toDouble();
    final lngSpan = (maxLng - minLng).abs().clamp(0.0001, 999).toDouble();
    const pad = 16.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;

    Offset toOffset(LatLng p) {
      final x = pad + ((p.longitude - minLng) / lngSpan) * w;
      final y = pad + h - ((p.latitude - minLat) / latSpan) * h;
      return Offset(x, y);
    }

    final path = Path()..moveTo(toOffset(points.first).dx, toOffset(points.first).dy);
    for (final p in points.skip(1)) {
      final o = toOffset(p);
      path.lineTo(o.dx, o.dy);
    }
    final linePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    final endDot = Paint()..color = const Color(0xFFFFD166);
    canvas.drawCircle(toOffset(points.last), 6, endDot);
    final startDot = Paint()..color = Colors.white;
    canvas.drawCircle(toOffset(points.first), 5, startDot);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) => oldDelegate.points != points;
}
