import 'package:PetsMatch/pages/association/admin/chenil_planning_page.dart';
import 'package:PetsMatch/pages/association/benevoles/benevoles_page.dart';
import 'package:PetsMatch/pages/association/familles_accueil/familles_accueil_page.dart';
import 'package:PetsMatch/pages/association/profil_association_edit.dart';
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_action_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_registry.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_theme.dart';
import 'package:flutter/material.dart';

/// Onboarding association — docs/PetsMatch_Specs_Onboarding_Anatomie.md §4.
void registerAssociationOnboarding() {
  onboardingRegistry['association'] = _steps;
}

final List<OnboardingStepDef> _steps = [
  OnboardingStepDef(
    key: 'profil',
    label: 'Profil',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.favorite_outlined,
      color: OnboardingTheme.teal,
      title: 'Complétez votre profil association',
      description: 'Nom, numéro RNA, agrément préfectoral, espèces accueillies, capacité '
          'd\'accueil... votre profil sera vérifié par l\'équipe PetsMatch sous 48h, vous pouvez '
          'utiliser l\'app pendant ce délai.',
      primaryLabel: 'Compléter mon profil →',
      pageBuilder: (_) => const ProfilAssociationEditPage(),
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
      title: 'Ajoutez un premier animal au refuge',
      description: 'Nom, espèce, race ou croisé, sexe, âge estimé, statut (en soin, '
          'disponible à l\'adoption, en famille d\'accueil)... Vous pourrez compléter sa fiche plus tard.',
      primaryLabel: 'Ajouter cet animal →',
      pageBuilder: (_) => const AnimalFichePage(isAssociation: true),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Passer cette étape',
    ),
  ),
  OnboardingStepDef(
    key: 'chenil_ou_fa',
    label: 'FA / Chenil',
    builder: (context, {required profileId, required onNext, required onSkip}) =>
        _ChenilOuFaStep(onNext: onNext, onSkip: onSkip),
  ),
  OnboardingStepDef(
    key: 'benevole',
    label: 'Équipe',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.groups_outlined,
      color: OnboardingTheme.teal,
      title: 'Votre équipe peut accéder à PetsMatch',
      description: 'Ajoutez un bénévole ou un employé pour qu\'il puisse voir les animaux '
          'et valider ses tâches.',
      primaryLabel: 'Ajouter un bénévole →',
      pageBuilder: (_) => const BenevolesPage(),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Plus tard',
    ),
  ),
];

/// Étape 3 — choix dédié (pas une simple action unique) : familles d'accueil,
/// chenil, les deux, ou passer.
class _ChenilOuFaStep extends StatelessWidget {
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _ChenilOuFaStep({required this.onNext, required this.onSkip});

  Future<void> _open(BuildContext context, Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    onNext();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: OnboardingTheme.teal.withAlpha(26), shape: BoxShape.circle),
            child: const Icon(Icons.home_outlined, size: 44, color: OnboardingTheme.teal),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Comment gérez-vous vos animaux ?', textAlign: TextAlign.center, style: OnboardingTheme.title),
        const SizedBox(height: 12),
        const Text(
          'Entre le refuge et les adoptants, familles d\'accueil et chenil / enclos.',
          textAlign: TextAlign.center,
          style: OnboardingTheme.body,
        ),
        const SizedBox(height: 28),
        _ChoiceCard(
          icon: Icons.home_outlined,
          color: OnboardingTheme.green,
          title: 'Familles d\'accueil',
          subtitle: 'Placer des animaux chez des particuliers bénévoles',
          onTap: () => _open(context, const FamillesAccueilPage()),
        ),
        const SizedBox(height: 12),
        _ChoiceCard(
          icon: Icons.apartment_outlined,
          color: OnboardingTheme.teal,
          title: 'Chenil / Enclos',
          subtitle: 'Gérer les logements de votre refuge',
          onTap: () => _open(context, const ChenilPlanningPage()),
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: onNext,
          child: const Text('Les deux — je configure plus tard →', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: OnboardingTheme.teal, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: onSkip,
          child: const Text('Passer pour l\'instant', style: OnboardingTheme.skipButtonStyle),
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          border: Border.all(color: color.withAlpha(80)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: color.withAlpha(30), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: color)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    );
  }
}
