import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Documents du stockage PRIVÉ (buckets `documents` / `contrats`) :
/// le lien enregistré en base ne s'ouvre plus directement. On demande à
/// l'Edge Function `lien-document` un lien temporaire (10 min), après
/// vérification des droits de l'utilisateur sur la fiche qui référence le
/// document. Tout autre lien (photo publique, Firebase…) est renvoyé tel quel.

final _prive = RegExp(r'/storage/v1/object/public/(documents|contrats)/');
final _cache = <String, (String, DateTime)>{};

bool estDocumentPrive(String? url) => url != null && _prive.hasMatch(url);

/// Lien utilisable pour afficher / ouvrir [url]. [lienSecret] : jeton d'un
/// lien de partage (acquéreur sans compte…), transmis en x-pm-token.
Future<String> lienDocument(String url, {String? lienSecret}) async {
  if (!estDocumentPrive(url)) return url;
  final cle = '$url|${lienSecret ?? ''}';
  final c = _cache[cle];
  if (c != null && c.$2.isAfter(DateTime.now())) return c.$1;
  final res = await Supabase.instance.client.functions.invoke(
    'lien-document',
    body: {'url': url},
    headers: lienSecret != null ? {'x-pm-token': lienSecret} : null,
  );
  final signe = (res.data as Map?)?['url'] as String?;
  if (signe == null || signe.isEmpty) throw Exception('Document inaccessible');
  _cache[cle] = (signe, DateTime.now().add(const Duration(minutes: 9)));
  return signe;
}

/// Ouvre [url] (PDF, image…) dans l'application externe, via un lien
/// temporaire si le document est privé. Affiche une erreur sinon.
Future<void> ouvrirDocument(BuildContext context, String? url, {String? lienSecret}) async {
  if (url == null || url.isEmpty) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final lien = await lienDocument(url, lienSecret: lienSecret);
    await launchUrl(Uri.parse(lien), mode: LaunchMode.externalApplication);
  } catch (_) {
    messenger?.showSnackBar(const SnackBar(content: Text("Impossible d'ouvrir le document.")));
  }
}

/// Image d'un document (privé ou non) : comme CachedNetworkImage, avec le
/// lien temporaire résolu au besoin. Le cache disque utilise le lien
/// d'origine comme clé (le lien temporaire change à chaque demande).
class ImagePrivee extends StatelessWidget {
  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final String? lienSecret;
  final Widget Function(BuildContext)? enErreur;

  const ImagePrivee(this.url, {super.key, this.fit, this.width, this.height, this.lienSecret, this.enErreur});

  @override
  Widget build(BuildContext context) {
    if (!estDocumentPrive(url)) {
      return CachedNetworkImage(imageUrl: url, fit: fit, width: width, height: height,
          errorWidget: (c, _, __) => enErreur?.call(c) ?? const Icon(Icons.broken_image_outlined));
    }
    return FutureBuilder<String>(
      future: lienDocument(url, lienSecret: lienSecret),
      builder: (c, snap) {
        if (snap.hasError) return enErreur?.call(c) ?? const Icon(Icons.lock_outline);
        if (!snap.hasData) {
          return SizedBox(width: width, height: height,
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        return CachedNetworkImage(imageUrl: snap.data!, cacheKey: url, fit: fit, width: width, height: height,
            errorWidget: (c, _, __) => enErreur?.call(c) ?? const Icon(Icons.broken_image_outlined));
      },
    );
  }
}
