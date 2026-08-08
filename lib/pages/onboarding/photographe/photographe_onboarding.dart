import 'package:PetsMatch/pages/pro/photographe_prestations_page.dart';
import 'package:PetsMatch/pages/pro/pro_profile_edit.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_action_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_registry.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_theme.dart';
import 'package:flutter/material.dart';

/// Onboarding photographe — docs/PetsMatch_Specs_Onboarding_Anatomie.md §12.
/// Le plus court des parcours pro (3 étapes, 3-4 min).
void registerPhotographeOnboarding() {
  onboardingRegistry['photographe'] = _steps;
}

final List<OnboardingStepDef> _steps = [
  OnboardingStepDef(
    key: 'profil',
    label: 'Profil',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.camera_alt_outlined,
      color: OnboardingTheme.teal,
      title: 'Votre profil et votre portfolio',
      description: 'Nom du studio, SIRET, zone d\'intervention, espèces photographiées, '
          'style... et au moins 5 photos de portfolio, le minimum pour apparaître dans les recherches.',
      primaryLabel: 'Compléter mon profil →',
      pageBuilder: (_) => const ProProfileEditPage(),
      onNext: onNext,
      onSkip: onSkip,
    ),
  ),
  OnboardingStepDef(
    key: 'tarifs',
    label: 'Tarifs',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.photo_library_outlined,
      color: OnboardingTheme.green,
      title: 'Vos tarifs et formules',
      description: 'Séance 1h, séance 2h, reportage, shooting en studio... indiquez un prix '
          'et un nombre de photos livrées pour chaque formule.',
      primaryLabel: 'Configurer mes formules →',
      pageBuilder: (_) => const PhotographePrestationsPage(),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Plus tard',
    ),
  ),
  OnboardingStepDef(
    key: 'disponibilites',
    label: 'Dispos',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.schedule_outlined,
      color: OnboardingTheme.teal,
      title: 'Vos disponibilités',
      description: 'Cochez vos jours et horaires habituels — les clients pourront vous '
          'contacter directement depuis votre profil PetsMatch.',
      primaryLabel: 'Renseigner mes disponibilités →',
      pageBuilder: (_) => const ProProfileEditPage(),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'C\'est parti',
    ),
  ),
];
