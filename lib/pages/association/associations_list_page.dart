import 'package:PetsMatch/pages/association/association_detail_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AssociationsListPage extends StatefulWidget {
  const AssociationsListPage({super.key});

  @override
  State<AssociationsListPage> createState() => _AssociationsListPageState();
}

class _AssociationsListPageState extends State<AssociationsListPage> {
  static const _teal = Color(0xFF0C5C6C);

  List<Map<String, dynamic>> _all      = [];
  List<Map<String, dynamic>> _filtered = [];
  bool   _loading  = true;
  bool   _showMap  = false;
  String _search   = '';

  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // name_elevage n'existe pas dans user_profiles → utiliser nom + profile_label
      final profiles = await Supabase.instance.client
          .from('user_profiles')
          .select('id,uid,nom,profile_label,avatar_url,profile_type,ville,latitude,longitude')
          .eq('profile_type', 'association')
          .order('nom');

      List<Map<String, dynamic>> primary = [];
      try {
        primary = await Supabase.instance.client
            .from('users')
            .select('uid,firstname,lastname,name_elevage,ville,ville_elevage,photo_profil_elevage,photo_url,latitude,longitude')
            .eq('is_association', true);
      } catch (_) {}

      final list = <Map<String, dynamic>>[];

      for (final p in profiles as List) {
        final uid       = p['uid']?.toString() ?? '';
        final profileId = p['id']?.toString() ?? '';
        final nom       = (p['nom'] as String?)?.trim() ?? '';
        final label     = (p['profile_label'] as String?)?.trim() ?? '';
        final name      = nom.isNotEmpty ? nom : (label.isNotEmpty ? label : 'Association');
        list.add({
          'uid':        uid,
          'profile_id': profileId,
          'name':       name,
          'avatar':     p['avatar_url']?.toString() ?? '',
          'ville':      (p['ville'] as String?)?.trim() ?? '',
          'lat':        p['latitude'] as double?,
          'lng':        p['longitude'] as double?,
          'source':     'profile',
        });
      }

      final existingUids = list.map((e) => e['uid']?.toString()).toSet();
      for (final u in primary) {
        final uid = u['uid']?.toString() ?? '';
        if (existingUids.contains(uid)) continue;
        final name = (u['name_elevage'] as String?)?.isNotEmpty == true
            ? u['name_elevage'] as String
            : '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
        final ville = (u['ville_elevage'] as String?)?.isNotEmpty == true
            ? u['ville_elevage'] as String
            : u['ville'] as String? ?? '';
        final avatar = (u['photo_profil_elevage'] as String?)?.isNotEmpty == true
            ? u['photo_profil_elevage'] as String
            : u['photo_url'] as String? ?? '';
        list.add({
          'uid':    uid,
          'name':   name,
          'avatar': avatar,
          'ville':  ville,
          'lat':    u['latitude'] as double?,
          'lng':    u['longitude'] as double?,
          'source': 'primary',
        });
      }

      if (mounted) setState(() { _all = list; _applyFilter(); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openDetail(BuildContext ctx, Map<String, dynamic> asso) {
    final uid = asso['uid']?.toString() ?? '';
    if (uid.isEmpty) return;
    Navigator.push(ctx, MaterialPageRoute(
      builder: (_) => AssociationDetailPage(
        uid:       uid,
        profileId: asso['profile_id']?.toString(),
        name:      asso['name']?.toString()   ?? 'Association',
        avatar:    asso['avatar']?.toString() ?? '',
        ville:     asso['ville']?.toString()  ?? '',
      ),
    ));
  }

  void _applyFilter() {
    if (_search.isEmpty) {
      _filtered = List.from(_all);
    } else {
      final q = _search.toLowerCase();
      _filtered = _all.where((a) =>
        (a['name']?.toString().toLowerCase().contains(q) ?? false) ||
        (a['ville']?.toString().toLowerCase().contains(q) ?? false)
      ).toList();
    }
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Associations & Refuges',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_showMap ? Icons.list : Icons.map_outlined),
            tooltip: _showMap ? 'Liste' : 'Carte',
            onPressed: () => setState(() => _showMap = !_showMap),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() { _search = v; _applyFilter(); }),
              style: const TextStyle(color: Colors.white, fontFamily: 'Galey'),
              decoration: InputDecoration(
                hintText: 'Rechercher une association…',
                hintStyle: const TextStyle(color: Colors.white70, fontFamily: 'Galey'),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white70),
                        onPressed: () { _searchCtrl.clear(); setState(() { _search = ''; _applyFilter(); }); })
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.15),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _showMap
              ? _AssociationMapView(assos: _filtered, onTap: (a) => _openDetail(context, a))
              : _filtered.isEmpty
                  ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.favorite_border, size: 60, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('Aucune association trouvée',
                          style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
                    ]))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) => _AssoCard(
                          asso: _filtered[i],
                          onTap: () => _openDetail(context, _filtered[i]),
                        ),
                      ),
                    ),
    );
  }
}

// ─── Carte ────────────────────────────────────────────────────────────────────

class _AssociationMapView extends StatefulWidget {
  final List<Map<String, dynamic>> assos;
  final void Function(Map<String, dynamic>) onTap;
  const _AssociationMapView({required this.assos, required this.onTap});
  @override
  State<_AssociationMapView> createState() => _AssociationMapViewState();
}

class _AssociationMapViewState extends State<_AssociationMapView> {
  static const _teal = Color(0xFF0C5C6C);
  GoogleMapController? _mapCtrl;
  final Map<MarkerId, Marker> _markers = {};
  Map<String, dynamic>? _selected;
  static const LatLng _france = LatLng(46.5, 2.5);

  @override
  void initState() { super.initState(); _buildMarkers(); }

  @override
  void didUpdateWidget(_AssociationMapView old) {
    super.didUpdateWidget(old);
    if (old.assos != widget.assos) _buildMarkers();
  }

  void _buildMarkers() {
    final m = <MarkerId, Marker>{};
    for (final a in widget.assos) {
      final lat = a['lat'] as double?;
      final lng = a['lng'] as double?;
      if (lat == null || lng == null) continue;
      final id = MarkerId(a['uid']?.toString() ?? '');
      m[id] = Marker(
        markerId: id,
        position: LatLng(lat, lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
        infoWindow: InfoWindow(
          title: a['name']?.toString(),
          snippet: a['ville']?.toString(),
          onTap: () => widget.onTap(a),
        ),
        onTap: () => setState(() => _selected = a),
      );
    }
    setState(() { _markers.clear(); _markers.addAll(m); });
    _fitBounds();
  }

  Future<void> _fitBounds() async {
    if (_markers.isEmpty || _mapCtrl == null) return;
    final pos = _markers.values.map((mk) => mk.position).toList();
    if (pos.length == 1) {
      _mapCtrl!.animateCamera(CameraUpdate.newLatLngZoom(pos.first, 10));
      return;
    }
    final minLat = pos.map((p) => p.latitude ).reduce((a, b) => a < b ? a : b);
    final maxLat = pos.map((p) => p.latitude ).reduce((a, b) => a > b ? a : b);
    final minLng = pos.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    final maxLng = pos.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
    _mapCtrl!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ), 60));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      GoogleMap(
        initialCameraPosition: const CameraPosition(target: _france, zoom: 5),
        markers: Set.from(_markers.values),
        onMapCreated: (c) { _mapCtrl = c; _fitBounds(); },
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        zoomControlsEnabled: true,
        mapToolbarEnabled: false,
      ),
      Positioned(
        top: 12, left: 0, right: 0,
        child: Center(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: _teal, borderRadius: BorderRadius.circular(20)),
          child: Text(
            '${_markers.length} association${_markers.length > 1 ? "s" : ""} sur la carte',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                color: Colors.white, fontWeight: FontWeight.w600),
          ),
        )),
      ),
      if (_selected != null)
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: GestureDetector(
            onTap: () => widget.onTap(_selected!),
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12)],
              ),
              child: Row(children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFDCEDD5),
                  backgroundImage: (_selected!['avatar'] as String?)?.isNotEmpty == true
                      ? CachedNetworkImageProvider(_selected!['avatar'] as String) as ImageProvider
                      : null,
                  child: (_selected!['avatar'] as String?)?.isNotEmpty != true
                      ? const Icon(Icons.favorite, color: _teal, size: 20) : null,
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_selected!['name']?.toString() ?? '',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                  if ((_selected!['ville'] as String?)?.isNotEmpty == true)
                    Text(_selected!['ville'] as String,
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                ])),
                const Icon(Icons.chevron_right, color: _teal),
              ]),
            ),
          ),
        ),
    ]);
  }

  @override
  void dispose() { _mapCtrl?.dispose(); super.dispose(); }
}

// ─── Card liste ───────────────────────────────────────────────────────────────

class _AssoCard extends StatelessWidget {
  final Map<String, dynamic> asso;
  final VoidCallback onTap;
  static const _teal = Color(0xFF0C5C6C);
  const _AssoCard({required this.asso, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name   = asso['name']?.toString() ?? 'Association';
    final ville  = asso['ville']?.toString() ?? '';
    final avatar = asso['avatar']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: const Color(0xFFDCEDD5),
          backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) as ImageProvider : null,
          child: avatar.isEmpty ? const Icon(Icons.favorite, color: _teal, size: 24) : null,
        ),
        title: Text(name,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
        subtitle: ville.isNotEmpty
            ? Row(children: [
                const Icon(Icons.location_on_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 3),
                Text(ville, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
              ])
            : null,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _teal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text('Voir',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                  color: _teal, fontWeight: FontWeight.w600)),
        ),
        onTap: onTap,
      ),
    );
  }
}
