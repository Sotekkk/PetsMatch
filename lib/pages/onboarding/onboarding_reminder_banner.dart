import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_flow_page.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_registry.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_theme.dart';
import 'package:PetsMatch/services/onboarding_service.dart';
import 'package:flutter/material.dart';

/// Bandeau "Finalisez votre profil — X étapes restantes", affiché en haut du
/// dashboard tant que l'onboarding du profil actif n'est pas complété
/// (docs/PetsMatch_Specs_Onboarding_Anatomie.md §1). Invisible tant que
/// l'utilisateur n'a jamais démarré l'onboarding (le déclenchement
/// automatique s'en charge à la première connexion) — n'apparaît que s'il l'a
/// commencé puis quitté avant la fin.
class OnboardingReminderBanner extends StatefulWidget {
  const OnboardingReminderBanner({super.key});

  @override
  State<OnboardingReminderBanner> createState() => _OnboardingReminderBannerState();
}

class _OnboardingReminderBannerState extends State<OnboardingReminderBanner> {
  int _remaining = 0;
  String _profileId = '';
  String _profileType = '';

  @override
  void initState() {
    super.initState();
    User_Info.profileNotifier.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    User_Info.profileNotifier.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final profileId = User_Info.activeProfileId;
    final profileType = User_Info.activeType;
    _profileId = profileId;
    _profileType = profileType;
    if (profileId.isEmpty || !onboardingRegistry.containsKey(profileType)) {
      if (mounted) setState(() => _remaining = 0);
      return;
    }
    // Pas de ligne du tout = jamais démarré : l'auto-launch s'en charge,
    // le bandeau ne doit pas doubler ce déclenchement.
    final progress = await OnboardingService.getProgress(profileId);
    final remaining = progress == null ? 0 : await OnboardingService.remainingSteps(profileId, profileType);
    if (mounted && profileId == User_Info.activeProfileId) {
      setState(() => _remaining = remaining);
    }
  }

  Future<void> _resume() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OnboardingFlowPage(profileId: _profileId, profileType: _profileType, resume: true),
      fullscreenDialog: true,
    ));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining <= 0) return const SizedBox.shrink();
    final label = _remaining == 1 ? '1 étape restante' : '$_remaining étapes restantes';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _resume,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: OnboardingTheme.green,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withAlpha(30), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(
            children: [
              const Icon(Icons.flag_outlined, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Finalisez votre profil — $label',
                  style: const TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
