import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PorteePoidsPage extends StatefulWidget {
  final List<Map<String, dynamic>> animals;
  final DateTime? dateNaissance;

  const PorteePoidsPage({
    super.key,
    required this.animals,
    this.dateNaissance,
  });

  @override
  State<PorteePoidsPage> createState() => _PorteePoidsPageState();
}

class _PorteePoidsPageState extends State<PorteePoidsPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _seriesColors = [
    Color(0xFF5F9EAA),
    Color(0xFF6E9E57),
    Color(0xFFE57373),
    Color(0xFFFFB74D),
    Color(0xFF9575CD),
    Color(0xFF4DB6AC),
    Color(0xFFE91E63),
    Color(0xFF795548),
  ];

  bool _loading = true;
  Map<String, List<Map<String, dynamic>>> _poidsPerAnimal = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = widget.animals
        .map((a) => a['id'] as String?)
        .whereType<String>()
        .toList();
    if (ids.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('poids')
          .select()
          .inFilter('animal_id', ids)
          .order('date', ascending: true);
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final r in rows) {
        final id = r['animal_id'] as String?;
        if (id != null) grouped.putIfAbsent(id, () => []).add(r);
      }
      if (mounted) setState(() { _poidsPerAnimal = grouped; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Courbes de poids — Portée',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final animalsWithData = widget.animals.where((a) {
      final id = a['id'] as String?;
      return id != null && (_poidsPerAnimal[id]?.isNotEmpty ?? false);
    }).toList();

    if (animalsWithData.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.monitor_weight_outlined, size: 60, color: Color(0xFFB0BEC5)),
          const SizedBox(height: 12),
          const Text('Aucune pesée enregistrée',
              style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Color(0xFFB0BEC5))),
          const SizedBox(height: 8),
          const Text('Ajoutez des pesées dans la fiche de chaque bébé.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFFB0BEC5))),
        ]),
      );
    }

    // Build series: animalId → [(xDays, yKg)]
    final series = <String, List<Offset>>{};
    for (final a in animalsWithData) {
      final id = a['id'] as String;
      final docs = _poidsPerAnimal[id] ?? [];
      final birth = widget.dateNaissance ??
          DateTime.tryParse(a['date_naissance'] as String? ?? '') ??
          DateTime.tryParse(docs.first['date'] as String? ?? '') ??
          DateTime.now();
      final pts = <Offset>[];
      for (final d in docs) {
        final dt = DateTime.tryParse(d['date'] as String? ?? '');
        final val = double.tryParse(d['valeur']?.toString() ?? '');
        if (dt == null || val == null) continue;
        pts.add(Offset(dt.difference(birth).inDays.toDouble(), val));
      }
      if (pts.isNotEmpty) series[id] = pts;
    }

    final colorMap = <String, Color>{};
    int ci = 0;
    for (final a in animalsWithData) {
      colorMap[a['id'] as String] = _seriesColors[ci % _seriesColors.length];
      ci++;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        // Chart
        Container(
          height: 260,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: LayoutBuilder(
              builder: (_, __) => CustomPaint(
                painter: _PorteeChartPainter(series: series, colors: colorMap),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Légende + dernière pesée
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Légende',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 12),
              ...animalsWithData.map((a) {
                final id = a['id'] as String;
                final nom = (a['nom'] as String?) ?? '—';
                final sexe = (a['sexe'] as String?) ?? '';
                final color = colorMap[id]!;
                final docs = _poidsPerAnimal[id] ?? [];
                final dernierPoids = docs.isNotEmpty
                    ? double.tryParse(docs.last['valeur']?.toString() ?? '')
                    : null;
                final nbPesees = docs.length;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    Container(
                      width: 14, height: 14,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          '$nom${sexe.isNotEmpty ? " · $sexe" : ""}',
                          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        Text(
                          '$nbPesees ${nbPesees > 1 ? 'pesées' : 'pesée'}',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey),
                        ),
                      ]),
                    ),
                    if (dernierPoids != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _fmtKg(dernierPoids),
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                              color: color, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ]),
                );
              }),
            ],
          ),
        ),
      ]),
    );
  }

  static String _fmtKg(double v) {
    if (v < 0.1) return '${(v * 1000).round()}g';
    if (v < 1)   return '${(v * 1000).round()}g';
    return '${v.toStringAsFixed(1)} kg';
  }
}

// ─── Painter multi-séries ────────────────────────────────────────────────────

class _PorteeChartPainter extends CustomPainter {
  final Map<String, List<Offset>> series;   // animalId → [(xDays, yKg)]
  final Map<String, Color> colors;

  static const _l = 46.0, _t = 24.0, _r = 12.0, _b = 28.0;

  const _PorteeChartPainter({required this.series, required this.colors});

  @override
  bool shouldRepaint(_PorteeChartPainter o) => o.series != series;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    final w = size.width - _l - _r;
    final h = size.height - _t - _b;

    // Compute global bounds
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final pts in series.values) {
      for (final p in pts) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
    }
    if (!minX.isFinite) return;

    final rangeX = (maxX - minX) < 1 ? 1.0 : (maxX - minX);
    final rangeY = (maxY - minY) < 0.001 ? 1.0 : (maxY - minY) * 1.25;
    final baseY = minY - rangeY * 0.1;

    Offset toC(Offset d) {
      final x = _l + (rangeX < 1 ? w / 2 : (d.dx - minX) / rangeX * w);
      final y = _t + h - ((d.dy - baseY) / rangeY) * h;
      return Offset(x, y);
    }

    // Title
    final titleTp = TextPainter(
      text: const TextSpan(
        text: 'Courbes de croissance comparatives',
        style: TextStyle(fontFamily: 'Galey', fontSize: 11,
            fontWeight: FontWeight.w600, color: Color(0xFF0C5C6C)),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    titleTp.paint(canvas, Offset(_l, (_t - titleTp.height) / 2));

    // Grid
    final gridPaint = Paint()..color = const Color(0xFFF0F0F0)..strokeWidth = 1;
    for (int g = 0; g <= 4; g++) {
      final yVal = baseY + g * rangeY / 4;
      final yPx  = _t + h - g * h / 4;
      canvas.drawLine(Offset(_l, yPx), Offset(size.width - _r, yPx), gridPaint);
      final lbl = yVal < 0.1 ? '${(yVal * 1000).round()}g'
                : yVal < 1   ? '${(yVal * 1000).round()}g'
                :               '${yVal.toStringAsFixed(1)}k';
      final tp = TextPainter(
        text: TextSpan(text: lbl,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 9, color: Color(0xFFBBBBBB))),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((_l - tp.width - 3).clamp(0, _l), yPx - tp.height / 2));
    }

    // X-axis labels
    for (final frac in <double>[0.0, 0.25, 0.5, 0.75, 1.0]) {
      final xDays = minX + frac * rangeX;
      final xPx   = _l + frac * w;
      final lbl   = xDays < 14  ? '${xDays.round()}j'
                  : xDays < 90  ? '${(xDays / 7).round()}sem'
                  :                '${(xDays / 30).round()}m';
      final tp = TextPainter(
        text: TextSpan(text: lbl,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 9, color: Color(0xFFBBBBBB))),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset((xPx - tp.width / 2).clamp(_l, size.width - _r - tp.width), _t + h + 5));
    }

    // Series
    for (final entry in series.entries) {
      final pts = entry.value.map(toC).toList();
      final color = colors[entry.key] ?? const Color(0xFF5F9EAA);

      if (pts.length >= 2) {
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (int i = 1; i < pts.length; i++) path.lineTo(pts[i].dx, pts[i].dy);
        canvas.drawPath(path, Paint()
          ..color = color
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke);
      }

      for (final p in pts) {
        canvas.drawCircle(p, 4.0, Paint()..color = color);
        canvas.drawCircle(p, 2.5, Paint()..color = Colors.white);
      }
    }
  }
}
