import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'story_create_page.dart';
import 'story_service.dart';
import 'story_viewer_page.dart';

/// Bandeau horizontal des stories actives — mon profil en premier (avec un
/// "+" pour publier), puis les autres (non-vues d'abord).
class StoryRing extends StatefulWidget {
  final String myUid;
  final String? myProfileId;
  const StoryRing({super.key, required this.myUid, this.myProfileId});

  @override
  State<StoryRing> createState() => StoryRingState();
}

class StoryRingState extends State<StoryRing> {
  static const _green = Color(0xFF6E9E57);
  static const _teal = Color(0xFF0C5C6C);

  List<StoryGroup> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void didUpdateWidget(covariant StoryRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.myProfileId != widget.myProfileId) reload();
  }

  Future<void> reload() async {
    try {
      final groups = await StoryService.loadActiveGroups(myUid: widget.myUid, myProfileId: widget.myProfileId);
      if (mounted) setState(() { _groups = groups; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  StoryGroup? get _mine => widget.myProfileId == null
      ? null
      : _groups.where((g) => g.authorProfileId == widget.myProfileId).firstOrNull;

  Future<void> _openCreate() async {
    if (widget.myProfileId == null) return;
    final posted = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => StoryCreatePage(myUid: widget.myUid, authorProfileId: widget.myProfileId!),
    ));
    if (posted == true) reload();
  }

  Future<void> _openViewer(StoryGroup group) async {
    final others = _groups.where((g) => g.authorProfileId != widget.myProfileId).toList();
    final ordered = [if (_mine != null) _mine!, ...others];
    final idx = ordered.indexWhere((g) => g.authorProfileId == group.authorProfileId);
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => StoryViewerPage(
        groups: ordered, startGroupIndex: idx < 0 ? 0 : idx,
        myUid: widget.myUid, myProfileId: widget.myProfileId,
      ),
    ));
    reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 96);
    final others = _groups.where((g) => g.authorProfileId != widget.myProfileId).toList();
    if (_mine == null && others.isEmpty && widget.myProfileId == null) return const SizedBox.shrink();

    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          if (widget.myProfileId != null) _myCircle(),
          ...others.map(_circle),
        ],
      ),
    );
  }

  Widget _myCircle() {
    final mine = _mine;
    return GestureDetector(
      onTap: mine != null ? () => _openViewer(mine) : _openCreate,
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Column(children: [
          Stack(children: [
            _ring(mine, size: 62, myProfilePhoto: true),
            if (mine == null || mine.allSeen)
              Positioned(
                right: 0, bottom: 0,
                child: GestureDetector(
                  onTap: _openCreate,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: _green, shape: BoxShape.circle, border: Border.all(color: const Color(0xFF0D1F22), width: 2)),
                    child: const Icon(Icons.add, color: Colors.white, size: 14),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          const Text('Ma story', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white70)),
        ]),
      ),
    );
  }

  Widget _circle(StoryGroup g) {
    final nom = g.authorProfile?['social_pseudo']?.toString().trim().isNotEmpty == true
        ? g.authorProfile!['social_pseudo'].toString()
        : '${g.authorProfile?['firstname'] ?? ''} ${g.authorProfile?['lastname'] ?? ''}'.trim();
    return GestureDetector(
      onTap: () => _openViewer(g),
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Column(children: [
          _ring(g, size: 62),
          const SizedBox(height: 4),
          SizedBox(width: 62, child: Text(nom.isEmpty ? 'Membre' : nom, maxLines: 1, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white70))),
        ]),
      ),
    );
  }

  Widget _ring(StoryGroup? g, {required double size, bool myProfilePhoto = false}) {
    final photo = (g?.authorProfile?['avatar_url'] ?? g?.authorProfile?['profile_picture_url_pro'])?.toString();
    final hasStory = g != null;
    final unseen = hasStory && !g.allSeen;
    return Container(
      width: size, height: size,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: unseen
            ? const LinearGradient(colors: [_teal, _green])
            : null,
        color: !hasStory ? Colors.white24 : (unseen ? null : Colors.white24),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0D1F22)),
        child: CircleAvatar(
          backgroundColor: Colors.white12,
          backgroundImage: photo?.isNotEmpty == true ? CachedNetworkImageProvider(photo!) : null,
          child: photo?.isNotEmpty != true ? const Icon(Icons.person_outline, color: Colors.white54) : null,
        ),
      ),
    );
  }
}
