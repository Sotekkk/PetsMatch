import type { OnboardingDiscoveryItem, OnboardingStepDef } from './types';

// Registre des parcours métier par profile_type, rempli au fur et à mesure
// que chaque profil est implémenté — miroir de
// lib/pages/onboarding/onboarding_registry.dart côté app.
export const onboardingRegistry: Record<string, OnboardingStepDef[]> = {};

// Raccourcis "Découvrez aussi" affichés après l'écran de fin, par
// profile_type. Optionnel : un profil sans entrée ici va directement du
// parcours principal au tableau de bord.
export const onboardingDiscoveryRegistry: Record<string, OnboardingDiscoveryItem[]> = {};
