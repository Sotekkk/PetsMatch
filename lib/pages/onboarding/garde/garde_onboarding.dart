import 'package:PetsMatch/pages/pro/pro_profile_edit.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_action_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_registry.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_theme.dart';
import 'package:flutter/material.dart';

/// Onboarding garde (pet sitter / promeneur) —
/// docs/PetsMatch_Specs_Onboarding_Anatomie.md §8.
///
/// Une seule étape : profil, zone, services et disponibilités vivent tous
/// dans la même page (ProProfileEditPage — la zone s'y ouvre en sous-écran).
/// Les séparer en plusieurs étapes obligeait à rouvrir/re-sauvegarder cette
/// même page plusieurs fois — et, depuis que l'ACACED y est obligatoire,
/// bloquait chaque étape suivante tant qu'il n'était pas renseigné.
void registerGardeOnboarding() {
  onboardingRegistry['garde'] = _steps;
}

final List<OnboardingStepDef> _steps = [
  OnboardingStepDef(
    key: 'profil',
    label: 'Profil',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.pets_outlined,
      color: OnboardingTheme.teal,
      title: 'Votre profil garde',
      description: 'Pet sitter, promeneur ou les deux, SIRET ou statut, ACACED, zone '
          'd\'intervention, services et tarifs, disponibilités... tout se configure sur '
          'une seule page.',
      primaryLabel: 'Compléter mon profil →',
      pageBuilder: (_) => ProProfileEditPage(secondaryProfileId: profileId),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Plus tard',
    ),
  ),
];
