import 'package:PetsMatch/utils/storage_helper.dart' show thumbUrl;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';

// ── Modèle ────────────────────────────────────────────────────────────────────

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
  final _uid  = FirebaseAuth.instance.currentUser?.uid ?? '';

  late final TabController _tabCtrl;

  List<_SavedItem> _favItems   = [];
  List<_SavedItem> _likeItems  = [];
  bool _loadingFavs   = false;
  bool _loadingLikes  = false;
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
    _loadTab('favoris'); // charger favoris par défaut
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<List<_SavedItem>> _fetchFromTable(String table) async {
    if (_uid.isEmpty) return [];
    final rows = await _supa
        .from(table)
        .select('annonce_id, bebe_index')
        .eq('user_uid', _uid)
        .order('created_at', ascending: false);

    if (rows.isEmpty) return [];

    final ids = rows.map((r) => r['annonce_id'] as String).toSet().toList();
    final annonces = await _supa
        .from('annonces')
        .select('id, titre, espece, race, type, photos, animaux_portee, prix, saillie_prix, ville_eleveur, sexe, nom_eleveur')
        .inFilter('id', ids);

    final annonceMap = <String, Map<String, dynamic>>{
      for (final a in annonces) a['id'] as String: a,
    };

    final result = <_SavedItem>[];
    for (final row in rows) {
      final a = annonceMap[row['annonce_id'] as String];
      if (a == null) continue;
      final aPhotos = List<String>.from(a['photos'] ?? []);
      final bebes   = List<Map<String, dynamic>>.from(a['animaux_portee'] ?? []);
      final bi      = row['bebe_index'] as int?;

      if (bi != null && bi < bebes.length) {
        final b     = bebes[bi];
        final bPh   = List<String>.from(b['photos'] ?? []);
        final photo = bPh.isNotEmpty ? bPh.first : (aPhotos.isNotEmpty ? aPhotos.first : null);
        if (photo == null) continue;
        result.add(_SavedItem(
          annonceId: row['annonce_id'] as String,
          bebeIndex: bi, photo: photo,
          nom:   (b['nom'] as String?)?.isNotEmpty == true ? b['nom'] as String : 'Bébé ${bi + 1}',
          race:  a['race'] as String?,
          espece: a['espece'] as String?,
          sexe:  b['sexe'] as String?,
          prix:  (b['prix'] as num?)?.toDouble(),
          ville: a['ville_eleveur'] as String?,
          nomEleveur: a['nom_eleveur'] as String?,
        ));
      } else if (bi == null) {
        if (aPhotos.isEmpty) continue;
        final prix = (a['saillie_prix'] as num? ?? a['prix'] as num?)?.toDouble();
        result.add(_SavedItem(
          annonceId: row['annonce_id'] as String,
          bebeIndex: null, photo: aPhotos.first,
          nom: (a['titre'] as String?)?.isNotEmpty == true
              ? a['titre'] as String
              : '${a['espece'] ?? ''} ${a['race'] ?? ''}'.trim(),
          race:  a['race'] as String?,
          espece: a['espece'] as String?,
          sexe:  a['sexe'] as String?,
          prix:  prix,
          ville: a['ville_eleveur'] as String?,
          nomEleveur: a['nom_eleveur'] as String?,
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

  Future<void> _removeItem(_SavedItem item, String table) async {
    setState(() {
      if (table == 'favoris') {
        _favItems.removeWhere((i) => i.annonceId == item.annonceId && i.bebeIndex == item.bebeIndex);
      } else {
        _likeItems.removeWhere((i) => i.annonceId == item.annonceId && i.bebeIndex == item.bebeIndex);
      }
    });
    try {
      var q = _supa.from(table).delete()
          .eq('user_uid', _uid)
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
      builder: (_) => AnnonceDetailPage(
        annonceId: item.annonceId,
        initialData: {'_id': item.annonceId},
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
          _buildTab(_favItems, _loadingFavs, 'favoris'),
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
          childAspectRatio: 0.72,
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
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(children: [
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: thumbUrl(item.photo, width: 400, quality: 75),
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: const Color(0xFFE5E7EB)),
              errorWidget: (_, __, ___) => Container(
                color: const Color(0xFFE5E7EB),
                child: const Icon(Icons.pets, color: Colors.white54, size: 40),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xBB000000)],
                  stops: [0.5, 1.0],
                ),
              ),
            ),
          ),
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
        ]),
      ),
    );
  }
}
