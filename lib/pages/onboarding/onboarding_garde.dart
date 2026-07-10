import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingGardePage extends StatefulWidget {
  const OnboardingGardePage({super.key});

  static const prefKey = 'onboarding_garde_done';

  @override
  State<OnboardingGardePage> createState() => _OnboardingGardePageState();
}

class _OnboardingGardePageState extends State<OnboardingGardePage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _dark  = Color(0xFF1F2A2E);

  final _ctrl = PageController();
  int _page = 0;

  static const _slides = [
    _Slide(
      icon: Icons.directions_walk_outlined,
      color: _teal,
      title: 'Bienvenue dans votre espace pet sitter',
      desc: 'Gérez vos visites et promenades, suivez vos clients et organisez votre activité en quelques clics.',
    ),
    _Slide(
      icon: Icons.checklist_outlined,
      color: _green,
      title: 'Registre visites & rapports',
      desc: 'Marquez vos visites terminées et envoyez un compte rendu (avec photo) aux propriétaires après chaque passage.',
    ),
    _Slide(
      icon: Icons.request_quote_outlined,
      color: _teal,
      title: 'Devis, contrats & tarifs',
      desc: 'Envoyez des devis et contrats de prestation en ligne, avec des tarifs personnalisables par client.',
    ),
    _Slide(
      icon: Icons.storefront_outlined,
      color: _green,
      title: 'Visible par les propriétaires',
      desc: 'Votre profil est référencé sur PetsMatch. Les propriétaires peuvent vous trouver et vous contacter directement.',
    ),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingGardePage.prefKey, true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _slides.length - 1;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Passer',
                    style: TextStyle(color: _teal, fontWeight: FontWeight.w500)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) {
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: s.color.withAlpha(26),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(s.icon, size: 56, color: s.color),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          s.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _dark,
                            fontFamily: 'Galey',
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          s.desc,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 15, color: Colors.grey.shade600, height: 1.6),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _page == i ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: _page == i ? _teal : Colors.grey.shade300,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: isLast
                      ? _finish
                      : () => _ctrl.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isLast ? _green : _teal,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: Text(
                    isLast ? 'Commencer !' : 'Suivant',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 36),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  final IconData icon;
  final Color color;
  final String title;
  final String desc;
  const _Slide({required this.icon, required this.color, required this.title, required this.desc});
}
