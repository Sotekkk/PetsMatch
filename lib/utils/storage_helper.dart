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
  return supa.storage.from(_bucket).getPublicUrl(storagePath);
}

/// Upload any file (PDF, image, etc.) without compression.
Future<String> uploadRawFile(File file, String storagePath) async {
  final bytes = await file.readAsBytes();
  final ext = file.path.split('.').last.toLowerCase();
  final contentType = switch (ext) {
    'pdf'          => 'application/pdf',
    'png'          => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    _              => 'application/octet-stream',
  };
  final supa = Supabase.instance.client;
  await supa.storage.from(_bucket).uploadBinary(
    storagePath,
    bytes,
    fileOptions: FileOptions(contentType: contentType, upsert: true),
  );
  return supa.storage.from(_bucket).getPublicUrl(storagePath);
}

/// Transform a Supabase Storage URL for thumbnail display.
/// Returns the original URL if it is not a Supabase Storage URL.
String thumbUrl(String url, {int width = 600, int quality = 75, String resize = 'cover'}) {
  if (!url.contains('/storage/v1/object/public/')) return url;
  return '${url.replaceFirst('/storage/v1/object/', '/storage/v1/render/image/')}?width=$width&quality=$quality&resize=$resize';
}
