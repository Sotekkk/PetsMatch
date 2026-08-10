import 'package:PetsMatch/pages/onboarding/association/association_onboarding.dart';
import 'package:PetsMatch/pages/onboarding/education/education_onboarding.dart';
import 'package:PetsMatch/pages/onboarding/eleveur/eleveur_onboarding.dart';
import 'package:PetsMatch/pages/onboarding/garde/garde_onboarding.dart';
import 'package:PetsMatch/pages/onboarding/particulier/particulier_onboarding.dart';
import 'package:PetsMatch/pages/onboarding/pension/pension_onboarding.dart';
import 'package:PetsMatch/pages/onboarding/photographe/photographe_onboarding.dart';
import 'package:PetsMatch/pages/onboarding/sante/sante_onboarding.dart';
import 'package:PetsMatch/pages/onboarding/toilettage/toilettage_onboarding.dart';
import 'package:PetsMatch/pages/onboarding/veterinaire/veterinaire_onboarding.dart';

/// Enregistre les parcours d'onboarding de chaque profil implémenté dans
/// onboardingRegistry / onboardingDiscoveryRegistry. À appeler une seule fois
/// au démarrage de l'app, avant runApp().
void registerAllOnboardingFlows() {
  registerEleveurOnboarding();
  registerAssociationOnboarding();
  registerParticulierOnboarding();
  registerVeterinaireOnboarding();
  registerPensionOnboarding();
  registerGardeOnboarding();
  registerEducationOnboarding();
  registerSanteOnboarding();
  registerToilettageOnboarding();
  registerPhotographeOnboarding();
}
