import 'package:PetsMatch/pages/pro/garde_fiche_animal_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/geocoding_helper.dart';
import 'package:PetsMatch/pages/pro/visite_rapport_sheet.dart';

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

      // Visites du jour + visites des jours précédents encore « confirmées »
      // (pas marquées terminées) : elles restent à clôturer, comme dans
      // l'agenda, au lieu de disparaître de la tournée. 30 jours en arrière.
      final depuis = startOfDay.subtract(const Duration(days: 30));
      // Visites terminées du jour gardées aussi (terminées / restantes).
      final rows = await _supa.from('rdv').select()
          .eq('pro_uid', uid).eq('pro_profile_id', pid)
          .inFilter('statut', ['confirme', 'termine'])
          .gte('date_heure', depuis.toIso8601String())
          .lte('date_heure', endOfDay.toIso8601String())
          .order('date_heure');
      final list = List<Map<String, dynamic>>.from(rows as List).where((r) {
        final d = DateTime.tryParse(r['date_heure']?.toString() ?? '');
        return r['statut'] == 'confirme' || (d != null && !d.isBefore(startOfDay));
      }).toList();
      for (final r in list) {
        final d = DateTime.tryParse(r['date_heure']?.toString() ?? '');
        r['_a_cloturer'] = r['statut'] == 'confirme' && d != null && d.isBefore(startOfDay);
        r['_termine'] = r['statut'] == 'termine';
      }
      // Clés en ma possession (gestion des clés existante) — jamais de code affiché.
      try {
        final cles = await _supa.from('cles_clients').select('animal_id, owner_uid, description')
            .eq('pro_profile_id', pid).eq('statut', 'en_possession');
        for (final r in list) {
          for (final c in cles as List) {
            if ((c['animal_id'] != null && c['animal_id'].toString() == r['animal_id']?.toString()) ||
                (c['owner_uid'] != null && c['owner_uid'].toString() == r['client_uid']?.toString())) {
              r['_cle'] = c['description']?.toString() ?? 'Clé';
              break;
            }
          }
        }
      } catch (_) {}

      final clientUids = list.map((r) => r['client_uid'] as String?).whereType<String>().toSet().toList();
      final animalIds = list.map((r) => r['animal_id']?.toString()).whereType<String>().where((s) => s.isNotEmpty).toSet().toList();

      final results = await Future.wait([
        clientUids.isNotEmpty
            ? _supa.from('user_profiles_complet').select('uid, firstname, lastname, nom').inFilter('uid', clientUids).eq('is_main', true)
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
        // Visites à clôturer (jours précédents) en tête, puis l'ordre du jour,
        // les visites déjà terminées en fin de liste.
        final ca = a['_a_cloturer'] == true, cb = b['_a_cloturer'] == true;
        if (ca != cb) return ca ? -1 : 1;
        final ta = a['_termine'] == true, tb = b['_termine'] == true;
        if (ta != tb) return ta ? 1 : -1;
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

  Future<void> _valider(Map<String, dynamic> rdv) async {
    try {
      await _supa.from('rdv').update({
        'statut': 'termine',
        // Fin effective (rdv.date_heure, l'heure prévue, n'est pas modifiée).
        'depart_valide_le': DateTime.now().toUtc().toIso8601String(),
        'termine_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', rdv['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Visite marquée terminée.', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Color(0xFF6E9E57),
          behavior: SnackBarBehavior.floating,
        ));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red));
      }
    }
  }

  void _openFiche(Map<String, dynamic> rdv) {
    final animalId = rdv['animal_id']?.toString() ?? '';
    if (animalId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Cette visite n\'est pas rattachée à une fiche animal.',
            style: TextStyle(fontFamily: 'Galey')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    Navigator.push(context, MaterialPageRoute(
      // Fiche pet-sitter (avant : fiche en mode propriétaire complet).
      builder: (_) => GardeFicheAnimalPage(animalId: animalId, animalNom: rdv['_animal_nom']?.toString() ?? 'Animal'),
    ));
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
                        onValider: () => _valider(_visites[i]),
                        onOpen: () => _openFiche(_visites[i]),
                        onNouvelles: () => sendGardeNews(context, _visites[i]),
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
  final VoidCallback onValider;
  final VoidCallback onOpen;
  final VoidCallback onNouvelles;
  static const _teal = Color(0xFF0C5C6C);

  const _VisiteTile({
    super.key,
    required this.index,
    required this.rdv,
    required this.onAddAddress,
    required this.onValider,
    required this.onOpen,
    required this.onNouvelles,
  });

  @override
  Widget build(BuildContext context) {
    final dh = DateTime.tryParse(rdv['date_heure']?.toString() ?? '')?.toLocal();
    // Visite d'un jour précédent non clôturée : date + « À clôturer ».
    final aCloturer = rdv['_a_cloturer'] == true;
    final termine = rdv['_termine'] == true;
    final consignes = (rdv['notes_client']?.toString() ?? '').trim();
    final heure = dh == null ? '' : aCloturer
        ? '${DateFormat('d MMM · HH:mm', 'fr_FR').format(dh)} — à clôturer'
        : DateFormat('HH:mm').format(dh);
    final lieu = rdv['lieu']?.toString() ?? '';
    final geocoded = rdv['lieu_lat'] != null && rdv['lieu_lng'] != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: _teal.withValues(alpha: 0.1),
              child: Text('${index + 1}',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _teal)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text('${rdv['_animal_nom']} — ${rdv['_client_nom']}',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14,
                          color: termine ? Colors.grey : null,
                          decoration: termine ? TextDecoration.lineThrough : null))),
                  if (rdv['_cle'] != null) ...[
                    const SizedBox(width: 6),
                    Tooltip(message: 'Clé en ma possession : ${rdv['_cle']}',
                        child: const Icon(Icons.vpn_key_outlined, size: 15, color: Color(0xFFB8860B))),
                  ],
                ]),
                const SizedBox(height: 2),
                Row(children: [
                  Text(heure, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      color: aCloturer ? const Color(0xFFB45309) : Colors.grey,
                      fontWeight: aCloturer ? FontWeight.w700 : FontWeight.normal)),
                  const SizedBox(width: 8),
                  if (lieu.isNotEmpty)
                    Expanded(
                      child: GestureDetector(
                        onTap: onAddAddress,
                        child: Row(children: [
                          Flexible(
                            child: Text(lieu,
                                style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                                    color: geocoded ? Colors.grey.shade700 : Colors.orange.shade800),
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (!geocoded) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.edit_location_alt_outlined, size: 13, color: Colors.orange.shade800),
                          ],
                        ]),
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: onAddAddress,
                      child: const Text('+ Ajouter une adresse',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _teal,
                              decoration: TextDecoration.underline)),
                    ),
                ]),
                if (consignes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Consignes : $consignes', maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
                  ),
              ]),
            ),
            IconButton(
              onPressed: onNouvelles,
              tooltip: 'Envoyer des nouvelles',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.photo_camera_outlined, color: _teal),
            ),
            termine
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Tooltip(message: 'Terminée', child: Icon(Icons.check_circle, color: Color(0xFF6E9E57))),
                  )
                : IconButton(
                    onPressed: onValider,
                    tooltip: 'Marquer terminée',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.check_circle_outline, color: Color(0xFF6E9E57)),
                  ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.drag_handle, color: Colors.grey),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
