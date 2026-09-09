import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Lecteur vidéo réseau minimal : vignette « play », tap pour lancer, tap pour
/// pause/reprise. Utilisé par le journal de pension/garde et les annonces.
class InlineVideo extends StatefulWidget {
  final String url;
  final double placeholderHeight;
  const InlineVideo({super.key, required this.url, this.placeholderHeight = 220});

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  VideoPlayerController? _controller;
  bool _playing = false;
  bool _loading = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await controller.initialize();
      await controller.play();
      if (!mounted) { controller.dispose(); return; }
      setState(() { _controller = controller; _playing = true; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_playing && _controller != null) {
      return AspectRatio(
        aspectRatio: _controller!.value.aspectRatio == 0 ? 16 / 9 : _controller!.value.aspectRatio,
        child: GestureDetector(
          onTap: () => setState(() {
            _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
          }),
          child: VideoPlayer(_controller!),
        ),
      );
    }
    return GestureDetector(
      onTap: _play,
      child: Container(
        height: widget.placeholderHeight, width: double.infinity, color: Colors.black87,
        child: Center(
          child: _loading
              ? const SizedBox(width: 32, height: 32,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.play_circle_fill, color: Colors.white, size: 56),
        ),
      ),
    );
  }
}
