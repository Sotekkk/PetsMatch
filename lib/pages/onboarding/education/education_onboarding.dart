import 'package:PetsMatch/pages/pro/education_devis_page.dart';
import 'package:PetsMatch/pages/pro/pro_profile_edit.dart';
import 'package:PetsMatch/pages/pro/pro_zone_page.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_action_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_registry.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_theme.dart';
import 'package:flutter/material.dart';

/// Onboarding éducateur / comportementaliste —
/// docs/PetsMatch_Specs_Onboarding_Anatomie.md §9.
void registerEducationOnboarding() {
  onboardingRegistry['education'] = _steps;
}

final List<OnboardingStepDef> _steps = [
  OnboardingStepDef(
    key: 'profil',
    label: 'Profil',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.school_outlined,
      color: OnboardingTheme.teal,
      title: 'Votre profil éducateur',
      description: 'SIRET, ACACED, certifications (CCPCC, CNECAD...), méthodes pratiquées, '
          'espèces travaillées, adresse... un profil complet inspire confiance aux propriétaires.',
      primaryLabel: 'Compléter mon profil →',
      pageBuilder: (_) => const ProProfileEditPage(),
      onNext: onNext,
      onSkip: onSkip,
    ),
  ),
  OnboardingStepDef(
    key: 'services',
    label: 'Services',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.checklist_outlined,
      color: OnboardingTheme.green,
      title: 'Vos types de séances',
      description: 'Cours individuel, cours collectif, bilan comportemental, stage intensif, '
          'suivi à distance... activez vos prestations et indiquez un tarif de base pour chacune.',
      primaryLabel: 'Configurer mes services →',
      pageBuilder: (_) => const ProProfileEditPage(),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Plus tard',
    ),
  ),
  OnboardingStepDef(
    key: 'zone',
    label: 'Zone',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.location_on_outlined,
      color: OnboardingTheme.teal,
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
    key: 'devis',
    label: 'Devis',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.receipt_long_outlined,
      color: OnboardingTheme.green,
      title: 'Envoyez un devis en moins de 2 minutes',
      description: 'Sélectionnez un service, choisissez un client — le devis est pré-rempli '
          'et envoyé par email.',
      primaryLabel: 'Créer un devis de démonstration →',
      pageBuilder: (_) => const DevisPage(),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Continuer',
    ),
  ),
];
