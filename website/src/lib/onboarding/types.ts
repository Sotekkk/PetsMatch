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
