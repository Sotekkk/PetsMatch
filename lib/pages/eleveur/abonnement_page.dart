import 'package:PetsMatch/services/plan_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AbonnementPage extends StatefulWidget {
  const AbonnementPage({super.key});

  @override
  State<AbonnementPage> createState() => _AbonnementPageState();
}

class _AbonnementPageState extends State<AbonnementPage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _bg    = Color(0xFFF8F8F6);

  String _planCode = 'free';
  int _activeCount = 0;
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
      PlanService.getPlanCode(uid),
      PlanService.countActiveAnnonces(uid),
    ]);
    if (!mounted) return;
    setState(() {
      _planCode    = results[0] as String;
      _activeCount = results[1] as int;
      _loading     = false;
    });
  }

  Future<void> _openWebsite([String path = '/abonnement']) async {
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
    final config = PlanService.getConfig(_planCode);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Mon abonnement',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0C5C6C)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Plan actuel ──────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0C5C6C), Color(0xFF5F9EAA)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${config.badge} Plan ${config.label}',
                          style: const TextStyle(
                              color: Colors.white, fontFamily: 'Galey',
                              fontWeight: FontWeight.w700, fontSize: 20)),
                      const SizedBox(height: 8),
                      if (config.maxAnnonces != -1) ...[
                        Text('$_activeCount / ${config.maxAnnonces} annonces actives',
                            style: const TextStyle(color: Colors.white70, fontFamily: 'Galey', fontSize: 13)),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (_activeCount / config.maxAnnonces).clamp(0.0, 1.0),
                            backgroundColor: Colors.white24,
                            color: _activeCount >= config.maxAnnonces ? Colors.red.shade300 : _green,
                            minHeight: 6,
                          ),
                        ),
                      ] else
                        const Text('Annonces illimitées',
                            style: TextStyle(color: Colors.white70, fontFamily: 'Galey', fontSize: 13)),
                      const SizedBox(height: 4),
                      Text('Durée annonce : ${config.dureeDays} jours · Registres : ${config.hasRegistres ? "✓" : "—"}',
                          style: const TextStyle(color: Colors.white60, fontFamily: 'Galey', fontSize: 12)),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                const Text('Changer de plan',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 17, color: Color(0xFF1F2A2E))),
                const SizedBox(height: 12),

                // ── Cartes plans ────────────────────────────────────────────
                _PlanCard(
                  config: PlanService.configs['free']!,
                  isCurrent: _planCode == 'free',
                  onSelect: null,
                ),
                const SizedBox(height: 10),
                _PlanCard(
                  config: PlanService.configs['pro']!,
                  isCurrent: _planCode == 'pro',
                  onSelect: _planCode == 'pro' ? null : () => _openWebsite('/abonnement'),
                ),
                const SizedBox(height: 10),
                _PlanCard(
                  config: PlanService.configs['premium']!,
                  isCurrent: _planCode == 'premium',
                  onSelect: _planCode == 'premium' ? null : () => _openWebsite('/abonnement'),
                ),

                const SizedBox(height: 20),

                // ── Achats ponctuels ────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Achats ponctuels',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                              fontSize: 15, color: Color(0xFF1F2A2E))),
                      const SizedBox(height: 12),
                      _PonctuelTile(
                        icon: Icons.add_circle_outline,
                        label: 'Annonce supplémentaire',
                        prix: '2,99 €',
                        onTap: () => _openWebsite('/abonnement?buy=annonce_sup'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => _openWebsite('/abonnement'),
                  child: const Text('Gérer mon abonnement sur le site →',
                      style: TextStyle(fontFamily: 'Galey', color: Color(0xFF0C5C6C))),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final PlanConfig config;
  final bool isCurrent;
  final VoidCallback? onSelect;

  const _PlanCard({required this.config, required this.isCurrent, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final teal = const Color(0xFF0C5C6C);
    final green = const Color(0xFF6E9E57);
    final accent = config.code == 'premium'
        ? const Color(0xFFD97706)
        : config.code == 'pro' ? teal : const Color(0xFF6B7280);

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
      child: Row(
        children: [
          Text(config.badge, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
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
                const SizedBox(height: 2),
                Text(
                  config.maxAnnonces == -1
                      ? 'Illimitées · ${config.dureeDays}j · Registres'
                      : '${config.maxAnnonces} annonces · ${config.dureeDays}j'
                          '${config.hasRegistres ? ' · Registres' : ''}',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
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
        ],
      ),
    ).withTap(onSelect == null ? null : () {
      if (onSelect != null) onSelect!();
    });
  }
}

class _PonctuelTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String prix;
  final VoidCallback onTap;

  const _PonctuelTile({required this.icon, required this.label, required this.prix, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(icon, color: const Color(0xFF6E9E57), size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(label,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1F2A2E)))),
          Text(prix,
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                  fontSize: 14, color: Color(0xFF0C5C6C))),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 16, color: Color(0xFF5F9EAA)),
        ]),
      ),
    );
  }
}

extension _TapWrapper on Widget {
  Widget withTap(VoidCallback? onTap) {
    if (onTap == null) return this;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: this,
    );
  }
}
