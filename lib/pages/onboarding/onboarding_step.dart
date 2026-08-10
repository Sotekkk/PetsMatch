import 'package:flutter/material.dart';

/// Contenu d'une étape métier. [onNext] valide l'étape (donnée créée ou action
/// effectuée) et avance ; [onSkip] passe cette étape précise sans bloquer la
/// suite du parcours — les deux font progresser le flow, seul le bouton
/// "Passer" global (OnboardingStepScaffold) abandonne tout l'onboarding.
typedef OnboardingStepBuilder = Widget Function(
  BuildContext context, {
  required String profileId,
  required VoidCallback onNext,
  required VoidCallback onSkip,
});

class OnboardingStepDef {
  final String key;
  final String label;
  final OnboardingStepBuilder builder;

  const OnboardingStepDef({required this.key, required this.label, required this.builder});
}
