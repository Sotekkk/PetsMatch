import 'package:PetsMatch/pages/pro/pro_profile_edit.dart';
import 'package:PetsMatch/pages/pro/pro_zone_page.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_action_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_registry.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_theme.dart';
import 'package:flutter/material.dart';

/// Onboarding garde (pet sitter / promeneur) —
/// docs/PetsMatch_Specs_Onboarding_Anatomie.md §8.
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
      description: 'Pet sitter, promeneur ou les deux, SIRET ou statut, ACACED, espèces '
          'gardées, adresse... un profil complet inspire confiance aux propriétaires.',
      primaryLabel: 'Compléter mon profil →',
      pageBuilder: (_) => const ProProfileEditPage(),
      onNext: onNext,
      onSkip: onSkip,
    ),
  ),
  OnboardingStepDef(
    key: 'zone',
    label: 'Zone',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.location_on_outlined,
      color: OnboardingTheme.green,
      title: 'Définissez votre zone d\'intervention',
      description: 'Glissez le curseur pour ajuster le rayon autour de votre adresse. Les '
          'propriétaires dans ce rayon verront votre profil en priorité.',
      primaryLabel: 'Configurer ma zone →',
      pageBuilder: (_) => const ProZonePage(),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Plus tard',
    ),
  ),
  OnboardingStepDef(
    key: 'services',
    label: 'Services',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.checklist_outlined,
      color: OnboardingTheme.teal,
      title: 'Vos services et tarifs',
      description: 'Garde à domicile, garde chez vous, promenade individuelle ou en groupe, '
          'visite quotidienne, garde de nuit... activez vos services et indiquez un tarif de base pour chacun.',
      primaryLabel: 'Configurer mes services →',
      pageBuilder: (_) => const ProProfileEditPage(),
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
      color: OnboardingTheme.green,
      title: 'Vos disponibilités',
      description: 'Cochez vos jours et horaires habituels, avec l\'option jours fériés si '
          'vous êtes disponible — vous pourrez toujours affiner plus tard.',
      primaryLabel: 'Renseigner mes disponibilités →',
      pageBuilder: (_) => const ProProfileEditPage(),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Plus tard',
    ),
  ),
];
