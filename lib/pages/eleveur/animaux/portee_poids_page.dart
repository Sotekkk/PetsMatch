import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PorteePoidsPage extends StatefulWidget {
  final List<Map<String, dynamic>> animals;
  final DateTime? dateNaissance;
  /// false = lecture seule (employé sans permission « Carnet de santé ») :
  /// on affiche le graphe et les pesées mais pas la saisie ni la suppression.
  final bool canEditPoids;

  const PorteePoidsPage({
    super.key,
    required this.animals,
    this.dateNaissance,
    this.canEditPoids = true,
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

  // Point sélectionné sur le graphe comparatif (tap) → info-bulle.
  String? _selId;
  int? _selIdx;

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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _BebePoidsSheet(
        animalId: id,
        animalNom: (animal['nom'] as String?)?.trim().isNotEmpty == true
            ? animal['nom'] as String
            : 'Bébé',
        dateNaissance: widget.dateNaissance ??
            DateTime.tryParse(animal['date_naissance'] as String? ?? ''),
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
    final nameMap = <String, String>{};
    for (var i = 0; i < widget.animals.length; i++) {
      final a = widget.animals[i];
      final id = a['id'] as String?;
      if (id == null) continue;
      colorMap[id] = _colorFor(i);
      nameMap[id] = (a['nom'] as String?)?.trim().isNotEmpty == true
          ? a['nom'] as String
          : 'Bébé ${i + 1}';
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
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.monitor_weight_outlined, size: 44, color: Color(0xFFB0BEC5)),
                    const SizedBox(height: 8),
                    const Text('Aucune pesée pour l\'instant',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFB0BEC5))),
                    if (widget.canEditPoids) ...[
                      const SizedBox(height: 4),
                      const Text('Appuyez sur un bébé ci-dessous pour peser',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFFB0BEC5))),
                    ],
                  ]),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: LayoutBuilder(
                    builder: (_, c) => GestureDetector(
                      onTapDown: (d) {
                        final hit = _PorteeChartPainter.nearestPoint(
                            d.localPosition, Size(c.maxWidth, c.maxHeight), series);
                        setState(() {
                          if (hit == null ||
                              (hit.$1 == _selId && hit.$2 == _selIdx)) {
                            _selId = null;
                            _selIdx = null;
                          } else {
                            _selId = hit.$1;
                            _selIdx = hit.$2;
                          }
                        });
                      },
                      child: CustomPaint(
                        painter: _PorteeChartPainter(
                          series: series,
                          colors: colorMap,
                          names: nameMap,
                          selId: _selId,
                          selIdx: _selIdx,
                        ),
                        child: const SizedBox.expand(),
                      ),
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
                if (widget.canEditPoids)
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
                  onTap: widget.canEditPoids ? () => _openAddPoids(a) : null,
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
                      if (widget.canEditPoids) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.add_circle_outline, size: 18, color: _teal.withValues(alpha: 0.6)),
                      ],
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

// ─── Sheet pesées d'un bébé (saisir / supprimer plusieurs d'affilée) ─────────

class _BebePoidsSheet extends StatefulWidget {
  final String animalId;
  final String animalNom;
  final DateTime? dateNaissance;
  const _BebePoidsSheet({required this.animalId, required this.animalNom, this.dateNaissance});
  @override
  State<_BebePoidsSheet> createState() => _BebePoidsSheetState();
}

class _BebePoidsSheetState extends State<_BebePoidsSheet> {
  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  final _supa = Supabase.instance.client;

  final _valeur = TextEditingController();
  final _dateCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  String _unite = 'g';
  bool _saving = false;
  bool _loading = true;
  List<Map<String, dynamic>> _pesees = [];

  @override
  void initState() {
    super.initState();
    _dateCtrl.text = DateFormat('dd/MM/yyyy').format(_date);
    _load();
  }

  @override
  void dispose() { _valeur.dispose(); _dateCtrl.dispose(); super.dispose(); }

  // Parse une date "jj/mm/aaaa" saisie à la main.
  DateTime? _parseFrDate(String s) {
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(s.trim());
    if (m == null) return null;
    final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), y = int.parse(m.group(3)!);
    final dt = DateTime(y, mo, d);
    if (dt.day != d || dt.month != mo) return null;
    return dt;
  }

  Future<void> _load() async {
    try {
      final rows = await _supa.from('poids').select()
          .eq('animal_id', widget.animalId).order('date', ascending: true);
      final list = List<Map<String, dynamic>>.from(rows as List);
      if (!mounted) return;
      setState(() {
        _pesees = list;
        _loading = false;
        // Unité par défaut : celle de la dernière pesée, sinon g.
        if (list.isNotEmpty) {
          final lastKg = double.tryParse(list.last['valeur']?.toString() ?? '');
          if (lastKg != null) _unite = lastKg < 1 ? 'g' : 'kg';
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtInput(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  String _fmtKg(double v) {
    if (v < 1) return '${(v * 1000).round()} g';
    return '${v.toStringAsFixed(1).replaceAll('.', ',')} kg';
  }

  void _switchUnite(String u) {
    if (u == _unite) return;
    final v = double.tryParse(_valeur.text.replaceAll(',', '.'));
    setState(() {
      _unite = u;
      if (v != null) _valeur.text = _fmtInput(u == 'g' ? v * 1000 : v / 1000);
    });
  }

  Future<void> _add() async {
    final v = double.tryParse(_valeur.text.replaceAll(',', '.'));
    if (v == null) return;
    // Prend la date tapée à la main si elle est valide, sinon celle sélectionnée.
    final typed = _parseFrDate(_dateCtrl.text);
    if (typed != null) {
      _date = typed;
    } else if (_dateCtrl.text.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Date invalide — format attendu : jj/mm/aaaa')));
      return;
    }
    final kg = _unite == 'g' ? v / 1000 : v;
    setState(() => _saving = true);
    try {
      await _supa.from('poids').insert({
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'animal_id': widget.animalId,
        'valeur': kg,
        'date': DateTime(_date.year, _date.month, _date.day).toIso8601String(),
      });
      _valeur.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await _supa.from('poids').delete().eq('id', id);
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Column(children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
            child: Row(children: [
              Expanded(
                child: Text('Pesées de ${widget.animalNom}',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: _teal)),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.grey),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),

          // Formulaire d'ajout (reste ouvert pour enchaîner)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(children: [
              TextField(
                controller: _dateCtrl,
                keyboardType: TextInputType.datetime,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
                  LengthLimitingTextInputFormatter(10),
                ],
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
                onChanged: (s) {
                  final d = _parseFrDate(s);
                  if (d != null) _date = d;
                },
                decoration: InputDecoration(
                  labelText: 'Date de la pesée',
                  hintText: 'jj/mm/aaaa',
                  labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                  hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFBDBDBD)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _green)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_today_outlined, size: 18, color: _green),
                    onPressed: () async {
                      final p = await showDatePicker(
                        context: context, initialDate: _date,
                        firstDate: DateTime(2015), lastDate: DateTime(2100),
                        builder: (ctx, child) => Theme(
                          data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: _green)),
                          child: child!),
                      );
                      if (p != null) {
                        setState(() => _date = p);
                        _dateCtrl.text = DateFormat('dd/MM/yyyy').format(p);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _valeur,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 15),
                    decoration: InputDecoration(
                      labelText: 'Poids',
                      labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _green)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _add(),
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
                const SizedBox(width: 8),
                SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _add,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _green, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14)),
                    child: _saving
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.add, size: 20),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Ajoutez plusieurs pesées d\'affilée — le panneau reste ouvert.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 10.5, color: Colors.grey.shade500)),
              ),
            ]),
          ),
          const Divider(height: 1),

          // Liste des pesées existantes (suppression)
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _teal))
                : _pesees.isEmpty
                    ? Center(child: Text('Aucune pesée',
                        style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)))
                    : ListView.separated(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(20, 10, 12, 24),
                        itemCount: _pesees.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final p = _pesees[_pesees.length - 1 - i]; // plus récentes en haut
                          final dt = DateTime.tryParse(p['date']?.toString() ?? '');
                          final kg = double.tryParse(p['valeur']?.toString() ?? '') ?? 0;
                          return Row(children: [
                            Expanded(
                              child: Text(dt != null ? df.format(dt) : '—',
                                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
                            ),
                            Text(_fmtKg(kg),
                                style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                                    fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                              onPressed: () => _delete(p['id']?.toString() ?? ''),
                            ),
                          ]);
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}

// ─── Painter multi-séries ────────────────────────────────────────────────────

class _PorteeChartPainter extends CustomPainter {
  final Map<String, List<Offset>> series;   // animalId → [(xDays, yKg)]
  final Map<String, Color> colors;
  final Map<String, String> names;
  final String? selId;
  final int? selIdx;

  static const _l = 46.0, _t = 24.0, _r = 12.0, _b = 28.0;

  const _PorteeChartPainter({
    required this.series,
    required this.colors,
    this.names = const {},
    this.selId,
    this.selIdx,
  });

  @override
  bool shouldRepaint(_PorteeChartPainter o) =>
      o.series != series || o.selId != selId || o.selIdx != selIdx;

  // Bornes globales de toutes les séries.
  static ({double minX, double rangeX, double baseY, double rangeY})? _bounds(
      Map<String, List<Offset>> series) {
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
    if (!minX.isFinite) return null;
    final rangeX = (maxX - minX) < 1 ? 1.0 : (maxX - minX);
    final rangeY = (maxY - minY) < 0.001 ? 1.0 : (maxY - minY) * 1.25;
    return (minX: minX, rangeX: rangeX, baseY: minY - rangeY * 0.1, rangeY: rangeY);
  }

  static Offset _toCanvas(Offset d, Size size,
      ({double minX, double rangeX, double baseY, double rangeY}) b) {
    final w = size.width - _l - _r;
    final h = size.height - _t - _b;
    final x = _l + (b.rangeX < 1 ? w / 2 : (d.dx - b.minX) / b.rangeX * w);
    final y = _t + h - ((d.dy - b.baseY) / b.rangeY) * h;
    return Offset(x, y);
  }

  /// Renvoie (animalId, index du point) le plus proche du tap, ou null.
  static (String, int)? nearestPoint(
      Offset tap, Size size, Map<String, List<Offset>> series) {
    final b = _bounds(series);
    if (b == null) return null;
    (String, int)? best;
    double bestDist = 30;
    for (final entry in series.entries) {
      for (var i = 0; i < entry.value.length; i++) {
        final dist = (_toCanvas(entry.value[i], size, b) - tap).distance;
        if (dist < bestDist) { bestDist = dist; best = (entry.key, i); }
      }
    }
    return best;
  }

  static String _fmtPoids(double kg) {
    if (kg < 1) return '${(kg * 1000).round()} g';
    if (kg < 10) {
      final s = kg.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
      return '${s.replaceAll('.', ',')} kg';
    }
    return '${kg.toStringAsFixed(1).replaceAll('.', ',')} kg';
  }

  static String _fmtAge(double days) {
    if (days < 14) return '${days.round()} j';
    if (days < 90) return '${(days / 7).round()} sem';
    return '${(days / 30).round()} mois';
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    final w = size.width - _l - _r;
    final h = size.height - _t - _b;

    final b = _bounds(series);
    if (b == null) return;
    final minX = b.minX, rangeX = b.rangeX, baseY = b.baseY, rangeY = b.rangeY;

    Offset toC(Offset d) => _toCanvas(d, size, b);

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

      final selPoint = entry.key == selId;
      for (var i = 0; i < pts.length; i++) {
        final p = pts[i];
        final isSel = selPoint && i == selIdx;
        canvas.drawCircle(p, isSel ? 6.0 : 4.0, Paint()..color = color);
        canvas.drawCircle(p, isSel ? 3.5 : 2.5, Paint()..color = Colors.white);
      }
    }

    // Info-bulle : nom de l'animal + poids (g ou kg) + âge
    final sId = selId, sIdx = selIdx;
    if (sId != null && sIdx != null) {
      final raw = series[sId];
      if (raw != null && sIdx >= 0 && sIdx < raw.length) {
        final dataPt = raw[sIdx];
        final p = toC(dataPt);
        final color = colors[sId] ?? const Color(0xFF5F9EAA);
        const pad = 8.0;
        final l1 = names[sId] ?? 'Bébé';
        final l2 = _fmtPoids(dataPt.dy);
        final l3 = _fmtAge(dataPt.dx);
        final tp1 = TextPainter(
          text: TextSpan(text: l1, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700)),
          textDirection: ui.TextDirection.ltr)..layout();
        final tp2 = TextPainter(
          text: TextSpan(text: l2, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white, fontWeight: FontWeight.w700)),
          textDirection: ui.TextDirection.ltr)..layout();
        final tp3 = TextPainter(
          text: TextSpan(text: l3, style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Color(0xCCFFFFFF))),
          textDirection: ui.TextDirection.ltr)..layout();
        final tw = [tp1.width, tp2.width, tp3.width].reduce((a, b) => a > b ? a : b) + pad * 2;
        final th = tp1.height + tp2.height + tp3.height + pad * 2 + 4;
        var tx = p.dx - tw / 2;
        var ty = p.dy - th - 12;
        if (tx < _l) tx = _l;
        if (tx + tw > size.width - _r) tx = size.width - _r - tw;
        if (ty < 0) ty = p.dy + 12;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(tx, ty, tw, th), const Radius.circular(8)),
          Paint()..color = color,
        );
        tp1.paint(canvas, Offset(tx + pad, ty + pad));
        tp2.paint(canvas, Offset(tx + pad, ty + pad + tp1.height + 2));
        tp3.paint(canvas, Offset(tx + pad, ty + pad + tp1.height + tp2.height + 4));
      }
    }
  }
}
