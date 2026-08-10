import 'package:PetsMatch/pages/onboarding/onboarding_theme.dart';
import 'package:flutter/material.dart';

/// Étape 0 — écran de bienvenue, identique pour tous les profils
/// (docs/PetsMatch_Specs_Onboarding_Anatomie.md §2).
class OnboardingWelcomePage extends StatelessWidget {
  final String firstName;
  final VoidCallback onStart;
  final VoidCallback onSkip;

  const OnboardingWelcomePage({
    super.key,
    required this.firstName,
    required this.onStart,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final name = firstName.isNotEmpty && firstName != 'none' ? firstName : '';
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
                child: const Icon(Icons.pets, size: 56, color: OnboardingTheme.green),
              ),
              const SizedBox(height: 32),
              Text(
                name.isNotEmpty ? 'Bienvenue sur PetsMatch, $name !' : 'Bienvenue sur PetsMatch !',
                textAlign: TextAlign.center,
                style: OnboardingTheme.title,
              ),
              const SizedBox(height: 16),
              const Text(
                'Votre essai gratuit de 30 jours commence aujourd\'hui.\n'
                'Accès complet à toutes les fonctionnalités — aucune CB requise.',
                textAlign: TextAlign.center,
                style: OnboardingTheme.body,
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: OnboardingTheme.primaryButton(),
                  onPressed: onStart,
                  child: const Text('Commencer la configuration →'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: onSkip,
                child: const Text('Passer pour l\'instant', style: OnboardingTheme.skipButtonStyle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
