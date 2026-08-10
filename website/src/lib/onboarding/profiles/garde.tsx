import { OnboardingActionStep } from '@/components/onboarding/OnboardingActionStep';
import { onboardingRegistry } from '../registry';
import type { OnboardingStepDef } from '../types';

// Onboarding garde (pet sitter / promeneur) —
// docs/PetsMatch_Specs_Onboarding_Anatomie.md §8.

const TEAL = '#0C5C6C';
const GREEN = '#6E9E57';

const steps: OnboardingStepDef[] = [
  {
    key: 'profil',
    label: 'Profil',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="🐕"
        color={TEAL}
        title="Votre profil garde"
        description="Pet sitter, promeneur ou les deux, SIRET ou statut, ACACED, espèces gardées, adresse... un profil complet inspire confiance aux propriétaires."
        primaryLabel="Compléter mon profil →"
        href="/profil"
        onNext={onNext}
        onSkip={onSkip}
      />
    ),
  },
  {
    key: 'zone',
    label: 'Zone',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="📍"
        color={GREEN}
        title="Définissez votre zone d'intervention"
        description="Ajustez le rayon autour de votre adresse. Les propriétaires dans ce rayon verront votre profil en priorité."
        primaryLabel="Configurer ma zone →"
        href="/profil"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Plus tard"
      />
    ),
  },
  {
    key: 'services',
    label: 'Services',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="✅"
        color={TEAL}
        title="Vos services et tarifs"
        description="Garde à domicile, garde chez vous, promenade individuelle ou en groupe, visite quotidienne, garde de nuit... activez vos services et indiquez un tarif de base pour chacun."
        primaryLabel="Configurer mes services →"
        href="/profil"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Plus tard"
      />
    ),
  },
  {
    key: 'disponibilites',
    label: 'Dispos',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="⏰"
        color={GREEN}
        title="Vos disponibilités"
        description="Cochez vos jours et horaires habituels, avec l'option jours fériés si vous êtes disponible — vous pourrez toujours affiner plus tard."
        primaryLabel="Renseigner mes disponibilités →"
        href="/pro/creneaux"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Plus tard"
      />
    ),
  },
];

export function registerGardeOnboarding() {
  onboardingRegistry.garde = steps;
}
