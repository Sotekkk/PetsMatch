import { OnboardingActionStep } from '@/components/onboarding/OnboardingActionStep';
import { onboardingRegistry } from '../registry';
import type { OnboardingStepDef } from '../types';

// Onboarding photographe — docs/PetsMatch_Specs_Onboarding_Anatomie.md §12.
// Le plus court des parcours pro (3 étapes, 3-4 min).

const TEAL = '#0C5C6C';
const GREEN = '#6E9E57';

const steps: OnboardingStepDef[] = [
  {
    key: 'profil',
    label: 'Profil',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="📷"
        color={TEAL}
        title="Votre profil et votre portfolio"
        description="Nom du studio, SIRET, zone d'intervention, espèces photographiées, style... et au moins 5 photos de portfolio, le minimum pour apparaître dans les recherches."
        primaryLabel="Compléter mon profil →"
        href="/profil"
        onNext={onNext}
        onSkip={onSkip}
      />
    ),
  },
  {
    key: 'tarifs',
    label: 'Tarifs',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="🖼️"
        color={GREEN}
        title="Vos tarifs et formules"
        description="Séance 1h, séance 2h, reportage, shooting en studio... indiquez un prix et un nombre de photos livrées pour chaque formule."
        primaryLabel="Configurer mes formules →"
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
        color={TEAL}
        title="Vos disponibilités"
        description="Cochez vos jours et horaires habituels — les clients pourront vous contacter directement depuis votre profil PetsMatch."
        primaryLabel="Renseigner mes disponibilités →"
        href="/pro/creneaux"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="C'est parti"
      />
    ),
  },
];

export function registerPhotographeOnboarding() {
  onboardingRegistry.photographe = steps;
}
