import 'package:PetsMatch/pages/onboarding/onboarding_theme.dart';
import 'package:flutter/material.dart';

/// Contenu générique d'une étape métier : icône, titre, description, un
/// bouton principal qui ouvre la vraie page de la fonctionnalité puis fait
/// avancer le parcours à son retour, et un bouton secondaire qui avance sans
/// ouvrir la page (ex: "Plus tard"). Les deux comptent l'étape comme vue —
/// seul le "Passer" global (OnboardingStepScaffold) abandonne tout le parcours.
class OnboardingActionStep extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final Widget? extra;
  final String primaryLabel;
  final WidgetBuilder pageBuilder;
  final VoidCallback onNext;
  final String secondaryLabel;
  final VoidCallback onSkip;

  const OnboardingActionStep({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    this.extra,
    required this.primaryLabel,
    required this.pageBuilder,
    required this.onNext,
    this.secondaryLabel = 'Plus tard',
    required this.onSkip,
  });

  Future<void> _open(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: pageBuilder));
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
            decoration: BoxDecoration(color: color.withAlpha(26), shape: BoxShape.circle),
            child: Icon(icon, size: 44, color: color),
          ),
        ),
        const SizedBox(height: 24),
        Text(title, textAlign: TextAlign.center, style: OnboardingTheme.title),
        const SizedBox(height: 12),
        Text(description, textAlign: TextAlign.center, style: OnboardingTheme.body),
        if (extra != null) ...[const SizedBox(height: 20), extra!],
        const SizedBox(height: 32),
        ElevatedButton(
          style: OnboardingTheme.primaryButton(color: color),
          onPressed: () => _open(context),
          child: Text(primaryLabel),
        ),
        const SizedBox(height: 10),
        TextButton(onPressed: onSkip, child: Text(secondaryLabel, style: OnboardingTheme.skipButtonStyle)),
      ],
    );
  }
}
