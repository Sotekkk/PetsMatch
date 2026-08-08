import { OnboardingActionStep } from '@/components/onboarding/OnboardingActionStep';
import { onboardingRegistry } from '../registry';
import type { OnboardingStepDef } from '../types';

// Onboarding éducateur / comportementaliste —
// docs/PetsMatch_Specs_Onboarding_Anatomie.md §9.

const TEAL = '#0C5C6C';
const GREEN = '#6E9E57';

const steps: OnboardingStepDef[] = [
  {
    key: 'profil',
    label: 'Profil',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="🎓"
        color={TEAL}
        title="Votre profil éducateur"
        description="SIRET, ACACED, certifications (CCPCC, CNECAD...), méthodes pratiquées, espèces travaillées, adresse... un profil complet inspire confiance aux propriétaires."
        primaryLabel="Compléter mon profil →"
        href="/profil"
        onNext={onNext}
        onSkip={onSkip}
      />
    ),
  },
  {
    key: 'services',
    label: 'Services',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="✅"
        color={GREEN}
        title="Vos types de séances"
        description="Cours individuel, cours collectif, bilan comportemental, stage intensif, suivi à distance... activez vos prestations et indiquez un tarif de base pour chacune."
        primaryLabel="Configurer mes services →"
        href="/profil"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Plus tard"
      />
    ),
  },
  {
    key: 'zone',
    label: 'Zone',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="📍"
        color={TEAL}
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
    key: 'devis',
    label: 'Devis',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="🧾"
        color={GREEN}
        title="Envoyez un devis en moins de 2 minutes"
        description="Sélectionnez un service, choisissez un client — le devis est pré-rempli et envoyé par email."
        primaryLabel="Créer un devis de démonstration →"
        href="/education/devis"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Continuer"
      />
    ),
  },
];

export function registerEducationOnboarding() {
  onboardingRegistry.education = steps;
}
