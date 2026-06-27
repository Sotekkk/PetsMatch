import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/storage_helper.dart' as storage;

const _tealC = Color(0xFF00ACC1);
const _darkC = Color(0xFF1E2025);
const _greyC = Color(0xFF6F767B);

// ─────────────────────────────────────────────────────────────────────────────
// Page de détail d'un groupe
// ─────────────────────────────────────────────────────────────────────────────

class GroupeDetailPage extends StatefulWidget {
  final Map<String, dynamic> groupe;
  const GroupeDetailPage({super.key, required this.groupe});

  @override
  State<GroupeDetailPage> createState() => _GroupeDetailPageState();
}

class _GroupeDetailPageState extends State<GroupeDetailPage> {
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  late Map<String, dynamic> _groupe;
  List<Map<String, dynamic>> _posts = [];
  Map<String, dynamic>? _myMembership; // {role, statut}
  Set<String> _myLikes = {};
  List<String> _friendsInGroup = [];
  bool _loading = true;
  int _membresCount = 0;

  @override
  void initState() {
    super.initState();
    _groupe = Map<String, dynamic>.from(widget.groupe);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // 1. Rafraîchir les données du groupe
      final gData = await _supa.from('groupes').select().eq('id', _groupe['id']).single();
      _groupe = Map<String, dynamic>.from(gData);

      // 2. Mon appartenance
      Map<String, dynamic>? myMem;
      if (_uid.isNotEmpty) {
        final memData = await _supa
            .from('groupes_membres')
            .select('role, statut')
            .eq('groupe_id', _groupe['id'])
            .eq('user_uid', _uid)
            .maybeSingle();
        myMem = memData != null ? Map<String, dynamic>.from(memData) : null;
      }

      // 3. Nombre de membres actifs
      final membresData = await _supa
          .from('groupes_membres')
          .select('user_uid')
          .eq('groupe_id', _groupe['id'])
          .eq('statut', 'active');
      final membresUids = (membresData as List).map((e) => e['user_uid'].toString()).toList();

      // 4. Mes amis dans le groupe
      List<String> friendsInGroup = [];
      if (_uid.isNotEmpty) {
        final friendsData = await _supa
            .from('petfriends')
            .select('uid_demandeur, uid_recepteur')
            .or('uid_demandeur.eq.$_uid,uid_recepteur.eq.$_uid')
            .eq('statut', 'accepte');
        final friendUids = <String>[];
        for (final f in (friendsData as List)) {
          final other = f['uid_demandeur'] == _uid ? f['uid_recepteur'] : f['uid_demandeur'];
          friendUids.add(other.toString());
        }
        friendsInGroup = friendUids.where((u) => membresUids.contains(u)).toList();
      }

      // 5. Posts (épinglés en premier)
      final postsData = await _supa
          .from('groupe_posts')
          .select()
          .eq('groupe_id', _groupe['id'])
          .order('epingle', ascending: false)
          .order('created_at', ascending: false)
          .limit(30);

      // 6. Mes likes
      Set<String> likes = {};
      if (_uid.isNotEmpty && (postsData as List).isNotEmpty) {
        final postIds = postsData.map((p) => p['id'].toString()).toList();
        final likesData = await _supa
            .from('groupe_post_likes')
            .select('post_id')
            .eq('user_uid', _uid)
            .inFilter('post_id', postIds);
        likes = Set<String>.from((likesData as List).map((l) => l['post_id'].toString()));
      }

      if (mounted) {
        setState(() {
          _myMembership = myMem;
          _membresCount = membresUids.length;
          _friendsInGroup = friendsInGroup;
          _posts = List<Map<String, dynamic>>.from(postsData);
          _myLikes = likes;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _isMember => _myMembership?['statut'] == 'active';
  bool get _isAdmin => _myMembership?['role'] == 'admin' && _isMember;
  bool get _isPending => _myMembership?['statut'] == 'pending';
  bool get _isPrive => _groupe['prive'] == true;

  Future<void> _joinOrLeave() async {
    if (_uid.isEmpty) return;
    if (_isMember || _isPending) {
      // Quitter
      await _supa
          .from('groupes_membres')
          .delete()
          .eq('groupe_id', _groupe['id'])
          .eq('user_uid', _uid);
      setState(() => _myMembership = null);
    } else {
      // Rejoindre
      final statut = _isPrive ? 'pending' : 'active';
      await _supa.from('groupes_membres').insert({
        'groupe_id': _groupe['id'],
        'user_uid': _uid,
        'role': 'membre',
        'statut': statut,
        'rejoint_at': DateTime.now().toIso8601String(),
      });
      setState(() => _myMembership = {'role': 'membre', 'statut': statut});
      if (!_isPrive) setState(() => _membresCount++);
    }
  }

  Future<void> _toggleLike(String postId) async {
    if (_uid.isEmpty || !_isMember) return;
    final liked = _myLikes.contains(postId);
    setState(() {
      if (liked) {
        _myLikes.remove(postId);
      } else {
        _myLikes.add(postId);
      }
      final idx = _posts.indexWhere((p) => p['id'] == postId);
      if (idx != -1) {
        _posts[idx] = Map<String, dynamic>.from(_posts[idx])
          ..['like_count'] = (_posts[idx]['like_count'] ?? 0) + (liked ? -1 : 1);
      }
    });
    try {
      if (liked) {
        await _supa.from('groupe_post_likes').delete()
            .eq('post_id', postId).eq('user_uid', _uid);
        await _supa.from('groupe_posts').update({'like_count': (_posts.firstWhere((p) => p['id'] == postId)['like_count'] ?? 0)}).eq('id', postId);
      } else {
        await _supa.from('groupe_post_likes').insert({'post_id': postId, 'user_uid': _uid});
        await _supa.from('groupe_posts').update({'like_count': (_posts.firstWhere((p) => p['id'] == postId)['like_count'] ?? 0)}).eq('id', postId);
      }
    } catch (_) {}
  }

  Future<void> _togglePin(String postId, bool currentPin) async {
    if (!_isAdmin) return;
    await _supa.from('groupe_posts').update({'epingle': !currentPin}).eq('id', postId);
    final idx = _posts.indexWhere((p) => p['id'] == postId);
    if (idx != -1) {
      setState(() {
        _posts[idx] = Map<String, dynamic>.from(_posts[idx])..['epingle'] = !currentPin;
        _posts.sort((a, b) {
          if (b['epingle'] == a['epingle']) return 0;
          return (b['epingle'] == true) ? 1 : -1;
        });
      });
    }
  }

  Future<void> _deletePost(String postId) async {
    final myUid = _uid;
    final post = _posts.firstWhere((p) => p['id'] == postId, orElse: () => {});
    if (post.isEmpty) return;
    if (post['auteur_uid'] != myUid && !_isAdmin) return;
    await _supa.from('groupe_posts').delete().eq('id', postId);
    setState(() => _posts.removeWhere((p) => p['id'] == postId));
  }

  Future<void> _openCreatePost() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreatePostSheet(groupeId: _groupe['id'].toString()),
    );
    if (created == true) _load();
  }

  Future<void> _openComments(Map<String, dynamic> post) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentsSheet(post: post, isMember: _isMember),
    );
    _load();
  }

  void _openAdmin() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdminSheet(
        groupe: _groupe,
        onUpdated: () {
          Navigator.pop(context);
          _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nom = _groupe['nom']?.toString() ?? '';
    final desc = _groupe['description']?.toString() ?? '';
    final type = _groupe['type']?.toString() ?? 'autre';
    final typeLabel = {'race': 'Race', 'region': 'Région', 'loisir': 'Loisir', 'autre': 'Autre'}[type] ?? type;
    final regles = (_groupe['regles'] as List?)?.cast<dynamic>() ?? [];

    final bannerUrl = _groupe['photo_cover_url']?.toString();
    final avatarUrl = _groupe['avatar_url']?.toString();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _tealC))
          : CustomScrollView(
              slivers: [
                // Header avec bannière + avatar
                SliverAppBar(
                  expandedHeight: bannerUrl != null ? 200 : 140,
                  pinned: true,
                  backgroundColor: _tealC,
                  foregroundColor: Colors.white,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  actions: [
                    if (_isAdmin)
                      IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: _openAdmin,
                      ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    title: Text(nom,
                        style: const TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Colors.white,
                            shadows: [Shadow(color: Colors.black38, blurRadius: 4)])),
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Bannière
                        if (bannerUrl != null)
                          Image.network(bannerUrl, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(color: _tealC))
                        else
                          Container(color: _tealC,
                              child: Center(child: Icon(Icons.group_rounded,
                                  size: 60, color: Colors.white.withValues(alpha: 0.2)))),
                        // Dégradé bas pour lisibilité du titre
                        Positioned(bottom: 0, left: 0, right: 0,
                            child: Container(height: 60,
                                decoration: const BoxDecoration(
                                    gradient: LinearGradient(begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [Colors.black54, Colors.transparent])))),
                        // Avatar du groupe
                        if (avatarUrl != null)
                          Positioned(
                            bottom: 12, left: 16,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                              ),
                              child: CircleAvatar(
                                radius: 30,
                                backgroundImage: NetworkImage(avatarUrl),
                                backgroundColor: _tealC,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info + stats
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              _badge(typeLabel),
                              if (_isPrive) ...[
                                const SizedBox(width: 8),
                                _badge('🔒 Privé', color: const Color(0xFFF3E5F5), textColor: const Color(0xFF8E24AA)),
                              ],
                              const Spacer(),
                              Text('$_membresCount membre${_membresCount > 1 ? 's' : ''}',
                                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _greyC)),
                            ]),
                            if (desc.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(desc,
                                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: _darkC)),
                            ],
                            // Amis dans le groupe
                            if (_friendsInGroup.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Row(children: [
                                const Icon(Icons.people_outline, size: 16, color: _tealC),
                                const SizedBox(width: 6),
                                Text(
                                  _friendsInGroup.length == 1
                                      ? '1 ami est dans ce groupe'
                                      : '${_friendsInGroup.length} amis sont dans ce groupe',
                                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _tealC, fontWeight: FontWeight.w600),
                                ),
                              ]),
                            ],
                            const SizedBox(height: 14),
                            // Bouton rejoindre / quitter
                            if (_uid.isNotEmpty) _buildJoinButton(),
                          ],
                        ),
                      ),

                      // Règles
                      if (regles.isNotEmpty) _buildRegles(regles),

                      // Séparateur
                      const SizedBox(height: 8),

                      // En-tête posts
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Row(children: [
                          const Text('Publications',
                              style: TextStyle(
                                  fontFamily: 'Galey',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: _darkC)),
                          const Spacer(),
                          if (_isMember)
                            GestureDetector(
                              onTap: _openCreatePost,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                    color: _tealC, borderRadius: BorderRadius.circular(20)),
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.add, size: 16, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text('Publier',
                                      style: TextStyle(
                                          fontFamily: 'Galey',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white)),
                                ]),
                              ),
                            ),
                        ]),
                      ),
                    ],
                  ),
                ),

                // Posts
                _posts.isEmpty
                    ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.article_outlined, size: 56, color: Color(0xFFCCCCCC)),
                            const SizedBox(height: 12),
                            Text(
                              _isMember
                                  ? 'Soyez le premier à publier !'
                                  : 'Rejoignez le groupe pour voir les publications',
                              style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFFAAAAAA)),
                            ),
                          ]),
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            child: _PostCard(
                              post: _posts[i],
                              isLiked: _myLikes.contains(_posts[i]['id']?.toString()),
                              isAdmin: _isAdmin,
                              myUid: _uid,
                              onLike: () => _toggleLike(_posts[i]['id'].toString()),
                              onComment: () => _openComments(_posts[i]),
                              onPin: () => _togglePin(
                                  _posts[i]['id'].toString(), _posts[i]['epingle'] == true),
                              onDelete: () => _deletePost(_posts[i]['id'].toString()),
                            ),
                          ),
                          childCount: _posts.length,
                        ),
                      ),

                const SliverToBoxAdapter(child: SizedBox(height: 60)),
              ],
            ),
    );
  }

  Widget _buildJoinButton() {
    String label;
    Color bg;
    Color fg;
    VoidCallback? onTap;

    if (_isAdmin) {
      label = 'Admin ★';
      bg = _tealC;
      fg = Colors.white;
      onTap = _openAdmin;
    } else if (_isMember) {
      label = 'Membre ✓';
      bg = _tealC;
      fg = Colors.white;
      onTap = () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Quitter le groupe ?', style: TextStyle(fontFamily: 'Galey')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Quitter', style: TextStyle(color: Colors.red))),
            ],
          ),
        );
        if (confirm == true) _joinOrLeave();
      };
    } else if (_isPending) {
      label = 'Demande en attente…';
      bg = const Color(0xFFFFF3E0);
      fg = const Color(0xFFEF6C00);
      onTap = () async {
        final cancel = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Annuler la demande ?', style: TextStyle(fontFamily: 'Galey')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Non')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Annuler', style: TextStyle(color: Colors.red))),
            ],
          ),
        );
        if (cancel == true) _joinOrLeave();
      };
    } else {
      label = _isPrive ? 'Demander à rejoindre' : 'Rejoindre';
      bg = Colors.transparent;
      fg = _tealC;
      onTap = _joinOrLeave;
    }

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          side: BorderSide(color: _tealC.withValues(alpha: bg == Colors.transparent ? 1 : 0)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: fg)),
      ),
    );
  }

  Widget _buildRegles(List regles) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)]),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: const Row(children: [
            Icon(Icons.rule_outlined, size: 18, color: _tealC),
            SizedBox(width: 8),
            Text('Règles du groupe',
                style: TextStyle(
                    fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _darkC)),
          ]),
          children: [
            ...regles.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(color: _tealC, shape: BoxShape.circle),
                      child: Center(
                        child: Text('${e.key + 1}',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(e.value.toString(),
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _darkC)),
                    ),
                  ]),
                )),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, {Color? color, Color? textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color ?? const Color(0xFFE0F7FA),
          borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontFamily: 'Galey',
              fontSize: 11,
              color: textColor ?? _tealC,
              fontWeight: FontWeight.w600)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card post
// ─────────────────────────────────────────────────────────────────────────────

class _PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final bool isLiked;
  final bool isAdmin;
  final String myUid;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  const _PostCard({
    required this.post,
    required this.isLiked,
    required this.isAdmin,
    required this.myUid,
    required this.onLike,
    required this.onComment,
    required this.onPin,
    required this.onDelete,
  });

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  void _showFullImage(BuildContext ctx, String url) {
    showDialog(
      context: ctx,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: InteractiveViewer(
            child: Image.network(url, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  static String _fmtDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'À l\'instant';
      if (diff.inHours < 1) return 'Il y a ${diff.inMinutes} min';
      if (diff.inDays < 1) return 'Il y a ${diff.inHours}h';
      if (diff.inDays < 7) return 'Il y a ${diff.inDays}j';
      return DateFormat('dd/MM/yyyy').format(dt);
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final contenu = widget.post['contenu']?.toString() ?? '';
    final epingle = widget.post['epingle'] == true;
    final likeCount = widget.post['like_count'] ?? 0;
    final commentCount = widget.post['comment_count'] ?? 0;
    final date = widget.post['created_at']?.toString() ?? '';
    final auteurUid = widget.post['auteur_uid']?.toString() ?? '';
    final isMyPost = auteurUid == widget.myUid;
    final canDelete = isMyPost || widget.isAdmin;
    final canPin = widget.isAdmin;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: epingle ? Border.all(color: _tealC.withValues(alpha: 0.4)) : null,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 0),
          child: Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: _tealC.withValues(alpha: 0.15),
              child: const Icon(Icons.person_outline, size: 20, color: _tealC),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isMyPost ? 'Moi' : 'Membre',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _darkC)),
                Text(_fmtDate(date),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: _greyC)),
              ]),
            ),
            if (epingle)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.push_pin, size: 16, color: _tealC),
              ),
            if (canDelete || canPin)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, color: _greyC, size: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (val) {
                  if (val == 'copy') {
                    Clipboard.setData(ClipboardData(text: contenu));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Copié !')));
                  } else if (val == 'pin') {
                    widget.onPin();
                  } else if (val == 'delete') {
                    widget.onDelete();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'copy', child: Row(children: [Icon(Icons.copy, size: 16), SizedBox(width: 8), Text('Copier')])),
                  if (canPin)
                    PopupMenuItem(
                        value: 'pin',
                        child: Row(children: [
                          Icon(epingle ? Icons.push_pin_outlined : Icons.push_pin, size: 16),
                          const SizedBox(width: 8),
                          Text(epingle ? 'Désépingler' : 'Épingler'),
                        ])),
                  if (canDelete)
                    const PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_outline, size: 16, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Supprimer', style: TextStyle(color: Colors.red)),
                        ])),
                ],
              ),
          ]),
        ),
        // Contenu texte
        if (contenu.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Text(contenu,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: _darkC)),
          ),
        // Photo du post
        if (widget.post['image_url'] != null) ...[
          if (contenu.isEmpty) const SizedBox(height: 10),
          ClipRRect(
            borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(0), bottomRight: Radius.circular(0)),
            child: GestureDetector(
              onTap: () => _showFullImage(context, widget.post['image_url'].toString()),
              child: Image.network(
                widget.post['image_url'].toString(),
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          const SizedBox(height: 2),
        ],
        // Actions
        const Divider(height: 1, thickness: 0.5),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(children: [
            _actionBtn(
              icon: widget.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              label: likeCount > 0 ? '$likeCount' : 'J\'aime',
              color: widget.isLiked ? Colors.red : _greyC,
              onTap: widget.onLike,
            ),
            const SizedBox(width: 4),
            _actionBtn(
              icon: Icons.chat_bubble_outline_rounded,
              label: commentCount > 0 ? '$commentCount' : 'Commenter',
              color: _greyC,
              onTap: widget.onComment,
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _actionBtn({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return Expanded(
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: color),
        label: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: color)),
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 6),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet commentaires
// ─────────────────────────────────────────────────────────────────────────────

class _CommentsSheet extends StatefulWidget {
  final Map<String, dynamic> post;
  final bool isMember;
  const _CommentsSheet({required this.post, required this.isMember});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await _supa
        .from('groupe_post_commentaires')
        .select()
        .eq('post_id', widget.post['id'])
        .order('created_at');
    if (mounted) {
      setState(() {
        _comments = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _uid.isEmpty) return;
    setState(() => _sending = true);
    try {
      final inserted = await _supa.from('groupe_post_commentaires').insert({
        'post_id': widget.post['id'],
        'auteur_uid': _uid,
        'contenu': text,
        'created_at': DateTime.now().toIso8601String(),
      }).select().single();
      await _supa.from('groupe_posts').update({
        'comment_count': (_comments.length + 1),
      }).eq('id', widget.post['id']);
      if (mounted) {
        setState(() {
          _comments.add(Map<String, dynamic>.from(inserted));
          _ctrl.clear();
          _sending = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  static String _fmtDate(String iso) {
    try {
      return DateFormat('dd/MM · HH:mm').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        const SizedBox(height: 10),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 12),
        const Text('Commentaires',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        const Divider(height: 20),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _tealC))
              : _comments.isEmpty
                  ? const Center(child: Text('Aucun commentaire', style: TextStyle(fontFamily: 'Galey', color: _greyC)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _comments.length,
                      itemBuilder: (_, i) {
                        final c = _comments[i];
                        final isMe = c['auteur_uid'] == _uid;
                        return Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isMe ? const Color(0xFFE0F7FA) : const Color(0xFFF8F8F8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(c['contenu'] ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _darkC)),
                              const SizedBox(height: 2),
                              Text(_fmtDate(c['created_at'] ?? ''), style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: _greyC)),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
        if (widget.isMember && _uid.isNotEmpty)
          Container(
            padding: EdgeInsets.only(
                left: 16, right: 16, top: 10, bottom: MediaQuery.of(context).padding.bottom + 10),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEEEEE)))),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  decoration: InputDecoration(
                    hintText: 'Votre commentaire…',
                    hintStyle: const TextStyle(fontFamily: 'Galey', color: _greyC),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: _tealC, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFFF8F8F8),
                  ),
                  maxLines: null,
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _sending ? null : _send,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(color: _tealC, shape: BoxShape.circle),
                  child: _sending
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet créer un post
// ─────────────────────────────────────────────────────────────────────────────

class _CreatePostSheet extends StatefulWidget {
  final String groupeId;
  const _CreatePostSheet({required this.groupeId});

  @override
  State<_CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<_CreatePostSheet> {
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  final _ctrl = TextEditingController();
  File? _imageFile;
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (picked != null) setState(() => _imageFile = File(picked.path));
  }

  Future<void> _publish() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty && _imageFile == null) return;
    if (_uid.isEmpty) return;
    setState(() => _saving = true);
    try {
      String? imageUrl;
      if (_imageFile != null) {
        final path = 'groupes/posts/${widget.groupeId}/${_uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        imageUrl = await storage.uploadPhoto(_imageFile!, path, quality: 82);
      }
      await _supa.from('groupe_posts').insert({
        'groupe_id': widget.groupeId,
        'auteur_uid': _uid,
        'contenu': text,
        if (imageUrl != null) 'image_url': imageUrl,
        'created_at': DateTime.now().toIso8601String(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(
          left: 20, right: 20, top: 12, bottom: MediaQuery.of(context).viewInsets.bottom + 28),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(
                child: Text('Nouvelle publication',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18))),
            IconButton(
                icon: const Icon(Icons.close, size: 22, color: _greyC),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints()),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: _imageFile == null,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: 'Partagez quelque chose avec le groupe…',
              hintStyle: const TextStyle(fontFamily: 'Galey', color: _greyC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _tealC, width: 1.5)),
              contentPadding: const EdgeInsets.all(14),
              filled: true,
              fillColor: const Color(0xFFF8F8F8),
            ),
          ),
          // Prévisualisation image sélectionnée
          if (_imageFile != null) ...[
            const SizedBox(height: 12),
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(_imageFile!, width: double.infinity, height: 200, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 8, right: 8,
                  child: GestureDetector(
                    onTap: () => setState(() => _imageFile = null),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          // Barre d'actions (photo)
          Row(children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                    color: const Color(0xFFF8F8F8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.photo_outlined, size: 20, color: _tealC),
                  SizedBox(width: 6),
                  Text('Photo', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _tealC, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            const Spacer(),
            SizedBox(
              child: FilledButton(
                onPressed: _saving ? null : _publish,
                style: FilledButton.styleFrom(
                    backgroundColor: _tealC, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Publier', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet admin
// ─────────────────────────────────────────────────────────────────────────────

class _AdminSheet extends StatefulWidget {
  final Map<String, dynamic> groupe;
  final VoidCallback onUpdated;
  const _AdminSheet({required this.groupe, required this.onUpdated});

  @override
  State<_AdminSheet> createState() => _AdminSheetState();
}

class _AdminSheetState extends State<_AdminSheet> with SingleTickerProviderStateMixin {
  final _supa = Supabase.instance.client;
  late TabController _tabCtrl;

  // Règles
  List<String> _regles = [];
  final _regleCtrl = TextEditingController();

  // Membres
  List<Map<String, dynamic>> _membres = [];
  bool _loadingMembres = true;

  // Infos groupe
  File? _avatarFile;
  File? _bannerFile;
  bool _uploadingAvatar = false;
  bool _uploadingBanner = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    final reglesRaw = widget.groupe['regles'] as List? ?? [];
    _regles = reglesRaw.map((r) => r.toString()).toList();
    _loadMembres();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _regleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUpload({required bool isAvatar}) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: isAvatar ? 400 : 1200,
    );
    if (picked == null) return;
    final file = File(picked.path);
    final groupeId = widget.groupe['id'].toString();
    if (isAvatar) {
      setState(() => _uploadingAvatar = true);
      try {
        final url = await storage.uploadPhoto(file, 'groupes/$groupeId/avatar.jpg', quality: 88);
        await _supa.from('groupes').update({'avatar_url': url}).eq('id', groupeId);
        if (mounted) {
          setState(() { _avatarFile = file; _uploadingAvatar = false; });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo de profil mise à jour !')));
        }
      } catch (e) {
        if (mounted) setState(() => _uploadingAvatar = false);
      }
    } else {
      setState(() => _uploadingBanner = true);
      try {
        final url = await storage.uploadPhoto(file, 'groupes/$groupeId/banner.jpg', quality: 82, maxDim: 1200);
        await _supa.from('groupes').update({'photo_cover_url': url}).eq('id', groupeId);
        if (mounted) {
          setState(() { _bannerFile = file; _uploadingBanner = false; });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bannière mise à jour !')));
        }
      } catch (e) {
        if (mounted) setState(() => _uploadingBanner = false);
      }
    }
  }

  Future<void> _loadMembres() async {
    final data = await _supa
        .from('groupes_membres')
        .select('user_uid, role, statut, rejoint_at')
        .eq('groupe_id', widget.groupe['id'])
        .order('rejoint_at');
    if (mounted) {
      setState(() {
        _membres = List<Map<String, dynamic>>.from(data);
        _loadingMembres = false;
      });
    }
  }

  Future<void> _saveRegles() async {
    await _supa.from('groupes').update({'regles': _regles}).eq('id', widget.groupe['id']);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Règles sauvegardées !')));
    }
  }

  Future<void> _updateMembre(String userUid, String action) async {
    switch (action) {
      case 'approve':
        await _supa.from('groupes_membres').update({'statut': 'active'})
            .eq('groupe_id', widget.groupe['id']).eq('user_uid', userUid);
        break;
      case 'promote':
        await _supa.from('groupes_membres').update({'role': 'admin'})
            .eq('groupe_id', widget.groupe['id']).eq('user_uid', userUid);
        break;
      case 'demote':
        await _supa.from('groupes_membres').update({'role': 'membre'})
            .eq('groupe_id', widget.groupe['id']).eq('user_uid', userUid);
        break;
      case 'ban':
        await _supa.from('groupes_membres').update({'statut': 'banned'})
            .eq('groupe_id', widget.groupe['id']).eq('user_uid', userUid);
        break;
      case 'remove':
        await _supa.from('groupes_membres').delete()
            .eq('groupe_id', widget.groupe['id']).eq('user_uid', userUid);
        break;
    }
    await _loadMembres();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        const SizedBox(height: 10),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 12),
        const Text('Gestion du groupe',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
        const SizedBox(height: 8),
        TabBar(
          controller: _tabCtrl,
          labelColor: _tealC,
          unselectedLabelColor: _greyC,
          indicatorColor: _tealC,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: 'Membres'),
            Tab(text: 'Demandes'),
            Tab(text: 'Règles'),
            Tab(text: 'Photos'),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildMembresList(actifOnly: true),
              _buildMembresList(pendingOnly: true),
              _buildReglesTab(),
              _buildPhotosTab(),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildMembresList({bool actifOnly = false, bool pendingOnly = false}) {
    if (_loadingMembres) return const Center(child: CircularProgressIndicator(color: _tealC));
    List<Map<String, dynamic>> list;
    if (pendingOnly) {
      list = _membres.where((m) => m['statut'] == 'pending').toList();
    } else if (actifOnly) {
      list = _membres.where((m) => m['statut'] == 'active').toList();
    } else {
      list = _membres;
    }
    if (list.isEmpty) {
      return Center(child: Text(
        pendingOnly ? 'Aucune demande en attente' : 'Aucun membre',
        style: const TextStyle(fontFamily: 'Galey', color: _greyC),
      ));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final m = list[i];
        final uid = m['user_uid'].toString();
        final role = m['role'].toString();
        final statut = m['statut']?.toString() ?? 'active';
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          leading: CircleAvatar(
            backgroundColor: _tealC.withValues(alpha: 0.15),
            child: const Icon(Icons.person_outline, color: _tealC, size: 20),
          ),
          title: Text(
            uid.length > 8 ? '${uid.substring(0, 8)}…' : uid,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
          ),
          subtitle: Row(mainAxisSize: MainAxisSize.min, children: [
            if (role == 'admin')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: _tealC.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: const Text('Admin', style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: _tealC)),
              ),
            if (statut == 'banned')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Text('Banni', style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.red)),
              ),
          ]),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18, color: _greyC),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) => _updateMembre(uid, val),
            itemBuilder: (_) => [
              if (statut == 'pending')
                const PopupMenuItem(value: 'approve', child: Row(children: [Icon(Icons.check_circle_outline, size: 16, color: Colors.green), SizedBox(width: 8), Text('Approuver')])),
              if (role == 'membre' && statut == 'active')
                const PopupMenuItem(value: 'promote', child: Row(children: [Icon(Icons.star_outline, size: 16, color: _tealC), SizedBox(width: 8), Text('Passer admin')])),
              if (role == 'admin')
                const PopupMenuItem(value: 'demote', child: Row(children: [Icon(Icons.star_border, size: 16), SizedBox(width: 8), Text('Retirer admin')])),
              const PopupMenuItem(value: 'ban', child: Row(children: [Icon(Icons.block, size: 16, color: Colors.orange), SizedBox(width: 8), Text('Bannir')])),
              const PopupMenuItem(value: 'remove', child: Row(children: [Icon(Icons.person_remove_outlined, size: 16, color: Colors.red), SizedBox(width: 8), Text('Retirer', style: TextStyle(color: Colors.red))])),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReglesTab() {
    return Column(children: [
      Expanded(
        child: _regles.isEmpty
            ? const Center(child: Text('Aucune règle définie', style: TextStyle(fontFamily: 'Galey', color: _greyC)))
            : ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: _regles.length,
                onReorderItem: (oldIdx, newIdx) {
                  setState(() {
                    final item = _regles.removeAt(oldIdx);
                    _regles.insert(newIdx, item);
                  });
                },
                itemBuilder: (_, i) => ListTile(
                  key: ValueKey(i),
                  leading: Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(color: _tealC, shape: BoxShape.circle),
                    child: Center(
                      child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  title: Text(_regles[i], style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    onPressed: () => setState(() => _regles.removeAt(i)),
                  ),
                ),
              ),
      ),
      // Ajouter une règle
      Container(
        padding: EdgeInsets.only(
            left: 16, right: 16, top: 8, bottom: MediaQuery.of(context).padding.bottom + 8),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEEEEE)))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _regleCtrl,
                decoration: InputDecoration(
                  hintText: 'Ajouter une règle…',
                  hintStyle: const TextStyle(fontFamily: 'Galey', color: _greyC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _tealC, width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: const Color(0xFFF8F8F8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_circle, color: _tealC, size: 30),
              onPressed: () {
                final text = _regleCtrl.text.trim();
                if (text.isNotEmpty) {
                  setState(() {
                    _regles.add(text);
                    _regleCtrl.clear();
                  });
                }
              },
            ),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saveRegles,
              style: FilledButton.styleFrom(backgroundColor: _tealC, padding: const EdgeInsets.symmetric(vertical: 12)),
              child: const Text('Sauvegarder les règles', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildPhotosTab() {
    final currentAvatar = widget.groupe['avatar_url']?.toString();
    final currentBanner = widget.groupe['photo_cover_url']?.toString();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Photo de profil du groupe
        const Text('Photo de profil', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _darkC)),
        const SizedBox(height: 12),
        Row(children: [
          // Avatar actuel ou sélectionné
          CircleAvatar(
            radius: 40,
            backgroundColor: _tealC.withValues(alpha: 0.15),
            backgroundImage: _avatarFile != null
                ? FileImage(_avatarFile!) as ImageProvider
                : (currentAvatar != null ? NetworkImage(currentAvatar) : null),
            child: (_avatarFile == null && currentAvatar == null)
                ? const Icon(Icons.group_rounded, size: 36, color: _tealC)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Photo carrée, visible sur la carte du groupe',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _greyC)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _uploadingAvatar ? null : () => _pickAndUpload(isAvatar: true),
                icon: _uploadingAvatar
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _tealC))
                    : const Icon(Icons.photo_camera_outlined, size: 18, color: _tealC),
                label: Text(_uploadingAvatar ? 'Upload…' : 'Changer la photo',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _tealC)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _tealC),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 28),

        // Bannière
        const Text('Bannière', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _darkC)),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _uploadingBanner ? null : () => _pickAndUpload(isAvatar: false),
          child: Container(
            height: 130,
            width: double.infinity,
            decoration: BoxDecoration(
              color: _tealC.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _tealC.withValues(alpha: 0.3), width: 1.5),
            ),
            clipBehavior: Clip.hardEdge,
            child: _uploadingBanner
                ? const Center(child: CircularProgressIndicator(color: _tealC))
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_bannerFile != null)
                        Image.file(_bannerFile!, fit: BoxFit.cover)
                      else if (currentBanner != null)
                        Image.network(currentBanner, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                              color: Colors.black38, borderRadius: BorderRadius.circular(20)),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.photo_outlined, color: Colors.white, size: 18),
                            SizedBox(width: 6),
                            Text('Changer la bannière',
                                style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                          ]),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Image panoramique affichée en haut de la page du groupe',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _greyC)),
      ]),
    );
  }
}
