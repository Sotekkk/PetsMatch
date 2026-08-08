import 'package:flutter/material.dart';

/// Palette et styles partagés par tous les écrans d'onboarding
/// (voir docs/PetsMatch_Specs_Onboarding_Anatomie.md §2 — Architecture commune).
class OnboardingTheme {
  static const green = Color(0xFF6E9E57);
  static const teal = Color(0xFF0C5C6C);
  static const bg = Color(0xFFF5F7F0);
  static const dark = Color(0xFF1F2A2E);

  static const title = TextStyle(
    fontFamily: 'Galey',
    fontSize: 22,
    fontWeight: FontWeight.bold,
    color: dark,
    height: 1.3,
  );

  static const body = TextStyle(
    fontFamily: 'Galey',
    fontSize: 15,
    color: Colors.black54,
    height: 1.6,
  );

  static ButtonStyle primaryButton({Color? color}) => ElevatedButton.styleFrom(
        backgroundColor: color ?? teal,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
        textStyle: const TextStyle(fontFamily: 'Galey', fontSize: 16, fontWeight: FontWeight.w600),
      );

  static const skipButtonStyle = TextStyle(
    fontFamily: 'Galey',
    fontSize: 13,
    color: Colors.grey,
    fontWeight: FontWeight.w500,
  );
}

/// Pastilles de progression avec libellés, présentes sur chaque étape métier
/// (pas sur les écrans bienvenue/fin, qui sont hors numérotation).
class OnboardingProgressBar extends StatelessWidget {
  final int currentStep; // 1-based
  final List<String> labels;

  const OnboardingProgressBar({super.key, required this.currentStep, required this.labels});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(labels.length * 2 - 1, (i) {
        if (i.isOdd) {
          final leftDone = (i ~/ 2) + 1 < currentStep;
          return Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              color: leftDone ? OnboardingTheme.green : Colors.grey.shade300,
            ),
          );
        }
        final step = i ~/ 2 + 1;
        final done = step < currentStep;
        final active = step == currentStep;
        return Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done || active ? OnboardingTheme.green : Colors.white,
                border: Border.all(
                  color: done || active ? OnboardingTheme.green : Colors.grey.shade300,
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: done
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : Text('$step',
                      style: TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : Colors.grey.shade500,
                      )),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 56,
              child: Text(
                labels[step - 1],
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Galey',
                  fontSize: 10,
                  color: active ? OnboardingTheme.dark : Colors.grey.shade500,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

/// Layout commun à chaque étape métier : bouton "Passer" discret en haut,
/// barre de progression, puis le contenu de l'étape.
class OnboardingStepScaffold extends StatelessWidget {
  final int currentStep;
  final List<String> stepLabels;
  final VoidCallback onSkip;
  final Widget child;

  const OnboardingStepScaffold({
    super.key,
    required this.currentStep,
    required this.stepLabels,
    required this.onSkip,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OnboardingTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: OnboardingProgressBar(currentStep: currentStep, labels: stepLabels),
                  ),
                  TextButton(
                    onPressed: onSkip,
                    child: const Text('Passer', style: OnboardingTheme.skipButtonStyle),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
