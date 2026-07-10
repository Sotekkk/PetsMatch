import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:PetsMatch/widgets/app_nav_drawer.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/services/service_detail_page.dart';
import 'package:PetsMatch/utils/french_geo.dart';
import 'package:PetsMatch/widgets/verification_badge.dart';
import 'package:url_launcher/url_launcher.dart';

/// Page annuaire — liste des professionnels d'une catégorie.
class ServiceListPage extends StatefulWidget {
  final String categoryLabel;
  final Color categoryColor;
  final IconData categoryIcon;
  final List<String> catProValues;
  final List<String>? professionValues;
  final String? searchQuery;

  const ServiceListPage({
    super.key,
    required this.categoryLabel,
    required this.categoryColor,
    required this.categoryIcon,
    required this.catProValues,
    this.professionValues,
    this.searchQuery,
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
  bool _nearMe = false;
  bool _locating = false;
  double? _userLat;
  double? _userLng;

  String _search = '';
  String _filterEspece = '';
  String _filterRegion = '';
  String _filterDept = '';

  GoogleMapController? _mapCtrl;

  static const _especes = ['Toutes', 'Chien', 'Chat', 'Lapin', 'Oiseau', 'Reptile', 'Rongeur', 'Cheval', 'Autre'];

  static const _regions = [
    'Île-de-France', 'Auvergne-Rhône-Alpes', 'Bretagne', 'Normandie',
    'Hauts-de-France', 'Grand Est', 'Pays de la Loire', 'Nouvelle-Aquitaine',
    'Occitanie', "Provence-Alpes-Côte d'Azur", 'Bourgogne-Franche-Comté',
    'Centre-Val de Loire', 'Corse',
  ];

  // ── Init ───────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (widget.searchQuery != null && widget.searchQuery!.isNotEmpty) {
      _search = widget.searchQuery!;
    }
    _loadPros();
  }

  Future<void> _loadPros() async {
    try {
      final hasFilter = widget.catProValues.isNotEmpty;

      // Exclure éleveurs et associations (ont leur propre espace dédié)
      const _excluded = '(eleveur,association)';

      // Primary profiles from users table
      // is_elevage = false : les éleveurs ont leur espace dédié
      final dynamic primaryRows = hasFilter
          ? await _supa
              .from('users')
              .select()
              .inFilter('cat_pro', widget.catProValues)
              .eq('is_elevage', false)
              .order('name_elevage')
          : await _supa
              .from('users')
              .select()
              .eq('is_elevage', false)
              .not('cat_pro', 'in', _excluded)
              .order('name_elevage');

      // Secondary profiles from user_profiles table (only validated ones)
      List<dynamic> secondaryRows = [];
      try {
        secondaryRows = hasFilter
            ? await _supa
                .from('user_profiles')
                .select()
                .inFilter('profile_type', widget.catProValues)
                .inFilter('statut_pro', ['actif', 'validated'])
            : await _supa
                .from('user_profiles')
                .select()
                .inFilter('statut_pro', ['actif', 'validated'])
                .not('profile_type', 'in', _excluded);
      } catch (_) {}

      // Secondaires d'abord : si un uid a un profil user_profiles (plus précis),
      // il prend la priorité sur la ligne users (qui peut avoir cat_pro générique).
      final seenUids = <String>{};
      final merged = <Map<String, dynamic>>[];

      for (final row in (secondaryRows as List)) {
        final uid = row['uid']?.toString() ?? '';
        if (!seenUids.add(uid)) continue;
        final nomVal = row['nom'] ?? row['name_elevage'] ?? '';
        final villeVal = row['ville_pro'] ?? row['ville'] ?? '';
        merged.add({
          'uid': uid,
          '_profile_table_id': row['id']?.toString(),
          'name_elevage': nomVal,
          'firstname': row['firstname'] ?? '',
          'cat_pro': row['profile_type'] ?? row['cat_pro'] ?? '',
          'profession_pro': row['profession_pro'] ?? '',
          'ville': villeVal,
          'ville_elevage': villeVal,
          'profile_picture_url': row['avatar_url'] ?? '',
          'profile_picture_url_elevage': row['avatar_url'] ?? '',
          'lat': row['latitude'] ?? row['lat'],
          'lng': row['longitude'] ?? row['lng'],
          'especes_acceptees': row['especes_acceptees'] ?? [],
          'accept_new_clients': row['accept_new_clients'] ?? true,
          'banner_url': row['banner_url'] ?? '',
          'desc_entreprise': row['desc_entreprise'] ?? row['description'] ?? '',
          'site_web': row['site_web'] ?? '',
          'instagram': row['instagram'] ?? '',
          'facebook': row['facebook'] ?? '',
          'rayon_intervention': row['rayon_intervention'] ?? 20,
          'region': row['region'] ?? '',
          'departement': row['departement'] ?? '',
          'region_elevage': row['region'] ?? '',
          'departement_elevage': row['departement'] ?? '',
          'horaires': row['horaires'] ?? {},
          'certifications': row['certifications'] ?? [],
          'tarifs': row['tarifs'] ?? '',
        });
      }

      // Primaires : on ajoute uniquement les uids pas encore couverts par un profil secondaire
      for (final row in (primaryRows as List)) {
        final uid = row['uid']?.toString() ?? '';
        if (!seenUids.add(uid)) continue;
        merged.add(Map<String, dynamic>.from(row));
      }

      if (mounted) {
        setState(() {
          _pros = merged;
          _filtered = merged;
          _loading = false;
        });
        // Si une recherche est pré-remplie (depuis la page annuaire), appliquer les filtres
        if (_search.isNotEmpty && mounted) {
          _applyFilters();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Markers ────────────────────────────────────────────────────────────────

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

  // ── "Proche de moi" — lat/lng du profil Supabase, fetchés au tap ────────

  Future<void> _toggleNearMe() async {
    if (_nearMe) {
      setState(() { _nearMe = false; _userLat = null; _userLng = null; });
      _applyFilters();
      return;
    }
    setState(() => _locating = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Connectez-vous pour utiliser cette fonctionnalité.',
              style: TextStyle(fontFamily: 'Galey')),
        ));
        return;
      }
      final row = await _supa
          .from('user_profiles')
          .select('lat, lng')
          .eq('uid', uid)
          .eq('is_main', true)
          .maybeSingle();
      final lat = (row?['lat'] as num?)?.toDouble();
      final lng = (row?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Position introuvable dans votre profil. Renseignez votre adresse dans les paramètres.',
              style: TextStyle(fontFamily: 'Galey')),
        ));
        return;
      }
      if (mounted) {
        setState(() { _userLat = lat; _userLng = lng; _nearMe = true; });
        _applyFilters();
        if (_showMap && _mapCtrl != null) {
          _mapCtrl!.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 10));
        }
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Impossible de récupérer votre position.', style: TextStyle(fontFamily: 'Galey')),
      ));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // ── Filtres ────────────────────────────────────────────────────────────────

  void _applyFilters() {
    setState(() {
      _filtered = _pros.where((p) {
        final nom      = ((p['name_elevage'] ?? p['firstname'] ?? '') as String).toLowerCase();
        final ville    = ((p['ville_elevage'] ?? p['ville'] ?? '') as String).toLowerCase();
        final profession = ((p['profession_pro'] ?? '') as String).toLowerCase();
        final matchSearch = _search.isEmpty ||
            nom.contains(_search.toLowerCase()) ||
            ville.contains(_search.toLowerCase()) ||
            profession.contains(_search.toLowerCase());

        final especes = p['especes_acceptees'];
        final matchEspece = _filterEspece.isEmpty ||
            _filterEspece == 'Toutes' ||
            (especes is List && especes.contains(_filterEspece));

        // Filtre région/département — lit aussi les colonnes *_elevage
        final loc = '$ville '
            '${(p['region_elevage'] ?? p['region'] ?? '').toString().toLowerCase()} '
            '${(p['departement_elevage'] ?? p['departement'] ?? '').toString().toLowerCase()}';
        bool matchRegion = true;
        if (_filterRegion.isNotEmpty) {
          final depts = FrenchGeo.departmentsInRegion(_filterRegion);
          matchRegion = loc.contains(_filterRegion.toLowerCase()) ||
              depts.any((d) => loc.contains(d.toLowerCase()));
        }
        final matchDept = _filterDept.isEmpty || loc.contains(_filterDept.toLowerCase());

        // Filtre "proche de moi"
        bool matchNearMe = true;
        if (_nearMe && _userLat != null && _userLng != null) {
          final pLat = (p['lat'] as num?)?.toDouble();
          final pLng = (p['lng'] as num?)?.toDouble();
          if (pLat == null || pLng == null) {
            matchNearMe = false;
          } else {
            // rayon = 0 signifie non configuré → on utilise 50 km par défaut
            final rawRayon = (p['rayon_intervention'] as num?)?.toDouble() ?? 0;
            final rayon = rawRayon > 0 ? rawRayon : 50.0;
            final distM = Geolocator.distanceBetween(_userLat!, _userLng!, pLat, pLng);
            matchNearMe = distM / 1000 <= rayon;
          }
        }

        return matchSearch && matchEspece && matchRegion && matchDept && matchNearMe;
      }).toList();
    });
  }

  bool get _hasActiveFilters =>
      _nearMe || _filterEspece.isNotEmpty || _filterRegion.isNotEmpty || _filterDept.isNotEmpty || _search.isNotEmpty;

  // ── Barre de filtres ───────────────────────────────────────────────────────

  Widget _buildFiltersBar() {
    final depts = _filterRegion.isNotEmpty
        ? FrenchGeo.departmentsInRegion(_filterRegion)
        : <String>[];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recherche texte
          TextField(
            onChanged: (v) { _search = v; _applyFilters(); },
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Rechercher par nom, ville, profession...',
              hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13),
              prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
              filled: true,
              fillColor: const Color(0xFFF0F0F0),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
          const SizedBox(height: 10),

          // Région + Département
          Row(children: [
            Expanded(
              child: _GeoDropdown(
                value: _filterRegion.isEmpty ? null : _filterRegion,
                hint: 'Région',
                items: _regions,
                color: widget.categoryColor,
                onChanged: (v) {
                  setState(() { _filterRegion = v ?? ''; _filterDept = ''; });
                  _applyFilters();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _GeoDropdown(
                value: _filterDept.isEmpty ? null : _filterDept,
                hint: 'Département',
                items: depts,
                color: widget.categoryColor,
                onChanged: (v) {
                  setState(() => _filterDept = v ?? '');
                  _applyFilters();
                },
              ),
            ),
          ]),
          const SizedBox(height: 10),

          // Espèces
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _especes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final e = _especes[i];
                final selected = (_filterEspece.isEmpty && e == 'Toutes') || (_filterEspece == e);
                return GestureDetector(
                  onTap: () { _filterEspece = e == 'Toutes' ? '' : e; _applyFilters(); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: selected ? widget.categoryColor : const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(e, style: TextStyle(
                      fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : const Color(0xFF555555),
                    )),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Proche de moi + reset filtres
          Row(children: [
            GestureDetector(
              onTap: _locating ? null : _toggleNearMe,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: _nearMe ? widget.categoryColor : const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_locating)
                    SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2,
                        color: _nearMe ? Colors.white : widget.categoryColor))
                  else
                    Icon(Icons.near_me_rounded, size: 14,
                      color: _nearMe ? Colors.white : const Color(0xFF555555)),
                  const SizedBox(width: 6),
                  Text('Proche de moi', style: TextStyle(
                    fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                    color: _nearMe ? Colors.white : const Color(0xFF555555),
                  )),
                ]),
              ),
            ),
            if (_hasActiveFilters) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _nearMe = false; _userLat = null; _userLng = null;
                    _search = ''; _filterEspece = ''; _filterRegion = ''; _filterDept = '';
                  });
                  _applyFilters();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Réinitialiser', style: TextStyle(
                    fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                    color: Color(0xFF888888),
                  )),
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  // ── Bannière urgences vétérinaires ────────────────────────────────────────

  Widget _buildUrgencesVetBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFF6F00).withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6F00).withValues(alpha: 0.10),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.emergency_rounded, color: Color(0xFFE65100), size: 18),
                  SizedBox(width: 8),
                  Text('Urgences vétérinaires 24h/24',
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Color(0xFFE65100))),
                ],
              ),
            ),
            // Ligne n° national
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Row(
                children: [
                  const Icon(Icons.phone_outlined, size: 16, color: Color(0xFFE65100)),
                  const SizedBox(width: 8),
                  const Text('3115',
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Color(0xFFE65100))),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('— Vétérinaire de garde national',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                  ),
                  GestureDetector(
                    onTap: () async {
                      final uri = Uri(scheme: 'tel', path: '3115');
                      try { await _launchUri(uri); } catch (_) {}
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE65100),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Appeler',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
            // Lien vétérinaire de garde Paris
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
              child: GestureDetector(
                onTap: () async {
                  final uri = Uri.parse('https://www.veterinaire-de-garde-paris.fr');
                  try { await _launchUri(uri); } catch (_) {}
                },
                child: Row(
                  children: [
                    const Icon(Icons.open_in_new_rounded, size: 13, color: Color(0xFF0C5C6C)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Vétérinaire de garde Paris',
                          style: const TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0C5C6C),
                              decoration: TextDecoration.underline)),
                    ),
                    Text('veterinaire-de-garde-paris.fr',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey.shade400)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUri(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  // ── Vue carte plein écran ─────────────────────────────────────────────────

  Widget _buildMapView() {
    final markers = _buildMarkers();
    final initialTarget = _userLat != null ? LatLng(_userLat!, _userLng!) : const LatLng(46.5, 2.5);
    final initialZoom = _userLat != null ? 10.0 : 6.0;

    return Scaffold(
      backgroundColor: const Color(0xFF1E2025),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator(color: Color(0xFF6E9E57)))
          else if (markers.isEmpty)
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(widget.categoryIcon, size: 64, color: Colors.white30),
                const SizedBox(height: 12),
                Text(
                  _filtered.isEmpty ? 'Aucun professionnel trouvé' : 'Aucun professionnel\navec position GPS',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.white54),
                ),
              ]),
            )
          else
            GoogleMap(
              initialCameraPosition: CameraPosition(target: initialTarget, zoom: initialZoom),
              markers: markers,
              onMapCreated: (c) => _mapCtrl = c,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
              zoomGesturesEnabled: true,
              scrollGesturesEnabled: true,
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: false,
            ),

          // Overlay
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                _mapIconButton(Icons.arrow_back_ios_new_rounded, () => Navigator.pop(context)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _locating ? null : _toggleNearMe,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _nearMe ? widget.categoryColor : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8)],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (_locating)
                        SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2,
                            color: _nearMe ? Colors.white : widget.categoryColor))
                      else
                        Icon(Icons.near_me_rounded, size: 14,
                          color: _nearMe ? Colors.white : widget.categoryColor),
                      const SizedBox(width: 6),
                      Text('Proche de moi', style: TextStyle(
                        fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                        color: _nearMe ? Colors.white : const Color(0xFF333333),
                      )),
                    ]),
                  ),
                ),
                const Spacer(),
                _mapIconButton(Icons.list_rounded, () => setState(() => _showMap = false)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapIconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: Colors.white, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8)],
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF1E2025)),
      ),
    );
  }

  // ── Build principal ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_showMap) return _buildMapView();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      endDrawer: const AppNavDrawer(),
      appBar: AppBar(
        title: Text(widget.categoryLabel,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFF0C5C6C),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Vue carte',
            onPressed: () => setState(() => _showMap = true),
          ),
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu_rounded),
              tooltip: 'Menu',
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildFiltersBar()),

          // Bannière urgences vétérinaires
          if (widget.catProValues.contains('veterinaire'))
            SliverToBoxAdapter(child: _buildUrgencesVetBanner()),

          if (_loading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: Color(0xFF6E9E57))))
          else if (_filtered.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(widget.categoryIcon, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('Aucun professionnel trouvé',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 16, color: Colors.grey.shade500)),
                  const SizedBox(height: 6),
                  Text('Essayez d\'élargir vos filtres.',
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
                          profileTableId: _filtered[i]['_profile_table_id'] as String?,
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

// ── Dropdown géographique ─────────────────────────────────────────────────────

class _GeoDropdown extends StatelessWidget {
  final String? value;
  final String hint;
  final List<String> items;
  final Color color;
  final ValueChanged<String?> onChanged;

  const _GeoDropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: value != null ? color.withValues(alpha: 0.1) : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(20),
        border: value != null ? Border.all(color: color.withValues(alpha: 0.4)) : null,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16,
            color: value != null ? color : Colors.grey.shade500),
          style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: value != null ? color : Colors.grey.shade700,
            fontWeight: value != null ? FontWeight.w700 : FontWeight.normal),
          items: [
            DropdownMenuItem<String>(value: null, child: Text('— $hint', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500))),
            ...items.map((s) => DropdownMenuItem<String>(value: s, child: Text(s))),
          ],
          onChanged: items.isEmpty ? null : onChanged,
        ),
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
    final nom    = pro['name_elevage'] ?? pro['firstname'] ?? 'Professionnel';
    final prof   = pro['profession_pro'] ?? '';
    final ville  = pro['ville_elevage'] ?? pro['ville'] ?? '';
    final photo  = pro['profile_picture_url_elevage'] ?? pro['profile_picture_url'] ?? '';
    final accept = pro['accept_new_clients'] ?? true;
    final especes = (pro['especes_acceptees'] as List? ?? []).map((e) => e.toString()).toList();

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
                    child: CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Icon(Icons.person_outline, color: categoryColor, size: 28)))
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
                  profileTableId: pro['_profile_table_id'] as String?,
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
    final photo      = pro['profile_picture_url_elevage'] ?? pro['profile_picture_url'] ?? '';
    final banner     = pro['banner_url'] ?? '';
    final accept     = pro['accept_new_clients'] ?? true;
    final especes    = pro['especes_acceptees'];
    final especeList = especes is List ? List<String>.from(especes) : <String>[];
    final urgences24h = pro['urgences_24h'] == true;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(clipBehavior: Clip.none, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 100, width: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                banner.isNotEmpty
                    ? CachedNetworkImage(imageUrl: banner, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _gradient())
                    : (photo.isNotEmpty
                        ? CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover,
                            color: Colors.black26, colorBlendMode: BlendMode.darken,
                            errorWidget: (_, __, ___) => _gradient())
                        : _gradient()),
                Positioned(top: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: accept ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(accept ? '✓ Dispo' : 'Complet',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w700,
                        color: accept ? const Color(0xFF388E3C) : const Color(0xFFF57C00))),
                  )),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 28, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(nom.toString(),
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1E2025)))),
                  if (urgences24h) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE65100).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.emergency_rounded, size: 11, color: Color(0xFFE65100)),
                        SizedBox(width: 3),
                        Text('24h/24', style: TextStyle(fontFamily: 'Galey', fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFE65100))),
                      ]),
                    ),
                    const SizedBox(width: 4),
                  ],
                  VerificationBadge(
                    level: getVerificationLevel(
                      statutPro: pro['statut_pro']?.toString(),
                      siret: pro['siret']?.toString(),
                      isPremium: pro['is_premium'] == true,
                    ),
                  ),
                ]),
                if (profession.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(profession.toString(),
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: categoryColor, fontWeight: FontWeight.w600)),
                ],
                if (ville.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.location_on_outlined, size: 12, color: Colors.grey.shade400),
                    const SizedBox(width: 2),
                    Text(ville.toString(), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
                  ]),
                ],
                if (especeList.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 4, runSpacing: 4, children: especeList.take(4).map((e) =>
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: categoryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(e, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: categoryColor, fontWeight: FontWeight.w600)),
                    )
                  ).toList()),
                ],
              ]),
            ),
          ]),
          Positioned(
            top: 58, left: 12,
            child: Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6)],
              ),
              child: ClipOval(
                child: photo.isNotEmpty
                    ? CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _avatarPlaceholder())
                    : _avatarPlaceholder(),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _gradient() => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [categoryColor.withValues(alpha: 0.8), const Color(0xFF1E2025)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
    ),
  );

  Widget _avatarPlaceholder() => Container(
    color: categoryColor.withValues(alpha: 0.15),
    child: Icon(Icons.store_outlined, size: 26, color: categoryColor),
  );
}
