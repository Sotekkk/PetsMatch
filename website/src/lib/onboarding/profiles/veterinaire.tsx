import { OnboardingActionStep } from '@/components/onboarding/OnboardingActionStep';
import { onboardingRegistry } from '../registry';
import type { OnboardingStepDef } from '../types';

// Onboarding vétérinaire — docs/PetsMatch_Specs_Onboarding_Anatomie.md §6.

const TEAL = '#0C5C6C';
const GREEN = '#6E9E57';

const steps: OnboardingStepDef[] = [
  {
    key: 'profil',
    label: 'Profil',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="🏥"
        color={TEAL}
        title="Votre profil professionnel"
        description="Raison sociale, n° Ordre des Vétérinaires, SIRET, adresse du cabinet, spécialités, espèces traitées... un profil complet vous rend visible auprès des propriétaires à proximité."
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
    key: 'disponibilites',
    label: 'Créneaux',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="⏰"
        color={TEAL}
        title="Vos créneaux de disponibilité"
        description="Cochez vos jours et horaires habituels — vous pourrez toujours affiner plus tard."
        primaryLabel="Renseigner mes horaires →"
        href="/pro/creneaux"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Plus tard"
      />
    ),
  },
  {
    key: 'carnet_sante',
    label: 'Carnet santé',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="📁"
        color={GREEN}
        title="Demandez l'accès aux fiches de vos patients"
        description="Vos clients peuvent partager le carnet santé de leur animal avec vous. Une fois l'accès accordé, vous le consultez en lecture et pouvez y ajouter des soins."
        primaryLabel="Voir mes patients →"
        href="/mes-patients"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Compris"
      />
    ),
  },
];

export function registerVeterinaireOnboarding() {
  onboardingRegistry.veterinaire = steps;
}
