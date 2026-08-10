import 'package:PetsMatch/pages/pro/pension_chenil_page.dart';
import 'package:PetsMatch/pages/pro/pension_planning_page.dart';
import 'package:PetsMatch/pages/pro/pension_tarifs_page.dart';
import 'package:PetsMatch/pages/pro/pro_profile_edit.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_action_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_registry.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_theme.dart';
import 'package:flutter/material.dart';

/// Onboarding pension — docs/PetsMatch_Specs_Onboarding_Anatomie.md §7.
void registerPensionOnboarding() {
  onboardingRegistry['pension'] = _steps;
}

final List<OnboardingStepDef> _steps = [
  OnboardingStepDef(
    key: 'profil',
    label: 'Profil',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.hotel_outlined,
      color: OnboardingTheme.teal,
      title: 'Votre profil pension',
      description: 'Nom de la pension, SIRET, agrément DDPP, ACACED, espèces accueillies, '
          'capacité totale, adresse... un profil complet rassure les propriétaires qui vous confient leur animal.',
      primaryLabel: 'Compléter mon profil →',
      pageBuilder: (_) => const ProProfileEditPage(),
      onNext: onNext,
      onSkip: onSkip,
    ),
  ),
  OnboardingStepDef(
    key: 'logements',
    label: 'Logements',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.night_shelter_outlined,
      color: OnboardingTheme.green,
      title: 'Ajoutez vos logements',
      description: 'Box individuel, enclos collectif, chatterie, cage NAC, suite haut de '
          'gamme... nommez chaque espace, ses espèces acceptées et sa capacité.',
      primaryLabel: 'Ajouter un logement →',
      pageBuilder: (_) => const PensionChenilPage(),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Passer cette étape',
    ),
  ),
  OnboardingStepDef(
    key: 'planning',
    label: 'Planning',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.calendar_view_week_outlined,
      color: OnboardingTheme.teal,
      title: 'Votre planning hôtelier en temps réel',
      description: 'Chaque logement est une ligne, chaque séjour une barre colorée. Un clic '
          'sur une case libre crée une nouvelle entrée.',
      primaryLabel: 'Explorer le planning →',
      pageBuilder: (_) => const PensionPlanningPage(),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Continuer',
    ),
  ),
  OnboardingStepDef(
    key: 'tarifs',
    label: 'Tarifs',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.euro_outlined,
      color: OnboardingTheme.green,
      title: 'Vos tarifs de base',
      description: 'Par espèce et par gabarit — ces tarifs seront automatiquement proposés '
          'à la facturation de chaque séjour.',
      primaryLabel: 'Configurer mes tarifs →',
      pageBuilder: (_) => const PensionTarifsPage(),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Configurer plus tard',
    ),
  ),
];
