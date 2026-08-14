import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:PetsMatch/pages/pro/pro_profile_edit.dart';
import 'package:PetsMatch/pages/pro/toilettage_prestations_page.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_action_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_registry.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_theme.dart';
import 'package:flutter/material.dart';

/// Onboarding toiletteur — docs/PetsMatch_Specs_Onboarding_Anatomie.md §11.
void registerToilettageOnboarding() {
  onboardingRegistry['toilettage'] = _steps;
}

final List<OnboardingStepDef> _steps = [
  OnboardingStepDef(
    key: 'profil',
    label: 'Profil',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.content_cut_outlined,
      color: OnboardingTheme.teal,
      title: 'Votre profil toilettage',
      description: 'Nom du salon, SIRET, certifications (BTM Toiletteur...), adresse, '
          'service à domicile ou non, races travaillées... un profil complet inspire confiance.',
      primaryLabel: 'Compléter mon profil →',
      pageBuilder: (_) => ProProfileEditPage(secondaryProfileId: profileId),
      onNext: onNext,
      onSkip: onSkip,
    ),
  ),
  OnboardingStepDef(
    key: 'prestations',
    label: 'Prestations',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.checklist_outlined,
      color: OnboardingTheme.green,
      title: 'Vos prestations et tarifs',
      description: 'Bain + séchage + brossage, coupe + toilettage complet, coupe seule, '
          'stripping, épilation... tarifez par taille ou par race.',
      primaryLabel: 'Configurer mes prestations →',
      pageBuilder: (_) => const ToilettagePrestationsPage(),
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
      description: 'Cochez vos jours et horaires habituels — vous pourrez toujours affiner '
          'plus tard depuis votre profil.',
      primaryLabel: 'Renseigner mes disponibilités →',
      pageBuilder: (_) => ProProfileEditPage(secondaryProfileId: profileId),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Plus tard',
    ),
  ),
  OnboardingStepDef(
    key: 'agenda',
    label: 'Agenda',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.calendar_month_outlined,
      color: OnboardingTheme.green,
      title: 'Votre agenda est prêt',
      description: 'Les clients peuvent prendre RDV directement depuis votre profil PetsMatch.',
      primaryLabel: 'Voir mon agenda →',
      pageBuilder: (_) => const ProAgendaPage(),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'C\'est parti',
    ),
  ),
];
