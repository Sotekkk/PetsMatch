import 'package:PetsMatch/pages/eleveur/admin/certificats_engagement_page.dart';
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/pages/eleveur/employes/employes_page.dart';
import 'package:PetsMatch/pages/eleveur/planning/plan_template_form_page.dart';
import 'package:PetsMatch/pages/eleveur/post/create_annonce_page.dart';
import 'package:PetsMatch/pages/eleveur/profil_eleveur_edit.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_entree_sortie.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_sanitaire.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_action_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_discovery.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_registry.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_theme.dart';
import 'package:flutter/material.dart';

/// Onboarding éleveur — docs/PetsMatch_Specs_Onboarding_Anatomie.md §3.
/// Sert de template pour les 9 autres profils.
void registerEleveurOnboarding() {
  onboardingRegistry['eleveur'] = _steps;
  onboardingDiscoveryRegistry['eleveur'] = _discoveryItems;
}

final List<OnboardingStepDef> _steps = [
  OnboardingStepDef(
    key: 'profil',
    label: 'Profil',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.storefront_outlined,
      color: OnboardingTheme.teal,
      title: 'Complétez votre profil élevage',
      description: 'Nom de l\'élevage, SIRET, numéro DDPP, ACACED, espèces élevées, '
          'adresse... un profil complet inspire confiance aux futurs acquéreurs.',
      primaryLabel: 'Compléter mon profil →',
      pageBuilder: (_) => const ProfilEleveurEditPage(),
      onNext: onNext,
      onSkip: onSkip,
    ),
  ),
  OnboardingStepDef(
    key: 'animal',
    label: 'Premier animal',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.pets,
      color: OnboardingTheme.green,
      title: 'Créez votre premier animal',
      description: 'Nom, espèce, race, sexe, date de naissance, puce ou tatouage. '
          'Vous pourrez ajouter la généalogie, le suivi repro et le carnet santé depuis sa fiche.',
      primaryLabel: 'Ajouter cet animal →',
      pageBuilder: (_) => const AnimalFichePage(),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Passer cette étape',
    ),
  ),
  OnboardingStepDef(
    key: 'certificat',
    label: 'Certificat',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.description_outlined,
      color: OnboardingTheme.teal,
      title: 'Le certificat d\'engagement',
      description: 'Obligatoire depuis 2022 pour toute cession de chien ou chat. PetsMatch '
          'le génère automatiquement depuis la fiche de votre animal, pré-rempli avec vos informations.',
      primaryLabel: 'Voir mes certificats →',
      pageBuilder: (_) => const CertificatsEngagementPage(),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Continuer',
    ),
  ),
  OnboardingStepDef(
    key: 'protocoles',
    label: 'Protocoles',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.calendar_month_outlined,
      color: OnboardingTheme.green,
      title: 'Planifiez vos protocoles sanitaires',
      description: 'Vermifuges, rappels, vaccins... créez-les une fois, ils s\'appliquent '
          'automatiquement à chaque nouvelle portée, avec tâches et rappels générés.',
      extra: const _ProtocoleExample(),
      primaryLabel: 'Créer mon premier protocole →',
      pageBuilder: (_) => const PlanTemplateFormPage(),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Plus tard',
    ),
  ),
];

final List<OnboardingDiscoveryItem> _discoveryItems = [
  OnboardingDiscoveryItem(
    icon: Icons.campaign_outlined,
    color: OnboardingTheme.teal,
    title: 'Publier une annonce',
    subtitle: 'Chiots, portées, saillies ou pensions — visibles par des milliers d\'acquéreurs',
    pageBuilder: (_) => const CreateAnnoncePage(),
  ),
  OnboardingDiscoveryItem(
    icon: Icons.favorite_border,
    color: OnboardingTheme.green,
    title: 'Carnet de santé',
    subtitle: 'Vaccins, vermifuges et visites vétérinaires, animal par animal',
    pageBuilder: (_) => const MesAnimauxPage(),
  ),
  OnboardingDiscoveryItem(
    icon: Icons.swap_horiz,
    color: OnboardingTheme.teal,
    title: 'Registre entrées / sorties',
    subtitle: 'Le registre légal de mouvement de vos animaux',
    pageBuilder: (_) => const RegistreEntreeSortiePage(),
  ),
  OnboardingDiscoveryItem(
    icon: Icons.medical_information_outlined,
    color: OnboardingTheme.green,
    title: 'Registre sanitaire',
    subtitle: 'Suivi des actes vétérinaires et traitements du cheptel',
    pageBuilder: (_) => const RegistreSanitairePage(),
  ),
  OnboardingDiscoveryItem(
    icon: Icons.groups_outlined,
    color: OnboardingTheme.teal,
    title: 'Votre équipe',
    subtitle: 'Ajoutez des employés et gérez leurs permissions',
    pageBuilder: (_) => const EmployesPage(),
  ),
];

class _ProtocoleExample extends StatelessWidget {
  const _ProtocoleExample();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Exemple : protocole vermifuge chiots',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey.shade800)),
          const SizedBox(height: 8),
          const _ProtocoleLine('J+21 naissance', 'Panacur® 5 jours'),
          const _ProtocoleLine('J+42', 'Rappel 3 jours'),
          const _ProtocoleLine('J+56', 'Rappel 3 jours'),
        ],
      ),
    );
  }
}

class _ProtocoleLine extends StatelessWidget {
  final String date;
  final String action;
  const _ProtocoleLine(this.date, this.action);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(date, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: OnboardingTheme.teal, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(action, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade700)),
          ),
        ],
      ),
    );
  }
}
