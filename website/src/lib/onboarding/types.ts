import type { ReactNode } from 'react';

export interface OnboardingStepRenderArgs {
  profileId: string;
  onNext: () => void;
  onSkip: () => void;
}

export interface OnboardingStepDef {
  key: string;
  label: string;
  render: (args: OnboardingStepRenderArgs) => ReactNode;
}

export interface OnboardingDiscoveryItem {
  icon: string; // emoji, même convention que EleveurDashboard.tsx
  color: string; // hex
  title: string;
  subtitle: string;
  href: string;
}

/** Les profils gratuits (particulier, association) n'ont pas d'abonnement :
 *  ne jamais leur afficher « essai gratuit de 30 jours ». */
export function onboardingHasTrial(profileType: string): boolean {
  return profileType !== 'particulier' && profileType !== 'association';
}
