import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

const _bucket = 'media';

/// Compress [file] then upload to Supabase Storage at [storagePath].
/// Returns the public URL.
Future<String> uploadPhoto(
  File file,
  String storagePath, {
  int maxDim = 1200,
  int quality = 82,
}) async {
  final result = await FlutterImageCompress.compressWithFile(
    file.absolute.path,
    minWidth: maxDim, minHeight: maxDim,
    quality: quality, keepExif: false,
  );
  final bytes = result ?? await file.readAsBytes();
  return _upload(bytes, storagePath);
}

/// Comme [uploadPhoto], mais dans le stockage PRIVÉ `documents` (KBIS,
/// ACACED…) : s'ouvre ensuite via lienDocument / ImagePrivee.
Future<String> uploadPhotoPrive(File file, String storagePath, {int maxDim = 1600, int quality = 85}) async {
  final result = await FlutterImageCompress.compressWithFile(
    file.absolute.path,
    minWidth: maxDim, minHeight: maxDim,
    quality: quality, keepExif: false,
  );
  final bytes = result ?? await file.readAsBytes();
  final supa = Supabase.instance.client;
  await supa.storage.from('documents').uploadBinary(
    storagePath, bytes,
    fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
  );
  final url = supa.storage.from('documents').getPublicUrl(storagePath);
  return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
}

/// Upload already-encoded [bytes] to Supabase Storage at [storagePath].
/// Returns the public URL.
Future<String> uploadPhotoBytes(
  Uint8List bytes,
  String storagePath,
) async {
  return _upload(bytes, storagePath);
}

Future<String> _upload(Uint8List bytes, String storagePath) async {
  final supa = Supabase.instance.client;
  await supa.storage.from(_bucket).uploadBinary(
    storagePath,
    bytes,
    fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
  );
  // Marqueur de version : beaucoup de photos gardent un nom fixe
  // (profiles/<uid>/photo.jpg…). Sans lui, l'URL ne change pas et l'appli
  // comme le CDN Supabase (cache 1 h) continuent d'afficher l'ancienne image
  // après un changement de photo.
  final url = supa.storage.from(_bucket).getPublicUrl(storagePath);
  return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
}

/// Upload any file (PDF, image, etc.) without compression — uses the `media` bucket.
Future<String> uploadRawFile(File file, String storagePath) async {
  return _uploadDoc(file, storagePath, _bucket);
}

/// Upload document/medical file to the `documents` bucket (allows PDF).
/// Octets déjà encodés (PDF généré…) → bucket PRIVÉ `documents`.
Future<String> uploadDocumentBytes(Uint8List bytes, String storagePath,
    {String contentType = 'application/pdf'}) async {
  final supa = Supabase.instance.client;
  await supa.storage.from('documents').uploadBinary(
    storagePath, bytes,
    fileOptions: FileOptions(contentType: contentType, upsert: true),
  );
  return supa.storage.from('documents').getPublicUrl(storagePath);
}

Future<String> uploadDocument(File file, String storagePath) async {
  return _uploadDoc(file, storagePath, 'documents');
}

/// Poids maximal d'un document non compressible (PDF…) : au-delà, chaque
/// ouverture coûte cher en trafic Supabase (« Cached Egress »).
const tailleMaxDocument = 15 * 1024 * 1024;

/// Vidéo réencodée en 960×540 (comme les stories : relue avant d'être
/// retenue) ; repli sur l'original si la compression échoue ou n'allège pas.
Future<File> compresserVideo(File video) async {
  try {
    final info = await VideoCompress.compressVideo(
      video.path, quality: VideoQuality.Res960x540Quality, deleteOrigin: false,
    );
    final f = info?.file;
    if (f == null || !await f.exists()) return video;
    final taille = await f.length();
    if (taille < 10000 || taille >= await video.length()) return video;
    final ctrl = VideoPlayerController.file(f);
    try {
      await ctrl.initialize().timeout(const Duration(seconds: 10));
      if (ctrl.value.isInitialized && ctrl.value.duration.inMilliseconds > 0) return f;
    } catch (_) {
    } finally {
      await ctrl.dispose();
    }
  } catch (_) {}
  return video;
}

Future<String> _uploadDoc(File file, String storagePath, String bucket) async {
  final ext = file.path.split('.').last.toLowerCase();
  final estVideo = const {'mp4', 'mov', 'webm', '3gp', 'm4v'}.contains(ext);
  final estImage = const {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'}.contains(ext);
  Uint8List bytes;
  var videoReencodee = false;
  if (estVideo) {
    final v = await compresserVideo(file);
    videoReencodee = v.path != file.path;
    bytes = await v.readAsBytes();
  } else if (estImage && await file.length() > 500 * 1024) {
    // Photo de document (scan, radio…) : 2000 px restent lisibles.
    final c = await FlutterImageCompress.compressWithFile(
      file.absolute.path, minWidth: 2000, minHeight: 2000, quality: 85, keepExif: false,
    );
    bytes = c ?? await file.readAsBytes();
  } else {
    bytes = await file.readAsBytes();
  }
  if (!estVideo && bytes.length > tailleMaxDocument) {
    throw Exception('Fichier trop lourd (${(bytes.length / 1048576).toStringAsFixed(0)} Mo, 15 Mo maximum). '
        'Pour un document scanné, envoyez plutôt une photo.');
  }
  final contentType = switch (ext) {
    'pdf'           => 'application/pdf',
    _ when estImage && bytes.isNotEmpty && bytes[0] == 0xFF => 'image/jpeg', // JPEG (réencodé ou d'origine)
    'png'           => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    _ when videoReencodee => 'video/mp4',
    'mp4'           => 'video/mp4',
    'mov'           => 'video/quicktime',
    'webm'          => 'video/webm',
    '3gp'           => 'video/3gpp',
    _               => 'application/octet-stream',
  };
  final supa = Supabase.instance.client;
  await supa.storage.from(bucket).uploadBinary(
    storagePath,
    bytes,
    fileOptions: FileOptions(contentType: contentType, upsert: true),
  );
  return supa.storage.from(bucket).getPublicUrl(storagePath);
}

/// Transform a Supabase Storage URL for thumbnail display.
/// Returns the original URL if it is not a Supabase Storage URL.
// NB : l'add-on de transformation d'image Supabase (/storage/v1/render/image/)
// n'est pas activé sur ce projet (403 FeatureNotEnabled) — réécrire l'URL vers
// /render/image/ laissait les photos Supabase vides dans le fil et les favoris.
// On renvoie l'URL d'origine (même choix que website/src/lib/upload-media.ts) ;
// la taille d'affichage reste gérée par le widget (BoxFit).
String thumbUrl(String url, {int width = 600, int? height, int quality = 75, String resize = 'cover'}) {
  return url;
}
