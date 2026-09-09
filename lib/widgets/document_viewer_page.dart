import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

/// Lecteur de document plein écran, dans l'appli (image ou PDF).
/// Ouvre via `DocumentViewerPage.open(context, url, title: …)`.
class DocumentViewerPage extends StatefulWidget {
  final String url;
  final String title;
  const DocumentViewerPage({super.key, required this.url, this.title = 'Document'});

  static Future<void> open(BuildContext context, String url, {String title = 'Document'}) {
    if (url.trim().isEmpty) return Future.value();
    return Navigator.push(context, MaterialPageRoute(
      builder: (_) => DocumentViewerPage(url: url, title: title),
    ));
  }

  bool get _isImage {
    final u = url.toLowerCase().split('?').first;
    return u.endsWith('.png') || u.endsWith('.jpg') || u.endsWith('.jpeg') || u.endsWith('.webp') || u.endsWith('.gif');
  }

  @override
  State<DocumentViewerPage> createState() => _DocumentViewerPageState();
}

class _DocumentViewerPageState extends State<DocumentViewerPage> {
  Uint8List? _bytes;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    if (widget._isImage) {
      _loading = false;
    } else {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    try {
      final res = await http.get(Uri.parse(widget.url));
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() { _bytes = res.bodyBytes; _loading = false; });
      } else {
        setState(() { _error = true; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = true; _loading = false; });
    }
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(widget.url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECEEF0),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C5C6C),
        foregroundColor: Colors.white,
        title: Text(widget.title,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16),
            overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Ouvrir dans une autre appli',
            onPressed: _openExternal,
          ),
        ],
      ),
      body: _build(),
    );
  }

  Widget _build() {
    if (widget._isImage) {
      return InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: Image.network(widget.url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _errorView()),
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF0C5C6C)));
    if (_error || _bytes == null) return _errorView();
    return PdfPreview(
      build: (_) => _bytes!,
      useActions: false,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      scrollViewDecoration: const BoxDecoration(color: Color(0xFFECEEF0)),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.description_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Impossible d\'afficher le document ici.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openExternal,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Ouvrir autrement', style: TextStyle(fontFamily: 'Galey')),
            ),
          ]),
        ),
      );
}
