import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/services/service_detail_page.dart';

/// Page annuaire — liste des professionnels d'une catégorie.
class ServiceListPage extends StatefulWidget {
  final String categoryLabel;
  final Color categoryColor;
  final IconData categoryIcon;
  /// Valeurs de `cat_pro` Supabase à filtrer (ex: ['sante', 'veterinaire']).
  final List<String> catProValues;
  /// Valeurs de `profession_pro` à filtrer (optionnel — affinement).
  final List<String>? professionValues;

  const ServiceListPage({
    super.key,
    required this.categoryLabel,
    required this.categoryColor,
    required this.categoryIcon,
    required this.catProValues,
    this.professionValues,
  });

  @override
  State<ServiceListPage> createState() => _ServiceListPageState();
}

class _ServiceListPageState extends State<ServiceListPage> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _pros = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  bool _showMap = false;
  String _search = '';
  String _filterEspece = '';
  GoogleMapController? _mapCtrl;

  static const _especes = ['Toutes', 'Chien', 'Chat', 'Lapin', 'Oiseau', 'Reptile', 'Rongeur', 'Cheval', 'Autre'];

  // ── Carte ─────────────────────────────────────────────────────────────────

  double _hueForCat(String cat) => switch (cat) {
    'sante' || 'veterinaire' => BitmapDescriptor.hueAzure,
    'education'              => BitmapDescriptor.hueOrange,
    'garde'                  => BitmapDescriptor.hueGreen,
    'referencement'          => BitmapDescriptor.hueYellow,
    _                        => BitmapDescriptor.hueViolet,
  };

  Set<Marker> _buildMarkers() => _filtered
      .where((p) => p['lat'] != null && p['lng'] != null)
      .map((p) => Marker(
            markerId: MarkerId(p['uid']?.toString() ?? p.hashCode.toString()),
            position: LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
            icon: BitmapDescriptor.defaultMarkerWithHue(_hueForCat(p['cat_pro'] ?? '')),
            onTap: () => _showProSheet(p),
          ))
      .toSet();

  void _showProSheet(Map<String, dynamic> pro) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ProMapSheet(
        pro: pro,
        categoryColor: widget.categoryColor,
        categoryLabel: widget.categoryLabel,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadPros();
  }

  Future<void> _loadPros() async {
    try {
      var query = _supa.from('users').select().eq('is_pro', true);

      // Filtre sur la catégorie — on utilise le premier catProValue comme base
      if (widget.catProValues.isNotEmpty) {
        query = query.inFilter('cat_pro', widget.catProValues);
      }

      final rows = await query.order('name_elevage');
      if (mounted) {
        setState(() {
          _pros = List<Map<String, dynamic>>.from(rows);
          _filtered = _pros;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filtered = _pros.where((p) {
        final nom = ((p['name_elevage'] ?? p['firstname'] ?? '') as String).toLowerCase();
        final ville = ((p['ville_elevage'] ?? p['ville'] ?? '') as String).toLowerCase();
        final profession = ((p['profession_pro'] ?? '') as String).toLowerCase();
        final matchSearch = _search.isEmpty ||
            nom.contains(_search.toLowerCase()) ||
            ville.contains(_search.toLowerCase()) ||
            profession.contains(_search.toLowerCase());

        final especes = p['especes_acceptees'];
        final matchEspece = _filterEspece.isEmpty ||
            _filterEspece == 'Toutes' ||
            (especes is List && especes.contains(_filterEspece));

        return matchSearch && matchEspece;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: CustomScrollView(
        slivers: [
          // AppBar
          SliverAppBar(
            expandedHeight: 130,
            pinned: true,
            backgroundColor: const Color(0xFF1E2025),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Icon(_showMap ? Icons.list_rounded : Icons.map_outlined, color: Colors.white),
                tooltip: _showMap ? 'Vue liste' : 'Vue carte',
                onPressed: () => setState(() => _showMap = !_showMap),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: false,
              titlePadding: const EdgeInsets.fromLTRB(56, 0, 60, 16),
              title: Text(
                widget.categoryLabel,
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [widget.categoryColor.withValues(alpha: 0.85), const Color(0xFF1E2025)],
                      ),
                    ),
                  ),
                  Positioned(
                    right: -20, top: -10,
                    child: Icon(widget.categoryIcon, size: 130, color: Colors.white.withValues(alpha: 0.07)),
                  ),
                ],
              ),
            ),
          ),

          // Barre de recherche + filtre espèce
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                children: [
                  // Champ de recherche
                  TextField(
                    onChanged: (v) { _search = v; _applyFilters(); },
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Rechercher par nom, ville...',
                      hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                      prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFFF0F0F0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Filtres espèces
                  SizedBox(
                    height: 32,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _especes.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, i) {
                        final e = _especes[i];
                        final selected = (_filterEspece.isEmpty && e == 'Toutes') ||
                            (_filterEspece == e);
                        return GestureDetector(
                          onTap: () {
                            _filterEspece = e == 'Toutes' ? '' : e;
                            _applyFilters();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: selected ? widget.categoryColor : const Color(0xFFF0F0F0),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(e,
                              style: TextStyle(
                                fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                                color: selected ? Colors.white : const Color(0xFF555555),
                              )),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Résultats — liste ou carte
          if (_loading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: Color(0xFF6E9E57))))
          else if (_showMap)
            SliverFillRemaining(
              child: _filtered.isEmpty
                  ? Center(child: Text('Aucun professionnel avec position GPS',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade500)))
                  : GoogleMap(
                      initialCameraPosition: const CameraPosition(target: LatLng(46.5, 2.5), zoom: 6),
                      markers: _buildMarkers(),
                      onMapCreated: (c) => _mapCtrl = c,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                    ),
            )
          else if (_filtered.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(widget.categoryIcon, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('Aucun professionnel trouvé',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 16, color: Colors.grey.shade500)),
                  const SizedBox(height: 6),
                  Text('Soyez le premier à vous inscrire !',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400)),
                ]),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ProCard(
                      pro: _filtered[i],
                      categoryColor: widget.categoryColor,
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ServiceDetailPage(
                          proUid: _filtered[i]['uid'] ?? '',
                          categoryLabel: widget.categoryLabel,
                          categoryColor: widget.categoryColor,
                        ),
                      )),
                    ),
                  ),
                  childCount: _filtered.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Bottom sheet carte ────────────────────────────────────────────────────────

class _ProMapSheet extends StatelessWidget {
  final Map<String, dynamic> pro;
  final Color categoryColor;
  final String categoryLabel;

  const _ProMapSheet({required this.pro, required this.categoryColor, required this.categoryLabel});

  @override
  Widget build(BuildContext context) {
    final nom      = pro['name_elevage'] ?? pro['firstname'] ?? 'Professionnel';
    final prof     = pro['profession_pro'] ?? '';
    final ville    = pro['ville_elevage'] ?? pro['ville'] ?? '';
    final photo    = pro['profile_picture_url'] ?? '';
    final accept   = pro['accept_new_clients'] ?? true;
    final especes  = (pro['especes_acceptees'] as List? ?? []).map((e) => e.toString()).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Row(children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: categoryColor.withValues(alpha: 0.12)),
            child: photo.isNotEmpty
                ? ClipRRect(borderRadius: BorderRadius.circular(14),
                    child: Image.network(photo, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(Icons.person_outline, color: categoryColor, size: 28)))
                : Icon(Icons.person_outline, color: categoryColor, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nom.toString(), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            if (prof.isNotEmpty)
              Text(prof.toString(), style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: categoryColor, fontWeight: FontWeight.w600)),
            if (ville.isNotEmpty)
              Row(children: [
                Icon(Icons.location_on_outlined, size: 12, color: Colors.grey.shade400),
                const SizedBox(width: 2),
                Text(ville.toString(), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
              ]),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accept ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(accept ? 'Dispo' : 'Complet',
                style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w700,
                    color: accept ? const Color(0xFF388E3C) : const Color(0xFFF57C00))),
          ),
        ]),
        if (especes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 4, children: especes.take(4).map((e) =>
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: categoryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Text(e, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: categoryColor, fontWeight: FontWeight.w600)),
            )).toList()),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: categoryColor, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => ServiceDetailPage(
                  proUid: pro['uid'] ?? '',
                  categoryLabel: categoryLabel,
                  categoryColor: categoryColor,
                ),
              ));
            },
            child: const Text('Voir le profil', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ]),
    );
  }
}

// ── Carte professionnel ───────────────────────────────────────────────────────

class _ProCard extends StatelessWidget {
  final Map<String, dynamic> pro;
  final Color categoryColor;
  final VoidCallback onTap;

  const _ProCard({required this.pro, required this.categoryColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nom        = pro['name_elevage'] ?? pro['firstname'] ?? 'Professionnel';
    final profession = pro['profession_pro'] ?? '';
    final ville      = pro['ville_elevage'] ?? pro['ville'] ?? '';
    final photo      = pro['profile_picture_url'] ?? '';
    final accept     = pro['accept_new_clients'] ?? true;
    final especes    = pro['especes_acceptees'];
    final especeList = especes is List ? List<String>.from(especes) : <String>[];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: categoryColor.withValues(alpha: 0.12),
                ),
                child: photo.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(photo, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(Icons.person_outline, color: categoryColor, size: 28)),
                      )
                    : Icon(Icons.person_outline, color: categoryColor, size: 28),
              ),
              const SizedBox(width: 12),
              // Infos
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nom.toString(), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                    if (profession.isNotEmpty)
                      Text(profession.toString(), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: categoryColor, fontWeight: FontWeight.w600)),
                    if (ville.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(children: [
                        Icon(Icons.location_on_outlined, size: 12, color: Colors.grey.shade400),
                        const SizedBox(width: 2),
                        Text(ville.toString(), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
                      ]),
                    ],
                    if (especeList.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 4, runSpacing: 4, children: especeList.take(3).map((e) =>
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: categoryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                          child: Text(e, style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: categoryColor, fontWeight: FontWeight.w600)),
                        )
                      ).toList()),
                    ],
                  ],
                ),
              ),
              // Badge dispo + flèche
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accept ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      accept ? 'Dispo' : 'Complet',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w700,
                        color: accept ? const Color(0xFF388E3C) : const Color(0xFFF57C00)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Colors.grey.shade400),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
