import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'story_service.dart';

/// Choix du passage du morceau à utiliser (façon TikTok/Instagram) : le
/// morceau dure souvent bien plus longtemps que la story elle-même (6s pour
/// une photo, la durée de la vidéo sinon) — on fait glisser une fenêtre sur
/// la timeline pour choisir où ça commence. La durée de la story elle-même
/// ne change jamais, seul le point de départ dans le MORCEAU change.
class StoryMusicTrimSheet extends StatefulWidget {
  final StoryMusicTrack track;
  final double neededSeconds;
  const StoryMusicTrimSheet({super.key, required this.track, required this.neededSeconds});

  @override
  State<StoryMusicTrimSheet> createState() => _StoryMusicTrimSheetState();
}

class _StoryMusicTrimSheetState extends State<StoryMusicTrimSheet> {
  static const _green = Color(0xFF6E9E57);

  late double _start; // secondes
  late final double _trackDuration;
  late final List<double> _bars; // hauteurs pseudo-waveform, stables pour ce morceau
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _trackDuration = (widget.track.dureeSecondes ?? widget.neededSeconds.ceil()).toDouble();
    _start = 0;
    // Pseudo-waveform déterministe (seedée sur l'id du morceau) — on n'a pas
    // de vraie analyse audio, mais un motif stable est suffisant pour donner
    // un repère visuel cohérent d'un passage à l'autre du sheet.
    final rng = Random(widget.track.id.hashCode);
    _bars = List.generate(60, (_) => 0.25 + rng.nextDouble() * 0.75);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  double get _maxStart => max(0, _trackDuration - widget.neededSeconds);

  Future<void> _togglePreview() async {
    if (_playing) {
      await _player.stop();
      setState(() => _playing = false);
      return;
    }
    setState(() => _playing = true);
    try {
      await _player.setAudioContext(AudioContext(
        android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
      ));
      await _player.play(UrlSource(widget.track.urlAudio), position: Duration(milliseconds: (_start * 1000).round()));
      // Coupe la pré-écoute à la fin du passage choisi, comme le fera la story.
      Future.delayed(Duration(milliseconds: (widget.neededSeconds * 1000).round()), () async {
        if (mounted && _playing) {
          await _player.stop();
          setState(() => _playing = false);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _onDragStart(double newStart) async {
    setState(() => _start = newStart.clamp(0, _maxStart));
    if (_playing) {
      await _player.stop();
      setState(() => _playing = false);
    }
  }

  String _fmt(double s) {
    final d = Duration(seconds: s.round());
    final m = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final canChoose = _maxStart > 0;

    return DraggableScrollableSheet(
      initialChildSize: 0.55, maxChildSize: 0.7, minChildSize: 0.4, expand: false,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(color: Color(0xFF0D1F22), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(widget.track.titre,
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17, color: Colors.white)),
            const SizedBox(height: 4),
            Text(
              canChoose ? 'Choisis le passage à utiliser' : 'Ce morceau tient tout entier dans ta story',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 24),

            if (canChoose) ...[
              // Pseudo-waveform + fenêtre de sélection.
              LayoutBuilder(builder: (context, constraints) {
                final w = constraints.maxWidth;
                final windowWidth = (widget.neededSeconds / _trackDuration * w).clamp(24.0, w);
                final windowLeft = (_start / _trackDuration * w).clamp(0.0, w - windowWidth);
                return GestureDetector(
                  onHorizontalDragUpdate: (d) {
                    final ratio = ((windowLeft + d.delta.dx) / w).clamp(0.0, 1.0);
                    _onDragStart(ratio * _trackDuration);
                  },
                  onTapUp: (d) {
                    final ratio = (d.localPosition.dx / w).clamp(0.0, 1.0);
                    _onDragStart(ratio * _trackDuration - widget.neededSeconds / 2);
                  },
                  child: SizedBox(
                    height: 64,
                    width: w,
                    child: Stack(children: [
                      // Barres pseudo-waveform.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: _bars.map((h) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: Container(height: 56 * h, decoration: BoxDecoration(
                                color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                          ),
                        )).toList(),
                      ),
                      // Fenêtre de sélection.
                      Positioned(
                        left: windowLeft, width: windowWidth, top: 0, bottom: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.25),
                            border: Border.all(color: _green, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ]),
                  ),
                );
              }),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(_fmt(0), style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white38)),
                Text(_fmt(_trackDuration), style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white38)),
              ]),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: _togglePreview,
                  child: Container(
                    width: 52, height: 52,
                    decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
                    child: Icon(_playing ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 26),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            SizedBox(
              width: double.infinity, height: 50,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _start),
                style: FilledButton.styleFrom(backgroundColor: _green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('Utiliser ce passage', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
