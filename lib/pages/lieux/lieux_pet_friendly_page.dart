import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:PetsMatch/widgets/liste_especes_cocher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/widgets/app_nav_drawer.dart';

import 'lieu_detail_page.dart';
import 'recommander_lieu_page.dart';
import 'mes_contributions_lieux_page.dart';
import 'lieux_feed_page.dart';

// Couleur d'épingle selon le référencement : communauté, établissement
// vérifié, partenaire PetsMatch (une seule carte pour les trois).
const _refHue = {
  'communaute': BitmapDescriptor.hueOrange,
  'verifie':    BitmapDescriptor.hueAzure,
  'partenaire': BitmapDescriptor.hueGreen,
};

/// Référencement d'un lieu : communauté (sans gestionnaire), établissement
/// vérifié (gestionnaire, formule gratuite) ou partenaire (formule payante).
String referencementLieu(Map<String, dynamic> l) {
  if (l['uid_pro'] == null) return 'communaute';
  if ((l['plan'] ?? 'decouverte') != 'decouverte') return 'partenaire';
  return 'verifie';
}

const kLibelleReferencement = {
  'communaute': 'Recommandé par la communauté',
  'verifie': 'Établissement vérifié',
  'partenaire': 'Partenaire PetsMatch',
};
const kIconeReferencement = {
  'communaute': Icons.groups_outlined,
  'verifie': Icons.verified_user_outlined,
  'partenaire': Icons.star_outline_rounded,
};

const _libelleCategorie = {
  'hebergement': 'Hébergement', 'restauration': 'Café / restaurant',
  'commerce': 'Commerce', 'activite': 'Activité ou loisir',
};

class LieuxPetFriendlyPage extends StatefulWidget {
  final String? filterCategorie; // 'hebergement' | 'restauration' | null = tous
  const LieuxPetFriendlyPage({super.key, this.filterCategorie});

  @override
  State<LieuxPetFriendlyPage> createState() => _LieuxPetFriendlyPageState();
}

class _LieuxPetFriendlyPageState extends State<LieuxPetFriendlyPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _darkC = Color(0xFF071C22);
  static const _bgGrad = LinearGradient(
    begin: Alignment.topCenter, end: Alignment.bottomCenter,
    colors: [Color(0xFF071C22), Color(0xFF0C3535), Color(0xFF0C3520)],
    stops: [0.0, 0.5, 1.0],
  );
  static const _pageSize = 12;

  final _supabase = Supabase.instance.client;
  final _scroll = ScrollController();

  String _categorie = 'tous'; // 'tous' | 'hebergement' | 'restauration'
  // Espèces cochées (vide = toutes) : un lieu correspond s'il accepte au moins l'une d'elles.
  final Set<String> _especesFiltre = {};
  // Référencement : tous | communaute | verifie | partenaire (combinable).
  String _referencement = 'tous';
  String _sortBy = 'recent'; // 'recent' | 'note' | 'misEnAvant'
  bool _mapView = false;

  List<Map<String, dynamic>> _lieux = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;

  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    if (widget.filterCategorie != null) {
      _categorie = widget.filterCategorie!;
    }
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore) {
      _load();
    }
  }

  bool _loadingAllForMap = false;

  Future<void> _toggleMapView() async {
    setState(() => _mapView = !_mapView);
    if (_mapView && _hasMore) {
      setState(() => _loadingAllForMap = true);
      while (_hasMore && mounted) {
        await _load();
      }
      if (mounted) setState(() => _loadingAllForMap = false);
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _page = 0;
        _lieux = [];
        _hasMore = true;
      });
    } else {
      if (_loadingMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      final from = _page * _pageSize;

      // Build base filter
      var base = _supabase
          .from('petfriendly_places')
          .select(
              'id, uid_pro, nom, categorie, sous_categorie, ville, lat, lng, especes_acceptees, horaires, photo_profil_url, banniere_url, photos, note_moyenne, nb_avis, nb_likes, plan, statut, origine, verification')
          .eq('statut', 'actif');
      if (_referencement == 'communaute') base = base.isFilter('uid_pro', null);
      if (_referencement == 'verifie') base = base.not('uid_pro', 'is', null).eq('plan', 'decouverte');
      if (_referencement == 'partenaire') base = base.not('uid_pro', 'is', null).neq('plan', 'decouverte');

      if (_categorie != 'tous') base = base.eq('categorie', _categorie);
      if (_especesFiltre.isNotEmpty) {
        base = base.overlaps('especes_acceptees', _especesFiltre.toList());
      }

      // Apply sort + pagination (returns PostgrestTransformBuilder — no reassign)
      final data = await (_sortBy == 'note'
              ? base.order('note_moyenne', ascending: false)
              : _sortBy == 'misEnAvant'
                  ? base
                      .order('plan', ascending: false)
                      .order('created_at', ascending: false)
                  : base.order('created_at', ascending: false))
          .range(from, from + _pageSize - 1);
      final rows = List<Map<String, dynamic>>.from(data as List);

      setState(() {
        if (reset) {
          _lieux = rows;
        } else {
          _lieux.addAll(rows);
        }
        _page++;
        _hasMore = rows.length == _pageSize;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  String _photoUrl(Map<String, dynamic> lieu) {
    final banniere = lieu['banniere_url'] as String?;
    if (banniere != null && banniere.isNotEmpty) return banniere;
    final photos = lieu['photos'] as List?;
    if (photos != null && photos.isNotEmpty) return photos.first as String;
    return lieu['photo_profil_url'] as String? ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkC,
      endDrawer: const AppNavDrawer(),
      body: Stack(children: [
        Positioned.fill(child: Container(decoration: const BoxDecoration(gradient: _bgGrad))),
        SafeArea(child: Builder(builder: (ctx) => Column(children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Lieux Pet-Friendly',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white)),
              ),
              _glassIconBtn(Icons.map_outlined, _mapView ? Icons.grid_view_rounded : Icons.map_outlined, _toggleMapView),
              const SizedBox(width: 8),
              _glassIconBtn(Icons.view_day_outlined, Icons.view_day_outlined,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LieuxFeedPage()))),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: const Icon(Icons.sort_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ),
                onSelected: (v) { _sortBy = v; _load(reset: true); },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'recent', child: Text('Les plus récents')),
                  PopupMenuItem(value: 'note', child: Text('Mieux notés')),
                  PopupMenuItem(value: 'misEnAvant', child: Text('Partenaires en premier (classement sponsorisé)')),
                ],
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => Scaffold.of(ctx).openEndDrawer(),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: const Icon(Icons.menu_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          // ── Recommander un lieu (contribution communautaire, modérée) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MesContributionsLieuxPage())),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                child: const Text('Mes contributions', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const RecommanderLieuPage()));
                  if (ok == true) _load(reset: true);
                },
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: const Text('Recommander un lieu', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
            ]),
          ),
          // ── Filtres ──
          _Filters(
            categorie: _categorie, especes: _especesFiltre, referencement: _referencement,
            onReferencement: (v) { _referencement = v; _load(reset: true); },
            onCategorie: (v) { _categorie = v; _load(reset: true); },
            onEspeces: (v) { _especesFiltre..clear()..addAll(v); _load(reset: true); },
          ),
          // ── Contenu ──
          Expanded(
            child: _loading || (_mapView && _loadingAllForMap)
                ? const Center(child: CircularProgressIndicator(color: _teal))
                : _lieux.isEmpty
                    ? _Empty(categorie: _categorie)
                    : _mapView
                        ? _LieuxMapView(
                            lieux: _lieux,
                            onTapLieu: (id) => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => LieuDetailPage(id: id)))
                                .then((_) => _load(reset: true)),
                          )
                        : RefreshIndicator(
                            color: _teal,
                            onRefresh: () => _load(reset: true),
                            child: GridView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.62,
                              ),
                              itemCount: _lieux.length + (_loadingMore ? 2 : 0),
                              itemBuilder: (ctx, i) {
                                if (i >= _lieux.length) return _SkeletonCard();
                                final lieu = _lieux[i];
                                final id = lieu['id'] as String;
                                return _LieuCard(
                                  lieu: lieu, photoUrl: _photoUrl(lieu),
                                  isLiked: false, likeCount: 0,
                                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LieuDetailPage(id: id)))
                                      .then((_) => _load(reset: true)),
                                  onLike: () {},
                                );
                              },
                            ),
                          ),
          ),
        ]))),
      ]),
    );
  }

  Widget _glassIconBtn(IconData icon1, IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    ),
  );
}

// ─── Filtres chips ───────────────────────────────────────────────────────────

class _Filters extends StatelessWidget {
  final String categorie;
  final Set<String> especes;
  final String referencement;
  final ValueChanged<String> onCategorie;
  final ValueChanged<Set<String>> onEspeces;
  final ValueChanged<String> onReferencement;

  static const _listeEspeces = kEspecesLieux;

  const _Filters({
    required this.categorie,
    required this.especes,
    required this.referencement,
    required this.onCategorie,
    required this.onEspeces,
    required this.onReferencement,
  });

  // Liste déroulante à cases à cocher, sans émoticônes.
  Future<void> _choisirEspeces(BuildContext context) async {
    final choix = {...especes};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => SafeArea(
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Align(alignment: Alignment.centerLeft,
                child: Text('Espèces acceptées', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16))),
          ),
          CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: const Color(0xFF0C5C6C),
            value: choix.length == _listeEspeces.length,
            onChanged: (v) => setS(() { choix.clear(); if (v == true) choix.addAll(_listeEspeces.map((e) => e.$1)); }),
            title: const Text('Tout cocher', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
          ),
          const Divider(height: 1),
          for (final e in _listeEspeces)
            CheckboxListTile(
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: const Color(0xFF0C5C6C),
              value: choix.contains(e.$1),
              onChanged: (v) => setS(() => v == true ? choix.add(e.$1) : choix.remove(e.$1)),
              title: Text(e.$2, style: const TextStyle(fontFamily: 'Galey')),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(width: double.infinity, child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0C5C6C), foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Appliquer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            )),
          ),
        ])),
      )),
    );
    if (ok == true) onEspeces(choix);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _Chip('Tout', 'tous', categorie, onCategorie,
                  Icons.explore_outlined),
              const SizedBox(width: 8),
              _Chip('Hébergements', 'hebergement', categorie, onCategorie,
                  Icons.hotel_outlined),
              const SizedBox(width: 8),
              _Chip('Cafés & Restos', 'restauration', categorie, onCategorie,
                  Icons.restaurant_outlined),
              const SizedBox(width: 8),
              _Chip('Commerces', 'commerce', categorie, onCategorie,
                  Icons.storefront_outlined),
              const SizedBox(width: 8),
              _Chip('Activités', 'activite', categorie, onCategorie,
                  Icons.park_outlined),
            ]),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _Chip('Tous les lieux', 'tous', referencement, onReferencement, null),
              const SizedBox(width: 8),
              _Chip('Communauté', 'communaute', referencement, onReferencement, Icons.groups_outlined),
              const SizedBox(width: 8),
              _Chip('Établissements vérifiés', 'verifie', referencement, onReferencement, Icons.verified_user_outlined),
              const SizedBox(width: 8),
              _Chip('Partenaires PetsMatch', 'partenaire', referencement, onReferencement, Icons.star_outline_rounded),
            ]),
          ),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _choisirEspeces(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: especes.isEmpty ? Colors.grey.shade300 : const Color(0xFF0C5C6C)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.pets_outlined, size: 15, color: Color(0xFF0C5C6C)),
                const SizedBox(width: 6),
                Text(
                  especes.isEmpty || especes.length == _listeEspeces.length
                      ? 'Toutes espèces'
                      : _listeEspeces.where((e) => especes.contains(e.$1)).map((e) => e.$2).join(', '),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E)),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more, size: 18, color: Color(0xFF5E6B70)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onTap;
  final IconData? icon;

  const _Chip(this.label, this.value, this.selected, this.onTap, this.icon);

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF0C5C6C);
    const green = Color(0xFF1E7A8C);
    final active = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              gradient: active ? const LinearGradient(colors: [teal, green]) : null,
              color: active ? null : Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: active ? Colors.transparent : Colors.white.withValues(alpha: 0.20)),
              boxShadow: active ? [BoxShadow(color: teal.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 3))] : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                ],
                Text(label,
                    style: TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: Colors.white,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Vue carte ────────────────────────────────────────────────────────────────

class _LieuxMapView extends StatefulWidget {
  final List<Map<String, dynamic>> lieux;
  final void Function(String id) onTapLieu;

  const _LieuxMapView({required this.lieux, required this.onTapLieu});

  @override
  State<_LieuxMapView> createState() => _LieuxMapViewState();
}

class _LieuxMapViewState extends State<_LieuxMapView> {
  final Map<MarkerId, Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _buildMarkers();
  }

  @override
  void didUpdateWidget(_LieuxMapView old) {
    super.didUpdateWidget(old);
    if (old.lieux.length != widget.lieux.length) _buildMarkers();
  }

  void _buildMarkers() {
    final m = <MarkerId, Marker>{};
    for (final lieu in widget.lieux) {
      final lat = (lieu['lat'] as num?)?.toDouble();
      final lng = (lieu['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final id = lieu['id'] as String;
      final cat = lieu['categorie'] as String? ?? '';
      final ref = referencementLieu(lieu);
      m[MarkerId(id)] = Marker(
        markerId: MarkerId(id),
        position: LatLng(lat, lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(_refHue[ref] ?? BitmapDescriptor.hueViolet),
        infoWindow: InfoWindow(
          title: lieu['nom'] as String? ?? '',
          snippet: '${_libelleCategorie[cat] ?? 'Lieu'} · ${kLibelleReferencement[ref]}',
          onTap: () => widget.onTapLieu(id),
        ),
      );
    }
    setState(() {
      _markers.clear();
      _markers.addAll(m);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: LatLng(46.603354, 1.888334),
          zoom: 5.5,
        ),
        markers: Set<Marker>.of(_markers.values),
        myLocationButtonEnabled: false,
        zoomControlsEnabled: true,
      ),
      Positioned(
        top: 12, left: 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
          ),
          child: Text('${widget.lieux.length} lieu(x)',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ),
      ),
    ]);
  }
}

// ─── Card lieu ───────────────────────────────────────────────────────────────

class _LieuCard extends StatelessWidget {
  final Map<String, dynamic> lieu;
  final String photoUrl;
  final bool isLiked;
  final int likeCount;
  final VoidCallback onTap;
  final VoidCallback onLike;

  const _LieuCard({
    required this.lieu,
    required this.photoUrl,
    required this.isLiked,
    required this.likeCount,
    required this.onTap,
    required this.onLike,
  });

  String get _logoUrl => lieu['photo_profil_url'] as String? ?? '';

  String _ouvertLabel(Map<String, dynamic> lieu) {
    final horaires = lieu['horaires'] as Map<String, dynamic>?;
    if (horaires == null || horaires.isEmpty) return '';
    final days = [
      'lundi',
      'mardi',
      'mercredi',
      'jeudi',
      'vendredi',
      'samedi',
      'dimanche'
    ];
    final now = DateTime.now();
    final dayKey = days[now.weekday - 1];
    final val = horaires[dayKey] as String?;
    if (val == null ||
        val.toLowerCase() == 'fermé' ||
        val.toLowerCase() == 'ferme') return '🔴 Fermé';
    final parts = val.split('-');
    if (parts.length < 2) return '';
    try {
      final open = _parseTime(parts[0].trim());
      final close = _parseTime(parts[1].trim());
      final t = now.hour * 60 + now.minute;
      if (t >= open && t < close) return '🟢 Ouvert';
      if (t < open) return '🔴 Fermé';
      return '🔴 Fermé';
    } catch (_) {
      return '';
    }
  }

  int _parseTime(String s) {
    final p = s.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  List<String> _especes(Map<String, dynamic> lieu) {
    final raw = lieu['especes_acceptees'];
    if (raw == null) return [];
    return List<String>.from(raw as List);
  }

  @override
  Widget build(BuildContext context) {
    final note = (lieu['note_moyenne'] as num?)?.toDouble() ?? 0.0;
    final nbAvis = lieu['nb_avis'] as int? ?? 0;
    final ville = lieu['ville'] as String? ?? '';
    final nom = lieu['nom'] as String? ?? '';
    final ouvert = _ouvertLabel(lieu);
    final especes = _especes(lieu);
    final ref = referencementLieu(lieu);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo 4:5
            Expanded(
              flex: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  photoUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: photoUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              _PlaceholderPhoto(lieu['categorie']),
                        )
                      : _PlaceholderPhoto(lieu['categorie']),
                  // Badge ouvert
                  if (ouvert.isNotEmpty)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(ouvert,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10)),
                      ),
                    ),
                  // Logo circle
                  if (_logoUrl.isNotEmpty)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4)
                          ],
                        ),
                        child: ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: _logoUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              color: const Color(0xFF0C5C6C),
                              child: const Icon(Icons.store_outlined,
                                  size: 18, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Infos
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nom,
                        style: const TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Color(0xFF1E2025),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded,
                            size: 11, color: Color(0xFF0C5C6C)),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(ville,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade600),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(kIconeReferencement[ref], size: 12,
                          color: ref == 'partenaire' ? const Color(0xFF4E7A3B) : ref == 'verifie' ? const Color(0xFF0C5C6C) : Colors.grey.shade600),
                      const SizedBox(width: 3),
                      Expanded(child: Text(kLibelleReferencement[ref]!,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade700))),
                    ]),
                    const SizedBox(height: 4),
                    if (note > 0)
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 13, color: Color(0xFFFFA000)),
                          const SizedBox(width: 2),
                          Text(note.toStringAsFixed(1),
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 3),
                          Text('($nbAvis)',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey.shade500)),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderPhoto extends StatelessWidget {
  final String? categorie;
  const _PlaceholderPhoto(this.categorie);

  @override
  Widget build(BuildContext context) {
    final isHeb = categorie == 'hebergement';
    return Container(
      color: isHeb ? const Color(0xFFE3F2FD) : const Color(0xFFFFF3E0),
      child: Center(
        child: Icon(
          isHeb ? Icons.hotel_outlined : Icons.restaurant_outlined,
          size: 48,
          color: isHeb ? const Color(0xFF1E88E5) : const Color(0xFFEF6C00),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Expanded(
            flex: 5,
            child: Container(color: Colors.grey.shade200),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      height: 12,
                      color: Colors.grey.shade200,
                      width: double.infinity),
                  const SizedBox(height: 6),
                  Container(height: 10, color: Colors.grey.shade100, width: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String categorie;
  const _Empty({required this.categorie});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.explore_off_outlined,
              size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            categorie == 'hebergement'
                ? 'Aucun hébergement pet-friendly\npour le moment'
                : categorie == 'restauration'
                    ? 'Aucun café/restaurant pet-friendly\npour le moment'
                    : 'Aucun lieu pet-friendly\npour le moment',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Galey',
              fontSize: 16,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}
