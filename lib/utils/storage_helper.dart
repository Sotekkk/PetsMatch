import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

Future<String> _uploadDoc(File file, String storagePath, String bucket) async {
  final bytes = await file.readAsBytes();
  final ext = file.path.split('.').last.toLowerCase();
  final contentType = switch (ext) {
    'pdf'           => 'application/pdf',
    'png'           => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
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
String thumbUrl(String url, {int width = 600, int? height, int quality = 75, String resize = 'cover'}) {
  if (!url.contains('/storage/v1/object/public/')) return url;
  final h = height != null ? '&height=$height' : '';
  final sep = url.contains('?') ? '&' : '?'; // URL déjà versionnée (?v=…)
  return '${url.replaceFirst('/storage/v1/object/', '/storage/v1/render/image/')}${sep}width=$width$h&quality=$quality&resize=$resize';
}
