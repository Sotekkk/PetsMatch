import 'package:PetsMatch/pages/onboarding/onboarding_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Écran de fin, identique pour tous les profils
/// (docs/PetsMatch_Specs_Onboarding_Anatomie.md §2). [achievements] liste ce
/// que l'utilisateur a accompli pendant le parcours (libellés des étapes
/// complétées, fournis par le flow).
class OnboardingCompletePage extends StatelessWidget {
  final List<String> achievements;
  final VoidCallback onFinish;

  const OnboardingCompletePage({
    super.key,
    required this.achievements,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final trialEnd = DateFormat('d MMMM yyyy', 'fr_FR').format(DateTime.now().add(const Duration(days: 30)));
    return Scaffold(
      backgroundColor: OnboardingTheme.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(color: Color(0x1A6E9E57), shape: BoxShape.circle),
                child: const Icon(Icons.check_circle, size: 56, color: OnboardingTheme.green),
              ),
              const SizedBox(height: 32),
              const Text('Votre espace est prêt !', textAlign: TextAlign.center, style: OnboardingTheme.title),
              const SizedBox(height: 20),
              Text('Vous avez créé :',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _AchievementLine('1 profil vérifié'),
                    for (final a in achievements) _AchievementLine(a),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('Votre essai se termine le $trialEnd.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: OnboardingTheme.primaryButton(color: OnboardingTheme.green),
                  onPressed: onFinish,
                  child: const Text('Accéder à mon tableau de bord →'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AchievementLine extends StatelessWidget {
  final String text;
  const _AchievementLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.circle, size: 6, color: OnboardingTheme.teal),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: OnboardingTheme.dark)),
          ),
        ],
      ),
    );
  }
}
