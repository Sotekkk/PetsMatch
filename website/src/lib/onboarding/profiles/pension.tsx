import { OnboardingActionStep } from '@/components/onboarding/OnboardingActionStep';
import { onboardingRegistry } from '../registry';
import type { OnboardingStepDef } from '../types';

// Onboarding pension — docs/PetsMatch_Specs_Onboarding_Anatomie.md §7.

const TEAL = '#0C5C6C';
const GREEN = '#6E9E57';

const steps: OnboardingStepDef[] = [
  {
    key: 'profil',
    label: 'Profil',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="🏨"
        color={TEAL}
        title="Votre profil pension"
        description="Nom de la pension, SIRET, agrément DDPP, ACACED, espèces accueillies, capacité totale, adresse... un profil complet rassure les propriétaires qui vous confient leur animal."
        primaryLabel="Compléter mon profil →"
        href="/profil"
        onNext={onNext}
        onSkip={onSkip}
      />
    ),
  },
  {
    key: 'logements',
    label: 'Logements',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="🏘️"
        color={GREEN}
        title="Ajoutez vos logements"
        description="Box individuel, enclos collectif, chatterie, cage NAC, suite haut de gamme... nommez chaque espace, ses espèces acceptées et sa capacité."
        primaryLabel="Ajouter un logement →"
        href="/pension/chenil"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Passer cette étape"
      />
    ),
  },
  {
    key: 'planning',
    label: 'Planning',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="🗓️"
        color={TEAL}
        title="Votre planning hôtelier en temps réel"
        description="Chaque logement est une ligne, chaque séjour une barre colorée. Un clic sur une case libre crée une nouvelle entrée."
        primaryLabel="Explorer le planning →"
        href="/pension/planning"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Continuer"
      />
    ),
  },
  {
    key: 'tarifs',
    label: 'Tarifs',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="💶"
        color={GREEN}
        title="Vos tarifs de base"
        description="Par espèce et par gabarit — ces tarifs seront automatiquement proposés à la facturation de chaque séjour."
        primaryLabel="Configurer mes tarifs →"
        href="/profil"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Configurer plus tard"
      />
    ),
  },
];

export function registerPensionOnboarding() {
  onboardingRegistry.pension = steps;
}
