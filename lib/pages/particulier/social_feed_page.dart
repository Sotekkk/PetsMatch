import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

// ─── Palette ──────────────────────────────────────────────────────────────────

const _tealC  = Color(0xFF0C5C6C);
const _darkC  = Color(0xFF0D1F22);
const _green  = Color(0xFF6E9E57);
const _greyC  = Color(0xFF9CA3AF);


// Fond — dégradé teal profond du haut vers le bas
const _bgGrad = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF071C22), Color(0xFF0C3535), Color(0xFF0C3520)],
  stops: [0.0, 0.5, 1.0],
);

// Ring avatar
const _ringGrad = LinearGradient(
  begin: Alignment.topRight,
  end: Alignment.bottomLeft,
  colors: [Color(0xFF6E9E57), Color(0xFF0C5C6C), Color(0xFF0A3F4A)],
);

// ─── Cosmétiques ───────────────────────────────────────────────────────────
const _cosmeticRings = <String, LinearGradient>{
  'ring_gold':    LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFFFFD700), Color(0xFFFF9500), Color(0xFFFF6B00)]),
  'ring_rose':    LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFFFF6B9D), Color(0xFFFF4081), Color(0xFF9B59B6)]),
  'ring_fire':    LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFFFF4500), Color(0xFFFF6B00), Color(0xFFFFAA00)]),
  'ring_arctic':  LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF90E0EF), Color(0xFF48CAE4), Color(0xFF00B4DB)]),
  'ring_galaxy':  LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFFF093FB), Color(0xFF764BA2), Color(0xFF667EEA)]),
  'ring_rainbow': LinearGradient(begin: Alignment.topLeft,  end: Alignment.bottomRight, colors: [Color(0xFFFF0080), Color(0xFFFF8C00), Color(0xFF00C9FF), Color(0xFF00FF87)]),
};

const _cosmeticBanners = <String, LinearGradient>{
  // ── Dégradés ──
  'banner_sunset': LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFC5C7D), Color(0xFF6A3093)]),
  'banner_ocean':  LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2193B0), Color(0xFF6DD5FA)]),
  'banner_forest': LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF134E5E), Color(0xFF71B280)]),
  'banner_galaxy': LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1A1A2E), Color(0xFF764BA2), Color(0xFFF093FB)]),
  'banner_rose':   LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFC466B), Color(0xFF3F5EFB)]),
  'banner_aurora': LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF00C9FF), Color(0xFF92FE9D)]),
  // ── Couleurs unies (même couleur x2 = solid) ──
  'color_noir':    LinearGradient(colors: [Color(0xFF0A0A0A), Color(0xFF0A0A0A)]),
  'color_blanc':   LinearGradient(colors: [Color(0xFFF2F2F2), Color(0xFFF2F2F2)]),
  'color_teal':    LinearGradient(colors: [Color(0xFF0C5C6C), Color(0xFF0C5C6C)]),
  'color_vert':    LinearGradient(colors: [Color(0xFF2D6A4F), Color(0xFF2D6A4F)]),
  'color_beige':   LinearGradient(colors: [Color(0xFFF5E6D3), Color(0xFFF5E6D3)]),
  'color_gris':    LinearGradient(colors: [Color(0xFF2C3E50), Color(0xFF2C3E50)]),
};

/// Résout la décoration d'une bannière à partir de son id :
/// - URL http → image réseau (BoxFit.cover)
/// - clé gradient/couleur → LinearGradient de _cosmeticBanners
/// - null → fond sombre par défaut
BoxDecoration _bannerDecoration(String? key) {
  if (key == null) return const BoxDecoration(gradient: _bgGrad);
  if (key.startsWith('http')) {
    return BoxDecoration(
      image: DecorationImage(image: NetworkImage(key), fit: BoxFit.cover),
    );
  }
  final grad = _cosmeticBanners[key];
  return grad != null ? BoxDecoration(gradient: grad) : const BoxDecoration(gradient: _bgGrad);
}

// Catalogue — ajouter ici les nouvelles bannières image quand prêtes
// Pour une bannière image : ajouter 'preview_url' avec l'URL de la miniature
const _cosmeticCatalog = <Map<String, Object>>[
  {'id': 'ring_gold',       'type': 'avatar_ring',    'label': 'Anneau Doré',              'cost': 150},
  {'id': 'ring_rose',       'type': 'avatar_ring',    'label': 'Anneau Rose Sakura',        'cost': 150},
  {'id': 'ring_fire',       'type': 'avatar_ring',    'label': 'Anneau Flammes',            'cost': 150},
  {'id': 'ring_arctic',     'type': 'avatar_ring',    'label': 'Anneau Arctique',           'cost': 150},
  {'id': 'ring_galaxy',     'type': 'avatar_ring',    'label': 'Anneau Galaxie',            'cost': 200},
  {'id': 'ring_rainbow',    'type': 'avatar_ring',    'label': 'Anneau Arc-en-ciel',        'cost': 250},
  // ── Bannières dégradé ──
  {'id': 'banner_sunset',   'type': 'profile_banner', 'label': 'Coucher de soleil',         'cost': 200},
  {'id': 'banner_ocean',    'type': 'profile_banner', 'label': 'Océan',                     'cost': 200},
  {'id': 'banner_forest',   'type': 'profile_banner', 'label': 'Forêt',                     'cost': 200},
  {'id': 'banner_galaxy',   'type': 'profile_banner', 'label': 'Galaxie',                   'cost': 250},
  {'id': 'banner_rose',     'type': 'profile_banner', 'label': 'Rose Violet',               'cost': 200},
  {'id': 'banner_aurora',   'type': 'profile_banner', 'label': 'Aurora',                    'cost': 250},
  // ── Couleurs unies ──
  {'id': 'color_noir',      'type': 'profile_banner', 'label': 'Noir',                      'cost': 100},
  {'id': 'color_blanc',     'type': 'profile_banner', 'label': 'Blanc',                     'cost': 100},
  {'id': 'color_teal',      'type': 'profile_banner', 'label': 'Teal',                      'cost': 100},
  {'id': 'color_vert',      'type': 'profile_banner', 'label': 'Vert forêt',                'cost': 100},
  {'id': 'color_beige',     'type': 'profile_banner', 'label': 'Beige',                     'cost': 100},
  {'id': 'color_gris',      'type': 'profile_banner', 'label': 'Gris ardoise',              'cost': 100},
  // ── Bannières image custom — ajouter ici ──
  // {'id': 'img_animaux',   'type': 'profile_banner', 'label': 'Animaux',  'cost': 350, 'preview_url': 'https://...', 'banner_url': 'https://...'},
];

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _profileName(Map<String, dynamic>? p) {
  if (p == null) return 'Membre';
  final n = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
  if (n.isNotEmpty) return n;
  final ne = (p['nom'] ?? '').toString();
  return ne.isNotEmpty ? ne : 'Membre';
}

const _kAuthorCols = 'id, uid, firstname, lastname, avatar_url, profile_type, nom';

/// Id du profil PARTICULIER d'un uid — identité utilisée dans le réseau social,
/// jamais le profil pro / is_main. Mémoïsé (les inserts like/follow l'appellent
/// souvent).
final Map<String, String?> _pidCache = {};
Future<String?> _particulierProfileId(String uid) async {
  if (uid.isEmpty) return null;
  if (_pidCache.containsKey(uid)) return _pidCache[uid];
  try {
    final rows = await Supabase.instance.client
        .from('user_profiles')
        .select('id')
        .eq('uid', uid)
        .eq('profile_type', 'particulier')
        .order('is_main', ascending: false)
        .limit(1);
    final id = (rows as List).isNotEmpty ? rows.first['id'] as String? : null;
    _pidCache[uid] = id;
    return id;
  } catch (_) {
    return null;
  }
}

/// Insère un like en renseignant le profil particulier du liker.
Future<void> _insertLike(String postId, String uid) async {
  final pid = await _particulierProfileId(uid);
  await Supabase.instance.client.from('post_likes').insert({
    'post_id': postId,
    'uid': uid,
    if (pid != null) 'author_profile_id': pid,
  });
}

/// Insère une relation de suivi en renseignant les profils particulier des
/// deux parties.
Future<void> _insertFollow(String followerUid, String followingUid) async {
  final fp = await _particulierProfileId(followerUid);
  final tp = await _particulierProfileId(followingUid);
  await Supabase.instance.client.from('follows').insert({
    'follower_uid': followerUid,
    'following_uid': followingUid,
    if (fp != null) 'follower_profile_id': fp,
    if (tp != null) 'following_profile_id': tp,
  });
}

/// Résout les profils PARTICULIER auteurs de posts/commentaires via
/// `author_profile_id` (repli : profil particulier de l'uid pour les anciennes
/// lignes non rétro-remplies). Retourne une map uid -> ligne user_profiles.
Future<Map<String, Map<String, dynamic>>> _resolveAuthors(List<dynamic> rows) async {
  final supa = Supabase.instance.client;
  final out = <String, Map<String, dynamic>>{};
  final profIds = rows
      .map((r) => r['author_profile_id'] as String?)
      .whereType<String>()
      .toSet()
      .toList();
  if (profIds.isNotEmpty) {
    final byId = await supa.from('user_profiles').select(_kAuthorCols).inFilter('id', profIds);
    for (final r in byId as List) {
      out[r['uid'] as String] = Map<String, dynamic>.from(r as Map);
    }
  }
  final missing = rows
      .map((r) => r['uid'] as String)
      .toSet()
      .where((u) => !out.containsKey(u))
      .toList();
  if (missing.isNotEmpty) {
    final byUid = await supa.from('user_profiles').select(_kAuthorCols)
        .inFilter('uid', missing).eq('profile_type', 'particulier');
    for (final r in byUid as List) {
      out.putIfAbsent(r['uid'] as String, () => Map<String, dynamic>.from(r as Map));
    }
  }
  // Fetch avatar ring cosmetics for all resolved authors
  final uids = out.keys.toList();
  if (uids.isNotEmpty) {
    try {
      final cosmetics = await supa.from('user_cosmetics')
          .select('uid, active_value')
          .inFilter('uid', uids)
          .eq('cosmetic_type', 'avatar_ring');
      for (final c in cosmetics as List) {
        final u = c['uid'] as String;
        if (out.containsKey(u) && c['active_value'] != null) {
          out[u]!['_ring'] = c['active_value'] as String;
        }
      }
    } catch (_) {}
  }
  return out;
}

String? _profilePhoto(Map<String, dynamic>? p) =>
    p?['avatar_url']?.toString();

List<String> _mediaUrls(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  if (raw.startsWith('[')) {
    try { return List<String>.from(jsonDecode(raw) as List); } catch (_) {}
  }
  return [raw];
}

String _fmtDate(String iso) {
  try {
    final dt   = DateTime.parse(iso).toLocal();
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inHours < 1) return 'Il y a ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'Il y a ${diff.inHours}h';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays}j';
    return DateFormat('dd/MM/yyyy').format(dt);
  } catch (_) {
    return '';
  }
}

Widget _avatarWidget(String? photoUrl, double radius, {String? ringStyle}) {
  final grad = ringStyle != null ? (_cosmeticRings[ringStyle] ?? _ringGrad) : _ringGrad;
  return Container(
    padding: const EdgeInsets.all(2.5),
    decoration: BoxDecoration(shape: BoxShape.circle, gradient: grad),
    child: Container(
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFFD4EDE8),
        backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
            ? NetworkImage(photoUrl)
            : null,
        child: (photoUrl == null || photoUrl.isEmpty)
            ? Icon(Icons.pets_outlined, size: radius * 0.9, color: _tealC)
            : null,
      ),
    ),
  );
}

// ─── Page principale ──────────────────────────────────────────────────────────

class SocialFeedPage extends StatefulWidget {
  const SocialFeedPage({super.key});
  @override
  State<SocialFeedPage> createState() => _SocialFeedPageState();
}

class _SocialFeedPageState extends State<SocialFeedPage> {
  int _tabIndex   = 0;
  int _refresh    = 0;
  int _notifCount = 0;
  final _supa = Supabase.instance.client;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _loadNotifCount();
  }

  Future<void> _loadNotifCount() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSeenStr = prefs.getString('notif_seen_at_$uid');
      final lastSeen = lastSeenStr != null ? DateTime.tryParse(lastSeenStr) : null;

      final myPosts = await _supa.from('posts_socialmedia').select('id').eq('uid', uid);
      final postIds = (myPosts as List).map((p) => p['id'] as String).toList();
      int count = 0;
      if (postIds.isNotEmpty) {
        var q = _supa.from('post_comments')
            .select('id')
            .inFilter('post_id', postIds)
            .neq('uid', uid);
        if (lastSeen != null) {
          q = q.gt('created_at', lastSeen.toIso8601String());
        }
        final comments = await q.limit(99);
        count += (comments as List).length;
      }
      var fq = _supa.from('follows').select('follower_uid').eq('following_uid', uid);
      if (lastSeen != null) {
        fq = fq.gt('created_at', lastSeen.toIso8601String());
      }
      final follows = await fq;
      count += (follows as List).length;
      if (mounted) setState(() => _notifCount = count > 99 ? 99 : count);
    } catch (_) {}
  }

  Future<void> _markNotifSeen() async {
    final uid = _uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_seen_at_$uid', DateTime.now().toIso8601String());
  }

  void _openCreate() {
    if (_uid == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreatePostSheet(
        myUid: _uid!,
        onPosted: () => setState(() => _refresh++),
      ),
    );
  }

  void _openSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchSheet(myUid: _uid ?? ''),
    );
  }

  void _openNotifications() {
    if (_uid == null) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SocialNotificationsPage(myUid: _uid!),
    ));
  }

  void _openMyProfile() {
    if (_uid == null) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SocialProfilePage(targetUid: _uid!, myUid: _uid!),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid ?? '';
    return Scaffold(
      backgroundColor: _darkC,
      body: Stack(children: [
        // ── Fond dégradé + silhouettes ─────────────────────────────
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(gradient: _bgGrad),
          ),
        ),

        // ── Contenu ────────────────────────────────────────────────
        SafeArea(
          child: Column(children: [
            _buildHeader(),
            _buildPillTabs(),
            Expanded(
              child: IndexedStack(
                index: _tabIndex,
                children: [
                  _FeedList(
                      key: ValueKey('following_$_refresh'),
                      type: 'following',
                      myUid: uid),
                  _FeedList(
                      key: ValueKey('discover_$_refresh'),
                      type: 'discover',
                      myUid: uid),
                  _MyPostsList(
                      key: ValueKey('myposts_$_refresh'),
                      myUid: uid,
                      onRefresh: () => setState(() => _refresh++)),
                ],
              ),
            ),
          ]),
        ),
      ]),

      // ── FAB ────────────────────────────────────────────────────
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_tealC, _green]),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
                color: _tealC.withValues(alpha: 0.45),
                blurRadius: 14,
                offset: const Offset(0, 5))
          ],
        ),
        child: FloatingActionButton(
          backgroundColor: Colors.transparent,
          elevation: 0,
          onPressed: _openCreate,
          child: const Icon(Icons.add_a_photo_outlined, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 10),
      child: Row(children: [
        // ── Titre "Pets Social" — INTOUCHÉ ──────────────────────
        Expanded(
          child: Row(children: [
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                colors: [Color(0xFFFFE080), Color(0xFFFFF5C3)],
              ).createShader(b),
              child: const Text('Pets',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      color: Colors.white)),
            ),
            const Text(' Social',
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w300,
                    fontSize: 22,
                    color: Colors.white,
                    letterSpacing: 0.5)),
          ]),
        ),
        // ── Boutons header ───────────────────────────────────────
        _headerBtn(Icons.search_rounded, _openSearch),
        const SizedBox(width: 8),
        Stack(clipBehavior: Clip.none, children: [
          _headerBtn(Icons.notifications_outlined, () {
            setState(() => _notifCount = 0);
            _markNotifSeen();
            _openNotifications();
          }),
          if (_notifCount > 0)
            Positioned(
              top: -4, right: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0D1F22), width: 1.5)),
                child: Text(_notifCount > 9 ? '9+' : '$_notifCount',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 9,
                        fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
        ]),
        const SizedBox(width: 8),
        _headerBtn(Icons.person_outline_rounded, _openMyProfile),
      ]),
    );
  }

  Widget _headerBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
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
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildPillTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _pill('Mon feed', 0),
          const SizedBox(width: 8),
          _pill('Découverte', 1),
          const SizedBox(width: 8),
          _pill('Mes posts', 2),
        ],
      ),
    );
  }

  Widget _pill(String label, int idx) {
    final active = _tabIndex == idx;
    return GestureDetector(
      onTap: () => setState(() => _tabIndex = idx),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: active ? const LinearGradient(colors: [_tealC, _green]) : null,
              color: active ? null : Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                  color: active
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.20)),
              boxShadow: active
                  ? [
                      BoxShadow(
                          color: _tealC.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 3))
                    ]
                  : null,
            ),
            child: Text(label,
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 12,
                    fontWeight:
                        active ? FontWeight.w700 : FontWeight.w500,
                    color: Colors.white,
                    letterSpacing: active ? 0.3 : 0)),
          ),
        ),
      ),
    );
  }
}

// ─── Skeleton loading ────────────────────────────────────────────────────────

class _SkeletonFeed extends StatefulWidget {
  const _SkeletonFeed();
  @override
  State<_SkeletonFeed> createState() => _SkeletonFeedState();
}

class _SkeletonFeedState extends State<_SkeletonFeed>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.04, end: 0.12).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, __) => Container(
          height: 220,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _anim.value),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 42, height: 42, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: _anim.value * 2))),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 120, height: 12, decoration: BoxDecoration(color: Colors.white.withValues(alpha: _anim.value * 2), borderRadius: BorderRadius.circular(6))),
                  const SizedBox(height: 6),
                  Container(width: 70, height: 9, decoration: BoxDecoration(color: Colors.white.withValues(alpha: _anim.value), borderRadius: BorderRadius.circular(6))),
                ]),
              ]),
              const SizedBox(height: 14),
              Container(width: double.infinity, height: 11, decoration: BoxDecoration(color: Colors.white.withValues(alpha: _anim.value * 1.5), borderRadius: BorderRadius.circular(6))),
              const SizedBox(height: 8),
              Container(width: 200, height: 11, decoration: BoxDecoration(color: Colors.white.withValues(alpha: _anim.value), borderRadius: BorderRadius.circular(6))),
              const SizedBox(height: 16),
              Expanded(child: Container(decoration: BoxDecoration(color: Colors.white.withValues(alpha: _anim.value), borderRadius: BorderRadius.circular(14)))),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── Suggestions à suivre (empty state Mon feed) ──────────────────────────────

class _SuggestionsWidget extends StatefulWidget {
  final String myUid;
  final VoidCallback onFollowed;
  const _SuggestionsWidget({required this.myUid, required this.onFollowed});
  @override
  State<_SuggestionsWidget> createState() => _SuggestionsWidgetState();
}

class _SuggestionsWidgetState extends State<_SuggestionsWidget> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _suggestions = [];
  Set<String> _followed = {};
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final follows = await _supa.from('follows').select('following_uid').eq('follower_uid', widget.myUid);
    _followed = {for (final r in follows as List) r['following_uid'] as String};
    final excludeUids = [..._followed, widget.myUid];

    final recent = await _supa.from('posts_socialmedia')
        .select('uid')
        .order('created_at', ascending: false)
        .limit(100);
    final uidsSeen = <String>{};
    final candidateUids = <String>[];
    for (final r in recent as List) {
      final uid = r['uid'] as String;
      if (!excludeUids.contains(uid) && uidsSeen.add(uid)) {
        candidateUids.add(uid);
        if (candidateUids.length >= 10) break;
      }
    }
    if (candidateUids.isEmpty) { if (mounted) setState(() => _loading = false); return; }
    final profRows = await _supa.from('user_profiles')
        .select('uid, firstname, lastname, avatar_url, profile_type, nom')
        .inFilter('uid', candidateUids)
        .eq('profile_type', 'particulier');
    if (mounted) {
      setState(() {
        _suggestions = (profRows as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    }
  }

  Future<void> _follow(String targetUid) async {
    await _insertFollow(widget.myUid, targetUid);
    setState(() => _followed.add(targetUid));
    await Future.delayed(const Duration(milliseconds: 600));
    widget.onFollowed();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_suggestions.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [_tealC, _green]), shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: _tealC.withValues(alpha: 0.35), blurRadius: 24)]),
            child: const Icon(Icons.photo_library_outlined, size: 52, color: Colors.white)),
          const SizedBox(height: 20),
          const Text('Soyez le premier à publier !', textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
      ));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text('Suggestions · À suivre', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
        ),
        ..._suggestions.map((prof) {
          final uid = prof['uid'] as String;
          final isFollowed = _followed.contains(uid);
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              leading: _avatarWidget(_profilePhoto(prof), 22),
              title: Text(_profileName(prof), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
              subtitle: prof['profile_type'] == 'eleveur'
                  ? const Text('Éleveur Pro', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: _green))
                  : const Text('Particulier', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white54)),
              trailing: GestureDetector(
                onTap: isFollowed ? null : () => _follow(uid),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: isFollowed ? null : const LinearGradient(colors: [_tealC, _green]),
                    color: isFollowed ? Colors.white.withValues(alpha: 0.10) : null,
                    borderRadius: BorderRadius.circular(18),
                    border: isFollowed ? Border.all(color: Colors.white24) : null,
                  ),
                  child: Text(isFollowed ? 'Suivi ✓' : 'Suivre',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ),
          );
        }),
      ]),
    );
  }
}

// ─── Feed list ────────────────────────────────────────────────────────────────

class _FeedList extends StatefulWidget {
  final String type;
  final String myUid;
  const _FeedList({super.key, required this.type, required this.myUid});
  @override
  State<_FeedList> createState() => _FeedListState();
}

class _FeedListState extends State<_FeedList>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _posts    = [];
  Map<String, Map<String, dynamic>> _profiles = {};
  Set<String> _liked     = {};
  Set<String> _following = {};
  bool   _loading   = true;
  String? _feedError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _feedError = null; });
    try {
      if (widget.myUid.isNotEmpty) {
        try {
          final rows = await _supa
              .from('follows')
              .select('following_uid')
              .eq('follower_uid', widget.myUid);
          _following = {for (final r in rows as List) r['following_uid'] as String};
        } catch (_) {
          _following = {};
        }
      }

      List<dynamic> posts;
      if (widget.type == 'following') {
        final uids = <String>{
          ..._following,
          if (widget.myUid.isNotEmpty) widget.myUid,
        }.toList();
        if (uids.isEmpty) {
          posts = [];
        } else if (uids.length == 1) {
          posts = await _supa
              .from('posts_socialmedia')
              .select()
              .eq('uid', uids.first)
              .order('created_at', ascending: false)
              .limit(50);
        } else {
          posts = await _supa
              .from('posts_socialmedia')
              .select()
              .inFilter('uid', uids)
              .order('created_at', ascending: false)
              .limit(50);
        }
      } else {
        posts = await _supa
            .from('posts_socialmedia')
            .select()
            .order('created_at', ascending: false)
            .limit(50);
        // Posts boostés remontent en tête de Découverte
        final now = DateTime.now();
        posts.sort((a, b) {
          final aUntil = a['boosted_until'] != null ? DateTime.tryParse(a['boosted_until'] as String) : null;
          final bUntil = b['boosted_until'] != null ? DateTime.tryParse(b['boosted_until'] as String) : null;
          final aBoosted = aUntil?.isAfter(now) == true;
          final bBoosted = bUntil?.isAfter(now) == true;
          if (aBoosted && !bBoosted) return -1;
          if (!aBoosted && bBoosted) return 1;
          return 0;
        });
      }

      if (posts.isEmpty) {
        if (mounted) setState(() { _posts = []; _loading = false; });
        return;
      }

      final postIds = posts.map((p) => p['id'] as String).toList();

      _profiles = await _resolveAuthors(posts);

      final allLikes = await _supa
          .from('post_likes')
          .select('post_id, uid')
          .inFilter('post_id', postIds);
      final likeCounts = <String, int>{};
      _liked = {};
      for (final l in allLikes as List) {
        final pid = l['post_id'] as String;
        likeCounts[pid] = (likeCounts[pid] ?? 0) + 1;
        if (l['uid'] == widget.myUid) _liked.add(pid);
      }

      final allComments = await _supa
          .from('post_comments')
          .select('post_id')
          .inFilter('post_id', postIds);
      final commentCounts = <String, int>{};
      for (final c in allComments as List) {
        final pid = c['post_id'] as String;
        commentCounts[pid] = (commentCounts[pid] ?? 0) + 1;
      }

      for (final post in posts) {
        post['like_count']    = likeCounts[post['id']] ?? 0;
        post['comment_count'] = commentCounts[post['id']] ?? 0;
      }

      if (mounted) {
        setState(() {
          _posts   = posts.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _feedError = e.toString(); });
    }
  }

  Future<void> _toggleLike(String postId) async {
    final isLiked = _liked.contains(postId);
    setState(() {
      if (isLiked) {
        _liked.remove(postId);
        final i = _posts.indexWhere((p) => p['id'] == postId);
        if (i >= 0) _posts[i]['like_count'] = (_posts[i]['like_count'] as int) - 1;
      } else {
        _liked.add(postId);
        final i = _posts.indexWhere((p) => p['id'] == postId);
        if (i >= 0) _posts[i]['like_count'] = (_posts[i]['like_count'] as int) + 1;
      }
    });
    try {
      if (isLiked) {
        await _supa.from('post_likes').delete()
            .eq('post_id', postId).eq('uid', widget.myUid);
      } else {
        await _insertLike(postId, widget.myUid);
      }
    } catch (_) {
      setState(() {
        if (isLiked) {
          _liked.add(postId);
          final i = _posts.indexWhere((p) => p['id'] == postId);
          if (i >= 0) _posts[i]['like_count'] = (_posts[i]['like_count'] as int) + 1;
        } else {
          _liked.remove(postId);
          final i = _posts.indexWhere((p) => p['id'] == postId);
          if (i >= 0) _posts[i]['like_count'] = (_posts[i]['like_count'] as int) - 1;
        }
      });
    }
  }

  Future<void> _toggleFollow(String targetUid) async {
    final isFollowing = _following.contains(targetUid);
    setState(() {
      if (isFollowing) { _following.remove(targetUid); }
      else { _following.add(targetUid); }
    });
    try {
      if (isFollowing) {
        await _supa.from('follows').delete()
            .eq('follower_uid', widget.myUid)
            .eq('following_uid', targetUid);
      } else {
        await _insertFollow(widget.myUid, targetUid);
      }
    } catch (_) {
      setState(() {
        if (isFollowing) { _following.add(targetUid); }
        else { _following.remove(targetUid); }
      });
    }
  }

  Future<void> _deletePost(String postId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Supprimer ?',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Cette action est irréversible.',
            style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    await _supa.from('posts_socialmedia').delete().eq('id', postId);
    setState(() => _posts.removeWhere((p) => p['id'] == postId));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const _SkeletonFeed();
    }
    if (_feedError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Erreur: $_feedError',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: 'Galey',
                  color: Colors.redAccent,
                  fontSize: 12)),
        ),
      );
    }
    if (_posts.isEmpty) {
      if (widget.type == 'following') {
        return _SuggestionsWidget(myUid: widget.myUid, onFollowed: _load);
      }
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [_tealC, _green]),
                shape: BoxShape.circle, boxShadow: [BoxShadow(color: _tealC.withValues(alpha: 0.35), blurRadius: 24)]),
            child: const Icon(Icons.photo_library_outlined, size: 52, color: Colors.white)),
          const SizedBox(height: 20),
          const Text('Aucune publication pour l\'instant', textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)),
        ]),
      ));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _tealC,
      backgroundColor: Colors.white,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _posts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, i) {
          final post   = _posts[i];
          final postId = post['id'] as String;
          return _SocialPostCard(
            post: post,
            profile: _profiles[post['uid']],
            isLiked: _liked.contains(postId),
            isFollowing: _following.contains(post['uid'] as String),
            isMyPost: post['uid'] == widget.myUid,
            myUid: widget.myUid,
            onLike: () => _toggleLike(postId),
            onFollow: () => _toggleFollow(post['uid'] as String),
            onDelete: () => _deletePost(postId),
            onComment: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _CommentsSheet(
                postId: postId,
                myUid: widget.myUid,
                onCommentAdded: () => setState(() {
                  final idx = _posts.indexWhere((p) => p['id'] == postId);
                  if (idx >= 0) {
                    _posts[idx]['comment_count'] =
                        (_posts[idx]['comment_count'] as int) + 1;
                  }
                }),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Post card ────────────────────────────────────────────────────────────────

class _SocialPostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final Map<String, dynamic>? profile;
  final bool isLiked;
  final bool isFollowing;
  final bool isMyPost;
  final String myUid;
  final VoidCallback onLike;
  final VoidCallback onFollow;
  final VoidCallback onDelete;
  final VoidCallback onComment;

  const _SocialPostCard({
    required this.post,
    required this.profile,
    required this.isLiked,
    required this.isFollowing,
    required this.isMyPost,
    required this.myUid,
    required this.onLike,
    required this.onFollow,
    required this.onDelete,
    required this.onComment,
  });

  @override
  State<_SocialPostCard> createState() => _SocialPostCardState();
}

class _SocialPostCardState extends State<_SocialPostCard> {
  bool _showHeart = false;
  String? _boostedUntilOverride;

  void _doubleTapLike() {
    if (!widget.isLiked) widget.onLike();
    HapticFeedback.lightImpact();
    setState(() => _showHeart = true);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _showHeart = false);
    });
  }

  void _goToProfile() {
    final targetUid = widget.profile?['uid'] as String?;
    if (targetUid == null) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SocialProfilePage(targetUid: targetUid, myUid: widget.myUid)));
  }

  void _showReportDialog() {
    final supa = Supabase.instance.client;
    final postId = widget.post['id'] as String;
    final reasons = ['Contenu inapproprié', 'Spam', 'Harcèlement', 'Fausse information', 'Autre'];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0C3535),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Signaler ce post', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pourquoi signaler ce contenu ?', style: TextStyle(fontFamily: 'Galey', color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 12),
            ...reasons.map((r) => GestureDetector(
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await supa.from('post_reports').insert({
                    'post_id': postId,
                    'reporter_uid': widget.myUid,
                    'reason': r,
                  });
                } catch (_) {}
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Signalement envoyé, merci.', style: TextStyle(fontFamily: 'Galey')),
                    backgroundColor: Color(0xFF0C5C6C),
                    duration: Duration(seconds: 3),
                  ));
                }
              },
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: Text(r, style: const TextStyle(fontFamily: 'Galey', color: Colors.white, fontSize: 13)),
              ),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey', color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  bool _isBoosted(String? until) {
    final raw = _boostedUntilOverride ?? until;
    if (raw == null) return false;
    final dt = DateTime.tryParse(raw);
    return dt != null && dt.isAfter(DateTime.now());
  }

  Future<void> _showBoostDialog() async {
    final supa = Supabase.instance.client;
    final uid = widget.myUid;
    const cost = 50;

    final walletRow = await supa.from('credit_wallets').select().eq('uid', uid).maybeSingle();
    final solde = (walletRow?['solde'] as int?) ?? 0;

    if (!mounted) return;

    if (solde < cost) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Crédits insuffisants',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
          content: Text(
            'Vous avez $solde crédit${solde > 1 ? 's' : ''}.\nBooster un post coûte $cost crédits.',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6E9E57)),
              child: const Text('Acheter des crédits',
                  style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
            ),
          ],
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Booster ce post',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text(
          'Dépenser $cost crédits pour mettre ce post en avant ?\n\nSolde actuel : $solde crédits',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0C5C6C)),
            child: const Text('Booster 🚀',
                style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final newSolde = solde - cost;
      final newTotalUtilise = ((walletRow?['total_utilise'] as int?) ?? 0) + cost;
      await Future.wait([
        supa.from('credit_wallets').upsert({
          'uid': uid,
          'solde': newSolde,
          'total_utilise': newTotalUtilise,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'uid'),
        supa.from('credit_transactions').insert({
          'uid': uid,
          'montant': -cost,
          'motif': 'Boost de post',
          'ref_id': widget.post['id'] as String,
        }),
        supa.from('posts_socialmedia').update({
          'boosted_until': DateTime.now().add(const Duration(hours: 48)).toIso8601String(),
        }).eq('id', widget.post['id'] as String),
      ]);
      if (mounted) {
        final until = DateTime.now().add(const Duration(hours: 48)).toIso8601String();
        setState(() => _boostedUntilOverride = until);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Post boosté ! 🚀', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Color(0xFF0C5C6C),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erreur lors du boost', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name         = _profileName(widget.profile);
    final photoUrl     = _profilePhoto(widget.profile);
    final text         = widget.post['texte']?.toString() ?? '';
    final mediaUrl     = widget.post['media_url']?.toString();
    final date         = widget.post['created_at']?.toString() ?? '';
    final likeCount    = widget.post['like_count'] as int? ?? 0;
    final commentCount = widget.post['comment_count'] as int? ?? 0;
    final urls         = _mediaUrls(mediaUrl);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, 6)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.90),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.95), width: 1.5),
            ),
            child: Stack(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Header (tap → profil) ────────────────────────
                GestureDetector(
                  onTap: _goToProfile,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 10, 0),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _avatarWidget(photoUrl, 20, ringStyle: widget.profile?['_ring'] as String?),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Flexible(
                                      child: Text(name,
                                          style: const TextStyle(
                                              fontFamily: 'Galey',
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                              color: Color(0xFF0D2A2E))),
                                    ),
                                    if (widget.profile?['profile_type'] == 'eleveur') ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                              colors: [_tealC, Color(0xFF1E7A8C)]),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.verified, size: 9, color: Colors.white),
                                              SizedBox(width: 3),
                                              Text('Pro', style: TextStyle(
                                                  fontFamily: 'Galey', fontSize: 9,
                                                  color: Colors.white, fontWeight: FontWeight.w700)),
                                            ]),
                                      ),
                                    ],
                                    if (_isBoosted(widget.post['boosted_until']?.toString())) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF6B35).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: const Color(0xFFFF6B35).withValues(alpha: 0.4)),
                                        ),
                                        child: const Text('Boosté', style: TextStyle(
                                              fontFamily: 'Galey', fontSize: 9,
                                              color: Color(0xFFFF6B35), fontWeight: FontWeight.w700)),
                                      ),
                                    ],
                                  ]),
                                  const SizedBox(height: 1),
                                  Text(_fmtDate(date),
                                      style: const TextStyle(
                                          fontFamily: 'Galey', fontSize: 11, color: _greyC)),
                                ]),
                          ),
                          if (!widget.isMyPost)
                            GestureDetector(
                              onTap: widget.onFollow,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: widget.isFollowing ? null : const LinearGradient(colors: [_tealC, _green]),
                                  color: widget.isFollowing ? const Color(0xFFE8F5F0) : null,
                                  borderRadius: BorderRadius.circular(20),
                                  border: widget.isFollowing ? Border.all(color: _tealC.withValues(alpha: 0.35)) : null,
                                  boxShadow: widget.isFollowing ? null : [
                                    BoxShadow(color: _tealC.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))
                                  ],
                                ),
                                child: Text(widget.isFollowing ? 'Suivi ✓' : 'Suivre',
                                    style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: widget.isFollowing ? _tealC : Colors.white)),
                              ),
                            ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_horiz, color: _greyC, size: 20),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            onSelected: (val) {
                              if (val == 'delete') { widget.onDelete(); }
                              if (val == 'report') { _showReportDialog(); }
                              if (val == 'boost')  { _showBoostDialog(); }
                            },
                            itemBuilder: (_) => [
                              if (widget.isMyPost) ...[
                                const PopupMenuItem(value: 'boost',
                                    child: Row(children: [
                                      Icon(Icons.rocket_launch_outlined, color: Color(0xFF0C5C6C), size: 18),
                                      SizedBox(width: 8),
                                      Text('Booster ce post', style: TextStyle(fontFamily: 'Galey', color: Color(0xFF0C5C6C))),
                                    ])),
                                const PopupMenuItem(value: 'delete',
                                    child: Row(children: [
                                      Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                      SizedBox(width: 8),
                                      Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.red)),
                                    ])),
                              ],
                              if (!widget.isMyPost)
                                const PopupMenuItem(value: 'report',
                                    child: Row(children: [
                                      Icon(Icons.flag_outlined, color: Colors.orange, size: 18),
                                      SizedBox(width: 8),
                                      Text('Signaler', style: TextStyle(fontFamily: 'Galey', color: Colors.orange)),
                                    ])),
                            ],
                          ),
                        ]),
                  ),
                ),

                // ── Texte ────────────────────────────────────────────
                if (text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                    child: Text(text, style: const TextStyle(
                        fontFamily: 'Galey', fontSize: 14,
                        color: Color(0xFF0D2A2E), height: 1.5)),
                  ),

                // ── Photo(s) double-tap to like ───────────────────
                if (urls.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    onDoubleTap: _doubleTapLike,
                    child: _ImagesDisplay(urls: urls),
                  ),
                ],

                // ── Actions ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                  child: Row(children: [
                    _ActionBtn(
                      icon: widget.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      label: likeCount > 0 ? '$likeCount' : 'J\'aime',
                      color: widget.isLiked ? const Color(0xFFE03055) : _greyC,
                      onTap: widget.onLike,
                    ),
                    _ActionBtn(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: commentCount > 0 ? '$commentCount' : 'Commenter',
                      color: _greyC,
                      onTap: widget.onComment,
                    ),
                  ]),
                ),
              ]),
              // ── Cœur double-tap animation ─────────────────────────
              if (_showHeart)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _showHeart ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: AnimatedScale(
                          scale: _showHeart ? 1.0 : 0.4,
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.elasticOut,
                          child: const Icon(Icons.favorite_rounded,
                              color: Colors.white, size: 90,
                              shadows: [Shadow(color: Colors.black38, blurRadius: 20)]),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── Mes posts ────────────────────────────────────────────────────────────────

class _MyPostsList extends StatefulWidget {
  final String myUid;
  final VoidCallback onRefresh;
  const _MyPostsList(
      {super.key, required this.myUid, required this.onRefresh});
  @override
  State<_MyPostsList> createState() => _MyPostsListState();
}

class _MyPostsListState extends State<_MyPostsList>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => false;

  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _posts = [];
  Map<String, dynamic>? _myProfile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _supa
            .from('posts_socialmedia')
            .select()
            .eq('uid', widget.myUid)
            .order('created_at', ascending: false),
        _supa
            .from('user_profiles')
            .select('uid, firstname, lastname, avatar_url, profile_type, nom')
            .eq('uid', widget.myUid)
            .eq('profile_type', 'particulier')
            .maybeSingle(),
      ]);
      if (mounted) {
        setState(() {
          _posts     = (results[0] as List).cast<Map<String, dynamic>>();
          _myProfile = results[1] as Map<String, dynamic>?;
          _loading   = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(String postId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Supprimer ?',
            style: TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Cette action est irréversible.',
            style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await _supa.from('posts_socialmedia').delete().eq('id', postId);
    setState(() => _posts.removeWhere((p) => p['id'] == postId));
    widget.onRefresh();
  }

  Future<void> _edit(Map<String, dynamic> post) async {
    final ctrl =
        TextEditingController(text: post['texte']?.toString() ?? '');
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditPostSheet(controller: ctrl),
    );
    if (saved == null || !mounted) return;
    try {
      await _supa
          .from('posts_socialmedia')
          .update({'texte': saved}).eq('id', post['id'].toString());
      setState(() {
        final i = _posts.indexWhere((p) => p['id'] == post['id']);
        if (i >= 0) _posts[i] = {..._posts[i], 'texte': saved};
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erreur lors de la modification: $e',
            style: const TextStyle(fontFamily: 'Galey')),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 5),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white54));
    }
    if (_posts.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [_tealC, _green]),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: _tealC.withValues(alpha: 0.35), blurRadius: 24)
              ],
            ),
            child: const Icon(Icons.photo_library_outlined,
                size: 52, color: Colors.white),
          ),
          const SizedBox(height: 20),
          const Text('Vous n\'avez aucune publication',
              style: TextStyle(
                  fontFamily: 'Galey',
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _tealC,
      backgroundColor: Colors.white,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _posts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, i) {
          final post     = _posts[i];
          final text     = post['texte']?.toString() ?? '';
          final mediaUrl = post['media_url']?.toString();
          final date     = post['created_at']?.toString() ?? '';
          final myName   = _profileName(_myProfile);
          final myPhoto  = _profilePhoto(_myProfile);
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 5))
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.95),
                        width: 1.5),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 10, 0),
                          child: Row(children: [
                            _avatarWidget(myPhoto, 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(myName,
                                        style: const TextStyle(
                                            fontFamily: 'Galey',
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: Color(0xFF0D2A2E))),
                                    const SizedBox(height: 1),
                                    Text(_fmtDate(date),
                                        style: TextStyle(
                                            fontFamily: 'Galey',
                                            fontSize: 11,
                                            color: _greyC)),
                                  ]),
                            ),
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_horiz,
                                  color: _greyC, size: 20),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              onSelected: (val) {
                                if (val == 'edit') { _edit(post); }
                                if (val == 'delete') { _delete(post['id'] as String); }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                    value: 'edit',
                                    child: Row(children: [
                                      Icon(Icons.edit_outlined,
                                          color: _tealC, size: 18),
                                      const SizedBox(width: 8),
                                      const Text('Modifier',
                                          style: TextStyle(
                                              fontFamily: 'Galey')),
                                    ])),
                                const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(children: [
                                      Icon(Icons.delete_outline,
                                          color: Colors.red, size: 18),
                                      SizedBox(width: 8),
                                      Text('Supprimer',
                                          style: TextStyle(
                                              fontFamily: 'Galey',
                                              color: Colors.red)),
                                    ])),
                              ],
                            ),
                          ]),
                        ),
                        if (text.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                            child: Text(text,
                                style: const TextStyle(
                                    fontFamily: 'Galey',
                                    fontSize: 14,
                                    color: Color(0xFF0D2A2E),
                                    height: 1.5)),
                          ),
                        if (mediaUrl != null) ...[
                          const SizedBox(height: 12),
                          _ImagesDisplay(urls: _mediaUrls(mediaUrl)),
                        ],
                        if (mediaUrl == null) const SizedBox(height: 14),
                      ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Edit post sheet ──────────────────────────────────────────────────────────

class _EditPostSheet extends StatelessWidget {
  final TextEditingController controller;
  const _EditPostSheet({required this.controller});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.only(top: 80),
      decoration: const BoxDecoration(
        color: Color(0xFF0C3535),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_tealC, _green]),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 20),
        Row(children: [
          const Text('Modifier la description',
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Colors.white)),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.pop(context, controller.text.trim()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_tealC, _green]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: _tealC.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ],
              ),
              child: const Text('Sauvegarder',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Colors.white)),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: TextField(
              controller: controller,
              maxLines: 5,
              minLines: 2,
              autofocus: true,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Description...',
                hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.white.withValues(alpha: 0.45)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _tealC, width: 1.5)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─── Action button ────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 13,
                      color: color,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}

// ─── Images display (single or carousel) ─────────────────────────────────────

class _ImagesDisplay extends StatefulWidget {
  final List<String> urls;
  const _ImagesDisplay({required this.urls});
  @override
  State<_ImagesDisplay> createState() => _ImagesDisplayState();
}

class _ImagesDisplayState extends State<_ImagesDisplay> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.only(
      bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24));
    if (widget.urls.length == 1) {
      return GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => _PhotoViewScreen(urls: widget.urls, initialIndex: 0))),
        child: ClipRRect(
          borderRadius: radius,
          child: CachedNetworkImage(
            imageUrl: widget.urls.first,
            width: double.infinity,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              height: 260,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFFD4EDE8), Color(0xFFD8EDCC)])),
              child: const Center(child: CircularProgressIndicator(color: _tealC, strokeWidth: 2)),
            ),
            errorWidget: (_, __, ___) => Container(
              height: 260, color: const Color(0xFFF4F6F8),
              child: const Icon(Icons.broken_image_outlined, color: _greyC, size: 40)),
          ),
        ),
      );
    }
    return Stack(children: [
      ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          height: 280,
          child: PageView.builder(
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => _PhotoViewScreen(urls: widget.urls, initialIndex: i))),
              child: CachedNetworkImage(
                imageUrl: widget.urls[i],
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: const Color(0xFFD4EDE8),
                  child: const Center(child: CircularProgressIndicator(color: _tealC, strokeWidth: 2)),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: const Color(0xFFF4F6F8),
                  child: const Icon(Icons.broken_image_outlined, color: _greyC, size: 40)),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: 10, left: 0, right: 0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.urls.length, (i) => AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == _page ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == _page ? Colors.white : Colors.white.withValues(alpha: 0.50),
              borderRadius: BorderRadius.circular(3),
            ),
          )),
        ),
      ),
    ]);
  }
}

// ─── Full-screen photo viewer ─────────────────────────────────────────────────

class _PhotoViewScreen extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const _PhotoViewScreen({required this.urls, this.initialIndex = 0});
  @override
  State<_PhotoViewScreen> createState() => _PhotoViewScreenState();
}

class _PhotoViewScreenState extends State<_PhotoViewScreen> {
  late int _page;
  @override
  void initState() { super.initState(); _page = widget.initialIndex; }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: widget.urls.length > 1
            ? Text('${_page + 1} / ${widget.urls.length}',
                style: const TextStyle(fontFamily: 'Galey', color: Colors.white, fontSize: 14))
            : null,
      ),
      body: PageView.builder(
        controller: PageController(initialPage: widget.initialIndex),
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _page = i),
        itemBuilder: (_, i) => PhotoView(
          imageProvider: CachedNetworkImageProvider(widget.urls[i]),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 4,
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          loadingBuilder: (_, __) => const Center(
              child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
          errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 40)),
        ),
      ),
    );
  }
}

// ─── Comments sheet ───────────────────────────────────────────────────────────

class _CommentsSheet extends StatefulWidget {
  final String postId;
  final String myUid;
  final VoidCallback onCommentAdded;
  const _CommentsSheet(
      {required this.postId,
      required this.myUid,
      required this.onCommentAdded});
  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _supa = Supabase.instance.client;
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _comments  = [];
  Map<String, Map<String, dynamic>> _profiles = {};
  bool _loading = true;
  bool _sending = false;
  String? _replyToName;
  String? _replyToId;
  Set<String> _following = {};
  String? _myProfileId;

  @override
  void initState() {
    super.initState();
    _load();
    _particulierProfileId(widget.myUid).then((id) { if (mounted) _myProfileId = id; });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final results = await Future.wait([
      _supa.from('post_comments').select().eq('post_id', widget.postId).order('created_at'),
      _supa.from('follows').select('following_uid').eq('follower_uid', widget.myUid),
    ]);
    final rows       = results[0] as List;
    final followRows = results[1] as List;
    _following = {for (final r in followRows) r['following_uid'] as String};
    if (rows.isNotEmpty) {
      _profiles = await _resolveAuthors(rows);
    }
    if (mounted) {
      setState(() {
        _comments = rows.cast<Map<String, dynamic>>();
        _loading  = false;
      });
    }
  }

  // Regroupe : commentaire racine puis ses réponses via parent_id
  // Fallback @mention si parent_id absent (anciens commentaires)
  List<Map<String, dynamic>> _sortedComments() {
    final hasParentId = _comments.any((c) => c.containsKey('parent_id'));
    if (hasParentId) {
      // Mode parent_id : fiable et précis
      final roots    = _comments.where((c) => c['parent_id'] == null).toList();
      final replyMap = <String, List<Map<String, dynamic>>>{};
      for (final c in _comments) {
        final pid = c['parent_id'] as String?;
        if (pid != null) replyMap.putIfAbsent(pid, () => []).add(c);
      }
      final result = <Map<String, dynamic>>[];
      for (final root in roots) {
        result.add(root);
        result.addAll(replyMap[root['id'] as String? ?? ''] ?? []);
      }
      return result;
    }
    // Fallback @mention (compatibilité anciens commentaires)
    final roots   = _comments.where((c) => !(c['texte']?.toString() ?? '').startsWith('@')).toList();
    final replies = _comments.where((c) =>  (c['texte']?.toString() ?? '').startsWith('@')).toList();
    final result  = <Map<String, dynamic>>[];
    for (final root in roots) {
      result.add(root);
      final authorName = _profileName(_profiles[root['uid']]);
      final matched = replies
          .where((r) => (r['texte']?.toString() ?? '').startsWith('@$authorName ') ||
                        (r['texte']?.toString() ?? '') == '@$authorName')
          .toList();
      result.addAll(matched);
      for (final m in matched) { replies.remove(m); }
    }
    result.addAll(replies);
    return result;
  }

  Future<void> _deleteComment(String commentId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: const Color(0xFF0C3535),
        title: const Text('Supprimer ce commentaire ?',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 15)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Annuler', style: TextStyle(fontFamily: 'Galey', color: Colors.white.withValues(alpha: 0.55)))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.redAccent, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _supa.from('post_comments').delete().eq('id', commentId);
    if (mounted) {
      setState(() => _comments.removeWhere((c) => c['id'] == commentId));
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final pid = _myProfileId ?? await _particulierProfileId(widget.myUid);
      final inserted = await _supa
          .from('post_comments')
          .insert({
            'post_id': widget.postId,
            'uid': widget.myUid,
            if (pid != null) 'author_profile_id': pid,
            'texte': text,
            if (_replyToId != null) 'parent_id': _replyToId,
          })
          .select()
          .single();
      _ctrl.clear();
      widget.onCommentAdded();
      if (mounted) {
        setState(() {
          _comments.add(inserted);
          _sending = false;
          _replyToName = null;
          _replyToId = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.80,
      margin: const EdgeInsets.only(top: 60),
      decoration: const BoxDecoration(
        color: Color(0xFF0C3535),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(children: [
        const SizedBox(height: 12),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_tealC, _green]),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        ShaderMask(
          shaderCallback: (b) =>
              const LinearGradient(colors: [_tealC, _green]).createShader(b),
          child: const Text('Commentaires',
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: Colors.white)),
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.10)),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white54))
              : _comments.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [_tealC, _green]),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.chat_bubble_outline_rounded,
                            size: 32, color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      Text('Aucun commentaire',
                          style: TextStyle(
                              fontFamily: 'Galey',
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 14)),
                    ]))
                  : Builder(builder: (ctx) {
                      final sorted = _sortedComments();
                      return ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      itemCount: sorted.length,
                      itemBuilder: (_, i) {
                        final c       = sorted[i];
                        final prof    = _profiles[c['uid']];
                        final photo   = _profilePhoto(prof);
                        final cUid    = c['uid'] as String;
                        final text    = c['texte']?.toString() ?? '';
                        final isReply = c['parent_id'] != null || text.startsWith('@');

                        // Parse @mention for rich display
                        Widget commentText() {
                          if (!isReply) {
                            return Text(text,
                                style: const TextStyle(
                                    fontFamily: 'Galey',
                                    fontSize: 13,
                                    color: Colors.white));
                          }
                          final sp = text.indexOf(' ');
                          if (sp == -1) {
                            return Text(text,
                                style: const TextStyle(
                                    fontFamily: 'Galey',
                                    fontSize: 13,
                                    color: _green,
                                    fontWeight: FontWeight.w700));
                          }
                          return RichText(
                            text: TextSpan(children: [
                              TextSpan(
                                  text: '${text.substring(0, sp + 1)} ',
                                  style: const TextStyle(
                                      fontFamily: 'Galey',
                                      fontSize: 13,
                                      color: _green,
                                      fontWeight: FontWeight.w700)),
                              TextSpan(
                                  text: text.substring(sp + 1),
                                  style: const TextStyle(
                                      fontFamily: 'Galey',
                                      fontSize: 13,
                                      color: Colors.white)),
                            ]),
                          );
                        }

                        return Padding(
                          padding: EdgeInsets.only(
                              left: isReply ? 28 : 0,
                              top: i > 0 ? (isReply ? 6 : 10) : 0,
                              bottom: 0),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Thread connector for replies
                                if (isReply)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        left: 13, bottom: 4),
                                    child: Row(children: [
                                      Container(
                                        width: 1.5,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: _tealC
                                              .withValues(alpha: 0.55),
                                          borderRadius:
                                              BorderRadius.circular(1),
                                        ),
                                      ),
                                      Container(
                                        width: 10,
                                        height: 1.5,
                                        decoration: BoxDecoration(
                                          color: _tealC
                                              .withValues(alpha: 0.55),
                                          borderRadius:
                                              BorderRadius.circular(1),
                                        ),
                                      ),
                                    ]),
                                  ),
                                // Comment row
                                Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _avatarWidget(
                                          photo, isReply ? 12 : 15,
                                          ringStyle: prof?['_ring'] as String?),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: GestureDetector(
                                          onLongPress: cUid == widget.myUid
                                              ? () => _deleteComment(c['id'] as String)
                                              : null,
                                          child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          child: BackdropFilter(
                                            filter: ImageFilter.blur(
                                                sigmaX: 6, sigmaY: 6),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8),
                                              decoration: BoxDecoration(
                                                color: Colors.white
                                                    .withValues(
                                                        alpha: isReply
                                                            ? 0.07
                                                            : 0.10),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                border: Border.all(
                                                    color: Colors.white
                                                        .withValues(
                                                            alpha: 0.12)),
                                              ),
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .start,
                                                  children: [
                                                    Text(
                                                        _profileName(prof),
                                                        style: TextStyle(
                                                            fontFamily:
                                                                'Galey',
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            fontSize:
                                                                isReply
                                                                    ? 11
                                                                    : 12,
                                                            color: _green)),
                                                    const SizedBox(height: 3),
                                                    commentText(),
                                                  ]),
                                            ),
                                          ),
                                        ),
                                        ),
                                      ),
                                      if (cUid != widget.myUid &&
                                          !_following.contains(cUid))
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              left: 8, top: 4),
                                          child: GestureDetector(
                                            onTap: () async {
                                              await _insertFollow(widget.myUid, cUid);
                                              if (mounted) {
                                                setState(() =>
                                                    _following.add(cUid));
                                              }
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 5),
                                              decoration: BoxDecoration(
                                                gradient:
                                                    const LinearGradient(
                                                        colors: [
                                                      _tealC,
                                                      _green
                                                    ]),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                boxShadow: [
                                                  BoxShadow(
                                                      color: _tealC
                                                          .withValues(
                                                              alpha: 0.35),
                                                      blurRadius: 6,
                                                      offset:
                                                          const Offset(0, 2))
                                                ],
                                              ),
                                              child: const Text('Suivre',
                                                  style: TextStyle(
                                                      fontFamily: 'Galey',
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Colors.white)),
                                            ),
                                          ),
                                        ),
                                    ]),
                                // "Répondre" + hint suppression
                                Padding(
                                  padding: EdgeInsets.only(
                                      left: isReply ? 20 : 40, top: 5),
                                  child: Row(children: [
                                    GestureDetector(
                                      onTap: () {
                                        final name = _profileName(prof);
                                        setState(() {
                                          _replyToName = name;
                                          _replyToId   = c['id'] as String?;
                                        });
                                        _ctrl.text = '@$name ';
                                        _ctrl.selection =
                                            TextSelection.fromPosition(
                                                TextPosition(offset: _ctrl.text.length));
                                      },
                                      child: Text('Répondre',
                                          style: TextStyle(
                                              fontFamily: 'Galey',
                                              fontSize: 11,
                                              color: Colors.white.withValues(alpha: 0.40))),
                                    ),
                                    if (cUid == widget.myUid)
                                      Text('  · Maintenir pour supprimer',
                                          style: TextStyle(
                                              fontFamily: 'Galey',
                                              fontSize: 10,
                                              color: Colors.white.withValues(alpha: 0.22))),
                                  ]),
                                ),
                              ]),
                        );
                      },
                    );
                    }),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.15),
            border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_replyToName != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                decoration: BoxDecoration(
                  color: _tealC.withValues(alpha: 0.18),
                  border: Border(
                      bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.08))),
                ),
                child: Row(children: [
                  const Icon(Icons.reply_rounded, size: 13, color: _green),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Répondre à @$_replyToName',
                        style: const TextStyle(
                            fontFamily: 'Galey', fontSize: 12, color: _green)),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() { _replyToName = null; _replyToId = null; _ctrl.clear(); });
                    },
                    child: const Icon(Icons.close_rounded,
                        size: 15, color: Colors.white54),
                  ),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                      child: TextField(
                        controller: _ctrl,
                        style: const TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 14,
                            color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Ajouter un commentaire...',
                          hintStyle: TextStyle(
                              fontFamily: 'Galey',
                              color: Colors.white.withValues(alpha: 0.45)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 11),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide.none),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_tealC, _green]),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: _tealC.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ],
                    ),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(11),
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send_rounded,
                            color: Colors.white, size: 18),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─── Create post sheet ────────────────────────────────────────────────────────

class _CreatePostSheet extends StatefulWidget {
  final String myUid;
  final VoidCallback onPosted;
  const _CreatePostSheet({required this.myUid, required this.onPosted});
  @override
  State<_CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<_CreatePostSheet> {
  final _supa   = Supabase.instance.client;
  final _ctrl   = TextEditingController();
  final _images = <File>[];
  bool  _posting = false;
  int   _charCount = 0;
  String? _myProfileId;

  static const _maxChars = 2000;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() { if (mounted) setState(() => _charCount = _ctrl.text.length); });
    _particulierProfileId(widget.myUid).then((id) { if (mounted) _myProfileId = id; });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _pickImages(ImageSource source) async {
    if (source == ImageSource.camera) {
      final xFile = await ImagePicker()
          .pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1080);
      if (xFile != null && mounted) setState(() => _images.add(File(xFile.path)));
    } else {
      final files = await ImagePicker()
          .pickMultiImage(imageQuality: 80, maxWidth: 1080);
      if (files.isNotEmpty && mounted) {
        setState(() => _images.addAll(files.map((f) => File(f.path))));
      }
    }
  }

  Future<void> _post() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty && _images.isEmpty) return;
    setState(() => _posting = true);
    try {
      final urls = <String>[];
      for (final img in _images) {
        final compressed = await FlutterImageCompress.compressWithFile(
          img.path, quality: 72, minWidth: 1080, minHeight: 1080, keepExif: false,
        );
        final bytes = compressed ?? await img.readAsBytes();
        final ext  = 'jpg';
        final path = '${widget.myUid}/${DateTime.now().millisecondsSinceEpoch}_${urls.length}.$ext';
        await _supa.storage.from('social').uploadBinary(
              path, bytes,
              fileOptions: const FileOptions(contentType: 'image/jpg', upsert: false),
            );
        urls.add(_supa.storage.from('social').getPublicUrl(path));
      }
      final mediaValue = urls.isEmpty
          ? null
          : urls.length == 1
              ? urls.first
              : jsonEncode(urls);
      final pid = _myProfileId ?? await _particulierProfileId(widget.myUid);
      await _supa.from('posts_socialmedia').insert({
        'uid': widget.myUid,
        if (pid != null) 'author_profile_id': pid,
        if (text.isNotEmpty) 'texte': text,
        if (mediaValue != null) 'media_url': mediaValue,
      });
      if (mounted) {
        Navigator.pop(context);
        await Future.delayed(const Duration(milliseconds: 400));
        widget.onPosted();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _posting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erreur: $e',
                style: const TextStyle(fontFamily: 'Galey')),
            duration: const Duration(seconds: 8)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.only(top: 40),
      decoration: const BoxDecoration(
        color: Color(0xFF0C3535),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_tealC, _green]),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            ShaderMask(
              shaderCallback: (b) =>
                  const LinearGradient(colors: [_tealC, _green]).createShader(b),
              child: const Text('Nouvelle publication',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: Colors.white)),
            ),
            const Spacer(),
            if (_posting)
              const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white54))
            else
              GestureDetector(
                onTap: _post,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_tealC, _green]),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                          color: _tealC.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: const Text('Publier',
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.white)),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: TextField(
                controller: _ctrl,
                maxLines: 10,
                minLines: 6,
                maxLength: _maxChars,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Partagez quelque chose avec la communauté...',
                  hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.white.withValues(alpha: 0.45)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.10),
                  counterStyle: TextStyle(
                      fontFamily: 'Galey', fontSize: 11,
                      color: _charCount > _maxChars * 0.9 ? Colors.orangeAccent : Colors.white38),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _tealC, width: 1.5)),
                ),
              ),
            ),
          ),
        ),
        // ── Barre d'icônes médias ─────────────────────────────────
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            _iconBtn(Icons.photo_library_outlined, 'Galerie', () => _pickImages(ImageSource.gallery)),
            const SizedBox(width: 10),
            _iconBtn(Icons.camera_alt_outlined, 'Photo', () => _pickImages(ImageSource.camera)),
            const Spacer(),
            if (_images.isNotEmpty)
              Text('${_images.length} photo${_images.length > 1 ? 's' : ''}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _green)),
          ]),
        ),

        // ── Aperçu images ─────────────────────────────────────────
        if (_images.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 190,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _images.length,
              itemBuilder: (_, i) => Padding(
                padding: EdgeInsets.only(right: i < _images.length - 1 ? 8 : 0),
                child: Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(_images[i], height: 190, width: 160, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 6, right: 6,
                    child: GestureDetector(
                      onTap: () => setState(() => _images.removeAt(i)),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _iconBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 17, color: _green),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}


// ─── Search sheet ─────────────────────────────────────────────────────────────

class _SearchSheet extends StatefulWidget {
  final String myUid;
  const _SearchSheet({required this.myUid});
  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _supa    = Supabase.instance.client;
  final _ctrl    = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  Set<String> _following = {};
  bool  _searching = false;
  Timer? _debounce;

  @override
  void initState() { super.initState(); _loadFollowing(); }

  @override
  void dispose() { _ctrl.dispose(); _debounce?.cancel(); super.dispose(); }

  Future<void> _loadFollowing() async {
    if (widget.myUid.isEmpty) return;
    try {
      final rows = await _supa
          .from('follows')
          .select('following_uid')
          .eq('follower_uid', widget.myUid);
      if (mounted) {
        setState(() {
          _following = {for (final r in rows as List) r['following_uid'] as String};
        });
      }
    } catch (_) {}
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() { _results = []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _doSearch(q.trim()));
  }

  Future<void> _doSearch(String q) async {
    if (!mounted) return;
    try {
      final rows = await _supa
          .from('user_profiles')
          .select('uid, firstname, lastname, avatar_url, profile_type, nom')
          .or('firstname.ilike.%$q%,lastname.ilike.%$q%,nom.ilike.%$q%')
          .eq('profile_type', 'particulier')
          .neq('uid', widget.myUid)
          .limit(20);
      if (mounted) {
        setState(() {
          _results   = (rows as List).cast<Map<String, dynamic>>();
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _toggleFollow(String targetUid) async {
    final isFollowing = _following.contains(targetUid);
    setState(() {
      if (isFollowing) { _following.remove(targetUid); }
      else { _following.add(targetUid); }
    });
    try {
      if (isFollowing) {
        await _supa.from('follows').delete()
            .eq('follower_uid', widget.myUid)
            .eq('following_uid', targetUid);
      } else {
        await _insertFollow(widget.myUid, targetUid);
      }
    } catch (_) {
      setState(() {
        if (isFollowing) { _following.add(targetUid); }
        else { _following.remove(targetUid); }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.86,
      margin: const EdgeInsets.only(top: 40),
      decoration: const BoxDecoration(
        color: Color(0xFF0C3535),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(children: [
        const SizedBox(height: 12),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_tealC, _green]),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: _onSearch,
                style: const TextStyle(
                    fontFamily: 'Galey', color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Rechercher un profil...',
                  hintStyle: TextStyle(
                      fontFamily: 'Galey',
                      color: Colors.white.withValues(alpha: 0.45)),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: Colors.white.withValues(alpha: 0.6)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.12))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide:
                          const BorderSide(color: _tealC, width: 1.5)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _searching
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white54))
              : _results.isEmpty
                  ? Center(
                      child: Text(
                          _ctrl.text.trim().length < 2
                              ? 'Tapez au moins 2 lettres'
                              : 'Aucun résultat',
                          style: TextStyle(
                              fontFamily: 'Galey',
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 14)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final r    = _results[i];
                        final uid  = r['uid'] as String;
                        final name = _profileName(r);
                        final photo = _profilePhoto(r);
                        final isPro = r['profile_type'] == 'eleveur';
                        final isFollowing = _following.contains(uid);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(
                                  sigmaX: 8, sigmaY: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.09),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: Colors.white
                                          .withValues(alpha: 0.15)),
                                ),
                                child: Row(children: [
                                  _avatarWidget(photo, 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(name,
                                              style: const TextStyle(
                                                  fontFamily: 'Galey',
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14,
                                                  color: Colors.white)),
                                          if (isPro)
                                            Text('Éleveur certifié',
                                                style: TextStyle(
                                                    fontFamily: 'Galey',
                                                    fontSize: 11,
                                                    color: _green)),
                                        ]),
                                  ),
                                  GestureDetector(
                                    onTap: () => _toggleFollow(uid),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 7),
                                      decoration: BoxDecoration(
                                        gradient: isFollowing
                                            ? null
                                            : const LinearGradient(
                                                colors: [_tealC, _green]),
                                        color: isFollowing
                                            ? Colors.white
                                                .withValues(alpha: 0.12)
                                            : null,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        border: isFollowing
                                            ? Border.all(
                                                color: Colors.white
                                                    .withValues(alpha: 0.3))
                                            : null,
                                        boxShadow: isFollowing
                                            ? null
                                            : [
                                                BoxShadow(
                                                    color: _tealC.withValues(
                                                        alpha: 0.35),
                                                    blurRadius: 8,
                                                    offset:
                                                        const Offset(0, 3))
                                              ],
                                      ),
                                      child: Text(
                                          isFollowing ? 'Suivi ✓' : 'Suivre',
                                          style: const TextStyle(
                                              fontFamily: 'Galey',
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white)),
                                    ),
                                  ),
                                ]),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

// ─── Page profil utilisateur ──────────────────────────────────────────────────

class SocialProfilePage extends StatefulWidget {
  final String targetUid;
  final String myUid;
  const SocialProfilePage({super.key, required this.targetUid, required this.myUid});
  @override
  State<SocialProfilePage> createState() => _SocialProfilePageState();
}

class _SocialProfilePageState extends State<SocialProfilePage> {
  final _supa = Supabase.instance.client;

  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _posts = [];
  int _followersCount = 0;
  int _followingCount = 0;
  bool _isFollowing = false;
  bool _loading = true;
  String? _activeRing;
  String? _activeBanner;
  List<String> _ownedRings = [];
  List<String> _ownedBanners = [];

  bool get _isMyProfile => widget.targetUid == widget.myUid;

  void _openShop() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CosmeticsShopSheet(
        myUid: widget.myUid,
        ownedRings: _ownedRings,
        ownedBanners: _ownedBanners,
        activeRing: _activeRing,
        activeBanner: _activeBanner,
        onEquip: (type, value, ownedRings, ownedBanners, activeRing, activeBanner) {
          setState(() {
            _ownedRings = ownedRings;
            _ownedBanners = ownedBanners;
            _activeRing = activeRing;
            _activeBanner = activeBanner;
          });
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _supa.from('user_profiles')
          .select('uid, firstname, lastname, avatar_url, profile_type, nom')
          .eq('uid', widget.targetUid)
          .eq('profile_type', 'particulier')
          .maybeSingle(),
      _supa.from('posts_socialmedia')
          .select()
          .eq('uid', widget.targetUid)
          .order('created_at', ascending: false),
      _supa.from('follows').select('follower_uid').eq('following_uid', widget.targetUid),
      _supa.from('follows').select('following_uid').eq('follower_uid', widget.targetUid),
      _supa.from('user_cosmetics')
          .select('cosmetic_type, active_value, owned')
          .eq('uid', widget.targetUid),
    ]);

    final followCheck = await _supa.from('follows')
        .select('follower_uid')
        .eq('follower_uid', widget.myUid)
        .eq('following_uid', widget.targetUid)
        .maybeSingle();

    String? ring; String? banner;
    List<String> ownedRings = []; List<String> ownedBanners = [];
    for (final c in (results[4] as List)) {
      final t = c['cosmetic_type'] as String;
      final val = c['active_value'] as String?;
      final owned = (c['owned'] as List?)?.cast<String>() ?? [];
      if (t == 'avatar_ring')    { ring = val; ownedRings = owned; }
      if (t == 'profile_banner') { banner = val; ownedBanners = owned; }
    }

    if (mounted) {
      setState(() {
        _profile = results[0] as Map<String, dynamic>?;
        _posts = (results[1] as List).cast<Map<String, dynamic>>();
        _followersCount = (results[2] as List).length;
        _followingCount = (results[3] as List).length;
        _isFollowing = followCheck != null;
        _activeRing = ring; _activeBanner = banner;
        _ownedRings = ownedRings; _ownedBanners = ownedBanners;
        _loading = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    if (_isMyProfile) return;
    if (_isFollowing) {
      await _supa.from('follows')
          .delete()
          .eq('follower_uid', widget.myUid)
          .eq('following_uid', widget.targetUid);
      setState(() { _isFollowing = false; _followersCount--; });
    } else {
      await _insertFollow(widget.myUid, widget.targetUid);
      setState(() { _isFollowing = true; _followersCount++; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _profileName(_profile);
    final photo = _profilePhoto(_profile);
    return Scaffold(
      backgroundColor: _darkC,
      body: Stack(children: [
        Positioned.fill(child: Container(decoration: const BoxDecoration(gradient: _bgGrad))),
        // Couvre status bar + AppBar en un seul bloc pour éviter le raccord
        if (_activeBanner != null)
          Positioned(
            top: 0, left: 0, right: 0,
            height: MediaQuery.of(context).padding.top + kToolbarHeight,
            child: Container(decoration: _bannerDecoration(_activeBanner)),
          ),
        SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _tealC))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _tealC,
                  backgroundColor: Colors.white,
                  child: CustomScrollView(slivers: [
                  // ── AppBar ──────────────────────────────────────
                  SliverAppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    shadowColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    iconTheme: const IconThemeData(color: Colors.white),
                    pinned: false,
                    flexibleSpace: null,
                    actions: [
                      if (_isMyProfile)
                        IconButton(
                          icon: const Icon(Icons.auto_awesome, color: Colors.white),
                          tooltip: 'Boutique cosmétiques',
                          onPressed: () => _openShop(),
                        ),
                    ],
                    title: Text(name,
                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                            fontSize: 18, color: Colors.white)),
                    centerTitle: true,
                  ),

                  SliverToBoxAdapter(child: Stack(children: [
                    if (_activeBanner != null)
                      Positioned.fill(child: Container(decoration: _bannerDecoration(_activeBanner))),
                    Column(children: [
                    const SizedBox(height: 8),
                    // ── Avatar ──────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: _activeRing != null
                            ? (_cosmeticRings[_activeRing!] ?? const LinearGradient(colors: [_tealC, _green], begin: Alignment.topLeft, end: Alignment.bottomRight))
                            : const LinearGradient(colors: [_tealC, _green], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      ),
                      child: CircleAvatar(
                        radius: 46,
                        backgroundColor: const Color(0xFF1A3A42),
                        backgroundImage: photo != null ? NetworkImage(photo) : null,
                        child: photo == null ? const Icon(Icons.pets, color: _tealC, size: 36) : null,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Nom + badge ─────────────────────────────────
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(name, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white)),
                      if (_profile?['profile_type'] == 'eleveur') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(gradient: const LinearGradient(colors: [_tealC, Color(0xFF1E7A8C)]), borderRadius: BorderRadius.circular(10)),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.verified, size: 11, color: Colors.white),
                            SizedBox(width: 3),
                            Text('Pro', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 20),

                    // ── Stats ───────────────────────────────────────
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 32),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                          ),
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                            _statCol('Posts', _posts.length),
                            Container(width: 1, height: 36, color: Colors.white30),
                            GestureDetector(
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
                                  _FollowListPage(targetUid: widget.targetUid, myUid: widget.myUid, type: 'followers'))),
                              child: _statCol('Abonnés', _followersCount)),
                            Container(width: 1, height: 36, color: Colors.white30),
                            GestureDetector(
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
                                  _FollowListPage(targetUid: widget.targetUid, myUid: widget.myUid, type: 'following'))),
                              child: _statCol('Abonnements', _followingCount)),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Bouton suivre / mon profil ──────────────────
                    if (!_isMyProfile)
                      GestureDetector(
                        onTap: _toggleFollow,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: _isFollowing ? null : const LinearGradient(colors: [_tealC, _green]),
                            color: _isFollowing ? Colors.white.withValues(alpha: 0.12) : null,
                            borderRadius: BorderRadius.circular(24),
                            border: _isFollowing ? Border.all(color: Colors.white30) : null,
                            boxShadow: _isFollowing ? null : [BoxShadow(color: _tealC.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
                          ),
                          child: Text(_isFollowing ? 'Abonné(e) ✓' : 'Suivre',
                              style: const TextStyle(fontFamily: 'Galey', fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                      ),
                    const SizedBox(height: 20),

                    // ── Séparateur ──────────────────────────────────
                    Divider(color: Colors.white.withValues(alpha: 0.15), height: 1),
                    const SizedBox(height: 4),
                  ]),   // Column
                ])),    // Stack + SliverToBoxAdapter

                  // ── Grille posts ────────────────────────────────────
                  _posts.isEmpty
                      ? SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(48),
                            child: Center(
                              child: Text(_isMyProfile ? 'Tu n\'as pas encore posté' : 'Aucun post',
                                  style: const TextStyle(fontFamily: 'Galey', color: Colors.white60, fontSize: 15)),
                            ),
                          ),
                        )
                      : SliverGrid(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) {
                              final post = _posts[i];
                              final urls = _mediaUrls(post['media_url']?.toString());
                              final thumb = urls.isNotEmpty ? urls.first : null;
                              return GestureDetector(
                                onTap: () => showModalBottomSheet(
                                  context: context, isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => _PostDetailSheet(post: post, myUid: widget.myUid)),
                                child: Container(
                                  margin: const EdgeInsets.all(1.5),
                                  decoration: BoxDecoration(color: const Color(0xFF1A3A42)),
                                  child: thumb != null
                                      ? Image.network(thumb, fit: BoxFit.cover)
                                      : Center(child: Text(post['texte']?.toString() ?? '',
                                          style: const TextStyle(fontFamily: 'Galey', color: Colors.white70, fontSize: 11),
                                          maxLines: 4, overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center)),
                                ),
                              );
                            },
                            childCount: _posts.length,
                          ),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3, mainAxisSpacing: 0, crossAxisSpacing: 0),
                        ),
                ]),
                ),  // RefreshIndicator
        ),
      ]),
    );
  }

  Widget _statCol(String label, int count) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('$count', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 20, color: Colors.white)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white60)),
    ]);
  }
}

// ─── Page notifications ───────────────────────────────────────────────────────

class SocialNotificationsPage extends StatefulWidget {
  final String myUid;
  const SocialNotificationsPage({super.key, required this.myUid});
  @override
  State<SocialNotificationsPage> createState() => _SocialNotificationsPageState();
}

class _SocialNotificationsPageState extends State<SocialNotificationsPage> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _notifs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 1. Mes posts → commentaires reçus
    final myPosts = await _supa.from('posts_socialmedia')
        .select('id')
        .eq('uid', widget.myUid);
    final postIds = (myPosts as List).map((p) => p['id'] as String).toList();

    List<Map<String, dynamic>> comments = [];
    if (postIds.isNotEmpty) {
      final rows = await _supa.from('post_comments')
          .select()
          .inFilter('post_id', postIds)
          .neq('uid', widget.myUid)
          .order('created_at', ascending: false)
          .limit(30);
      comments = (rows as List).cast<Map<String, dynamic>>();
    }

    // 2. Nouveaux abonnés
    final followers = await _supa.from('follows')
        .select()
        .eq('following_uid', widget.myUid)
        .order('created_at', ascending: false)
        .limit(20);
    final followerRows = (followers as List).cast<Map<String, dynamic>>();

    // 3. Profils
    final uids = {
      ...comments.map((c) => c['uid'] as String),
      ...followerRows.map((f) => f['follower_uid'] as String),
    }.toList();
    Map<String, Map<String, dynamic>> profiles = {};
    if (uids.isNotEmpty) {
      final profRows = await _supa.from('user_profiles')
          .select('uid, firstname, lastname, avatar_url, profile_type, nom')
          .inFilter('uid', uids)
          .eq('profile_type', 'particulier');
      profiles = { for (final r in profRows as List) r['uid'] as String: r as Map<String, dynamic> };
    }

    // Merge en une liste triée par date
    final all = <Map<String, dynamic>>[];
    for (final c in comments) {
      final prof = profiles[c['uid'] as String];
      all.add({
        'type': 'comment',
        'created_at': c['created_at'],
        'profile': prof,
        'texte': c['texte'],
        'post_id': c['post_id'],
      });
    }
    for (final f in followerRows) {
      final prof = profiles[f['follower_uid'] as String];
      all.add({
        'type': 'follow',
        'created_at': f['created_at'],
        'profile': prof,
        'follower_uid': f['follower_uid'],
      });
    }
    all.sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));

    if (mounted) setState(() { _notifs = all; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkC,
      body: Stack(children: [
        Positioned.fill(child: Container(decoration: const BoxDecoration(gradient: _bgGrad))),
        SafeArea(
          child: Column(children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 16),
                const Text('Notifications', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white)),
              ]),
            ),
            const Divider(color: Colors.white12, height: 1),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _tealC))
                  : _notifs.isEmpty
                      ? const Center(child: Text('Aucune notification', style: TextStyle(fontFamily: 'Galey', color: Colors.white60, fontSize: 15)))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1, indent: 70),
                          itemCount: _notifs.length,
                          itemBuilder: (_, i) {
                            final n = _notifs[i];
                            final prof = n['profile'] as Map<String, dynamic>?;
                            final name = _profileName(prof);
                            final photo = _profilePhoto(prof);
                            final isFollow = n['type'] == 'follow';
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              leading: GestureDetector(
                                onTap: () {
                                  final uid = prof?['uid'] as String?;
                                  if (uid == null) return;
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => SocialProfilePage(targetUid: uid, myUid: widget.myUid)));
                                },
                                child: _avatarWidget(photo, 22),
                              ),
                              title: RichText(text: TextSpan(
                                style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.white),
                                children: [
                                  TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  TextSpan(text: isFollow ? ' a commencé à vous suivre' : ' a commenté votre post'),
                                ],
                              )),
                              subtitle: isFollow
                                  ? null
                                  : Text('"${() { final t = n['texte'] as String? ?? ''; return t.length > 50 ? '${t.substring(0, 50)}…' : t; }()}"',
                                      style: const TextStyle(fontFamily: 'Galey', color: Colors.white54, fontSize: 12)),
                              trailing: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [_tealC, _green]),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(isFollow ? Icons.person_add_rounded : Icons.chat_bubble_outline_rounded,
                                    color: Colors.white, size: 14),
                              ),
                            );
                          },
                        ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─── Post detail sheet (depuis grille profil) ────────────────────────────────

class _PostDetailSheet extends StatefulWidget {
  final Map<String, dynamic> post;
  final String myUid;
  const _PostDetailSheet({required this.post, required this.myUid});
  @override
  State<_PostDetailSheet> createState() => _PostDetailSheetState();
}

class _PostDetailSheetState extends State<_PostDetailSheet> {
  final _supa = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  bool _isLiked = false;
  bool _isFollowing = false;
  int  _likeCount = 0;
  int  _commentCount = 0;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.post['like_count'] as int? ?? 0;
    _commentCount = widget.post['comment_count'] as int? ?? 0;
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = widget.post['uid'] as String;
    final authorPid = widget.post['author_profile_id'] as String?;
    final profQ = authorPid != null
        ? _supa.from('user_profiles').select(_kAuthorCols).eq('id', authorPid).maybeSingle()
        : _supa.from('user_profiles').select(_kAuthorCols)
            .eq('uid', uid).eq('profile_type', 'particulier').maybeSingle();
    final results = await Future.wait([
      profQ,
      _supa.from('post_likes').select('uid').eq('post_id', widget.post['id'] as String).eq('uid', widget.myUid).maybeSingle(),
      _supa.from('follows').select('follower_uid').eq('follower_uid', widget.myUid).eq('following_uid', uid).maybeSingle(),
    ]);
    if (mounted) {
      setState(() {
        _profile = (results[0] as Map?)?.cast<String, dynamic>();
        _isLiked = results[1] != null;
        _isFollowing = results[2] != null;
      });
    }
  }

  Future<void> _toggleLike() async {
    final postId = widget.post['id'] as String;
    if (_isLiked) {
      await _supa.from('post_likes').delete().eq('post_id', postId).eq('uid', widget.myUid);
      setState(() { _isLiked = false; _likeCount--; });
    } else {
      await _insertLike(postId, widget.myUid);
      setState(() { _isLiked = true; _likeCount++; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _profileName(_profile);
    final photo = _profilePhoto(_profile);
    final text = widget.post['texte']?.toString() ?? '';
    final urls = _mediaUrls(widget.post['media_url']?.toString());
    final date = widget.post['created_at']?.toString() ?? '';
    return DraggableScrollableSheet(
      initialChildSize: 0.90, minChildSize: 0.5, maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0C3535),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              GestureDetector(
                onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(
                    builder: (_) => SocialProfilePage(targetUid: widget.post['uid'] as String, myUid: widget.myUid))); },
                child: _avatarWidget(photo, 20),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
                Text(_fmtDate(date), style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white54)),
              ])),
              if (widget.post['uid'] != widget.myUid)
                GestureDetector(
                  onTap: () async {
                    final uid = widget.post['uid'] as String;
                    if (_isFollowing) {
                      await _supa.from('follows').delete().eq('follower_uid', widget.myUid).eq('following_uid', uid);
                      setState(() => _isFollowing = false);
                    } else {
                      await _insertFollow(widget.myUid, uid);
                      setState(() => _isFollowing = true);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: _isFollowing ? null : const LinearGradient(colors: [_tealC, _green]),
                      color: _isFollowing ? Colors.white12 : null,
                      borderRadius: BorderRadius.circular(20),
                      border: _isFollowing ? Border.all(color: Colors.white24) : null,
                    ),
                    child: Text(_isFollowing ? 'Suivi ✓' : 'Suivre',
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          Expanded(child: SingleChildScrollView(
            controller: ctrl,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (text.isNotEmpty) Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(text, style: const TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.white, height: 1.5)),
              ),
              if (urls.isNotEmpty) ...[
                const SizedBox(height: 12),
                _ImagesDisplay(urls: urls),
              ],
              const SizedBox(height: 16),
            ]),
          )),
          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Row(children: [
              _ActionBtn(
                icon: _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                label: _likeCount > 0 ? '$_likeCount' : 'J\'aime',
                color: _isLiked ? const Color(0xFFE03055) : _greyC,
                onTap: _toggleLike,
              ),
              _ActionBtn(
                icon: Icons.chat_bubble_outline_rounded,
                label: _commentCount > 0 ? '$_commentCount' : 'Commenter',
                color: _greyC,
                onTap: () => showModalBottomSheet(
                  context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
                  builder: (_) => _CommentsSheet(postId: widget.post['id'] as String, myUid: widget.myUid, onCommentAdded: () => setState(() => _commentCount++))),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─── Liste abonnés / abonnements ─────────────────────────────────────────────

class _FollowListPage extends StatefulWidget {
  final String targetUid;
  final String myUid;
  final String type; // 'followers' or 'following'
  const _FollowListPage({required this.targetUid, required this.myUid, required this.type});
  @override
  State<_FollowListPage> createState() => _FollowListPageState();
}

class _FollowListPageState extends State<_FollowListPage> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _users = [];
  Set<String> _myFollowing = {};
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final results = await Future.wait([
      widget.type == 'followers'
          ? _supa.from('follows').select('follower_uid').eq('following_uid', widget.targetUid)
          : _supa.from('follows').select('following_uid').eq('follower_uid', widget.targetUid),
      _supa.from('follows').select('following_uid').eq('follower_uid', widget.myUid),
    ]);
    final uids = (results[0] as List).map((r) {
      return (widget.type == 'followers' ? r['follower_uid'] : r['following_uid']) as String;
    }).toList();
    _myFollowing = {for (final r in results[1] as List) r['following_uid'] as String};
    if (uids.isEmpty) { if (mounted) setState(() => _loading = false); return; }
    final profRows = await _supa.from('user_profiles')
        .select('uid, firstname, lastname, avatar_url, profile_type, nom')
        .inFilter('uid', uids).eq('profile_type', 'particulier');
    if (mounted) {
      setState(() {
        _users = (profRows as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    }
  }

  Future<void> _toggleFollow(String targetUid) async {
    if (_myFollowing.contains(targetUid)) {
      await _supa.from('follows').delete().eq('follower_uid', widget.myUid).eq('following_uid', targetUid);
      setState(() => _myFollowing.remove(targetUid));
    } else {
      await _insertFollow(widget.myUid, targetUid);
      setState(() => _myFollowing.add(targetUid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.type == 'followers' ? 'Abonnés' : 'Abonnements';
    return Scaffold(
      backgroundColor: _darkC,
      body: Stack(children: [
        Positioned.fill(child: Container(decoration: const BoxDecoration(gradient: _bgGrad))),
        SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(children: [
              GestureDetector(onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20)),
              const SizedBox(width: 16),
              Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white)),
            ])),
          const Divider(color: Colors.white12, height: 1),
          Expanded(child: _loading
              ? const Center(child: CircularProgressIndicator(color: _tealC))
              : _users.isEmpty
                  ? Center(child: Text('Aucun $title'.toLowerCase(), style: const TextStyle(fontFamily: 'Galey', color: Colors.white60, fontSize: 15)))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1, indent: 70),
                      itemCount: _users.length,
                      itemBuilder: (_, i) {
                        final prof = _users[i];
                        final uid = prof['uid'] as String;
                        final isMe = uid == widget.myUid;
                        final isFollowed = _myFollowing.contains(uid);
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          leading: GestureDetector(
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => SocialProfilePage(targetUid: uid, myUid: widget.myUid))),
                            child: _avatarWidget(_profilePhoto(prof), 22)),
                          title: Text(_profileName(prof), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white)),
                          subtitle: prof['profile_type'] == 'eleveur'
                              ? const Text('Éleveur Pro', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: _green))
                              : null,
                          trailing: isMe ? null : GestureDetector(
                            onTap: () => _toggleFollow(uid),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: isFollowed ? null : const LinearGradient(colors: [_tealC, _green]),
                                color: isFollowed ? Colors.white12 : null,
                                borderRadius: BorderRadius.circular(18),
                                border: isFollowed ? Border.all(color: Colors.white24) : null,
                              ),
                              child: Text(isFollowed ? 'Suivi ✓' : 'Suivre',
                                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                            ),
                          ),
                        );
                      },
                    )),
        ])),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Boutique cosmétiques
// ═══════════════════════════════════════════════════════════════════════════

typedef _OnEquip = void Function(
  String type, String value,
  List<String> ownedRings, List<String> ownedBanners,
  String? activeRing, String? activeBanner,
);

class _CosmeticsShopSheet extends StatefulWidget {
  final String myUid;
  final List<String> ownedRings;
  final List<String> ownedBanners;
  final String? activeRing;
  final String? activeBanner;
  final _OnEquip onEquip;
  const _CosmeticsShopSheet({
    required this.myUid, required this.ownedRings, required this.ownedBanners,
    required this.activeRing, required this.activeBanner, required this.onEquip,
  });
  @override
  State<_CosmeticsShopSheet> createState() => _CosmeticsShopSheetState();
}

class _CosmeticsShopSheetState extends State<_CosmeticsShopSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _supa = Supabase.instance.client;
  bool _busy = false;
  late List<String> _ownedRings;
  late List<String> _ownedBanners;
  late String? _activeRing;
  late String? _activeBanner;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _ownedRings = List.from(widget.ownedRings);
    _ownedBanners = List.from(widget.ownedBanners);
    _activeRing = widget.activeRing;
    _activeBanner = widget.activeBanner;
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _buyOrEquip(Map<String, Object> item) async {
    if (_busy) return;
    final id = item['id'] as String;
    final type = item['type'] as String;
    final cost = item['cost'] as int;
    final isRing = type == 'avatar_ring';
    final owned = isRing ? _ownedRings : _ownedBanners;
    final alreadyOwned = owned.contains(id);

    if (!alreadyOwned) {
      // Acheter
      setState(() => _busy = true);
      try {
        final walletRow = await _supa.from('credit_wallets').select().eq('uid', widget.myUid).maybeSingle();
        final solde = (walletRow?['solde'] as int?) ?? 0;
        if (solde < cost) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Crédits insuffisants ($solde cr. disponibles, $cost cr. requis)',
                  style: const TextStyle(fontFamily: 'Galey')),
              backgroundColor: const Color(0xFF1F2A2E), behavior: SnackBarBehavior.floating,
            ));
          }
          setState(() => _busy = false);
          return;
        }
        final newOwned = [...owned, id];
        await Future.wait([
          _supa.from('credit_wallets').upsert({
            'uid': widget.myUid,
            'solde': solde - cost,
            'total_utilise': ((walletRow?['total_utilise'] as int?) ?? 0) + cost,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'uid'),
          _supa.from('credit_transactions').insert({
            'uid': widget.myUid, 'montant': -cost,
            'motif': 'Cosmétique ${item['label']}', 'ref_id': id,
          }),
          _supa.from('user_cosmetics').upsert({
            'uid': widget.myUid, 'cosmetic_type': type,
            'active_value': id, 'owned': newOwned,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'uid,cosmetic_type'),
        ]);
        if (mounted) {
          setState(() {
            if (isRing) { _ownedRings = newOwned; _activeRing = id; }
            else { _ownedBanners = newOwned; _activeBanner = id; }
            _busy = false;
          });
          widget.onEquip(type, id, _ownedRings, _ownedBanners, _activeRing, _activeBanner);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${item['label']} acheté et équipé !', style: const TextStyle(fontFamily: 'Galey')),
            backgroundColor: _tealC, behavior: SnackBarBehavior.floating,
          ));
        }
      } catch (_) {
        if (mounted) setState(() => _busy = false);
      }
    } else {
      // Équiper / déséquiper
      final isActive = isRing ? _activeRing == id : _activeBanner == id;
      final newActive = isActive ? null : id;
      try {
        await _supa.from('user_cosmetics').upsert({
          'uid': widget.myUid, 'cosmetic_type': type,
          'active_value': newActive, 'owned': owned,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'uid,cosmetic_type');
        if (mounted) {
          setState(() {
            if (isRing) { _activeRing = newActive; }
            else { _activeBanner = newActive; }
          });
          widget.onEquip(type, id, _ownedRings, _ownedBanners, _activeRing, _activeBanner);
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final rings   = _cosmeticCatalog.where((c) => c['type'] == 'avatar_ring').toList();
    final banners = _cosmeticCatalog.where((c) => c['type'] == 'profile_banner').toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF0D1F22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        const SizedBox(height: 10),
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        const Text('Boutique', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white)),
        const SizedBox(height: 4),
        Text('Personnalisez votre profil Pets Social', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
        const SizedBox(height: 14),
        TabBar(
          controller: _tab,
          indicatorColor: _green,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [Tab(text: 'Anneaux avatar'), Tab(text: 'Bannières profil')],
        ),
        Expanded(child: TabBarView(controller: _tab, children: [
          _itemGrid(rings,   isRing: true),
          _itemGrid(banners, isRing: false),
        ])),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).padding.bottom + 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.toll_outlined, size: 15, color: Colors.white38),
            const SizedBox(width: 6),
            Text('Achetez des crédits dans Paramètres → Abonnements & achats',
                style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white38)),
          ]),
        ),
      ]),
    );
  }

  Widget _bannerPreviewWidget(Map<String, Object> item, bool active) {
    final id = item['id'] as String;
    final previewUrl = item['preview_url'] as String?;
    final bannerUrl  = item['banner_url']  as String?;
    final url = previewUrl ?? bannerUrl;
    final isImage = url != null || id.startsWith('http');

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 80, height: 32,
        child: isImage
            ? Image.network(url ?? id, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: Colors.white12))
            : Container(decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: _cosmeticBanners[id] ?? _bgGrad,
              )),
      ),
    );
  }

  Widget _itemGrid(List<Map<String, Object>> items, {required bool isRing}) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, childAspectRatio: 1.1, crossAxisSpacing: 12, mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        final id = item['id'] as String;
        final owned = isRing ? _ownedRings.contains(id) : _ownedBanners.contains(id);
        final active = isRing ? _activeRing == id : _activeBanner == id;
        final grad = isRing
            ? (_cosmeticRings[id] ?? _ringGrad)
            : (_cosmeticBanners[id] ?? _bgGrad);

        return GestureDetector(
          onTap: _busy ? null : () => _buyOrEquip(item),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: active ? _green : (owned ? Colors.white24 : Colors.white12),
                width: active ? 2.5 : 1,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Colors.white.withValues(alpha: 0.07), Colors.white.withValues(alpha: 0.03)],
              ),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              // Preview
              if (isRing)
                Container(
                  width: 54, height: 54,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: grad),
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0D1F22)),
                    child: const Icon(Icons.pets, color: Colors.white38, size: 22),
                  ),
                )
              else
                _bannerPreviewWidget(item, active),
              const SizedBox(height: 8),
              Text(item['label'] as String,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 4),
              if (!owned)
                Text('${item['cost']} cr.', style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: _green))
              else if (active)
                const Text('Équipé ✓', style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: _green, fontWeight: FontWeight.w700))
              else
                Text('Équiper', style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.white.withValues(alpha: 0.5))),
            ]),
          ),
        );
      },
    );
  }
}
