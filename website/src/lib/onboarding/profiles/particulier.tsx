'use client';

import { OnboardingActionStep } from '@/components/onboarding/OnboardingActionStep';
import { onboardingRegistry } from '../registry';
import type { OnboardingStepDef } from '../types';

// Onboarding particulier — docs/PetsMatch_Specs_Onboarding_Anatomie.md §5.
// Le plus court des parcours (3 étapes, 2-3 min) : profil, animal, vitrine.

const TEAL = '#0C5C6C';
const GREEN = '#6E9E57';

const FEATURES = [
  { icon: '❤️', color: TEAL, title: 'Carnet de santé numérique', desc: 'Vaccins, antiparasitaires, visites vétérinaires — tout en un endroit' },
  { icon: '🔍', color: GREEN, title: 'Animaux perdus / trouvés', desc: 'Signalez ou retrouvez un animal sur la carte' },
  { icon: '📅', color: TEAL, title: 'Agenda & rappels', desc: 'Vaccins, RDV vétérinaires — jamais oublié' },
  { icon: '💬', color: GREEN, title: 'Messagerie', desc: 'Contactez éleveurs et professionnels directement' },
];

function ShowcaseStep({ onNext }: { onNext: () => void }) {
  return (
    <div className="w-full max-w-md mx-auto">
      <h2 className="font-['Galey'] text-xl font-bold text-[#1F2A2E] text-center mb-6">Avec PetsMatch, vous pouvez :</h2>
      <div className="space-y-4">
        {FEATURES.map((f) => (
          <div key={f.title} className="flex items-start gap-3">
            <div
              className="w-11 h-11 rounded-full flex items-center justify-center text-xl shrink-0"
              style={{ backgroundColor: `${f.color}1A` }}
            >
              {f.icon}
            </div>
            <div>
              <div className="font-bold text-sm text-[#1F2A2E]">{f.title}</div>
              <div className="text-xs text-gray-500">{f.desc}</div>
            </div>
          </div>
        ))}
      </div>
      <button
        onClick={onNext}
        className="w-full rounded-xl px-6 py-3 text-white font-semibold bg-[#6E9E57] hover:opacity-90 transition-opacity mt-8"
      >
        Accéder à mon espace →
      </button>
    </div>
  );
}

const steps: OnboardingStepDef[] = [
  {
    key: 'profil',
    label: 'Profil',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="🙂"
        color={TEAL}
        title="Complétez votre profil"
        description="Prénom, nom, ville, téléphone et photo de profil — de quoi vous identifier auprès des éleveurs et professionnels que vous contactez."
        primaryLabel="Compléter mon profil →"
        href="/profil"
        onNext={onNext}
        onSkip={onSkip}
      />
    ),
  },
  {
    key: 'animal',
    label: 'Mon compagnon',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="🐾"
        color={GREEN}
        title="Quel est votre compagnon ?"
        description="Nom, race, date de naissance, photo, numéro de puce — créez sa fiche en quelques secondes."
        primaryLabel="Ajouter mon animal →"
        href="/mes-animaux/ajouter"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Passer cette étape"
      />
    ),
  },
  {
    key: 'decouverte',
    label: "C'est parti",
    render: ({ onNext }) => <ShowcaseStep onNext={onNext} />,
  },
];

export function registerParticulierOnboarding() {
  onboardingRegistry.particulier = steps;
}
