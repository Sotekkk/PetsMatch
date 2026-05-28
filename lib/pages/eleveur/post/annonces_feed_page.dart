import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/chatScreen.dart';
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:PetsMatch/pages/user_detail_page_feed.dart';
import 'package:PetsMatch/pages/main_feed.dart' show UserSelected;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/utils/storage_helper.dart' show thumbUrl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Modèle ───────────────────────────────────────────────────────────────────

class _FeedItem {
  final String annonceId;
  final int? bebeIndex;
  final List<String> photos;
  final String nom;
  final String? race;
  final String? espece;
  final String? sexe;
  final double? prix;
  final String? statut;
  final String? description;
  final String? ville;
  final String? uidEleveur;
  final String? nomEleveur;
  final String? photoEleveur;

  const _FeedItem({
    required this.annonceId, required this.bebeIndex,
    required this.photos, required this.nom,
    this.race, this.espece, this.sexe, this.prix,
    this.statut, this.description, this.ville,
    this.uidEleveur, this.nomEleveur, this.photoEleveur,
  });

  _FeedItem withPhoto(String? p) => _FeedItem(
    annonceId: annonceId, bebeIndex: bebeIndex, photos: photos, nom: nom,
    race: race, espece: espece, sexe: sexe, prix: prix, statut: statut,
    description: description, ville: ville, uidEleveur: uidEleveur,
    nomEleveur: nomEleveur, photoEleveur: p,
  );
}

List<_FeedItem> _buildFeedItems(List<Map<String, dynamic>> rows) {
  final items = <_FeedItem>[];
  for (final a in rows) {
    final aPhotos    = List<String>.from(a['photos'] ?? []);
    final bebes      = List<Map<String, dynamic>>.from(a['animaux_portee'] ?? []);
    final uid        = a['uid_eleveur'] as String?;
    final nomEleveur = a['nom_eleveur'] as String?;

    if (a['type'] == 'portee' && bebes.isNotEmpty) {
      for (int i = 0; i < bebes.length; i++) {
        final b = bebes[i];
        final bPhotos = List<String>.from(b['photos'] ?? []);
        final photos  = bPhotos.isNotEmpty ? bPhotos : aPhotos;
        if (photos.isEmpty) continue;
        items.add(_FeedItem(
          annonceId: a['id'] as String, bebeIndex: i, photos: photos,
          nom: b['nom'] as String? ?? 'Bébé ${i + 1}',
          race: a['race'] as String?, espece: a['espece'] as String?,
          sexe: b['sexe'] as String?,
          prix: b['prix'] is num ? (b['prix'] as num).toDouble()
              : b['prix'] is String ? double.tryParse(b['prix'] as String) : null,
          statut: b['statut'] as String?,
          description: b['description'] as String?,
          ville: a['ville_eleveur'] as String?,
          uidEleveur: uid, nomEleveur: nomEleveur,
        ));
      }
    } else if (aPhotos.isNotEmpty) {
      items.add(_FeedItem(
        annonceId: a['id'] as String, bebeIndex: null, photos: aPhotos,
        nom: (a['titre'] as String?)?.isNotEmpty == true
            ? a['titre'] as String
            : '${a['espece'] ?? ''} ${a['race'] ?? ''}'.trim(),
        race: a['race'] as String?, espece: a['espece'] as String?,
        sexe: a['sexe'] as String?,
        prix: () { final v = a['saillie_prix'] ?? a['prix']; return v is num ? v.toDouble() : v is String ? double.tryParse(v) : null; }(),
        ville: a['ville_eleveur'] as String?,
        uidEleveur: uid, nomEleveur: nomEleveur,
      ));
    }
  }
  return items;
}

// ─── Page principale ──────────────────────────────────────────────────────────

class AnnoncesFeedPage extends StatefulWidget {
  final String initialTypeFilter;
  final String initialEspece;
  const AnnoncesFeedPage({
    super.key,
    this.initialTypeFilter = 'tous',
    this.initialEspece = 'tous',
  });

  @override
  State<AnnoncesFeedPage> createState() => _AnnoncesFeedPageState();
}

class _AnnoncesFeedPageState extends State<AnnoncesFeedPage> {
  static const _teal = Color(0xFF0C5C6C);

  bool _feedStarted  = false;
  bool _loading      = false;
  bool _openingChat  = false;

  late String _espece    = widget.initialEspece;
  late String _typeVente = widget.initialTypeFilter;

  List<_FeedItem> _items = [];
  final _vertCtrl        = PageController();
  final _likedKeys       = <String>{};
  final _favoriKeys      = <String>{};

  static const _especeList = [
    ('tous',    'Tous',    '🐾'),
    ('chien',   'Chien',   '🐕'),
    ('chat',    'Chat',    '🐈'),
    ('lapin',   'Lapin',   '🐇'),
    ('oiseau',  'Oiseau',  '🐦'),
    ('reptile', 'Reptile', '🦎'),
    ('autre',   'Autre',   '🐾'),
  ];

  // ── Chargement ──────────────────────────────────────────────────────────────

  Future<void> _loadFeed() async {
    setState(() => _loading = true);
    try {
      var q = Supabase.instance.client
          .from('annonces')
          .select('id, titre, espece, race, type, type_vente, photos, animaux_portee, prix, saillie_prix, ville_eleveur, sexe, nom_eleveur, uid_eleveur')
          .eq('statut', 'disponible');
      if (_espece != 'tous')       q = q.eq('espece', _espece);
      if (_typeVente == 'saillie') q = q.eq('type_vente', 'saillie');
      if (_typeVente == 'vente')   q = q.neq('type_vente', 'saillie');

      final rows = await q.order('created_at', ascending: false);
      var items = _buildFeedItems(List<Map<String, dynamic>>.from(rows));

      // Batch photos éleveurs
      final uids = items.map((i) => i.uidEleveur).whereType<String>().toSet().toList();
      if (uids.isNotEmpty) {
        try {
          final users = await Supabase.instance.client
              .from('users')
              .select('uid, profile_picture_url_elevage, profile_picture_url')
              .inFilter('uid', uids);
          final map = <String, String>{};
          for (final u in List<Map<String, dynamic>>.from(users)) {
            final id  = u['uid'] as String?;
            if (id == null) continue;
            final ph = (u['profile_picture_url_elevage'] as String?)?.isNotEmpty == true
                ? u['profile_picture_url_elevage'] as String
                : (u['profile_picture_url'] as String?) ?? '';
            if (ph.isNotEmpty) map[id] = ph;
          }
          items = items.map((i) => i.withPhoto(i.uidEleveur != null ? map[i.uidEleveur!] : null)).toList();
        } catch (_) {}
      }

      // Likes & favoris
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        try {
          final likes = await Supabase.instance.client
              .from('likes').select('annonce_id, bebe_index').eq('user_uid', uid);
          _likedKeys
            ..clear()
            ..addAll(List<Map<String, dynamic>>.from(likes)
                .map((l) => '${l['annonce_id']}_${l['bebe_index'] ?? 'null'}'));
        } catch (_) {}
        try {
          final favs = await Supabase.instance.client
              .from('favoris').select('annonce_id, bebe_index').eq('user_uid', uid);
          _favoriKeys
            ..clear()
            ..addAll(List<Map<String, dynamic>>.from(favs)
                .map((f) => '${f['annonce_id']}_${f['bebe_index'] ?? 'null'}'));
        } catch (_) {}
      }

      if (mounted) setState(() { _items = items; _loading = false; _feedStarted = true; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Like ────────────────────────────────────────────────────────────────────

  Future<void> _toggleLike(_FeedItem item) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final key     = '${item.annonceId}_${item.bebeIndex ?? 'null'}';
    final wasLiked = _likedKeys.contains(key);
    setState(() { wasLiked ? _likedKeys.remove(key) : _likedKeys.add(key); });
    try {
      if (wasLiked) {
        var q = Supabase.instance.client.from('likes').delete()
            .eq('user_uid', uid).eq('annonce_id', item.annonceId);
        item.bebeIndex != null ? await q.eq('bebe_index', item.bebeIndex!) : await q.isFilter('bebe_index', null);
      } else {
        await Supabase.instance.client.from('likes').upsert({
          'user_uid': uid, 'annonce_id': item.annonceId, 'bebe_index': item.bebeIndex,
        });
        if (item.uidEleveur != null && item.uidEleveur != uid) {
          final name = User_Info.firstname.isNotEmpty ? User_Info.firstname : 'Quelqu\'un';
          await Supabase.instance.client.from('notifications').insert({
            'uid': item.uidEleveur, 'type': 'like',
            'title': '❤️ Nouveau like sur votre annonce',
            'body': '$name a aimé "${item.nom}"',
            'data': {'annonceId': item.annonceId, 'bebeIndex': item.bebeIndex, 'fromUid': uid},
            'read': false,
          });
        }
      }
    } catch (_) {
      setState(() { wasLiked ? _likedKeys.add(key) : _likedKeys.remove(key); });
    }
  }

  // ── Favori ──────────────────────────────────────────────────────────────────

  Future<void> _toggleFavori(_FeedItem item) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final key = '${item.annonceId}_${item.bebeIndex ?? 'null'}';
    final was = _favoriKeys.contains(key);
    setState(() { was ? _favoriKeys.remove(key) : _favoriKeys.add(key); });
    try {
      if (was) {
        var q = Supabase.instance.client.from('favoris').delete()
            .eq('user_uid', uid).eq('annonce_id', item.annonceId);
        item.bebeIndex != null ? await q.eq('bebe_index', item.bebeIndex!) : await q.isFilter('bebe_index', null);
      } else {
        await Supabase.instance.client.from('favoris').upsert({
          'user_uid': uid, 'annonce_id': item.annonceId, 'bebe_index': item.bebeIndex,
        });
      }
    } catch (_) {
      setState(() { was ? _favoriKeys.add(key) : _favoriKeys.remove(key); });
    }
  }

  // ── Partage ──────────────────────────────────────────────────────────────────

  void _shareItem(_FeedItem item) {
    final url = 'https://petsmatch.fr/annonces/${item.annonceId}';
    final parts = <String>[
      item.nom,
      if (item.race?.isNotEmpty == true) item.race!,
      if (item.prix != null) '${item.prix!.toInt()} €',
      if (item.ville?.isNotEmpty == true) '📍 ${item.ville!}',
      if (item.nomEleveur?.isNotEmpty == true) '🏡 ${item.nomEleveur!}',
    ];
    final text = '${parts.join(' · ')}\n\n$url';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareSheet(text: text, url: url, nom: item.nom),
    );
  }

  // ── Profil éleveur ──────────────────────────────────────────────────────────

  Future<void> _navigateToEleveurProfile(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!mounted || !doc.exists) return;
      final user = UserSelected.fromMap(doc.data()!, uid);
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => UserDetailPageFeed(user: user)));
      }
    } catch (_) {}
  }

  // ── Chat ────────────────────────────────────────────────────────────────────

  Future<void> _openChat(_FeedItem item) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null || item.uidEleveur == null || me == item.uidEleveur) return;
    setState(() => _openingChat = true);
    try {
      final sorted       = [me, item.uidEleveur!]..sort();
      final participantIds = sorted.join('_');
      final snap = await FirebaseFirestore.instance
          .collection('conversations')
          .where('participantIds', isEqualTo: participantIds)
          .limit(1).get();
      final ref = snap.docs.isEmpty
          ? await FirebaseFirestore.instance.collection('conversations').add({
              'participants': [me, item.uidEleveur!],
              'participantIds': participantIds,
              'lastMessage': '',
              'timestamp': FieldValue.serverTimestamp(),
              'categorie': 'annonces',
            })
          : snap.docs.first.reference;
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => ChatScreen(conversationId: ref.id, eleveurId: item.uidEleveur!)));
      }
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  void dispose() { _vertCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => _feedStarted ? _buildFeed() : _buildFilters();

  Widget _buildFilters() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F0), elevation: 0,
        foregroundColor: const Color(0xFF1F2A2E),
        title: const Text('Fil d\'actualité',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Personnalise ton feed',
              style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF6F767B))),
          const SizedBox(height: 24),
          const Text('Espèce', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 4, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.85,
            children: _especeList.map((e) {
              final sel = _espece == e.$1;
              return GestureDetector(
                onTap: () => setState(() => _espece = e.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFFE8F4F6) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: sel ? _teal : const Color(0xFFE5E7EB), width: 2),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(e.$3, style: const TextStyle(fontSize: 24)),
                    const SizedBox(height: 4),
                    Text(e.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                        fontWeight: FontWeight.w600, color: sel ? _teal : const Color(0xFF6F767B))),
                  ]),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          const Text('Type', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          Row(children: [
            for (final t in [('tous', 'Tous'), ('vente', '🐾 Compagnon'), ('saillie', '💜 Saillie')])
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _typeVente = t.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _typeVente == t.$1 ? const Color(0xFFE8F4F6) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _typeVente == t.$1 ? _teal : const Color(0xFFE5E7EB), width: 2),
                    ),
                    child: Text(t.$2, textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                            color: _typeVente == t.$1 ? _teal : const Color(0xFF6F767B))),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 40),
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _loadFeed,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal, foregroundColor: Colors.white,
                disabledBackgroundColor: _teal.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Lancer le feed  →',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildFeed() {
    if (_items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('Aucune annonce avec photos',
              style: TextStyle(color: Colors.white, fontFamily: 'Galey', fontSize: 16)),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => setState(() => _feedStarted = false),
            child: const Text('Modifier les filtres', style: TextStyle(color: Colors.white54)),
          ),
        ])),
      );
    }

    return Stack(children: [
      Scaffold(
        backgroundColor: Colors.black,
        body: PageView.builder(
          controller: _vertCtrl,
          scrollDirection: Axis.vertical,
          itemCount: _items.length,
          itemBuilder: (_, i) {
            final item = _items[i];
            final key  = '${item.annonceId}_${item.bebeIndex ?? 'null'}';
            return _FeedCard(
              item:        item,
              isLiked:     _likedKeys.contains(key),
              isFavorited: _favoriKeys.contains(key),
              onLike:      () => _toggleLike(item),
              onFavorite:  () => _toggleFavori(item),
              onMessage:   () => _openChat(item),
              onEleveurTap: item.uidEleveur != null
                  ? () => _navigateToEleveurProfile(item.uidEleveur!)
                  : null,
              onShare: () => _shareItem(item),
              onBack:   () => setState(() => _feedStarted = false),
              onDetail: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AnnonceDetailPage(
                      annonceId: item.annonceId,
                      initialData: {'_id': item.annonceId}))),
            );
          },
        ),
      ),
      if (_openingChat)
        Container(color: Colors.black54,
            child: const Center(child: CircularProgressIndicator(color: Colors.white))),
    ]);
  }
}

// ─── Card ─────────────────────────────────────────────────────────────────────

class _FeedCard extends StatefulWidget {
  final _FeedItem item;
  final bool isLiked;
  final bool isFavorited;
  final VoidCallback onLike;
  final VoidCallback onFavorite;
  final VoidCallback onMessage;
  final VoidCallback onShare;
  final VoidCallback onBack;
  final VoidCallback onDetail;
  final VoidCallback? onEleveurTap;

  const _FeedCard({
    required this.item,
    required this.isLiked, required this.isFavorited,
    required this.onLike, required this.onFavorite,
    required this.onMessage, required this.onShare,
    required this.onBack, required this.onDetail,
    this.onEleveurTap,
  });

  @override
  State<_FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends State<_FeedCard> with SingleTickerProviderStateMixin {
  final _horizCtrl   = PageController();
  int  _photoIndex   = 0;
  bool _descExpanded = false;

  late final AnimationController _likeAnim;
  late final Animation<double>   _likeScale;

  @override
  void initState() {
    super.initState();
    _likeAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _likeScale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _likeAnim, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(_FeedCard old) {
    super.didUpdateWidget(old);
    if (old.item != widget.item) setState(() { _descExpanded = false; _photoIndex = 0; });
  }

  @override
  void dispose() { _horizCtrl.dispose(); _likeAnim.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final item   = widget.item;
    final photos = item.photos;
    final safe   = MediaQuery.of(context).padding;

    return Stack(children: [

      // Photos
      PageView.builder(
        controller: _horizCtrl,
        itemCount: photos.length,
        onPageChanged: (i) => setState(() => _photoIndex = i),
        itemBuilder: (_, pi) => CachedNetworkImage(
          imageUrl: thumbUrl(photos[pi], width: 800, quality: 80, resize: 'contain'),
          fit: BoxFit.contain,
          width: double.infinity, height: double.infinity,
          placeholder: (_, __) => Container(color: Colors.black),
          errorWidget: (_, __, ___) => Container(color: const Color(0xFF111111),
              child: const Center(child: Icon(Icons.pets, color: Colors.white24, size: 60))),
        ),
      ),

      // Dégradé
      Positioned.fill(child: IgnorePointer(child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0x55000000), Colors.transparent, Colors.transparent, Color(0xCC000000)],
            stops: [0, 0.2, 0.5, 1],
          ),
        ),
      ))),

      // Bouton fermer
      Positioned(top: safe.top + 8, left: 16,
        child: _CircleBtn(icon: Icons.close, onTap: widget.onBack)),

      // Flèches photos
      if (photos.length > 1) ...[
        if (_photoIndex > 0)
          Positioned(left: 12, top: 0, bottom: 0,
            child: Center(child: _CircleBtn(icon: Icons.chevron_left,
                onTap: () => _horizCtrl.previousPage(
                    duration: const Duration(milliseconds: 250), curve: Curves.easeInOut)))),
        if (_photoIndex < photos.length - 1)
          Positioned(right: 72, top: 0, bottom: 0,
            child: Center(child: _CircleBtn(icon: Icons.chevron_right,
                onTap: () => _horizCtrl.nextPage(
                    duration: const Duration(milliseconds: 250), curve: Curves.easeInOut)))),
      ],

      // ── Colonne droite TikTok ────────────────────────────────────────────────
      Positioned(
        right: 8, bottom: safe.bottom + 100,
        child: Column(mainAxisSize: MainAxisSize.min, children: [

          // Photo éleveur → profil
          GestureDetector(
            onTap: widget.onEleveurTap,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4)],
              ),
              child: ClipOval(
                child: item.photoEleveur?.isNotEmpty == true
                    ? CachedNetworkImage(imageUrl: item.photoEleveur!,
                        width: 44, height: 44, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _EleveurPhotoPlaceholder())
                    : _EleveurPhotoPlaceholder(),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ❤️ Like
          ScaleTransition(
            scale: _likeScale,
            child: _ActionIcon(
              icon: widget.isLiked ? Icons.favorite : Icons.favorite_border,
              color: widget.isLiked ? Colors.redAccent : Colors.white,
              label: 'J\'aime',
              onTap: () { widget.onLike(); _likeAnim.forward(from: 0); },
            ),
          ),
          const SizedBox(height: 6),

          // 🔖 Favoris
          _ActionIcon(
            icon: widget.isFavorited ? Icons.bookmark : Icons.bookmark_border,
            color: widget.isFavorited ? Colors.amber : Colors.white,
            label: 'Sauvegarder',
            onTap: widget.onFavorite,
          ),
          const SizedBox(height: 6),

          // ✉️ Message
          _ActionIcon(
            icon: Icons.mail_outline_rounded,
            color: Colors.white,
            label: 'Message',
            onTap: widget.onMessage,
          ),
          const SizedBox(height: 6),

          // ↗ Partager
          _ActionIcon(
            icon: Icons.share_outlined,
            color: Colors.white,
            label: 'Partager',
            onTap: widget.onShare,
          ),
        ]),
      ),

      // ── Infos bas (nom → race → ville → description) ─────────────────────────
      Positioned(
        bottom: 0, left: 0, right: 66,
        child: GestureDetector(
          onTap: item.description?.isNotEmpty == true
              ? () => setState(() => _descExpanded = !_descExpanded)
              : null,
          behavior: HitTestBehavior.opaque,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
                stops: [0, 0.55],
              ),
            ),
            padding: EdgeInsets.fromLTRB(16, 80, 16, safe.bottom + 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nom + sexe + prix
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  if (item.sexe != null) ...[
                    Text(item.sexe == 'male' ? '♂' : '♀',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                  ],
                  Expanded(child: Text(item.nom,
                      style: const TextStyle(color: Colors.white, fontFamily: 'Galey',
                          fontWeight: FontWeight.w700, fontSize: 22),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (item.prix != null) ...[
                    const SizedBox(width: 8),
                    Text('${item.prix!.toInt()} €',
                        style: const TextStyle(color: Colors.white, fontFamily: 'Galey',
                            fontWeight: FontWeight.w700, fontSize: 18)),
                  ],
                ]),
                // Race + ville
                if (item.race?.isNotEmpty == true || item.ville?.isNotEmpty == true)
                  Padding(padding: const EdgeInsets.only(top: 3),
                    child: Row(children: [
                      if (item.race?.isNotEmpty == true)
                        Expanded(child: Text(item.race!,
                            style: const TextStyle(color: Colors.white70, fontFamily: 'Galey', fontSize: 14),
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (item.ville?.isNotEmpty == true)
                        Text('📍 ${item.ville}',
                            style: const TextStyle(color: Colors.white54, fontFamily: 'Galey', fontSize: 12)),
                    ])),
                // Éleveur
                if (item.nomEleveur?.isNotEmpty == true)
                  Padding(padding: const EdgeInsets.only(top: 2),
                    child: Text('🏡 ${item.nomEleveur}',
                        style: const TextStyle(color: Colors.white54, fontFamily: 'Galey', fontSize: 11),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                // Description expandable
                if (item.description?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    alignment: Alignment.bottomLeft,
                    child: _descExpanded
                      ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item.description!,
                              style: const TextStyle(color: Colors.white, fontFamily: 'Galey', fontSize: 13,
                                  shadows: [Shadow(color: Colors.black54, blurRadius: 6)])),
                          const SizedBox(height: 4),
                          const Text('↑ Moins', style: TextStyle(color: Colors.white, fontFamily: 'Galey',
                              fontSize: 12, fontWeight: FontWeight.w700)),
                        ])
                      : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Expanded(child: Text(item.description!,
                              style: const TextStyle(color: Colors.white70, fontFamily: 'Galey', fontSize: 13,
                                  shadows: [Shadow(color: Colors.black54, blurRadius: 6)]),
                              maxLines: 2, overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 6),
                          const Text('+ Lire', style: TextStyle(color: Colors.white, fontFamily: 'Galey',
                              fontSize: 12, fontWeight: FontWeight.w700)),
                        ]),
                  ),
                ],
                const SizedBox(height: 10),
                // Voir annonce
                GestureDetector(
                  onTap: widget.onDetail,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white30),
                    ),
                    child: const Text('Voir l\'annonce →',
                        style: TextStyle(color: Colors.white, fontFamily: 'Galey',
                            fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ),
                // Barre photos
                if (photos.length > 1) ...[
                  const SizedBox(height: 10),
                  Row(children: photos.asMap().entries.map((e) => Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 2, margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: e.key == _photoIndex ? Colors.white : Colors.white30,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  )).toList()),
                ],
              ],
            ),
          ),
        ),
      ),
    ]);
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _ActionIcon({required this.icon, required this.color, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Icon(icon, color: color, size: 24),
    ),
  );
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
      child: Icon(icon, color: Colors.white, size: 22),
    ),
  );
}

class _EleveurPhotoPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFF0C5C6C),
    child: const Icon(Icons.store_outlined, color: Colors.white, size: 22),
  );
}

// ─── Share sheet ──────────────────────────────────────────────────────────────

class _ShareSheet extends StatelessWidget {
  final String text, url, nom;
  const _ShareSheet({required this.text, required this.url, required this.nom});

  Future<void> _copy(BuildContext ctx) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (ctx.mounted) {
      Navigator.pop(ctx);
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Lien copié !'), duration: Duration(seconds: 2)));
    }
  }

  Future<void> _launch(BuildContext ctx, Uri uri) async {
    try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
    if (ctx.mounted) Navigator.pop(ctx);
  }

  @override
  Widget build(BuildContext context) {
    final encoded = Uri.encodeComponent(text);
    final waUrl    = Uri.parse('https://wa.me/?text=$encoded');
    final smsUrl   = Uri.parse('sms:?body=$encoded');
    final emailUrl = Uri.parse('mailto:?subject=${Uri.encodeComponent(nom)}&body=$encoded');
    final safe     = MediaQuery.of(context).padding;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, safe.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Text(nom,
          style: const TextStyle(color: Colors.white, fontFamily: 'Galey',
              fontWeight: FontWeight.w700, fontSize: 15),
          maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _ShareBtn(
            icon: const Icon(Icons.link_rounded, color: Colors.white, size: 24),
            bg: const Color(0xFF3A3A4E),
            label: 'Copier le lien',
            onTap: () => _copy(context),
          ),
          _ShareBtn(
            icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white, size: 24),
            bg: const Color(0xFF25D366),
            label: 'WhatsApp',
            onTap: () => _launch(context, waUrl),
          ),
          _ShareBtn(
            icon: const Icon(Icons.sms_outlined, color: Colors.white, size: 24),
            bg: const Color(0xFF4A90E2),
            label: 'SMS',
            onTap: () => _launch(context, smsUrl),
          ),
          _ShareBtn(
            icon: const Icon(Icons.mail_outline_rounded, color: Colors.white, size: 24),
            bg: const Color(0xFFEA4335),
            label: 'Email',
            onTap: () => _launch(context, emailUrl),
          ),
        ]),
      ]),
    );
  }
}

class _ShareBtn extends StatelessWidget {
  final Widget icon;
  final Color bg;
  final String label;
  final VoidCallback onTap;
  const _ShareBtn({required this.icon, required this.bg, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 56, height: 56,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Center(child: icon),
      ),
      const SizedBox(height: 6),
      SizedBox(width: 60,
        child: Text(label,
          style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'Galey'),
          textAlign: TextAlign.center, maxLines: 2)),
    ]),
  );
}
