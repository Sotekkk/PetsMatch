import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _profileName(Map<String, dynamic>? p) {
  if (p == null) return 'Membre';
  if (p['profile_type'] == 'eleveur') {
    final ne = (p['nom'] ?? '').toString();
    if (ne.isNotEmpty) return ne;
  }
  final n = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
  return n.isNotEmpty ? n : 'Membre';
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

Widget _avatarWidget(String? photoUrl, double radius) {
  return Container(
    padding: const EdgeInsets.all(2.5),
    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _ringGrad),
    child: Container(
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: Color(0xFFD4EDE8),
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

// ─── Peintre silhouettes animaux ──────────────────────────────────────────────

class _AnimalBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.055)
      ..style  = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap   = StrokeCap.round
      ..strokeJoin  = StrokeJoin.round;

    final fill = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Chat haut-gauche
    _cat(canvas, stroke, Offset(w * 0.07, h * 0.10), 56);
    // Chien haut-droite
    _dog(canvas, stroke, Offset(w * 0.88, h * 0.07), 50);
    // Lapin bas-gauche
    _rabbit(canvas, stroke, Offset(w * 0.06, h * 0.80), 46);
    // Oiseau centre-haut
    _bird(canvas, stroke, Offset(w * 0.54, h * 0.04), 38);
    // Poisson bas-droite
    _fish(canvas, stroke, Offset(w * 0.90, h * 0.86), 44);
    // Chat petit milieu-droite
    _cat(canvas, stroke, Offset(w * 0.82, h * 0.50), 32);
    // Empreintes
    _paw(canvas, fill, Offset(w * 0.48, h * 0.94), 20);
    _paw(canvas, fill, Offset(w * 0.32, h * 0.18), 14);
    _paw(canvas, fill, Offset(w * 0.68, h * 0.60), 16);
    _paw(canvas, fill, Offset(w * 0.14, h * 0.50), 12);
    _paw(canvas, fill, Offset(w * 0.76, h * 0.28), 11);
  }

  void _cat(Canvas c, Paint p, Offset o, double s) {
    c.drawOval(Rect.fromCenter(center: o + Offset(0, s * 0.42), width: s * 0.72, height: s * 0.58), p);
    c.drawCircle(o, s * 0.26, p);
    _path(c, p, [
      Offset(o.dx - s * 0.19, o.dy - s * 0.16),
      Offset(o.dx - s * 0.10, o.dy - s * 0.38),
      Offset(o.dx - s * 0.03, o.dy - s * 0.16),
    ], close: true);
    _path(c, p, [
      Offset(o.dx + s * 0.19, o.dy - s * 0.16),
      Offset(o.dx + s * 0.10, o.dy - s * 0.38),
      Offset(o.dx + s * 0.03, o.dy - s * 0.16),
    ], close: true);
    final tail = Path()
      ..moveTo(o.dx + s * 0.32, o.dy + s * 0.62)
      ..cubicTo(o.dx + s * 0.68, o.dy + s * 0.66, o.dx + s * 0.78, o.dy + s * 0.36, o.dx + s * 0.56, o.dy + s * 0.14);
    c.drawPath(tail, p);
  }

  void _dog(Canvas c, Paint p, Offset o, double s) {
    c.drawRRect(RRect.fromRectAndRadius(
      Rect.fromCenter(center: o + Offset(0, s * 0.44), width: s * 0.82, height: s * 0.66),
      Radius.circular(s * 0.22)), p);
    c.drawCircle(o, s * 0.29, p);
    final le = Path()
      ..moveTo(o.dx - s * 0.21, o.dy - s * 0.10)
      ..cubicTo(o.dx - s * 0.42, o.dy + s * 0.02, o.dx - s * 0.43, o.dy + s * 0.30, o.dx - s * 0.26, o.dy + s * 0.32);
    c.drawPath(le, p);
    final re = Path()
      ..moveTo(o.dx + s * 0.21, o.dy - s * 0.10)
      ..cubicTo(o.dx + s * 0.42, o.dy + s * 0.02, o.dx + s * 0.43, o.dy + s * 0.30, o.dx + s * 0.26, o.dy + s * 0.32);
    c.drawPath(re, p);
    c.drawOval(Rect.fromCenter(center: o + Offset(0, s * 0.16), width: s * 0.30, height: s * 0.22), p);
    final tail = Path()
      ..moveTo(o.dx + s * 0.39, o.dy + s * 0.40)
      ..cubicTo(o.dx + s * 0.62, o.dy + s * 0.22, o.dx + s * 0.66, o.dy - s * 0.06, o.dx + s * 0.50, o.dy - s * 0.14);
    c.drawPath(tail, p);
  }

  void _rabbit(Canvas c, Paint p, Offset o, double s) {
    c.drawOval(Rect.fromCenter(center: o + Offset(0, s * 0.36), width: s * 0.62, height: s * 0.68), p);
    c.drawCircle(o, s * 0.23, p);
    c.drawOval(Rect.fromCenter(center: o + Offset(-s * 0.10, -s * 0.52), width: s * 0.14, height: s * 0.42), p);
    c.drawOval(Rect.fromCenter(center: o + Offset(s * 0.10, -s * 0.52), width: s * 0.14, height: s * 0.42), p);
  }

  void _bird(Canvas c, Paint p, Offset o, double s) {
    c.drawOval(Rect.fromCenter(center: o + Offset(s * 0.10, 0), width: s * 0.72, height: s * 0.46), p);
    c.drawCircle(o + Offset(-s * 0.26, -s * 0.10), s * 0.20, p);
    _path(c, p, [
      Offset(o.dx - s * 0.44, o.dy - s * 0.08),
      Offset(o.dx - s * 0.60, o.dy - s * 0.14),
      Offset(o.dx - s * 0.44, o.dy - s * 0.20),
    ], close: true);
    final tail = Path()
      ..moveTo(o.dx + s * 0.40, o.dy)
      ..lineTo(o.dx + s * 0.64, o.dy - s * 0.22)
      ..moveTo(o.dx + s * 0.40, o.dy + s * 0.05)
      ..lineTo(o.dx + s * 0.66, o.dy + s * 0.06)
      ..moveTo(o.dx + s * 0.40, o.dy + s * 0.10)
      ..lineTo(o.dx + s * 0.64, o.dy + s * 0.26);
    c.drawPath(tail, p);
  }

  void _fish(Canvas c, Paint p, Offset o, double s) {
    c.drawOval(Rect.fromCenter(center: o + Offset(-s * 0.10, 0), width: s * 0.72, height: s * 0.42), p);
    _path(c, p, [
      Offset(o.dx + s * 0.26, o.dy - s * 0.24),
      Offset(o.dx + s * 0.58, o.dy),
      Offset(o.dx + s * 0.26, o.dy + s * 0.24),
    ]);
    c.drawCircle(o + Offset(-s * 0.22, -s * 0.06), s * 0.07, p);
  }

  void _paw(Canvas c, Paint p, Offset o, double s) {
    c.drawOval(Rect.fromCenter(center: o, width: s * 0.72, height: s * 0.62), p);
    for (int i = 0; i < 4; i++) {
      final a = -0.5 + (i / 3.0);
      c.drawOval(Rect.fromCenter(
        center: Offset(o.dx + math.cos(a) * s * 0.46, o.dy - s * 0.44 + math.sin(a.abs()) * s * 0.10),
        width: s * 0.23, height: s * 0.21,
      ), p);
    }
  }

  void _path(Canvas c, Paint p, List<Offset> pts, {bool close = false}) {
    if (pts.isEmpty) return;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var pt in pts.skip(1)) {
      path.lineTo(pt.dx, pt.dy);
    }
    if (close) path.close();
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ─── Page principale ──────────────────────────────────────────────────────────

class SocialFeedPage extends StatefulWidget {
  const SocialFeedPage({super.key});
  @override
  State<SocialFeedPage> createState() => _SocialFeedPageState();
}

class _SocialFeedPageState extends State<SocialFeedPage> {
  int _tabIndex = 0;
  int _refresh  = 0;
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

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
        _headerBtn(Icons.notifications_outlined, _openNotifications),
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
      }

      if (posts.isEmpty) {
        if (mounted) setState(() { _posts = []; _loading = false; });
        return;
      }

      final postIds    = posts.map((p) => p['id'] as String).toList();
      final authorUids = posts.map((p) => p['uid'] as String).toSet().toList();

      final profileRows = await _supa
          .from('user_profiles')
          .select('uid, firstname, lastname, avatar_url, profile_type, nom')
          .inFilter('uid', authorUids)
          .eq('is_main', true);
      _profiles = {
        for (final r in profileRows as List)
          r['uid'] as String: r as Map<String, dynamic>
      };

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
        await _supa.from('post_likes')
            .insert({'post_id': postId, 'uid': widget.myUid});
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
        await _supa.from('follows')
            .insert({'follower_uid': widget.myUid, 'following_uid': targetUid});
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
      return const Center(
          child: CircularProgressIndicator(color: Colors.white54));
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF0C5C6C), Color(0xFF6E9E57)]),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: _tealC.withValues(alpha: 0.35),
                      blurRadius: 24)
                ],
              ),
              child: const Icon(Icons.photo_library_outlined,
                  size: 52, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Text(
              widget.type == 'following'
                  ? 'Suivez des personnes\npour voir leurs posts ici'
                  : 'Aucune publication pour l\'instant',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: 'Galey',
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.4),
            ),
          ]),
        ),
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
                          _avatarWidget(photoUrl, 20),
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
                          if (widget.isMyPost)
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_horiz, color: _greyC, size: 20),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              onSelected: (val) { if (val == 'delete') { widget.onDelete(); } },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'delete',
                                    child: Row(children: [
                                      Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                      SizedBox(width: 8),
                                      Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.red)),
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
            .eq('is_main', true)
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

  @override
  void initState() { super.initState(); _load(); }

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
    final uids = rows.map((r) => r['uid'] as String).toSet().toList();
    if (uids.isNotEmpty) {
      final profRows = await _supa
          .from('user_profiles')
          .select('uid, firstname, lastname, avatar_url, profile_type, nom')
          .inFilter('uid', uids)
          .eq('is_main', true);
      _profiles = {
        for (final r in profRows as List)
          r['uid'] as String: r as Map<String, dynamic>
      };
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
      final inserted = await _supa
          .from('post_comments')
          .insert({
            'post_id': widget.postId,
            'uid': widget.myUid,
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
                                          photo, isReply ? 12 : 15),
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
                                              await _supa
                                                  .from('follows')
                                                  .insert({
                                                'follower_uid': widget.myUid,
                                                'following_uid': cUid,
                                              });
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
        final ext  = img.path.split('.').last.toLowerCase();
        final path = '${widget.myUid}/${DateTime.now().millisecondsSinceEpoch}_${urls.length}.$ext';
        await _supa.storage.from('social').uploadBinary(
              path,
              await img.readAsBytes(),
              fileOptions: FileOptions(contentType: 'image/$ext', upsert: false),
            );
        urls.add(_supa.storage.from('social').getPublicUrl(path));
      }
      final mediaValue = urls.isEmpty
          ? null
          : urls.length == 1
              ? urls.first
              : jsonEncode(urls);
      await _supa.from('posts_socialmedia').insert({
        'uid': widget.myUid,
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
      margin: const EdgeInsets.only(top: 80),
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
                maxLines: 4,
                minLines: 2,
                style: const TextStyle(
                    fontFamily: 'Galey', fontSize: 15, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Partagez quelque chose avec la communauté...',
                  hintStyle: TextStyle(
                      fontFamily: 'Galey',
                      color: Colors.white.withValues(alpha: 0.45)),
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
                    child: Image.file(_images[i],
                        height: 190, width: 160, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 6, right: 6,
                    child: GestureDetector(
                      onTap: () => setState(() => _images.removeAt(i)),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(
                            color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            _MediaBtn(
                icon: Icons.photo_library_outlined,
                label: 'Galerie',
                onTap: () => _pickImages(ImageSource.gallery)),
            const SizedBox(width: 10),
            _MediaBtn(
                icon: Icons.camera_alt_outlined,
                label: 'Photo',
                onTap: () => _pickImages(ImageSource.camera)),
          ]),
        ),
      ]),
    );
  }
}

// ─── Media button ─────────────────────────────────────────────────────────────

class _MediaBtn extends StatelessWidget {
  final IconData icon;
  final String   label;
  final VoidCallback onTap;
  const _MediaBtn(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 18, color: _green),
                const SizedBox(width: 7),
                Text(label,
                    style: const TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      );
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
          .eq('is_main', true)
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
        await _supa.from('follows')
            .insert({'follower_uid': widget.myUid, 'following_uid': targetUid});
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

  bool get _isMyProfile => widget.targetUid == widget.myUid;

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
          .eq('is_main', true)
          .maybeSingle(),
      _supa.from('posts_socialmedia')
          .select()
          .eq('uid', widget.targetUid)
          .order('created_at', ascending: false),
      _supa.from('follows').select('follower_uid').eq('following_uid', widget.targetUid),
      _supa.from('follows').select('following_uid').eq('follower_uid', widget.targetUid),
    ]);

    final followCheck = await _supa.from('follows')
        .select('follower_uid')
        .eq('follower_uid', widget.myUid)
        .eq('following_uid', widget.targetUid)
        .maybeSingle();

    if (mounted) {
      setState(() {
        _profile = results[0] as Map<String, dynamic>?;
        _posts = (results[1] as List).cast<Map<String, dynamic>>();
        _followersCount = (results[2] as List).length;
        _followingCount = (results[3] as List).length;
        _isFollowing = followCheck != null;
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
      await _supa.from('follows')
          .insert({'follower_uid': widget.myUid, 'following_uid': widget.targetUid});
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
        SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _tealC))
              : CustomScrollView(slivers: [
                  // ── AppBar ──────────────────────────────────────
                  SliverAppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    iconTheme: const IconThemeData(color: Colors.white),
                    pinned: false,
                    title: Text(name,
                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                            fontSize: 18, color: Colors.white)),
                    centerTitle: true,
                  ),

                  SliverToBoxAdapter(child: Column(children: [
                    const SizedBox(height: 8),
                    // ── Avatar ──────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(colors: [_tealC, _green], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        boxShadow: [BoxShadow(color: _tealC.withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 2)],
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
                            _statCol('Abonnés', _followersCount),
                            Container(width: 1, height: 36, color: Colors.white30),
                            _statCol('Abonnements', _followingCount),
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
                  ])),

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
                                onTap: () {/* TODO: ouvrir le post */},
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
          .eq('is_main', true);
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
