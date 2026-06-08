import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart';

class PartnerDashboardPage extends StatefulWidget {
  const PartnerDashboardPage({super.key});

  @override
  State<PartnerDashboardPage> createState() => _PartnerDashboardPageState();
}

class _PartnerDashboardPageState extends State<PartnerDashboardPage> {
  final _supabase = Supabase.instance.client;

  Map<String, dynamic>? _partner;
  int _impressions = 0;
  int _clics = 0;
  int _leads = 0;
  List<_DayStats> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Récupère le partenaire lié à l'uid
      final partners = await _supabase
          .from('marketplace_partners')
          .select()
          .eq('user_id', User_Info.uid)
          .limit(1);

      if ((partners as List).isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final partner = Map<String, dynamic>.from(partners.first);

      // Events du mois en cours
      final now = DateTime.now();
      final firstOfMonth =
          DateTime(now.year, now.month, 1).toIso8601String();

      final events = await _supabase
          .from('marketplace_events')
          .select('event_type, created_at')
          .eq('partner_id', partner['id'])
          .gte('created_at', firstOfMonth);

      final list = List<Map<String, dynamic>>.from(events);
      int imp = 0, cl = 0, ld = 0;
      for (final e in list) {
        switch (e['event_type']) {
          case 'impression': imp++; break;
          case 'clic': cl++; break;
          case 'lead': ld++; break;
        }
      }

      // Historique 30 jours
      final since30 =
          now.subtract(const Duration(days: 30)).toIso8601String();
      final hist = await _supabase
          .from('marketplace_events')
          .select('event_type, created_at')
          .eq('partner_id', partner['id'])
          .gte('created_at', since30);

      final dailyMap = <String, _DayStats>{};
      for (final e in List<Map<String, dynamic>>.from(hist)) {
        final day = (e['created_at'] as String).substring(0, 10);
        dailyMap[day] ??= _DayStats(day: day);
        switch (e['event_type']) {
          case 'impression': { dailyMap[day]!.impressions++; } break;
          case 'clic': { dailyMap[day]!.clics++; } break;
          case 'lead': { dailyMap[day]!.leads++; } break;
        }
      }
      final sorted = dailyMap.values.toList()
        ..sort((a, b) => a.day.compareTo(b.day));

      if (mounted) {
        setState(() {
          _partner = partner;
          _impressions = imp;
          _clics = cl;
          _leads = ld;
          _history = sorted;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _ctr =>
      _impressions > 0 ? (_clics / _impressions * 100) : 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFA7C79A),
        elevation: 0,
        title: const Text('Ma campagne',
            style: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w500,
                color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6E9E57)))
          : _partner == null
              ? _buildNoPartner()
              : RefreshIndicator(
                  color: const Color(0xFF6E9E57),
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPartnerHeader(),
                        const SizedBox(height: 20),
                        _buildMetricsRow(),
                        const SizedBox(height: 20),
                        _buildCtrCard(),
                        const SizedBox(height: 20),
                        _buildChartCard(),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildNoPartner() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.storefront_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('Vous n\'êtes pas encore partenaire',
                style: TextStyle(fontFamily: 'Galey', fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Rejoignez notre réseau pour accéder aux statistiques.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildPartnerHeader() {
    final plan = _partner!['plan'] as String? ?? 'starter';
    final planColors = {'starter': Colors.grey, 'visible': const Color(0xFF1E88E5), 'premium': const Color(0xFF8E24AA)};
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      child: Row(
        children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(color: const Color(0xFFF0F7EC), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.storefront_outlined, color: Color(0xFF6E9E57), size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_partner!['nom'] ?? '', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: planColors[plan]!.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                      child: Text(plan.toUpperCase(),
                          style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: planColors[plan], fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _partner!['statut'] == 'actif'
                            ? const Color(0xFF6E9E57).withValues(alpha: 0.1)
                            : Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _partner!['statut'] == 'actif' ? '● Actif' : '● En attente',
                        style: TextStyle(
                          fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600,
                          color: _partner!['statut'] == 'actif' ? const Color(0xFF6E9E57) : Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsRow() {
    return Row(
      children: [
        Expanded(child: _MetricCard(label: 'Impressions', value: _impressions.toString(), icon: Icons.visibility_outlined, color: const Color(0xFF1E88E5))),
        const SizedBox(width: 10),
        Expanded(child: _MetricCard(label: 'Clics', value: _clics.toString(), icon: Icons.touch_app_outlined, color: const Color(0xFF6E9E57))),
        const SizedBox(width: 10),
        Expanded(child: _MetricCard(label: 'Leads', value: _leads.toString(), icon: Icons.person_add_outlined, color: const Color(0xFF8E24AA))),
      ],
    );
  }

  Widget _buildCtrCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatRow(label: 'CTR moyen', value: '${_ctr.toStringAsFixed(1)}%',
                sub: '(clics / impressions)'),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 40, color: Colors.grey.shade200),
          const SizedBox(width: 12),
          Expanded(
            child: _StatRow(
              label: 'Ce mois',
              value: '${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}',
              sub: '${_impressions + _clics + _leads} events total',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Évolution 30 jours',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 4),
          Row(
            children: [
              _LegendDot(color: const Color(0xFF1E88E5), label: 'Impressions'),
              const SizedBox(width: 12),
              _LegendDot(color: const Color(0xFF6E9E57), label: 'Clics'),
              const SizedBox(width: 12),
              _LegendDot(color: const Color(0xFF8E24AA), label: 'Leads'),
            ],
          ),
          const SizedBox(height: 12),
          if (_history.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('Aucune donnée sur 30 jours',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
              ),
            )
          else
            SizedBox(
              height: 140,
              child: CustomPaint(
                painter: _HistoryChartPainter(data: _history),
                size: Size.infinite,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Data ──────────────────────────────────────────────────────────────────────

class _DayStats {
  final String day;
  int impressions = 0;
  int clics = 0;
  int leads = 0;
  _DayStats({required this.day});
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _MetricCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 22, color: color)),
          Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label, value, sub;
  const _StatRow({required this.label, required this.value, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
        Text(value, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        Text(sub, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade400)),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }
}

// ── Chart painter ─────────────────────────────────────────────────────────────

class _HistoryChartPainter extends CustomPainter {
  final List<_DayStats> data;
  const _HistoryChartPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final maxVal = data
        .map((d) => max(d.impressions, max(d.clics, d.leads)))
        .reduce(max)
        .toDouble();
    if (maxVal == 0) return;

    const pad = 8.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    final n = data.length;

    void drawLine(List<int> vals, Color color) {
      final path = Path();
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      for (int i = 0; i < n; i++) {
        final x = pad + (i / (n - 1)) * w;
        final y = pad + h - (vals[i] / maxVal) * h;
        if (i == 0) path.moveTo(x, y);
        else path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }

    drawLine(data.map((d) => d.impressions).toList(), const Color(0xFF1E88E5));
    drawLine(data.map((d) => d.clics).toList(), const Color(0xFF6E9E57));
    drawLine(data.map((d) => d.leads).toList(), const Color(0xFF8E24AA));
  }

  @override
  bool shouldRepaint(_HistoryChartPainter old) => old.data != data;
}
