import 'package:PetsMatch/pages/onboarding/onboarding_theme.dart';
import 'package:flutter/material.dart';

/// Raccourci affiché sur l'écran "Découvrez aussi" (après l'écran de fin) —
/// pas de progression suivie, un simple accès direct au module.
class OnboardingDiscoveryItem {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final WidgetBuilder pageBuilder;

  const OnboardingDiscoveryItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.pageBuilder,
  });
}

/// Écran optionnel après la fin du parcours principal : met en avant les
/// fonctionnalités clés du profil qui n'ont pas leur propre étape numérotée.
class OnboardingDiscoveryPage extends StatelessWidget {
  final List<OnboardingDiscoveryItem> items;
  final VoidCallback onFinish;

  const OnboardingDiscoveryPage({super.key, required this.items, required this.onFinish});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OnboardingTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Découvrez aussi', style: OnboardingTheme.title),
                  const SizedBox(height: 8),
                  Text(
                    'Ces modules vous attendent quand vous serez prêt.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _DiscoveryTile(item: items[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: OnboardingTheme.primaryButton(color: OnboardingTheme.green),
                  onPressed: onFinish,
                  child: const Text('Accéder à mon tableau de bord →'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveryTile extends StatelessWidget {
  final OnboardingDiscoveryItem item;
  const _DiscoveryTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: item.pageBuilder)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: item.color.withAlpha(26), shape: BoxShape.circle),
              child: Icon(item.icon, color: item.color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: const TextStyle(
                          fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: OnboardingTheme.dark)),
                  const SizedBox(height: 2),
                  Text(item.subtitle,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
