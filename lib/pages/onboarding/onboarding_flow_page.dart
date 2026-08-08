import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_complete_page.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_discovery.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_registry.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_step.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_theme.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_welcome_page.dart';
import 'package:PetsMatch/services/onboarding_service.dart';
import 'package:flutter/material.dart';

enum _Phase { welcome, steps, complete, discovery }

/// Orchestre le parcours complet d'un profil : bienvenue → étapes métier
/// (registre par profile_type) → écran de fin → raccourcis "Découvrez aussi"
/// optionnels. Persiste la progression dans onboarding_progress à chaque
/// étape (docs/PetsMatch_Specs_Onboarding_Anatomie.md §2).
class OnboardingFlowPage extends StatefulWidget {
  final String profileId;
  final String profileType;
  /// true : saute l'écran de bienvenue et reprend à la première étape non
  /// complétée (bandeau de rappel, "Reprendre le guide"). false : parcours
  /// complet depuis le début (déclenchement automatique première connexion).
  final bool resume;

  const OnboardingFlowPage({
    super.key,
    required this.profileId,
    required this.profileType,
    this.resume = false,
  });

  @override
  State<OnboardingFlowPage> createState() => _OnboardingFlowPageState();
}

class _OnboardingFlowPageState extends State<OnboardingFlowPage> {
  _Phase _phase = _Phase.welcome;
  int _stepIndex = 0;
  bool _resolving = false;
  final List<String> _achievements = [];

  List<OnboardingStepDef> get _steps => onboardingRegistry[widget.profileType] ?? const [];
  List<OnboardingDiscoveryItem> get _discoveryItems =>
      onboardingDiscoveryRegistry[widget.profileType] ?? const [];

  @override
  void initState() {
    super.initState();
    if (widget.resume) {
      _resolving = true;
      _resolveResume();
    }
  }

  Future<void> _resolveResume() async {
    final progress = await OnboardingService.getProgress(widget.profileId);
    final completed =
        (progress?['completed_steps'] as List?)?.map((e) => e.toString()).toSet() ?? <String>{};
    final steps = _steps;
    if (completed.isEmpty || steps.isEmpty) {
      _phase = steps.isEmpty ? _Phase.complete : _Phase.welcome;
    } else {
      final nextIndex = steps.indexWhere((s) => !completed.contains(s.key));
      if (nextIndex == -1) {
        _phase = _Phase.complete;
      } else {
        _stepIndex = nextIndex;
        _phase = _Phase.steps;
      }
    }
    if (mounted) setState(() => _resolving = false);
  }

  void _start() => setState(() => _phase = _steps.isEmpty ? _Phase.complete : _Phase.steps);

  Future<void> _skipAll() async {
    await OnboardingService.markSkipped(widget.profileId);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _completeStep(String key, String label, {required bool skipped}) async {
    await OnboardingService.markStepCompleted(widget.profileId, key);
    if (!skipped) _achievements.add(label);
    if (_stepIndex < _steps.length - 1) {
      setState(() => _stepIndex++);
    } else {
      setState(() => _phase = _Phase.complete);
    }
  }

  void _afterCompleteScreen() {
    if (_discoveryItems.isEmpty) {
      _finish();
    } else {
      setState(() => _phase = _Phase.discovery);
    }
  }

  Future<void> _finish() async {
    await OnboardingService.markCompleted(widget.profileId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_resolving) {
      return const Scaffold(
        backgroundColor: OnboardingTheme.bg,
        body: Center(child: CircularProgressIndicator(color: OnboardingTheme.green)),
      );
    }
    switch (_phase) {
      case _Phase.welcome:
        return OnboardingWelcomePage(
          firstName: User_Info.firstname,
          onStart: _start,
          onSkip: _skipAll,
        );

      case _Phase.steps:
        final steps = _steps;
        final step = steps[_stepIndex];
        return OnboardingStepScaffold(
          currentStep: _stepIndex + 1,
          stepLabels: steps.map((s) => s.label).toList(),
          onSkip: _skipAll,
          child: step.builder(
            context,
            profileId: widget.profileId,
            onNext: () => _completeStep(step.key, step.label, skipped: false),
            onSkip: () => _completeStep(step.key, step.label, skipped: true),
          ),
        );

      case _Phase.complete:
        return OnboardingCompletePage(achievements: _achievements, onFinish: _afterCompleteScreen);

      case _Phase.discovery:
        return OnboardingDiscoveryPage(items: _discoveryItems, onFinish: _finish);
    }
  }
}
