import 'package:PetsMatch/pages/particulier/mes_animaux_page.dart';
import 'package:PetsMatch/pages/particulier/user_feed.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_action_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_registry.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_theme.dart';
import 'package:flutter/material.dart';

/// Onboarding particulier — docs/PetsMatch_Specs_Onboarding_Anatomie.md §5.
/// Le plus court des parcours (3 étapes, 2-3 min) : profil, animal, vitrine.
void registerParticulierOnboarding() {
  onboardingRegistry['particulier'] = _steps;
}

final List<OnboardingStepDef> _steps = [
  OnboardingStepDef(
    key: 'profil',
    label: 'Profil',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.person_outline,
      color: OnboardingTheme.teal,
      title: 'Complétez votre profil',
      description: 'Prénom, nom, ville, téléphone et photo de profil — de quoi vous '
          'identifier auprès des éleveurs et professionnels que vous contactez.',
      primaryLabel: 'Compléter mon profil →',
      pageBuilder: (_) => const UserParticulierFeed(initialTab: 0),
      onNext: onNext,
      onSkip: onSkip,
    ),
  ),
  OnboardingStepDef(
    key: 'animal',
    label: 'Mon compagnon',
    builder: (context, {required profileId, required onNext, required onSkip}) => OnboardingActionStep(
      icon: Icons.pets,
      color: OnboardingTheme.green,
      title: 'Quel est votre compagnon ?',
      description: 'Nom, race, date de naissance, photo, numéro de puce — créez sa fiche '
          'en quelques secondes.',
      primaryLabel: 'Ajouter mon animal →',
      pageBuilder: (_) => const AnimalFormPage(),
      onNext: onNext,
      onSkip: onSkip,
      secondaryLabel: 'Passer cette étape',
    ),
  ),
  OnboardingStepDef(
    key: 'decouverte',
    label: 'C\'est parti',
    builder: (context, {required profileId, required onNext, required onSkip}) =>
        _ShowcaseStep(onNext: onNext),
  ),
];

/// Étape 3 — vitrine des features particulier, aucune donnée à saisir
/// (docs/PetsMatch_Specs_Onboarding_Anatomie.md §5).
class _ShowcaseStep extends StatelessWidget {
  final VoidCallback onNext;
  const _ShowcaseStep({required this.onNext});

  static const _features = [
    (
      icon: Icons.favorite_border,
      color: OnboardingTheme.teal,
      title: 'Carnet de santé numérique',
      desc: 'Vaccins, antiparasitaires, visites vétérinaires — tout en un endroit',
    ),
    (
      icon: Icons.search,
      color: OnboardingTheme.green,
      title: 'Animaux perdus / trouvés',
      desc: 'Signalez ou retrouvez un animal sur la carte',
    ),
    (
      icon: Icons.calendar_month_outlined,
      color: OnboardingTheme.teal,
      title: 'Agenda & rappels',
      desc: 'Vaccins, RDV vétérinaires — jamais oublié',
    ),
    (
      icon: Icons.chat_bubble_outline,
      color: OnboardingTheme.green,
      title: 'Messagerie',
      desc: 'Contactez éleveurs et professionnels directement',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const Text('Avec PetsMatch, vous pouvez :', textAlign: TextAlign.center, style: OnboardingTheme.title),
        const SizedBox(height: 24),
        for (final f in _features) _FeatureRow(icon: f.icon, color: f.color, title: f.title, desc: f.desc),
        const SizedBox(height: 12),
        ElevatedButton(
          style: OnboardingTheme.primaryButton(color: OnboardingTheme.green),
          onPressed: onNext,
          child: const Text('Accéder à mon espace →'),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String desc;

  const _FeatureRow({required this.icon, required this.color, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withAlpha(26), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: OnboardingTheme.dark)),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
