import 'package:PetsMatch/pages/pro/pro_clients_page.dart';
import 'package:PetsMatch/pages/pro/pro_profile_edit.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_action_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_registry.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_theme.dart';
import 'package:flutter/material.dart';

/// Onboarding ostéopathe / para-médical (santé) —
/// docs/PetsMatch_Specs_Onboarding_Anatomie.md §10.
void registerSanteOnboarding() {
  onboardingRegistry['sante'] = _steps;
}

final List<OnboardingStepDef> _steps = [
  OnboardingStepDef(
    key: 'profil',
    label: 'Profil',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.self_improvement_outlined,
      color: OnboardingTheme.teal,
      title: 'Votre profil para-médical',
      description: 'Spécialité (ostéopathe, kinésithérapeute, acupuncteur...), SIRET, '
          'diplôme, ACACED, espèces traitées, zone d\'intervention... un profil complet inspire confiance.',
      primaryLabel: 'Compléter mon profil →',
      pageBuilder: (_) => const ProProfileEditPage(),
      onNext: onNext,
      onSkip: onSkip,
    ),
  ),
  OnboardingStepDef(
    key: 'seances',
    label: 'Séances',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.checklist_outlined,
      color: OnboardingTheme.green,
      title: 'Vos séances',
      description: 'Consultation initiale (bilan), séance de suivi, à domicile ou en cabinet '
          '— indiquez une durée et un tarif pour chacune, elles serviront à calculer vos créneaux disponibles.',
      primaryLabel: 'Configurer mes séances →',
      pageBuilder: (_) => const ProProfileEditPage(),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Plus tard',
    ),
  ),
  OnboardingStepDef(
    key: 'anatomie',
    label: 'Anatomie',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.accessibility_new_outlined,
      color: OnboardingTheme.teal,
      title: 'Un outil conçu pour votre pratique',
      description: 'PetsMatch intègre une vue anatomique interactive : sélectionnez une zone '
          'sur le schéma, annotez vos observations, l\'annotation est enregistrée dans la fiche patient. '
          'Ouvrez la fiche d\'un patient puis l\'onglet Anatomie pour l\'essayer.',
      primaryLabel: 'Voir mes patients →',
      pageBuilder: (_) => const ProClientsPage(),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Plus tard',
    ),
  ),
  OnboardingStepDef(
    key: 'acces_patients',
    label: 'Patients',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.folder_shared_outlined,
      color: OnboardingTheme.green,
      title: 'Demandez l\'accès aux fiches de vos patients',
      description: 'Vos clients peuvent partager le carnet santé de leur animal avec vous. '
          'Une fois l\'accès accordé, vous le consultez en lecture et pouvez y ajouter des soins.',
      primaryLabel: 'Voir mes patients →',
      pageBuilder: (_) => const ProClientsPage(),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Compris',
    ),
  ),
];
