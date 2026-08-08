import 'package:PetsMatch/pages/onboarding/onboarding_discovery.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_step.dart';

/// Registre des parcours métier par profile_type, rempli au fur et à mesure
/// que chaque profil est implémenté (éleveur en premier — voir
/// docs/PetsMatch_Specs_Onboarding_Anatomie.md §3-12). Un profile_type absent
/// de ce registre n'a pas encore d'onboarding métier : le déclenchement
/// automatique (BottomNav) l'ignore silencieusement.
final Map<String, List<OnboardingStepDef>> onboardingRegistry = {};

/// Raccourcis "Découvrez aussi" affichés après l'écran de fin, par
/// profile_type. Optionnel : un profil sans entrée ici va directement du
/// parcours principal au tableau de bord.
final Map<String, List<OnboardingDiscoveryItem>> onboardingDiscoveryRegistry = {};
