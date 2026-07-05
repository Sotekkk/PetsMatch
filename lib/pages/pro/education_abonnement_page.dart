import 'package:PetsMatch/services/plan_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class EducationAbonnementPage extends StatefulWidget {
  const EducationAbonnementPage({super.key});

  @override
  State<EducationAbonnementPage> createState() => _EducationAbonnementPageState();
}

class _EducationAbonnementPageState extends State<EducationAbonnementPage> {
  static const _purple = Color(0xFF7B5EA7);
  static const _bg     = Color(0xFFF8F8F6);

  String _planCode = 'free';
  Map<String, EducationPlanConfig> _plans = PlanService.educationConfigs;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    final results = await Future.wait([
      PlanService.getEducationPlanCode(uid),
      PlanService.getEducationPlansLive(),
    ]);
    if (!mounted) return;
    setState(() {
      _planCode = results[0] as String;
      _plans    = results[1] as Map<String, EducationPlanConfig>;
      _loading  = false;
    });
  }

  Future<void> _openWebsite([String path = '/education/abonnement']) async {
    final uri = Uri.parse('${PlanService.kWebsiteUrl}$path');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d\'ouvrir le navigateur',
              style: TextStyle(fontFamily: 'Galey'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _plans[_planCode] ?? PlanService.getEducationConfig(_planCode);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        title: const Text('Mon abonnement',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _purple))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7B5EA7), Color(0xFFAB94C9)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Formule ${config.label}',
                          style: const TextStyle(
                              color: Colors.white, fontFamily: 'Galey',
                              fontWeight: FontWeight.w700, fontSize: 20)),
                      const SizedBox(height: 8),
                      Text(_summaryLine(config),
                          style: const TextStyle(color: Colors.white70, fontFamily: 'Galey', fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Changer de formule',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 17, color: Color(0xFF1F2A2E))),
                const SizedBox(height: 12),
                for (final code in ['free', 'pro', 'premium']) ...[
                  _EducationPlanCard(
                    config: _plans[code] ?? PlanService.getEducationConfig(code),
                    isCurrent: _planCode == code,
                    onSelect: _planCode == code ? null : () => _openWebsite('/education/abonnement'),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => _openWebsite('/education/abonnement'),
                  child: const Text('Gérer mon abonnement sur le site →',
                      style: TextStyle(fontFamily: 'Galey', color: _purple)),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  String _summaryLine(EducationPlanConfig c) {
    final parts = <String>[
      c.hasEmployes ? (c.maxEmployes == -1 ? 'Employés illimités' : '${c.maxEmployes} employés') : 'Sans employés',
      if (c.hasFactureExport) 'Export factures',
      if (c.hasBadgePremium) 'Badge premium',
    ];
    return parts.join(' · ');
  }
}

class _EducationPlanCard extends StatelessWidget {
  final EducationPlanConfig config;
  final bool isCurrent;
  final VoidCallback? onSelect;

  const _EducationPlanCard({required this.config, required this.isCurrent, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF7B5EA7);
    final accent = config.code == 'premium'
        ? const Color(0xFFD97706)
        : config.code == 'pro' ? purple : const Color(0xFF6B7280);
    final badge = config.code == 'premium' ? '👑' : config.code == 'pro' ? '⚡' : '🌱';

    final features = <String?>[
      'Planning + cours individuels/collectifs',
      'Tarification & suivi de progression',
      'Réservation en ligne',
      config.hasEmployes ? (config.maxEmployes == -1 ? 'Employés illimités' : 'Jusqu\'à ${config.maxEmployes} employés') : null,
      config.hasFactureExport ? 'Export factures' : null,
      config.hasBadgePremium ? 'Badge premium + mise en avant' : null,
      config.hasAccesPrioritaire ? 'Accès prioritaire support' : null,
    ].whereType<String>().toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isCurrent ? accent : Colors.grey.shade100,
            width: isCurrent ? 2 : 1),
        boxShadow: isCurrent
            ? [BoxShadow(color: accent.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 3))]
            : [],
      ),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(badge, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Row(children: [
                  Text(config.label,
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                          fontSize: 15, color: accent)),
                  if (isCurrent) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('Actuel', style: TextStyle(fontFamily: 'Galey',
                          fontSize: 10, color: accent, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
              ),
              if (config.prixMensuel > 0)
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${config.prixMensuel.toStringAsFixed(0)} €/mois',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                          fontSize: 13, color: Color(0xFF1F2A2E))),
                  Text('ou ${config.prixAnnuel.toStringAsFixed(0)} €/an',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey.shade400)),
                ])
              else
                const Text('Gratuit', style: TextStyle(fontFamily: 'Galey',
                    fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF6B7280))),
            ]),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: features.map((f) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F4),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(f, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade700)),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
