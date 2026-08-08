import { OnboardingActionStep } from '@/components/onboarding/OnboardingActionStep';
import { onboardingRegistry } from '../registry';
import type { OnboardingStepDef } from '../types';

// Onboarding toiletteur — docs/PetsMatch_Specs_Onboarding_Anatomie.md §11.

const TEAL = '#0C5C6C';
const GREEN = '#6E9E57';

const steps: OnboardingStepDef[] = [
  {
    key: 'profil',
    label: 'Profil',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="✂️"
        color={TEAL}
        title="Votre profil toilettage"
        description="Nom du salon, SIRET, certifications (BTM Toiletteur...), adresse, service à domicile ou non, races travaillées... un profil complet inspire confiance."
        primaryLabel="Compléter mon profil →"
        href="/profil"
        onNext={onNext}
        onSkip={onSkip}
      />
    ),
  },
  {
    key: 'prestations',
    label: 'Prestations',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="✅"
        color={GREEN}
        title="Vos prestations et tarifs"
        description="Bain + séchage + brossage, coupe + toilettage complet, coupe seule, stripping, épilation... tarifez par taille ou par race."
        primaryLabel="Configurer mes prestations →"
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
        description="Cochez vos jours et horaires habituels — vous pourrez toujours affiner plus tard depuis votre profil."
        primaryLabel="Renseigner mes disponibilités →"
        href="/pro/creneaux"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Plus tard"
      />
    ),
  },
  {
    key: 'agenda',
    label: 'Agenda',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="📅"
        color={GREEN}
        title="Votre agenda est prêt"
        description="Les clients peuvent prendre RDV directement depuis votre profil PetsMatch."
        primaryLabel="Voir mon agenda →"
        href="/agenda"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="C'est parti"
      />
    ),
  },
];

export function registerToilettageOnboarding() {
  onboardingRegistry.toilettage = steps;
}
