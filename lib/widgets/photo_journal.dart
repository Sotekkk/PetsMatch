// Photo d'un journal (pension, garde, comptes rendus) : affichée en entier
// (contain sur fond flouté, jamais rognée — comme les favoris), plein écran au
// toucher avec zoom, et bouton « Télécharger » (partage natif : Enregistrer
// dans Photos / Fichiers…). Photos privées : lien signé (document_prive.dart).
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';

import 'package:PetsMatch/utils/document_prive.dart';

Future<String> _lien(String url) async => estDocumentPrive(url) ? await lienDocument(url) : url;

class PhotoJournal extends StatelessWidget {
  final String url;
  final double height;
  final BorderRadius? radius;
  const PhotoJournal(this.url, {super.key, this.height = 220, this.radius});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => ouvrirPhotoPleinEcran(context, url),
      child: ClipRRect(
        borderRadius: radius ?? BorderRadius.circular(10),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: FutureBuilder<String>(
            future: _lien(url),
            builder: (c, snap) {
              if (!snap.hasData) {
                return Container(color: const Color(0xFFF1F1EF),
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
              }
              final img = snap.data!;
              return Stack(fit: StackFit.expand, children: [
                // Fond : la même photo, floutée (pas de bandes vides).
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: CachedNetworkImage(imageUrl: img, cacheKey: url, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const SizedBox()),
                ),
                Container(color: Colors.black.withValues(alpha: 0.08)),
                // Photo entière, jamais rognée.
                CachedNetworkImage(imageUrl: img, cacheKey: url, fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined, color: Colors.grey))),
                Positioned(
                  right: 8, bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.open_in_full, size: 16, color: Colors.white),
                  ),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

Future<void> ouvrirPhotoPleinEcran(BuildContext context, String url) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => PhotoPleinEcranPage(url: url)));

class PhotoPleinEcranPage extends StatefulWidget {
  final String url;
  const PhotoPleinEcranPage({super.key, required this.url});
  @override
  State<PhotoPleinEcranPage> createState() => _PhotoPleinEcranPageState();
}

class _PhotoPleinEcranPageState extends State<PhotoPleinEcranPage> {
  late final Future<String> _lienF = _lien(widget.url);
  bool _telechargement = false;

  Future<void> _telecharger() async {
    setState(() => _telechargement = true);
    try {
      final lien = await _lienF;
      final r = await http.get(Uri.parse(lien));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final type = r.headers['content-type'] ?? '';
      final ext = type.contains('png') ? 'png' : type.contains('webp') ? 'webp' : 'jpg';
      final f = File('${(await getTemporaryDirectory()).path}/photo_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await f.writeAsBytes(r.bodyBytes);
      await Share.shareXFiles([XFile(f.path, mimeType: type.isEmpty ? 'image/jpeg' : type)]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Téléchargement impossible : $e')));
      }
    } finally {
      if (mounted) setState(() => _telechargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          _telechargement
              ? const Padding(padding: EdgeInsets.all(16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
              : TextButton.icon(
                  onPressed: _telecharger,
                  icon: const Icon(Icons.download_outlined, color: Colors.white),
                  label: const Text('Télécharger', style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
                ),
        ],
      ),
      body: FutureBuilder<String>(
        future: _lienF,
        builder: (c, snap) => !snap.hasData
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : PhotoView(
                imageProvider: CachedNetworkImageProvider(snap.data!, cacheKey: widget.url),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4,
                backgroundDecoration: const BoxDecoration(color: Colors.black),
              ),
      ),
    );
  }
}
