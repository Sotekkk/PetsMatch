import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import 'package:PetsMatch/widgets/mention_hashtag.dart' show notifyMentions;
import 'story_service.dart';

/// Publication d'une story en tâche de fond — l'utilisateur revient
/// immédiatement au fil (comme Instagram) pendant que compression + upload
/// continuent ; [progress] pilote l'anneau affiché sur « Ma story ».
class StoryUploadService {
  StoryUploadService._();
  static final instance = StoryUploadService._();

  /// null = pas de publication en cours, sinon 0..1.
  final ValueNotifier<double?> progress = ValueNotifier(null);
  final ValueNotifier<String?> error = ValueNotifier(null);
  VoidCallback? onDone;

  Future<void> upload({
    required String myUid,
    required String authorProfileId,
    File? media,
    required String mediaType, // 'photo' | 'video' | 'texte'
    int? videoDureeSecondes,
    StoryMusicTrack? music,
    String? legende,
    String legendeCouleur = '#FFFFFF',
    String legendeTaille = 'm',
    bool legendeGras = false,
    double legendeX = 0.5,
    double legendeY = 0.5,
    String? fond,
  }) async {
    progress.value = 0.02;
    error.value = null;
    Subscription? sub;
    try {
      String? url;
      if (mediaType == 'texte') {
        progress.value = 0.5;
      } else if (media != null) {
        final supa = Supabase.instance.client;
        Uint8List bytes;
        String ext;
        String contentType;
        if (mediaType == 'photo') {
          final compressed = await FlutterImageCompress.compressWithFile(
            media.path, quality: 82, minWidth: 1080, minHeight: 1080, keepExif: false,
          );
          bytes = compressed ?? await media.readAsBytes();
          ext = 'jpg'; contentType = 'image/jpg';
          progress.value = 0.5;
        } else {
          sub = VideoCompress.compressProgress$.subscribe((p) {
            progress.value = 0.02 + (p.clamp(0, 100) / 100) * 0.5;
          });
          File videoToUpload = media;
          try {
            final info = await VideoCompress.compressVideo(
              media.path, quality: VideoQuality.MediumQuality, deleteOrigin: false,
            );
            final compressed = info?.file;
            if (compressed != null && await compressed.exists() && await compressed.length() > 10000) {
              final testCtrl = VideoPlayerController.file(compressed);
              try {
                await testCtrl.initialize().timeout(const Duration(seconds: 10));
                if (testCtrl.value.isInitialized && testCtrl.value.duration.inMilliseconds > 0) {
                  videoToUpload = compressed;
                }
              } catch (_) {
                // Compression illisible → on garde l'original.
              } finally {
                await testCtrl.dispose();
              }
            }
          } catch (_) {
            // Repli sur le fichier d'origine si la compression échoue.
          }
          bytes = await videoToUpload.readAsBytes();
          ext = 'mp4'; contentType = 'video/mp4';
          progress.value = 0.55;
        }
        final path = '$authorProfileId/${DateTime.now().millisecondsSinceEpoch}.$ext';
        progress.value = 0.65;
        await supa.storage.from('stories').uploadBinary(path, bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: false));
        progress.value = 0.9;
        url = supa.storage.from('stories').getPublicUrl(path);
      }

      await StoryService.createStory(
        uid: myUid,
        authorProfileId: authorProfileId,
        mediaUrl: url,
        mediaType: mediaType,
        dureeSecondes: mediaType == 'video' ? videoDureeSecondes : null,
        musicTrackId: music?.id,
        legende: legende,
        legendeCouleur: legendeCouleur,
        legendeTaille: legendeTaille,
        legendeGras: legendeGras,
        legendeX: legendeX,
        legendeY: legendeY,
        fond: fond,
      );
      progress.value = 1;

      if (legende != null && legende.isNotEmpty) {
        unawaited(notifyMentions(
          text: legende,
          actorUid: myUid,
          notifType: 'social_mention',
          title: '📣 Tu as été mentionné(e)',
          body: 'Tu as été mentionné(e) dans une story Pets Social',
          data: const {},
        ));
      }
    } catch (e) {
      error.value = e.toString();
    } finally {
      sub?.unsubscribe();
      await Future.delayed(const Duration(milliseconds: 500));
      progress.value = null;
      onDone?.call();
    }
  }
}
