import { OnboardingActionStep } from '@/components/onboarding/OnboardingActionStep';
import { onboardingRegistry } from '../registry';
import type { OnboardingStepDef } from '../types';

// Onboarding ostéopathe / para-médical (santé) —
// docs/PetsMatch_Specs_Onboarding_Anatomie.md §10.

const TEAL = '#0C5C6C';
const GREEN = '#6E9E57';

const steps: OnboardingStepDef[] = [
  {
    key: 'profil',
    label: 'Profil',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="🧘"
        color={TEAL}
        title="Votre profil para-médical"
        description="Spécialité (ostéopathe, kinésithérapeute, acupuncteur...), SIRET, diplôme, ACACED, espèces traitées, zone d'intervention... un profil complet inspire confiance."
        primaryLabel="Compléter mon profil →"
        href="/profil"
        onNext={onNext}
        onSkip={onSkip}
      />
    ),
  },
  {
    key: 'seances',
    label: 'Séances',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="✅"
        color={GREEN}
        title="Vos séances"
        description="Consultation initiale (bilan), séance de suivi, à domicile ou en cabinet — indiquez une durée et un tarif pour chacune, elles serviront à calculer vos créneaux disponibles."
        primaryLabel="Configurer mes séances →"
        href="/profil"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Plus tard"
      />
    ),
  },
  {
    key: 'anatomie',
    label: 'Anatomie',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="🦴"
        color={TEAL}
        title="Un outil conçu pour votre pratique"
        description="PetsMatch intègre une vue anatomique interactive : sélectionnez une zone sur le schéma, annotez vos observations, l'annotation est enregistrée dans la fiche patient. Ouvrez la fiche d'un patient pour l'essayer."
        primaryLabel="Voir mes patients →"
        href="/mes-patients"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Plus tard"
      />
    ),
  },
  {
    key: 'acces_patients',
    label: 'Patients',
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

export function registerSanteOnboarding() {
  onboardingRegistry.sante = steps;
}
