import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import 'package:PetsMatch/widgets/mention_hashtag.dart';
import 'story_music_picker.dart';
import 'story_service.dart';

/// Création d'une story (photo ou vidéo, 24h) — musique optionnelle, piochée
/// uniquement dans la bibliothèque maison (jamais d'import libre, cf.
/// story_service.dart).
class StoryCreatePage extends StatefulWidget {
  final String myUid;
  final String authorProfileId;
  final VoidCallback? onPosted;
  const StoryCreatePage({super.key, required this.myUid, required this.authorProfileId, this.onPosted});

  @override
  State<StoryCreatePage> createState() => _StoryCreatePageState();
}

class _StoryCreatePageState extends State<StoryCreatePage> {
  static const _green = Color(0xFF6E9E57);

  static const _legendeColors = [Colors.white, Colors.black, Color(0xFFFFE066), Color(0xFFFF6B6B), Color(0xFF6E9E57), Color(0xFF4ECDC4)];

  File? _mediaFile;
  String _mediaType = 'photo'; // photo | video
  VideoPlayerController? _videoCtrl;
  int? _videoDureeSecondes;
  StoryMusicTrack? _music;
  final _legendeCtrl = MentionTextEditingController();
  MentionController? _mentionCtrl;
  List<MentionSuggestion>? _mentionSuggestions;
  Color _legendeColor = Colors.white;
  String _legendeTaille = 'm'; // s | m | l
  bool _legendeGras = false;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _mentionCtrl = MentionController(
      textController: _legendeCtrl,
      excludeUid: widget.myUid,
      onSuggestionsChanged: (s) { if (mounted) setState(() => _mentionSuggestions = s); },
    );
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    _mentionCtrl?.dispose();
    _legendeCtrl.dispose();
    super.dispose();
  }

  double get _legendeFontSize => switch (_legendeTaille) { 's' => 14, 'l' => 22, _ => 17 };

  String _hex(Color c) => '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  Future<void> _pickPhoto(ImageSource source) async {
    final x = await ImagePicker().pickImage(source: source, imageQuality: 90, maxWidth: 1440);
    if (x == null) return;
    _videoCtrl?.dispose();
    setState(() { _mediaFile = File(x.path); _mediaType = 'photo'; _videoCtrl = null; _videoDureeSecondes = null; });
  }

  Future<void> _pickVideo(ImageSource source) async {
    final x = await ImagePicker().pickVideo(source: source, maxDuration: const Duration(seconds: 30));
    if (x == null) return;
    final file = File(x.path);
    final ctrl = VideoPlayerController.file(file);
    await ctrl.initialize();
    if (!mounted) return;
    setState(() {
      _mediaFile = file;
      _mediaType = 'video';
      _videoCtrl = ctrl..setLooping(true)..play();
      _videoDureeSecondes = ctrl.value.duration.inSeconds.clamp(1, 30);
    });
  }

  Future<void> _pickMusic() async {
    final track = await showModalBottomSheet<StoryMusicTrack?>(
      context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const StoryMusicPickerSheet(),
    );
    if (track != null && mounted) setState(() => _music = track);
  }

  Future<void> _post() async {
    final media = _mediaFile;
    if (media == null || _posting) return;
    setState(() => _posting = true);
    try {
      final supa = Supabase.instance.client;
      Uint8List bytes;
      String ext;
      String contentType;
      if (_mediaType == 'photo') {
        final compressed = await FlutterImageCompress.compressWithFile(
          media.path, quality: 82, minWidth: 1080, minHeight: 1080, keepExif: false,
        );
        bytes = compressed ?? await media.readAsBytes();
        ext = 'jpg'; contentType = 'image/jpg';
      } else {
        bytes = await media.readAsBytes();
        ext = 'mp4'; contentType = 'video/mp4';
      }
      final path = '${widget.authorProfileId}/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await supa.storage.from('stories').uploadBinary(path, bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false));
      final url = supa.storage.from('stories').getPublicUrl(path);

      final legende = _legendeCtrl.resolveMarkup().trim();
      await StoryService.createStory(
        uid: widget.myUid,
        authorProfileId: widget.authorProfileId,
        mediaUrl: url,
        mediaType: _mediaType,
        dureeSecondes: _mediaType == 'video' ? _videoDureeSecondes : null,
        musicTrackId: _music?.id,
        legende: legende,
        legendeCouleur: _hex(_legendeColor),
        legendeTaille: _legendeTaille,
        legendeGras: _legendeGras,
      );
      if (legende.isNotEmpty) {
        unawaited(notifyMentions(
          text: legende,
          actorUid: widget.myUid,
          notifType: 'social_mention',
          title: '📣 Tu as été mentionné(e)',
          body: 'Tu as été mentionné(e) dans une story Pets Social',
          data: const {},
        ));
      }

      if (mounted) {
        widget.onPosted?.call();
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
            backgroundColor: Colors.red.shade800));
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context)),
              const Spacer(),
              const Text('Nouvelle story', style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              const Spacer(),
              const SizedBox(width: 48),
            ]),
          ),
          Expanded(
            child: _mediaFile == null ? _buildPicker() : _buildPreview(),
          ),
        ]),
      ),
    );
  }

  Widget _buildPicker() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.auto_stories_outlined, color: Colors.white38, size: 72),
        const SizedBox(height: 24),
        Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
          _pickerBtn(Icons.camera_alt_outlined, 'Photo', () => _pickPhoto(ImageSource.camera)),
          _pickerBtn(Icons.photo_library_outlined, 'Galerie photo', () => _pickPhoto(ImageSource.gallery)),
          _pickerBtn(Icons.videocam_outlined, 'Vidéo (30s max)', () => _pickVideo(ImageSource.camera)),
          _pickerBtn(Icons.video_library_outlined, 'Galerie vidéo', () => _pickVideo(ImageSource.gallery)),
        ]),
      ]),
    );
  }

  Widget _pickerBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          Icon(icon, color: Colors.white, size: 26),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Galey', color: Colors.white70, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _buildPreview() {
    return Stack(fit: StackFit.expand, children: [
      _mediaType == 'photo'
          ? Image.file(_mediaFile!, fit: BoxFit.cover)
          : (_videoCtrl != null && _videoCtrl!.value.isInitialized
              ? FittedBox(fit: BoxFit.cover,
                  child: SizedBox(width: _videoCtrl!.value.size.width, height: _videoCtrl!.value.size.height,
                      child: VideoPlayer(_videoCtrl!)))
              : const Center(child: CircularProgressIndicator(color: Colors.white))),
      Positioned(
        left: 16, right: 16, bottom: 24,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_music != null)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.music_note, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Flexible(child: Text('${_music!.titre}${_music!.artiste != null ? ' — ${_music!.artiste}' : ''}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', color: Colors.white, fontSize: 12))),
                const SizedBox(width: 6),
                GestureDetector(onTap: () => setState(() => _music = null),
                    child: const Icon(Icons.close, color: Colors.white70, size: 16)),
              ]),
            ),
          // Style du texte — couleur / taille / gras.
          Row(children: [
            for (final c in _legendeColors) ...[
              GestureDetector(
                onTap: () => setState(() => _legendeColor = c),
                child: Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    color: c, shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: _legendeColor == c ? 2.5 : 1),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Spacer(),
            for (final t in const [('s', 'P'), ('m', 'M'), ('l', 'G')]) ...[
              GestureDetector(
                onTap: () => setState(() => _legendeTaille = t.$1),
                child: Container(
                  width: 26, height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _legendeTaille == t.$1 ? _green : Colors.white10,
                  ),
                  child: Text(t.$2, style: const TextStyle(fontFamily: 'Galey', color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 6),
            ],
            GestureDetector(
              onTap: () => setState(() => _legendeGras = !_legendeGras),
              child: Container(
                width: 26, height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: _legendeGras ? _green : Colors.white10),
                child: const Text('B', style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _legendeCtrl,
            maxLines: 3, minLines: 1,
            style: TextStyle(fontFamily: 'Galey', color: _legendeColor,
                fontSize: _legendeFontSize, fontWeight: _legendeGras ? FontWeight.w800 : FontWeight.w400),
            decoration: InputDecoration(
              hintText: 'Ajouter une légende… @ pour mentionner',
              hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.white54, fontSize: 14),
              filled: true, fillColor: Colors.black38,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          if (_mentionSuggestions != null)
            Container(
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
              child: MentionSuggestionsBar(
                suggestions: _mentionSuggestions!,
                onSelect: (s) { _mentionCtrl?.select(s); setState(() => _mentionSuggestions = null); },
              ),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickMusic,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38), padding: const EdgeInsets.symmetric(vertical: 12)),
                icon: const Icon(Icons.music_note_outlined, size: 18),
                label: Text(_music == null ? 'Musique' : 'Changer', style: const TextStyle(fontFamily: 'Galey')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _posting ? null : _post,
                style: FilledButton.styleFrom(backgroundColor: _green, padding: const EdgeInsets.symmetric(vertical: 12)),
                child: _posting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Publier', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ]),
      ),
    ]);
  }
}
