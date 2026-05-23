import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:PetsMatch/pages/chatScreen.dart';

class AnimauxPerdusPage extends StatefulWidget {
  final String? initialAlertId;
  const AnimauxPerdusPage({super.key, this.initialAlertId});

  @override
  State<AnimauxPerdusPage> createState() => _AnimauxPerdusPageState();
}

class _AnimauxPerdusPageState extends State<AnimauxPerdusPage>
    with SingleTickerProviderStateMixin {
  static const _orange = Color(0xFFE65100);

  late TabController _tabController;
  List<Map<String, dynamic>> _alertes = [];
  bool _loading = true;
  GoogleMapController? _mapController;
  bool _locating = false;

  // Filtres
  String? _filterEspece;
  String _searchLieu = '';

  static const _especes = [
    'tous', 'chien', 'chat', 'lapin', 'oiseau', 'nac',
    'cheval', 'ovin', 'caprin', 'porcin', 'autre'
  ];

  List<Map<String, dynamic>> get _filtered {
    return _alertes.where((a) {
      if (_filterEspece != null && _filterEspece != 'tous') {
        if ((a['espece'] as String? ?? '') != _filterEspece) return false;
      }
      if (_searchLieu.isNotEmpty) {
        final loc = (a['derniere_localisation'] as String? ?? '').toLowerCase();
        if (!loc.contains(_searchLieu.toLowerCase())) return false;
      }
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await Supabase.instance.client
          .from('alertes_perdus')
          .select()
          .eq('statut', 'perdu')
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _alertes = List<Map<String, dynamic>>.from(rows as List);
          _loading = false;
        });
        if (widget.initialAlertId != null) {
          final target = _alertes.firstWhere(
            (a) => a['id'] == widget.initialAlertId,
            orElse: () => {},
          );
          if (target.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _showAlertDetail(target));
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAlertDetail(Map<String, dynamic> a) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AlertDetailSheet(
        alerte: a,
        onShare: () { Navigator.pop(context); _share(a); },
        onContact: () { Navigator.pop(context); _contact(a); },
      ),
    );
  }

  Future<void> _share(Map<String, dynamic> a) async {
    final nom     = (a['nom_animal'] ?? 'Animal') as String;
    final espece  = (a['espece'] ?? '') as String;
    final lieu    = (a['derniere_localisation'] ?? '') as String;
    final dateStr = a['date_perte'] as String?;
    final date    = dateStr != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(dateStr))
        : '';
    final desc    = (a['description'] as String?) ?? '';
    final contact = (a['contact'] as String?) ?? '';
    final numero  = (a['numero_alerte'] as String?) ?? '';
    final photoUrl = a['photo_url'] as String?;

    final text = [
      'ANIMAL PERDU — $nom ($espece)${numero.isNotEmpty ? ' [N° $numero]' : ''}',
      if (lieu.isNotEmpty) 'Dernière localisation : $lieu',
      if (date.isNotEmpty) 'Disparu le $date',
      if (desc.isNotEmpty) desc,
      if (contact.isNotEmpty) 'Contact : $contact',
      'Si vous l\'avez vu, signalez-le sur l\'app PetsMatch',
    ].join('\n');

    if (photoUrl != null && photoUrl.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(photoUrl));
        final tempPath = '${Directory.systemTemp.path}/alert_${a['id']}.jpg';
        await File(tempPath).writeAsBytes(response.bodyBytes);
        await Share.shareXFiles([XFile(tempPath)], text: text);
        return;
      } catch (_) {}
    }
    Share.share(text);
  }

  Future<void> _contact(Map<String, dynamic> a) async {
    final ownerId = a['uid_proprietaire'] as String?;
    if (ownerId == null) return;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;
    if (currentUid == ownerId) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('C\'est votre propre alerte')));
      return;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      // Find existing conversation
      final existing = await firestore
          .collection('conversations')
          .where('participants', arrayContains: currentUid)
          .get();

      String? conversationId;
      for (final doc in existing.docs) {
        final participants = List<String>.from(doc.data()['participants'] ?? []);
        if (participants.contains(ownerId)) {
          conversationId = doc.id;
          break;
        }
      }

      // Create if not found
      bool isNew = false;
      if (conversationId == null) {
        final nom = a['nom_animal'] as String? ?? 'Animal';
        final docRef = await firestore.collection('conversations').add({
          'participants': [currentUid, ownerId],
          'lastMessage': '',
          'timestamp': FieldValue.serverTimestamp(),
          'unreadCount': {currentUid: 0, ownerId: 0},
        });
        conversationId = docRef.id;
        isNew = true;
      }

      if (!mounted) return;
      final alerteId = a['id'] as String? ?? a['alerte_id'] as String?;
      final nomAnimal = a['nom_animal'] as String?;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: conversationId!,
          eleveurId: ownerId,
          alerteId: alerteId,
          nomAnimal: nomAnimal,
          isNewConversation: isNew,
        ),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _recenterMap() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.medium));
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
            target: LatLng(pos.latitude, pos.longitude), zoom: 12),
      ));
    } catch (_) {
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _orange,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Animaux perdus',
            style: TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt_outlined), text: 'Liste'),
            Tab(icon: Icon(Icons.map_outlined), text: 'Carte'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _orange))
          : TabBarView(
              controller: _tabController,
              children: [
                RefreshIndicator(
                  onRefresh: _load,
                  color: _orange,
                  child: _buildList(),
                ),
                _buildMap(),
              ],
            ),
    );
  }

  Widget _buildList() {
    final list = _filtered;
    return Column(children: [
      _buildFilters(),
      Expanded(
        child: list.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.search_off, size: 60, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('Aucun résultat',
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 16,
                          color: Colors.grey.shade500)),
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: list.length,
                itemBuilder: (_, i) =>
                    _AlertCard(alerte: list[i], onShare: () => _share(list[i]), onContact: () => _contact(list[i])),
              ),
      ),
    ]);
  }

  Widget _buildFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(children: [
        SizedBox(
          height: 38,
          child: TextField(
            onChanged: (v) => setState(() => _searchLieu = v),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Rechercher par ville, lieu…',
              hintStyle: const TextStyle(
                  fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
              prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: _orange)),
              filled: true,
              fillColor: const Color(0xFFF8F8F8),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _especes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final e = _especes[i];
              final selected = e == 'tous'
                  ? (_filterEspece == null || _filterEspece == 'tous')
                  : _filterEspece == e;
              return GestureDetector(
                onTap: () => setState(
                    () => _filterEspece = (e == 'tous') ? null : e),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: selected ? _orange : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    e[0].toUpperCase() + e.substring(1),
                    style: TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : Colors.black87),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _buildMap() {
    final list = _filtered;
    final markers = <Marker>{};
    for (final a in list) {
      final lat = (a['lat'] as num?)?.toDouble();
      final lng = (a['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      markers.add(Marker(
        markerId: MarkerId(a['id'].toString()),
        position: LatLng(lat, lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(
          title: '${a['nom_animal']} (${a['espece'] ?? ''})',
          snippet: a['derniere_localisation'] as String? ?? '',
        ),
      ));
    }

    return Column(children: [
      _buildFilters(),
      Expanded(
        child: Stack(children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(46.603354, 1.888334),
              zoom: 5.5,
            ),
            markers: markers,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            onMapCreated: (c) => _mapController = c,
          ),
          // Recenter button
          Positioned(
            right: 12,
            bottom: 100,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              backgroundColor: Colors.white,
              onPressed: _locating ? null : _recenterMap,
              child: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _orange))
                  : const Icon(Icons.my_location, color: _orange, size: 20),
            ),
          ),
          // No coords warning if markers is empty but there are alerts
          if (markers.isEmpty && list.isNotEmpty)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Text(
                  'Certaines alertes n\'ont pas de coordonnées GPS et n\'apparaissent pas sur la carte.',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 12,
                      color: Colors.orange.shade800),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ]),
      ),
    ]);
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _AlertCard extends StatelessWidget {
  final Map<String, dynamic> alerte;
  final VoidCallback onShare;
  final VoidCallback onContact;

  const _AlertCard({required this.alerte, required this.onShare, required this.onContact});

  @override
  Widget build(BuildContext context) {
    final nom      = (alerte['nom_animal'] ?? '') as String;
    final espece   = (alerte['espece'] ?? '') as String;
    final sexe     = (alerte['sexe'] as String?) ?? '';
    final race     = (alerte['race'] ?? '') as String;
    final lieu     = (alerte['derniere_localisation'] ?? '') as String;
    final photoUrl = alerte['photo_url'] as String?;
    final desc     = alerte['description'] as String?;
    final contact  = (alerte['contact'] as String?) ?? '';
    final numero   = (alerte['numero_alerte'] as String?) ?? '';
    final dateStr  = alerte['date_perte'] as String?;
    final date     = dateStr != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(dateStr))
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200, width: 1.2),
        boxShadow: [
          BoxShadow(
              color: Colors.orange.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 72,
              height: 72,
              child: photoUrl != null && photoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photoUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _placeholder(),
                      errorWidget: (_, __, ___) => _placeholder())
                  : _placeholder(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      borderRadius: BorderRadius.circular(20)),
                  child: const Text('PERDU',
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(nom,
                      style: const TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Color(0xFF1F2A2E)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
              const SizedBox(height: 3),
              Text(
                [espece, if (race.isNotEmpty) race, if (sexe.isNotEmpty) sexe].join(' · '),
                style: const TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 12,
                    color: Color(0xFF6F767B)),
              ),
              if (lieu.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.location_on_outlined,
                      size: 12, color: Colors.orange),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(lieu,
                        style: const TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 11,
                            color: Color(0xFF6F767B)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ],
              if (date.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('Disparu le $date',
                    style: TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 11,
                        color: Colors.orange.shade700)),
              ],
              if (desc != null && desc.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(desc,
                    style: const TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 12,
                        color: Color(0xFF4A5568)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
              if (contact.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.phone_outlined,
                      size: 12, color: Color(0xFF6F767B)),
                  const SizedBox(width: 4),
                  Text(contact,
                      style: const TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 11,
                          color: Color(0xFF6F767B))),
                ]),
              ],
              if (numero.isNotEmpty)
                Text('N° $numero',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                        color: Colors.orange.shade400, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                OutlinedButton.icon(
                  onPressed: onContact,
                  icon: const Icon(Icons.message_outlined, size: 14),
                  label: const Text('Contacter',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0C5C6C),
                    side: const BorderSide(color: Color(0xFF0C5C6C)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.share, size: 14),
                  label: const Text('Partager',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade700,
                    side: BorderSide(color: Colors.orange.shade300),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: Colors.orange.shade50,
        child: Center(
            child: Icon(Icons.pets, color: Colors.orange.shade200, size: 32)),
      );
}

class _AlertDetailSheet extends StatelessWidget {
  final Map<String, dynamic> alerte;
  final VoidCallback onShare;
  final VoidCallback onContact;

  const _AlertDetailSheet({required this.alerte, required this.onShare, required this.onContact});

  @override
  Widget build(BuildContext context) {
    final nom     = (alerte['nom_animal'] ?? '') as String;
    final espece  = (alerte['espece'] ?? '') as String;
    final race    = (alerte['race'] ?? '') as String;
    final sexe    = (alerte['sexe'] as String?) ?? '';
    final lieu    = (alerte['derniere_localisation'] ?? '') as String;
    final desc    = alerte['description'] as String?;
    final contact = (alerte['contact'] as String?) ?? '';
    final numero  = (alerte['numero_alerte'] as String?) ?? '';
    final photoUrl = alerte['photo_url'] as String?;
    final dateStr = alerte['date_perte'] as String?;
    final date    = dateStr != null ? DateFormat('dd/MM/yyyy').format(DateTime.parse(dateStr)) : '';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (photoUrl != null && photoUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(imageUrl: photoUrl, width: 90, height: 90, fit: BoxFit.cover),
              ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(20)),
                  child: const Text('PERDU', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(nom, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17, color: Color(0xFF1F2A2E)), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
              const SizedBox(height: 4),
              Text([espece, if (race.isNotEmpty) race, if (sexe.isNotEmpty) sexe].join(' · '),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
              if (date.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Disparu le $date', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.orange.shade700)),
              ],
            ])),
          ]),
          if (lieu.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 16, color: Colors.orange),
              const SizedBox(width: 6),
              Expanded(child: Text(lieu, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF4A5568)))),
            ]),
          ],
          if (desc != null && desc.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(desc, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF4A5568))),
          ],
          if (contact.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.phone_outlined, size: 14, color: Color(0xFF6F767B)),
              const SizedBox(width: 6),
              Text(contact, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
            ]),
          ],
          if (numero.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('N° $numero', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.orange.shade400, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onContact,
                icon: const Icon(Icons.message_outlined, size: 16),
                label: const Text('Contacter', style: TextStyle(fontFamily: 'Galey')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0C5C6C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: onShare,
              icon: const Icon(Icons.share, size: 16),
              label: const Text('Partager', style: TextStyle(fontFamily: 'Galey')),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange.shade700,
                side: BorderSide(color: Colors.orange.shade300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
