import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'story_service.dart';

/// Choix d'un morceau dans la bibliothèque maison (les seuls disponibles —
/// aucun import libre côté utilisateur, cf. story_service.dart) avec
/// pré-écoute avant de valider.
class StoryMusicPickerSheet extends StatefulWidget {
  const StoryMusicPickerSheet({super.key});

  @override
  State<StoryMusicPickerSheet> createState() => _StoryMusicPickerSheetState();
}

class _StoryMusicPickerSheetState extends State<StoryMusicPickerSheet> {
  static const _green = Color(0xFF6E9E57);

  List<StoryMusicTrack> _tracks = [];
  bool _loading = true;
  String? _playingId;
  final _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final tracks = await StoryService.loadMusicLibrary();
      if (mounted) setState(() { _tracks = tracks; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _togglePreview(StoryMusicTrack t) async {
    if (_playingId == t.id) {
      await _player.stop();
      setState(() => _playingId = null);
      return;
    }
    await _player.stop();
    setState(() => _playingId = t.id);
    try {
      await _player.setAudioContext(AudioContext(
        android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
      ));
      await _player.play(UrlSource(t.urlAudio));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7, maxChildSize: 0.9, minChildSize: 0.4, expand: false,
      builder: (_, sc) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('Musique', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 4),
          Text('Bibliothèque libre de droits PetsMatch', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 14),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _green))
                : _tracks.isEmpty
                    ? const Center(child: Text('Aucun morceau disponible pour le moment',
                        style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
                    : ListView.builder(
                        controller: sc,
                        itemCount: _tracks.length,
                        itemBuilder: (_, i) {
                          final t = _tracks[i];
                          final playing = _playingId == t.id;
                          return ListTile(
                            leading: GestureDetector(
                              onTap: () => _togglePreview(t),
                              child: CircleAvatar(
                                radius: 20, backgroundColor: const Color(0xFFE8F5E9),
                                child: Icon(playing ? Icons.pause : Icons.play_arrow, color: _green),
                              ),
                            ),
                            title: Text(t.titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: t.artiste != null ? Text(t.artiste!, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)) : null,
                            trailing: t.dureeSecondes != null
                                ? Text('${t.dureeSecondes}s', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey))
                                : null,
                            onTap: () => Navigator.pop(context, t),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}
