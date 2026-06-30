import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingAssoPage extends StatefulWidget {
  const OnboardingAssoPage({super.key});

  @override
  State<OnboardingAssoPage> createState() => _OnboardingAssoPageState();
}

class _OnboardingAssoPageState extends State<OnboardingAssoPage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _dark  = Color(0xFF1F2A2E);

  final _ctrl = PageController();
  int _page = 0;

  static const _slides = [
    _Slide(
      icon: Icons.favorite_outlined,
      color: _teal,
      title: 'Bienvenue dans votre espace association',
      desc: 'Gérez votre refuge ou association depuis un seul endroit : animaux, adoptions, équipe, planning et documents.',
    ),
    _Slide(
      icon: Icons.pets,
      color: _green,
      title: 'Vos animaux au refuge',
      desc: 'Créez la fiche de chaque animal, suivez son carnet de santé et publiez des annonces d\'adoption.',
    ),
    _Slide(
      icon: Icons.people_outline,
      color: _teal,
      title: 'Gérez votre équipe',
      desc: 'Ajoutez bénévoles et employés, définissez leurs permissions et coordonnez les activités du refuge.',
    ),
    _Slide(
      icon: Icons.home_work_outlined,
      color: _green,
      title: 'Familles d\'accueil',
      desc: 'Trouvez et gérez des familles d\'accueil pour vos animaux en attente d\'adoption.',
    ),
    _Slide(
      icon: Icons.campaign_outlined,
      color: _teal,
      title: 'Publiez vos annonces',
      desc: 'Vos annonces d\'adoption sont visibles par des milliers d\'utilisateurs PetsMatch.',
    ),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_asso_done', true);
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
                child: const Text('Passer', style: TextStyle(color: _teal, fontWeight: FontWeight.w500)),
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
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade600, height: 1.6),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: _page == i ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: _page == i ? _teal : Colors.grey.shade300,
                ),
              )),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    if (isLast) {
                      _finish();
                    } else {
                      _ctrl.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
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
