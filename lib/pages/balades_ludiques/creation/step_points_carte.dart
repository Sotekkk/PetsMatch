part of 'creation_flow_page.dart';

class _StepPointsCarte extends StatefulWidget {
  final _CreationFlowPageState s;
  const _StepPointsCarte({required this.s});

  @override
  State<_StepPointsCarte> createState() => _StepPointsCarteState();
}

class _StepPointsCarteState extends State<_StepPointsCarte> {
  GoogleMapController? _mapCtrl;

  Future<void> _recenter() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      _mapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15));
    } catch (_) {}
  }

  Future<void> _onMapTap(LatLng pos) async {
    final s = widget.s;
    final nouveauPoint = <String, dynamic>{
      'titre': 'Point ${s.points.length + 1}',
      'description': '',
      'lat': pos.latitude,
      'lng': pos.longitude,
      'rayon_validation_m': 30,
      'type_defi': 'photo',
    };
    final edite = await showPointDefiSheet(context, nouveauPoint);
    if (edite != null) setState(() => s.points.add(edite));
  }

  Future<void> _editPoint(int index) async {
    final edite = await showPointDefiSheet(context, widget.s.points[index]);
    if (edite != null) setState(() => widget.s.points[index] = edite);
  }

  void _removePoint(int index) => setState(() => widget.s.points.removeAt(index));

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final markers = <Marker>{};
    for (var i = 0; i < s.points.length; i++) {
      final p = s.points[i];
      markers.add(Marker(
        markerId: MarkerId('pt_$i'),
        position: LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
        infoWindow: InfoWindow(title: p['titre']?.toString() ?? ''),
      ));
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(children: [
          const Expanded(child: Text('Placez vos points sur la carte', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 16))),
          IconButton(icon: const Icon(Icons.my_location, color: kBlTeal), onPressed: _recenter),
        ]),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text('Touchez la carte pour ajouter une étape et configurer son défi.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 260,
        child: GoogleMap(
          initialCameraPosition: const CameraPosition(target: LatLng(46.603354, 1.888334), zoom: 5.5),
          markers: markers,
          onMapCreated: (c) => _mapCtrl = c,
          onTap: _onMapTap,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
        ),
      ),
      Expanded(
        child: s.points.isEmpty
            ? const Center(child: Padding(padding: EdgeInsets.all(24),
                child: Text('Aucun point pour l\'instant.\nTouchez la carte ci-dessus pour en ajouter un.',
                    textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Galey', color: Colors.grey))))
            : ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: s.points.length,
                onReorder: (oldIndex, newIndex) => setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = s.points.removeAt(oldIndex);
                  s.points.insert(newIndex, item);
                }),
                itemBuilder: (_, i) {
                  final p = s.points[i];
                  return Container(
                    key: ValueKey('point_$i${p['titre']}'),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)]),
                    child: ListTile(
                      leading: CircleAvatar(radius: 14, backgroundColor: kBlTeal, child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12))),
                      title: Text(p['titre']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: Row(children: [
                        Icon(blTypeDefiIcon(p['type_defi']?.toString() ?? ''), size: 13, color: kBlGreen),
                        const SizedBox(width: 4),
                        Text(blTypeDefiLabel(p['type_defi']?.toString() ?? ''), style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
                      ]),
                      onTap: () => _editPoint(i),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red), onPressed: () => _removePoint(i)),
                        const Icon(Icons.drag_handle, color: Colors.grey),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}
