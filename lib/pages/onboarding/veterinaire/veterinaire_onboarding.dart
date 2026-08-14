import 'package:PetsMatch/pages/pro/pro_profile_edit.dart';
import 'package:PetsMatch/pages/pro/pro_zone_page.dart';
import 'package:PetsMatch/pages/pro/vet_patients_page.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_action_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_registry.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_theme.dart';
import 'package:flutter/material.dart';

/// Onboarding vétérinaire — docs/PetsMatch_Specs_Onboarding_Anatomie.md §6.
void registerVeterinaireOnboarding() {
  onboardingRegistry['veterinaire'] = _steps;
}

final List<OnboardingStepDef> _steps = [
  OnboardingStepDef(
    key: 'profil',
    label: 'Profil',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.local_hospital_outlined,
      color: OnboardingTheme.teal,
      title: 'Votre profil professionnel',
      description: 'Raison sociale, n° Ordre des Vétérinaires, SIRET, adresse du cabinet, '
          'spécialités, espèces traitées... un profil complet vous rend visible auprès des '
          'propriétaires à proximité.',
      primaryLabel: 'Compléter mon profil →',
      pageBuilder: (_) => ProProfileEditPage(secondaryProfileId: profileId),
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
    key: 'disponibilites',
    label: 'Créneaux',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.schedule_outlined,
      color: OnboardingTheme.teal,
      title: 'Vos créneaux de disponibilité',
      description: 'Cochez vos jours et horaires habituels — vous pourrez toujours affiner '
          'plus tard depuis votre profil.',
      primaryLabel: 'Renseigner mes horaires →',
      pageBuilder: (_) => ProProfileEditPage(secondaryProfileId: profileId),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Plus tard',
    ),
  ),
  OnboardingStepDef(
    key: 'carnet_sante',
    label: 'Carnet santé',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.folder_shared_outlined,
      color: OnboardingTheme.green,
      title: 'Demandez l\'accès aux fiches de vos patients',
      description: 'Vos clients peuvent partager le carnet santé de leur animal avec vous. '
          'Une fois l\'accès accordé, vous le consultez en lecture et pouvez y ajouter des soins.',
      primaryLabel: 'Voir mes patients →',
      pageBuilder: (_) => const VetPatientsPage(),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Compris',
    ),
  ),
];
