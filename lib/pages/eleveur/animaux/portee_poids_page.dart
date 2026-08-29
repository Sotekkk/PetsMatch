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

  // Couleur stable par bébé (indépendante du fait qu'il ait des pesées).
  Color _colorFor(int index) => _seriesColors[index % _seriesColors.length];

  Future<void> _openAddPoids(Map<String, dynamic> animal) async {
    final id = animal['id'] as String?;
    if (id == null) return;
    final docs = _poidsPerAnimal[id] ?? [];
    final lastKg = docs.isNotEmpty
        ? double.tryParse(docs.last['valeur']?.toString() ?? '')
        : null;
    await showDialog<void>(
      context: context,
      builder: (_) => _QuickPoidsDialog(
        animalId: id,
        animalNom: (animal['nom'] as String?) ?? 'Bébé',
        lastKg: lastKg,
      ),
    );
    _load();
  }

  Widget _buildContent() {
    if (widget.animals.isEmpty) {
      return const Center(
        child: Text('Aucun bébé dans cette portée',
            style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Color(0xFFB0BEC5))),
      );
    }

    // Séries pour le graphe — uniquement les bébés qui ont des pesées.
    final series = <String, List<Offset>>{};
    final colorMap = <String, Color>{};
    for (var i = 0; i < widget.animals.length; i++) {
      final a = widget.animals[i];
      final id = a['id'] as String?;
      if (id == null) continue;
      colorMap[id] = _colorFor(i);
      final docs = _poidsPerAnimal[id] ?? [];
      if (docs.isEmpty) continue;
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        // Graphe (ou message si aucune pesée encore)
        Container(
          height: 260,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
          ),
          child: series.isEmpty
              ? const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.monitor_weight_outlined, size: 44, color: Color(0xFFB0BEC5)),
                    SizedBox(height: 8),
                    Text('Aucune pesée pour l\'instant',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFB0BEC5))),
                    SizedBox(height: 4),
                    Text('Appuyez sur un bébé ci-dessous pour peser',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFFB0BEC5))),
                  ]),
                )
              : ClipRRect(
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

        // Liste des bébés — TOUS, avec pesée ou non ; tap = ajouter une pesée
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('Bébés de la portée',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(width: 6),
                Text('· appuyez pour peser',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
              ]),
              const SizedBox(height: 10),
              ...List.generate(widget.animals.length, (i) {
                final a = widget.animals[i];
                final id = a['id'] as String? ?? '';
                final nom = (a['nom'] as String?)?.trim().isNotEmpty == true
                    ? a['nom'] as String
                    : 'Bébé ${i + 1}';
                final sexe = (a['sexe'] as String?) ?? '';
                final color = _colorFor(i);
                final docs = _poidsPerAnimal[id] ?? [];
                final nbPesees = docs.length;
                final dernierPoids = docs.isNotEmpty
                    ? double.tryParse(docs.last['valeur']?.toString() ?? '')
                    : null;
                return InkWell(
                  onTap: () => _openAddPoids(a),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(children: [
                      Container(
                        width: 14, height: 14,
                        decoration: BoxDecoration(
                          color: nbPesees > 0 ? color : Colors.transparent,
                          border: Border.all(color: color, width: 1.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('$nom${sexe.isNotEmpty ? " · $sexe" : ""}',
                              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
                          Text(
                            nbPesees == 0
                                ? 'Aucune pesée'
                                : '$nbPesees ${nbPesees > 1 ? 'pesées' : 'pesée'}',
                            style: TextStyle(
                                fontFamily: 'Galey', fontSize: 11,
                                color: nbPesees == 0 ? const Color(0xFFE29B3B) : Colors.grey),
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
                          child: Text(_fmtKg(dernierPoids),
                              style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                                  color: color, fontWeight: FontWeight.w700)),
                        ),
                      const SizedBox(width: 4),
                      Icon(Icons.add_circle_outline, size: 18, color: _teal.withValues(alpha: 0.6)),
                    ]),
                  ),
                );
              }),
            ],
          ),
        ),
      ]),
    );
  }

  static String _fmtKg(double v) {
    if (v < 1) return '${(v * 1000).round()} g';
    return '${v.toStringAsFixed(1).replaceAll('.', ',')} kg';
  }
}

// ─── Dialog pesée rapide (choix g / kg) ──────────────────────────────────────

class _QuickPoidsDialog extends StatefulWidget {
  final String animalId;
  final String animalNom;
  final double? lastKg;
  const _QuickPoidsDialog({required this.animalId, required this.animalNom, this.lastKg});
  @override
  State<_QuickPoidsDialog> createState() => _QuickPoidsDialogState();
}

class _QuickPoidsDialogState extends State<_QuickPoidsDialog> {
  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  final _valeur = TextEditingController();
  DateTime _date = DateTime.now();
  String _unite = 'g';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Défaut : g si le bébé a déjà été pesé en g (ou pas encore pesé), sinon kg.
    _unite = (widget.lastKg == null || widget.lastKg! < 1) ? 'g' : 'kg';
  }

  @override
  void dispose() { _valeur.dispose(); super.dispose(); }

  String _fmtInput(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  void _switchUnite(String u) {
    if (u == _unite) return;
    final v = double.tryParse(_valeur.text.replaceAll(',', '.'));
    setState(() {
      _unite = u;
      if (v != null) _valeur.text = _fmtInput(u == 'g' ? v * 1000 : v / 1000);
    });
  }

  Future<void> _save() async {
    final v = double.tryParse(_valeur.text.replaceAll(',', '.'));
    if (v == null) return;
    final kg = _unite == 'g' ? v / 1000 : v;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('poids').insert({
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'animal_id': widget.animalId,
        'valeur': kg,
        'date': DateTime(_date.year, _date.month, _date.day).toIso8601String(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Peser ${widget.animalNom}',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: _teal)),
          const SizedBox(height: 16),
          // Date
          GestureDetector(
            onTap: () async {
              final p = await showDatePicker(
                context: context, initialDate: _date,
                firstDate: DateTime(2015), lastDate: DateTime(2100),
                builder: (ctx, child) => Theme(
                  data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: _green)),
                  child: child!),
              );
              if (p != null) setState(() => _date = p);
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Date',
                labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                isDense: true,
                suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16, color: _green),
              ),
              child: Text(
                '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Poids + unité
          Row(children: [
            Expanded(
              child: TextField(
                controller: _valeur,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 15),
                decoration: InputDecoration(
                  labelText: 'Poids *',
                  labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _green)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  isDense: true,
                ),
                onSubmitted: (_) => _save(),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE4E7E2)),
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (final u in const ['g', 'kg']) ...[
                  if (u == 'kg') Container(width: 1, height: 34, color: const Color(0xFFE4E7E2)),
                  GestureDetector(
                    onTap: () => _switchUnite(u),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      color: _unite == u ? _green : Colors.transparent,
                      child: Text(u, style: TextStyle(
                          fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700,
                          color: _unite == u ? Colors.white : const Color(0xFF6F767B))),
                    ),
                  ),
                ],
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Annuler', style: TextStyle(color: Colors.grey, fontFamily: 'Galey')),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white),
              child: _saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey')),
            ),
          ]),
        ]),
      ),
    );
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
