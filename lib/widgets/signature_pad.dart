import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Contrôleur d'un [SignaturePad].
/// Exporte le PNG en data-URL base64 (`data:image/png;base64,...`), format
/// attendu par `documents_animaux.metadata.signature_*` et
/// `cessions.signature_acquereur` (identique au canvas du site).
class SignaturePadController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];
  final GlobalKey _boundaryKey = GlobalKey();

  List<List<Offset>> get strokes => _strokes;
  bool get isEmpty => _strokes.every((s) => s.length < 2);

  void startStroke(Offset p) {
    _strokes.add([p]);
    notifyListeners();
  }

  void appendPoint(Offset p) {
    if (_strokes.isEmpty) _strokes.add([]);
    _strokes.last.add(p);
    notifyListeners();
  }

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  Future<String?> exportDataUrl() async {
    if (isEmpty) return null;
    try {
      final ctx = _boundaryKey.currentContext;
      if (ctx == null) return null;
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      final Uint8List bytes = byteData.buffer.asUint8List();
      return 'data:image/png;base64,${base64Encode(bytes)}';
    } catch (_) {
      return null;
    }
  }
}

/// Pavé de signature manuscrite. Utilise [Listener] (événements pointeur bruts)
/// pour ne jamais entrer en concurrence avec le scroll d'une liste parente.
class SignaturePad extends StatelessWidget {
  final SignaturePadController controller;
  final Color penColor;
  final Color backgroundColor;

  const SignaturePad({
    super.key,
    required this.controller,
    this.penColor = const Color(0xFF1F2A2E),
    this.backgroundColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: controller._boundaryKey,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => controller.startStroke(e.localPosition),
        onPointerMove: (e) => controller.appendPoint(e.localPosition),
        child: Container(
          color: backgroundColor,
          child: AnimatedBuilder(
            animation: controller,
            builder: (_, __) => CustomPaint(
              painter: _SignaturePainter(controller.strokes, penColor),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final Color color;

  _SignaturePainter(this.strokes, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawPoints(ui.PointMode.points, stroke, paint);
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter old) => true;
}

/// Affiche une signature déjà enregistrée (data-URL ou URL) en lecture seule.
class SignatureView extends StatelessWidget {
  final String signature;
  final double height;
  const SignatureView(this.signature, {super.key, this.height = 90});

  @override
  Widget build(BuildContext context) {
    final ImageProvider provider = signature.startsWith('data:image')
        ? MemoryImage(base64Decode(signature.substring(signature.indexOf(',') + 1)))
        : NetworkImage(signature) as ImageProvider;
    return Container(
      height: height,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x666E9E57)),
      ),
      child: Image(image: provider, fit: BoxFit.contain),
    );
  }
}

/// Écran plein écran pour signer confortablement. Retourne la data-URL PNG
/// (ou `null` si annulé / vide).
class SignatureFullScreen extends StatefulWidget {
  final String titre;
  const SignatureFullScreen({super.key, this.titre = 'Votre signature'});

  @override
  State<SignatureFullScreen> createState() => _SignatureFullScreenState();
}

class _SignatureFullScreenState extends State<SignatureFullScreen> {
  final _ctrl = SignaturePadController();
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_ctrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dessinez votre signature avant de valider.')),
      );
      return;
    }
    setState(() => _saving = true);
    final dataUrl = await _ctrl.exportDataUrl();
    if (mounted) Navigator.pop(context, dataUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C5C6C),
        foregroundColor: Colors.white,
        title: Text(widget.titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            const Text('Signez dans le cadre ci-dessous',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF5B5B5B))),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x330C5C6C), width: 1.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: SignaturePad(controller: _ctrl),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _ctrl.clear,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Effacer'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6F767B),
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _valider,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check, size: 18),
                  label: const Text('Valider ma signature',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6E9E57),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
