import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminMarketplaceTab extends StatefulWidget {
  const AdminMarketplaceTab({super.key});

  @override
  State<AdminMarketplaceTab> createState() => _AdminMarketplaceTabState();
}

class _AdminMarketplaceTabState extends State<AdminMarketplaceTab> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _partners = [];
  Map<String, _PartnerStats> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final partners = await _supabase
          .from('marketplace_partners')
          .select()
          .order('created_at', ascending: false);

      final now = DateTime.now();
      final firstOfMonth = DateTime(now.year, now.month, 1).toIso8601String();

      final events = await _supabase
          .from('marketplace_events')
          .select('partner_id, event_type')
          .gte('created_at', firstOfMonth);

      final statsMap = <String, _PartnerStats>{};
      for (final e in List<Map<String, dynamic>>.from(events)) {
        final pid = e['partner_id'] as String?;
        if (pid == null) continue;
        statsMap[pid] ??= _PartnerStats();
        switch (e['event_type']) {
          case 'impression': { statsMap[pid]!.impressions++; } break;
          case 'clic':       { statsMap[pid]!.clics++; }       break;
          case 'lead':       { statsMap[pid]!.leads++; }       break;
        }
      }

      if (mounted) {
        setState(() {
          _partners = List<Map<String, dynamic>>.from(partners);
          _stats = statsMap;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateStatut(String id, String statut) async {
    await _supabase
        .from('marketplace_partners')
        .update({'statut': statut})
        .eq('id', id);
    _load();
  }

  int get _totalImpressions =>
      _stats.values.fold(0, (s, p) => s + p.impressions);
  int get _totalClics =>
      _stats.values.fold(0, (s, p) => s + p.clics);
  int get _totalLeads =>
      _stats.values.fold(0, (s, p) => s + p.leads);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF6E9E57)));
    }

    return RefreshIndicator(
      color: const Color(0xFF6E9E57),
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Totaux globaux
            const Text('Vue globale — ce mois',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _GlobalCard(label: 'Impressions', value: _totalImpressions, color: const Color(0xFF1E88E5))),
                const SizedBox(width: 10),
                Expanded(child: _GlobalCard(label: 'Clics', value: _totalClics, color: const Color(0xFF6E9E57))),
                const SizedBox(width: 10),
                Expanded(child: _GlobalCard(label: 'Leads', value: _totalLeads, color: const Color(0xFF8E24AA))),
              ],
            ),
            const SizedBox(height: 24),

            // Liste partenaires
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Partenaires',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
                Text('${_partners.length} total',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 10),

            if (_partners.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text('Aucun partenaire',
                      style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)),
                ),
              )
            else
              ...List.generate(_partners.length, (i) {
                final p = _partners[i];
                final s = _stats[p['id']] ?? _PartnerStats();
                return _PartnerRow(
                  partner: p,
                  stats: s,
                  onActivate: () => _updateStatut(p['id'], 'actif'),
                  onSuspend: () => _updateStatut(p['id'], 'suspendu'),
                );
              }),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ── Data ──────────────────────────────────────────────────────────────────────

class _PartnerStats {
  int impressions = 0;
  int clics = 0;
  int leads = 0;
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _GlobalCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _GlobalCard({required this.label, required this.value, required this.color});

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
          Text(value.toString(),
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 22, color: color)),
          Text(label,
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _PartnerRow extends StatelessWidget {
  final Map<String, dynamic> partner;
  final _PartnerStats stats;
  final VoidCallback onActivate;
  final VoidCallback onSuspend;
  const _PartnerRow({required this.partner, required this.stats, required this.onActivate, required this.onSuspend});

  @override
  Widget build(BuildContext context) {
    final statut = partner['statut'] as String? ?? 'en_attente';
    final statutColor = statut == 'actif'
        ? const Color(0xFF6E9E57)
        : statut == 'suspendu'
            ? Colors.red
            : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(partner['nom'] ?? '',
                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                    Text(partner['categorie'] ?? '',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statutColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(statut,
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: statutColor, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatChip(label: '👁 ${stats.impressions}', color: const Color(0xFF1E88E5)),
              const SizedBox(width: 6),
              _StatChip(label: '👆 ${stats.clics}', color: const Color(0xFF6E9E57)),
              const SizedBox(width: 6),
              _StatChip(label: '👤 ${stats.leads}', color: const Color(0xFF8E24AA)),
              const Spacer(),
              if (statut != 'actif')
                TextButton(
                  onPressed: onActivate,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6E9E57),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Activer', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700)),
                )
              else
                TextButton(
                  onPressed: onSuspend,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Suspendre', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
