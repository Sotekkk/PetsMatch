import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:PetsMatch/pages/particulier/social_feed_page.dart' show openMentionedProfile;
import 'package:PetsMatch/widgets/mention_hashtag.dart';
import 'story_service.dart';

/// Lecteur plein écran des stories (façon Instagram) : barres de progression
/// segmentées, avance auto, tap gauche/droite, musique/audio synchronisée.
class StoryViewerPage extends StatefulWidget {
  final List<StoryGroup> groups;
  final int startGroupIndex;
  final String myUid;
  final String? myProfileId;
  const StoryViewerPage({
    super.key, required this.groups, this.startGroupIndex = 0,
    required this.myUid, this.myProfileId,
  });

  @override
  State<StoryViewerPage> createState() => _StoryViewerPageState();
}

class _StoryViewerPageState extends State<StoryViewerPage> with SingleTickerProviderStateMixin {
  late final PageController _pageCtrl;
  late int _groupIndex;
  int _itemIndex = 0;
  late AnimationController _progressCtrl; // photos uniquement (durée fixe)
  VideoPlayerController? _videoCtrl;
  double _videoProgress = 0; // vidéos : dérivé de la position RÉELLE du lecteur
  bool _videoEnded = false;
  AudioPlayer? _musicPlayer; // lazy — créé seulement si une story a de la musique
  bool _paused = false;
  bool _liked = false;
  int _likesCount = 0;
  bool _disposed = false;

  static const _defaultDuration = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _groupIndex = widget.startGroupIndex;
    _pageCtrl = PageController(initialPage: _groupIndex);
    _progressCtrl = AnimationController(vsync: this)
      ..addStatusListener((s) { if (s == AnimationStatus.completed) _next(); });
    WidgetsBinding.instance.addPostFrameCallback((_) => _playCurrent());
  }

  @override
  void dispose() {
    _disposed = true;
    _progressCtrl.dispose();
    _videoCtrl?.removeListener(_onVideoTick);
    _videoCtrl?.dispose();
    try { _musicPlayer?.dispose(); } catch (_) {}
    _pageCtrl.dispose();
    super.dispose();
  }

  StoryGroup get _group => widget.groups[_groupIndex];
  StoryItem get _item => _group.items[_itemIndex];

  Future<void> _playCurrent() async {
    if (_disposed) return;
    _progressCtrl.stop();
    _progressCtrl.reset();
    _videoCtrl?.removeListener(_onVideoTick);
    _videoCtrl?.dispose();
    _videoCtrl = null;
    _videoProgress = 0;
    _videoEnded = false;
    try { await _musicPlayer?.stop(); } catch (_) {}
    if (_disposed) return;

    final currentItem = _item;
    StoryService.markViewed(currentItem.id, viewerUid: widget.myUid, viewerProfileId: widget.myProfileId);
    _liked = false;
    _likesCount = 0;
    StoryService.isLiked(currentItem.id, widget.myProfileId).then((v) {
      if (mounted && identical(currentItem, _item)) setState(() => _liked = v);
    });
    StoryService.likesCount(currentItem.id).then((v) {
      if (mounted && identical(currentItem, _item)) setState(() => _likesCount = v);
    });

    if (currentItem.mediaType == 'video') {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(currentItem.mediaUrl));
      try {
        await ctrl.initialize().timeout(const Duration(seconds: 15));
      } catch (_) {
        // Vidéo injouable (réseau, format…) : on ne reste pas bloqué dessus,
        // on passe directement à la suite.
        ctrl.dispose();
        if (!_disposed && mounted && identical(currentItem, _item)) _next();
        return;
      }
      if (_disposed || !mounted || !identical(currentItem, _item)) { ctrl.dispose(); return; }
      // Musique en fond → on coupe le son natif de la vidéo (comme demandé :
      // priorité à la musique choisie, pas de mix).
      ctrl.setVolume(currentItem.music != null ? 0 : 1);
      // La barre de progression suit la position RÉELLE du lecteur (pas une
      // minuterie indépendante) : sans ça, un ralentissement réseau figeait
      // l'image pendant que la barre continuait d'avancer sur son propre
      // rythme, donnant l'impression que la vidéo « se bloque ».
      ctrl.addListener(_onVideoTick);
      ctrl.play();
      setState(() => _videoCtrl = ctrl);
    } else {
      _progressCtrl.duration = _defaultDuration;
      if (!_paused) _progressCtrl.forward();
    }
    if (currentItem.music != null) {
      _musicPlayer ??= AudioPlayer();
      try { await _musicPlayer!.play(UrlSource(currentItem.music!.urlAudio)); } catch (_) {}
    }
  }

  void _onVideoTick() {
    if (_disposed) return;
    final ctrl = _videoCtrl;
    if (ctrl == null || !mounted) return;
    final v = ctrl.value;
    if (!v.isInitialized || v.hasError) return;
    final dur = v.duration;
    if (dur.inMilliseconds <= 0) return;
    final progress = (v.position.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
    if ((progress - _videoProgress).abs() > 0.002) setState(() => _videoProgress = progress);
    if (!_videoEnded && !_paused && v.position >= dur - const Duration(milliseconds: 200)) {
      _videoEnded = true;
      _next();
    }
  }

  void _next() {
    if (_itemIndex < _group.items.length - 1) {
      setState(() => _itemIndex++);
      _playCurrent();
    } else if (_groupIndex < widget.groups.length - 1) {
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      // Différer le pop au prochain frame — appeler Navigator.pop depuis
      // un listener d'AnimationController (pendant un frame) gèle le rendu.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  void _prev() {
    if (_itemIndex > 0) {
      setState(() => _itemIndex--);
      _playCurrent();
    } else if (_groupIndex > 0) {
      _pageCtrl.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  void _onGroupChanged(int i) {
    setState(() { _groupIndex = i; _itemIndex = 0; });
    _playCurrent();
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_paused) {
      if (_item.mediaType == 'photo') _progressCtrl.stop();
      _videoCtrl?.pause();
      try { _musicPlayer?.pause(); } catch (_) {}
    } else {
      if (_item.mediaType == 'photo') _progressCtrl.forward();
      _videoCtrl?.play();
      try { _musicPlayer?.resume(); } catch (_) {}
    }
  }

  Future<void> _showViewers() async {
    final viewers = await StoryService.viewers(_item.id);
    if (!mounted) return;
    _paused = true; _progressCtrl.stop(); _videoCtrl?.pause(); try { _musicPlayer?.pause(); } catch (_) {}
    await showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF1F2A2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Vu par ${viewers.length}', style: const TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            if (viewers.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('Personne n\'a encore vu cette story', style: TextStyle(fontFamily: 'Galey', color: Colors.white54)))
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: viewers.length,
                  itemBuilder: (_, i) {
                    final p = viewers[i]['profile'] as Map<String, dynamic>?;
                    final nom = p?['social_pseudo']?.toString().trim().isNotEmpty == true
                        ? p!['social_pseudo'].toString()
                        : '${p?['firstname'] ?? ''} ${p?['lastname'] ?? ''}'.trim();
                    final photo = (p?['avatar_url'] ?? p?['profile_picture_url_pro'])?.toString();
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 18, backgroundColor: Colors.white24,
                        backgroundImage: photo?.isNotEmpty == true ? CachedNetworkImageProvider(photo!) : null,
                        child: photo?.isNotEmpty != true ? const Icon(Icons.person_outline, color: Colors.white70, size: 18) : null,
                      ),
                      title: Text(nom.isEmpty ? 'Membre' : nom, style: const TextStyle(fontFamily: 'Galey', color: Colors.white, fontSize: 13)),
                    );
                  },
                ),
              ),
          ]),
        ),
      ),
    );
    if (mounted) {
      _paused = false;
      if (_item.mediaType == 'photo') _progressCtrl.forward();
      _videoCtrl?.play();
      try { _musicPlayer?.resume(); } catch (_) {}
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Supprimer cette story ?', style: TextStyle(fontFamily: 'Galey')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    await StoryService.deleteStory(_item.id, mediaUrl: _item.mediaUrl);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _toggleLike() async {
    final item = _item;
    final wasLiked = _liked;
    setState(() { _liked = !wasLiked; _likesCount += wasLiked ? -1 : 1; });
    final liked = await StoryService.toggleLike(
      item.id,
      uid: widget.myUid, profileId: widget.myProfileId,
      authorUid: _group.authorUid, authorProfileId: _group.authorProfileId,
    );
    if (mounted && identical(item, _item) && liked != _liked) {
      setState(() { _liked = liked; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMine = _group.authorProfileId == widget.myProfileId;
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageCtrl,
        itemCount: widget.groups.length,
        onPageChanged: _onGroupChanged,
        itemBuilder: (_, gi) {
          final g = widget.groups[gi];
          if (gi != _groupIndex) return const SizedBox.shrink();
          final item = g.items[_itemIndex];
          final nom = g.authorProfile?['social_pseudo']?.toString().trim().isNotEmpty == true
              ? g.authorProfile!['social_pseudo'].toString()
              : '${g.authorProfile?['firstname'] ?? ''} ${g.authorProfile?['lastname'] ?? ''}'.trim();
          final photo = (g.authorProfile?['avatar_url'] ?? g.authorProfile?['profile_picture_url_pro'])?.toString();
          return GestureDetector(
            onTapUp: (d) {
              final w = MediaQuery.of(context).size.width;
              if (d.globalPosition.dx < w / 3) { _prev(); } else if (d.globalPosition.dx > w * 2 / 3) { _next(); }
            },
            onLongPressStart: (_) => _togglePause(),
            onLongPressEnd: (_) => _togglePause(),
            child: Stack(fit: StackFit.expand, children: [
              item.mediaType == 'photo'
                  ? CachedNetworkImage(imageUrl: item.mediaUrl, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(color: Colors.black))
                  : (_videoCtrl != null && _videoCtrl!.value.isInitialized
                      ? FittedBox(fit: BoxFit.cover,
                          child: SizedBox(width: _videoCtrl!.value.size.width, height: _videoCtrl!.value.size.height,
                              child: VideoPlayer(_videoCtrl!)))
                      : const Center(child: CircularProgressIndicator(color: Colors.white))),
              // Dégradé pour la lisibilité du haut.
              Positioned(top: 0, left: 0, right: 0, height: 140,
                  child: Container(decoration: const BoxDecoration(gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.black54, Colors.transparent])))),
              // Texte positionné librement (glissé à la création), comme
              // Instagram/Snapchat — pas figé en bas.
              if (item.legende != null && item.legende!.isNotEmpty)
                Positioned(
                  left: (item.legendeX * MediaQuery.of(context).size.width).clamp(0, MediaQuery.of(context).size.width) - 90,
                  top: (item.legendeY * MediaQuery.of(context).size.height).clamp(0, MediaQuery.of(context).size.height) - 20,
                  width: 180,
                  child: MentionHashtagText(
                    text: item.legende!,
                    enableHashtags: false,
                    style: TextStyle(
                      fontFamily: 'Galey',
                      color: _parseHexColor(item.legendeCouleur),
                      fontSize: switch (item.legendeTaille) { 's' => 14, 'l' => 22, _ => 17 },
                      fontWeight: item.legendeGras ? FontWeight.w800 : FontWeight.w400,
                    ),
                    onMentionTap: (pid) => openMentionedProfile(context, widget.myUid, pid),
                  ),
                ),
              SafeArea(
                child: Column(children: [
                  // Barres de progression segmentées.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(children: [
                      for (int i = 0; i < g.items.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(
                          child: AnimatedBuilder(
                            animation: _progressCtrl,
                            builder: (_, __) => ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                minHeight: 2.5,
                                value: i < _itemIndex
                                    ? 1
                                    : (i == _itemIndex
                                        ? (_item.mediaType == 'video' ? _videoProgress : _progressCtrl.value)
                                        : 0),
                                backgroundColor: Colors.white30,
                                valueColor: const AlwaysStoppedAnimation(Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
                    child: Row(children: [
                      CircleAvatar(radius: 16, backgroundColor: Colors.white24,
                          backgroundImage: photo?.isNotEmpty == true ? CachedNetworkImageProvider(photo!) : null,
                          child: photo?.isNotEmpty != true ? const Icon(Icons.person_outline, color: Colors.white70, size: 16) : null),
                      const SizedBox(width: 8),
                      Expanded(child: Text(nom.isEmpty ? 'Membre' : nom,
                          style: const TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
                      if (item.music != null) ...[
                        const Icon(Icons.music_note, color: Colors.white70, size: 15),
                        const SizedBox(width: 4),
                      ],
                      if (isMine)
                        IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white, size: 20), onPressed: _delete),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 22), onPressed: () => Navigator.pop(context)),
                    ]),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(children: [
                      if (isMine) ...[
                        GestureDetector(
                          onTap: _showViewers,
                          child: const Text('👁 Vu par…',
                              style: TextStyle(fontFamily: 'Galey', color: Colors.white70, fontSize: 12, decoration: TextDecoration.underline)),
                        ),
                        const Spacer(),
                        if (_likesCount > 0) ...[
                          const Icon(Icons.favorite, color: Colors.redAccent, size: 16),
                          const SizedBox(width: 4),
                          Text('$_likesCount', style: const TextStyle(fontFamily: 'Galey', color: Colors.white70, fontSize: 12)),
                        ],
                      ] else ...[
                        const Spacer(),
                        GestureDetector(
                          onTap: _toggleLike,
                          child: AnimatedScale(
                            scale: _liked ? 1.15 : 1,
                            duration: const Duration(milliseconds: 150),
                            child: Icon(_liked ? Icons.favorite : Icons.favorite_border,
                                color: _liked ? Colors.redAccent : Colors.white, size: 28),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }
}

Color _parseHexColor(String hex) {
  final h = hex.replaceAll('#', '');
  try {
    return Color(int.parse('FF$h', radix: 16));
  } catch (_) {
    return Colors.white;
  }
}
