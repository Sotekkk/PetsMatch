import 'dart:ui';
import 'package:PetsMatch/utils/storage_helper.dart' show thumbUrl;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_feed_page.dart';
import 'package:PetsMatch/pages/lieux/lieu_detail_page.dart';
import 'package:PetsMatch/main.dart' show User_Info;

// ── Modèles ───────────────────────────────────────────────────────────────────

class _PlaceFavori {
  final String placeId;
  final String nom;
  final String ville;
  final String? photoUrl;
  final String? logoUrl;
  const _PlaceFavori({required this.placeId, required this.nom, required this.ville, this.photoUrl, this.logoUrl});
}

class _SavedItem {
  final String annonceId;
  final int?   bebeIndex;
  final String photo;
  final String nom;
  final String? race;
  final String? espece;
  final String? sexe;
  final double? prix;
  final String? ville;
  final String? nomEleveur;

  const _SavedItem({
    required this.annonceId,
    required this.bebeIndex,
    required this.photo,
    required this.nom,
    this.race, this.espece, this.sexe, this.prix, this.ville, this.nomEleveur,
  });
}

// ── Page ──────────────────────────────────────────────────────────────────────

class LikesPage extends StatefulWidget {
  const LikesPage({super.key});
  @override
  State<LikesPage> createState() => _LikesPageState();
}

class _LikesPageState extends State<LikesPage> with SingleTickerProviderStateMixin {
  static const _teal   = Color(0xFF0C5C6C);

  final _supa = Supabase.instance.client;

  late final TabController _tabCtrl;

  List<_SavedItem> _favItems   = [];
  List<_SavedItem> _likeItems  = [];
  List<_PlaceFavori> _placeItems = [];
  bool _loadingFavs   = false;
  bool _loadingLikes  = false;
  bool _loadingPlaces = false;
  bool _loadedFavs    = false;
  bool _loadedLikes   = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.indexIsChanging) return;
      if (_tabCtrl.index == 0 && !_loadedFavs)  _loadTab('favoris');
      if (_tabCtrl.index == 1 && !_loadedLikes) _loadTab('likes');
    });
    _initLoad();
  }

  // Attend que Firebase Auth soit prêt avant de charger
  Future<void> _initLoad() async {
    if (FirebaseAuth.instance.currentUser != null) {
      _loadTab('favoris');
      _loadPlaces();
      return;
    }
    try {
      await FirebaseAuth.instance.authStateChanges()
          .firstWhere((u) => u != null)
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
    if (mounted) {
      _loadTab('favoris');
      _loadPlaces();
    }
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<List<_SavedItem>> _fetchFromTable(String table) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return [];

    final profileType = User_Info.activeType;
    final isSecondary = User_Info.activeProfileId.isNotEmpty;
    dynamic q = _supa
        .from(table)
        .select('annonce_id, bebe_index')
        .eq('user_uid', uid);
    // Profil secondaire : filtre strict. Profil primaire : inclure les anciens (null).
    if (isSecondary) {
      q = q.eq('profile_type', profileType);
    } else {
      q = q.or('profile_type.eq.$profileType,profile_type.is.null');
    }
    final rawRows = await q;

    final rows = List<Map<String, dynamic>>.from(rawRows);
    if (rows.isEmpty) return [];

    final ids = rows
        .map((r) => r['annonce_id']?.toString())
        .whereType<String>()
        .toSet()
        .toList();
    if (ids.isEmpty) return [];

    final rawAnnonces = await _supa
        .from('annonces')
        .select('id, titre, espece, race, type, photos, animaux_portee, prix, saillie_prix, ville_eleveur, sexe, nom_eleveur')
        .inFilter('id', ids);

    final annonces = List<Map<String, dynamic>>.from(rawAnnonces);
    final annonceMap = <String, Map<String, dynamic>>{
      for (final a in annonces)
        if (a['id'] != null) a['id'].toString(): a,
    };

    // Supabase peut retourner des entiers/décimaux comme String selon le contexte
    int? safeInt(dynamic v) => v == null ? null
        : v is num ? v.toInt()
        : int.tryParse(v.toString());
    double? safeDbl(dynamic v) => v == null ? null
        : v is num ? v.toDouble()
        : double.tryParse(v.toString());
    String? safeStr(dynamic v) => v?.toString();

    final result = <_SavedItem>[];
    for (final row in rows) {
      final annonceId = row['annonce_id']?.toString();
      if (annonceId == null) continue;
      final a = annonceMap[annonceId];
      if (a == null) continue;
      final aPhotos = List<String>.from(a['photos'] ?? []);
      final bebes   = List<Map<String, dynamic>>.from(a['animaux_portee'] ?? []);
      final bi      = safeInt(row['bebe_index']);

      if (bi != null && bi < bebes.length) {
        final b     = bebes[bi];
        final bPh   = List<String>.from(b['photos'] ?? []);
        final photo = bPh.isNotEmpty ? bPh.first : (aPhotos.isNotEmpty ? aPhotos.first : null);
        if (photo == null) continue;
        final bNom = safeStr(b['nom']);
        result.add(_SavedItem(
          annonceId: annonceId,
          bebeIndex: bi, photo: photo,
          nom:   bNom?.isNotEmpty == true ? bNom! : 'Bébé ${bi + 1}',
          race:  safeStr(a['race']),
          espece: safeStr(a['espece']),
          sexe:  safeStr(b['sexe']),
          prix:  safeDbl(b['prix']),
          ville: safeStr(a['ville_eleveur']),
          nomEleveur: safeStr(a['nom_eleveur']),
        ));
      } else if (bi == null) {
        final photo = aPhotos.isNotEmpty ? aPhotos.first : null;
        if (photo == null) continue;
        final prix = safeDbl(a['saillie_prix']) ?? safeDbl(a['prix']);
        final titre = safeStr(a['titre']);
        result.add(_SavedItem(
          annonceId: annonceId,
          bebeIndex: null, photo: photo,
          nom: titre?.isNotEmpty == true
              ? titre!
              : '${a['espece'] ?? ''} ${a['race'] ?? ''}'.trim(),
          race:  safeStr(a['race']),
          espece: safeStr(a['espece']),
          sexe:  safeStr(a['sexe']),
          prix:  prix,
          ville: safeStr(a['ville_eleveur']),
          nomEleveur: safeStr(a['nom_eleveur']),
        ));
      }
    }
    return result;
  }

  Future<void> _loadTab(String table) async {
    if (table == 'favoris') {
      setState(() => _loadingFavs = true);
      try {
        final items = await _fetchFromTable('favoris');
        if (mounted) setState(() { _favItems = items; _loadingFavs = false; _loadedFavs = true; });
      } catch (_) {
        if (mounted) setState(() => _loadingFavs = false);
      }
    } else {
      setState(() => _loadingLikes = true);
      try {
        final items = await _fetchFromTable('likes');
        if (mounted) setState(() { _likeItems = items; _loadingLikes = false; _loadedLikes = true; });
      } catch (_) {
        if (mounted) setState(() => _loadingLikes = false);
      }
    }
  }

  Future<void> _loadPlaces() async {
    setState(() => _loadingPlaces = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isEmpty) { setState(() { _loadingPlaces = false; }); return; }
      final profileRow = await _supa.from('user_profiles').select('id').eq('uid', uid).eq('is_main', true).maybeSingle();
      final profileId = profileRow?['id'] as String?;
      final filterCol = profileId != null ? 'user_profile_id' : 'user_uid';
      final filterVal = profileId ?? uid;
      final rows = await _supa
          .from('place_favoris')
          .select('place_id')
          .eq(filterCol, filterVal);
      final ids = (rows as List).map((r) => r['place_id'] as String).toList();
      if (ids.isEmpty) {
        if (mounted) setState(() { _placeItems = []; _loadingPlaces = false; });
        return;
      }
      final places = await _supa
          .from('petfriendly_places')
          .select('id, nom, ville, banniere_url, photo_profil_url')
          .inFilter('id', ids);
      final items = (places as List).map((p) => _PlaceFavori(
        placeId: p['id'] as String,
        nom: p['nom'] as String? ?? '',
        ville: p['ville'] as String? ?? '',
        photoUrl: p['banniere_url'] as String?,
        logoUrl: p['photo_profil_url'] as String?,
      )).toList();
      if (mounted) setState(() { _placeItems = items; _loadingPlaces = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingPlaces = false);
    }
  }

  Future<void> _removePlace(String placeId) async {
    setState(() => _placeItems.removeWhere((p) => p.placeId == placeId));
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isNotEmpty) {
        await _supa.from('place_favoris').delete().eq('user_uid', uid).eq('place_id', placeId);
      }
    } catch (_) {
      _loadPlaces();
    }
  }

  Future<void> _removeItem(_SavedItem item, String table) async {
    setState(() {
      if (table == 'favoris') {
        _favItems.removeWhere((i) => i.annonceId == item.annonceId && i.bebeIndex == item.bebeIndex);
      } else {
        _likeItems.removeWhere((i) => i.annonceId == item.annonceId && i.bebeIndex == item.bebeIndex);
      }
    });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isEmpty) return;
      var q = _supa.from(table).delete()
          .eq('user_uid', uid)
          .eq('annonce_id', item.annonceId);
      if (item.bebeIndex != null) {
        await q.eq('bebe_index', item.bebeIndex!);
      } else {
        await q.isFilter('bebe_index', null);
      }
    } catch (_) {
      // rollback
      if (table == 'favoris') {
        _loadTab('favoris');
      } else {
        _loadTab('likes');
      }
    }
  }

  void _openDetail(_SavedItem item) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => AnnoncesFeedPage(
        initialAnnonceId: item.annonceId,
        initialBebeIndex: item.bebeIndex,
        initialEspece: item.espece ?? 'tous',
      ),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Mes interactions',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.bookmark, size: 18), text: 'Sauvegardés'),
            Tab(icon: Icon(Icons.favorite, size: 18), text: 'J\'aime'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildFavorisTab(),
          _buildTab(_likeItems, _loadingLikes, 'likes'),
        ],
      ),
    );
  }

  Widget _buildTab(List<_SavedItem> items, bool loading, String table) {
    if (loading) return const Center(child: CircularProgressIndicator(color: _teal));
    if (items.isEmpty) return _buildEmpty(table);
    return RefreshIndicator(
      onRefresh: () => _loadTab(table),
      color: _teal,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.75,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _SavedCard(
          item: items[i],
          isFavori: table == 'favoris',
          onTap:    () => _openDetail(items[i]),
          onRemove: () => _removeItem(items[i], table),
        ),
      ),
    );
  }

  Widget _buildFavorisTab() {
    final loading = _loadingFavs || _loadingPlaces;
    if (loading && _favItems.isEmpty && _placeItems.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: _teal));
    }
    if (_favItems.isEmpty && _placeItems.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.bookmark_border, size: 72, color: Color(0xFFDDE1E4)),
          const SizedBox(height: 16),
          const Text('Aucune sauvegarde',
              style: TextStyle(fontFamily: 'Galey', fontSize: 16, color: Color(0xFFADB5BD))),
          const SizedBox(height: 8),
          const Text('Sauvegarde des annonces ou des lieux\npour les retrouver ici.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFADB5BD))),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: () async { await Future.wait([_loadTab('favoris'), _loadPlaces()]); },
      color: _teal,
      child: CustomScrollView(
        slivers: [
          // ── Lieux sauvegardés ──
          if (_placeItems.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Text('Lieux pet-friendly',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 13, color: Color(0xFF6B7280))),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                  child: _PlaceFavoriCard(
                    place: _placeItems[i],
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => LieuDetailPage(id: _placeItems[i].placeId))),
                    onRemove: () => _removePlace(_placeItems[i].placeId),
                  ),
                ),
                childCount: _placeItems.length,
              ),
            ),
          ],
          // ── Annonces sauvegardées ──
          if (_favItems.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Text('Annonces',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 13, color: Color(0xFF6B7280))),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.75,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _SavedCard(
                    item: _favItems[i],
                    isFavori: true,
                    onTap: () => _openDetail(_favItems[i]),
                    onRemove: () => _removeItem(_favItems[i], 'favoris'),
                  ),
                  childCount: _favItems.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmpty(String table) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(
          table == 'favoris' ? Icons.bookmark_border : Icons.favorite_border,
          size: 72, color: const Color(0xFFDDE1E4)),
        const SizedBox(height: 16),
        Text(
          table == 'favoris' ? 'Aucun animal sauvegardé' : 'Aucun like pour l\'instant',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 16, color: Color(0xFFADB5BD))),
        const SizedBox(height: 8),
        const Text('Utilise le feed pour découvrir et\nsauvegarder des annonces.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFADB5BD))),
        const SizedBox(height: 20),
        TextButton.icon(
          onPressed: () {
            setState(() {
              if (table == 'favoris') _loadedFavs = false;
              else _loadedLikes = false;
            });
            _loadTab(table);
          },
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Réessayer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
          style: TextButton.styleFrom(foregroundColor: _teal),
        ),
      ]),
    );
  }
}

// ── Carte individuelle ────────────────────────────────────────────────────────

class _SavedCard extends StatelessWidget {
  final _SavedItem item;
  final bool isFavori;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _SavedCard({required this.item, required this.isFavori, required this.onTap, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        debugPrint('CARD constraints: ${constraints.maxWidth}×${constraints.maxHeight}');
        return GestureDetector(
          onTap: onTap,
          child: AspectRatio(
            aspectRatio: 0.75,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Fond flouté (couvre toute la carte)
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: CachedNetworkImage(
                      imageUrl: thumbUrl(item.photo, width: 200, quality: 30),
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: const Color(0xFF1A1A1A)),
                      errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFF1A1A1A)),
                    ),
                  ),
                  // Test : URL brute + contain + center pour voir le chiot entier
                  CachedNetworkImage(
                    imageUrl: item.photo,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.high,
                    placeholder: (_, __) => const SizedBox.shrink(),
                    errorWidget: (_, __, ___) => const Icon(Icons.pets, color: Colors.white24, size: 40),
                  ),
                  // Gradient bas pour lisibilité du texte
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xBB000000)],
                        stops: [0.5, 1.0],
                      ),
                    ),
                  ),
                  // Infos bas
                  Positioned(bottom: 10, left: 10, right: 10,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        if (item.sexe != null) ...[
                          Text(item.sexe == 'male' ? '♂' : '♀',
                              style: const TextStyle(color: Colors.white,
                                  fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 4),
                        ],
                        Flexible(child: Text(item.nom,
                            style: const TextStyle(color: Colors.white,
                                fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14),
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ]),
                      if (item.race?.isNotEmpty == true)
                        Text(item.race!,
                            style: const TextStyle(color: Colors.white70,
                                fontFamily: 'Galey', fontSize: 11),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (item.prix != null)
                        Text('${item.prix!.toInt()} €',
                            style: const TextStyle(color: Colors.white,
                                fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
                      if (item.nomEleveur?.isNotEmpty == true)
                        Text('🏡 ${item.nomEleveur}',
                            style: const TextStyle(color: Colors.white60,
                                fontFamily: 'Galey', fontSize: 10),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  // Badge retirer
                  Positioned(top: 8, right: 8,
                    child: GestureDetector(
                      onTap: onRemove,
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          isFavori ? Icons.bookmark : Icons.favorite,
                          color: isFavori ? Colors.amber : Colors.redAccent,
                          size: 17,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Card lieu favori ──────────────────────────────────────────────────────────

class _PlaceFavoriCard extends StatelessWidget {
  final _PlaceFavori place;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  const _PlaceFavoriCard({required this.place, required this.onTap, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF0C5C6C);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        height: 90,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
              child: SizedBox(
                width: 90, height: 90,
                child: place.photoUrl != null
                    ? CachedNetworkImage(imageUrl: place.photoUrl!, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(color: teal, child: const Icon(Icons.store_outlined, color: Colors.white, size: 32)))
                    : Container(color: teal, child: const Icon(Icons.store_outlined, color: Colors.white, size: 32)),
              ),
            ),
            // Infos
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(place.nom,
                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.location_on_outlined, size: 13, color: teal),
                      const SizedBox(width: 3),
                      Expanded(child: Text(place.ville,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          overflow: TextOverflow.ellipsis)),
                    ]),
                  ],
                ),
              ),
            ),
            // Bouton retirer
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.bookmark_remove_outlined, color: Color(0xFF0C5C6C)),
              tooltip: 'Retirer des favoris',
            ),
          ],
        ),
      ),
    );
  }
}
