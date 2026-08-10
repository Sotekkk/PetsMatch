import { registerAssociationOnboarding } from './profiles/association';
import { registerEducationOnboarding } from './profiles/education';
import { registerEleveurOnboarding } from './profiles/eleveur';
import { registerGardeOnboarding } from './profiles/garde';
import { registerParticulierOnboarding } from './profiles/particulier';
import { registerPensionOnboarding } from './profiles/pension';
import { registerPhotographeOnboarding } from './profiles/photographe';
import { registerSanteOnboarding } from './profiles/sante';
import { registerToilettageOnboarding } from './profiles/toilettage';
import { registerVeterinaireOnboarding } from './profiles/veterinaire';

let registered = false;

/** Enregistre les parcours d'onboarding de chaque profil implémenté. Appelé
 * une seule fois au montage de OnboardingGate — miroir de
 * lib/pages/onboarding/onboarding_bootstrap.dart (app Flutter). */
export function registerAllOnboardingFlows() {
  if (registered) return;
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
  registered = true;
}
