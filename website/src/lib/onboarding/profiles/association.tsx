import { OnboardingActionStep } from '@/components/onboarding/OnboardingActionStep';
import { onboardingRegistry } from '../registry';
import type { OnboardingStepDef } from '../types';

// Onboarding association — docs/PetsMatch_Specs_Onboarding_Anatomie.md §4.

const TEAL = '#0C5C6C';
const GREEN = '#6E9E57';

function ChenilOuFaStep({ onNext, onSkip }: { onNext: () => void; onSkip: () => void }) {
  function openAndAdvance(href: string) {
    const win = window.open(href, '_blank', 'noopener');
    if (!win) {
      onNext();
      return;
    }
    const onFocus = () => {
      window.removeEventListener('focus', onFocus);
      onNext();
    };
    window.addEventListener('focus', onFocus);
  }

  return (
    <div className="flex flex-col items-center text-center gap-1 w-full max-w-md mx-auto">
      <div className="w-24 h-24 rounded-full flex items-center justify-center text-4xl mb-3" style={{ backgroundColor: `${TEAL}1A` }}>
        🏠
      </div>
      <h2 className="font-['Galey'] text-xl font-bold text-[#1F2A2E]">Comment gérez-vous vos animaux ?</h2>
      <p className="text-sm text-gray-600 leading-relaxed">
        Entre le refuge et les adoptants, familles d&apos;accueil et chenil / enclos.
      </p>
      <div className="w-full flex flex-col gap-3 mt-6">
        <button
          onClick={() => openAndAdvance('/association/familles-accueil')}
          className="flex items-center gap-3 bg-[#6E9E571A] border border-[#6E9E57]/30 rounded-2xl p-4 text-left hover:shadow-md transition-shadow"
        >
          <span className="text-2xl">🏠</span>
          <div className="flex-1">
            <div className="font-bold text-sm text-[#6E9E57]">Familles d&apos;accueil</div>
            <div className="text-xs text-gray-600">Placer des animaux chez des particuliers bénévoles</div>
          </div>
          <span className="text-[#6E9E57]">→</span>
        </button>
        <button
          onClick={() => openAndAdvance('/association/chenil')}
          className="flex items-center gap-3 bg-[#0C5C6C1A] border border-[#0C5C6C]/30 rounded-2xl p-4 text-left hover:shadow-md transition-shadow"
        >
          <span className="text-2xl">🏢</span>
          <div className="flex-1">
            <div className="font-bold text-sm text-[#0C5C6C]">Chenil / Enclos</div>
            <div className="text-xs text-gray-600">Gérer les logements de votre refuge</div>
          </div>
          <span className="text-[#0C5C6C]">→</span>
        </button>
        <button onClick={onNext} className="text-sm text-[#0C5C6C] font-semibold hover:underline">
          Les deux — je configure plus tard →
        </button>
        <button onClick={onSkip} className="text-sm text-gray-400 font-medium hover:text-gray-600">
          Passer pour l&apos;instant
        </button>
      </div>
    </div>
  );
}

const steps: OnboardingStepDef[] = [
  {
    key: 'profil',
    label: 'Profil',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="❤️"
        color={TEAL}
        title="Complétez votre profil association"
        description="Nom, numéro RNA, agrément préfectoral, espèces accueillies, capacité d'accueil... votre profil sera vérifié par l'équipe PetsMatch sous 48h, vous pouvez utiliser l'app pendant ce délai."
        primaryLabel="Compléter mon profil →"
        href="/profil"
        onNext={onNext}
        onSkip={onSkip}
      />
    ),
  },
  {
    key: 'animal',
    label: 'Premier animal',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="🐾"
        color={GREEN}
        title="Ajoutez un premier animal au refuge"
        description="Nom, espèce, race ou croisé, sexe, âge estimé, statut (en soin, disponible à l'adoption, en famille d'accueil)... Vous pourrez compléter sa fiche plus tard."
        primaryLabel="Ajouter cet animal →"
        href="/association/animaux/nouveau"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Passer cette étape"
      />
    ),
  },
  {
    key: 'chenil_ou_fa',
    label: 'FA / Chenil',
    render: ({ onNext, onSkip }) => <ChenilOuFaStep onNext={onNext} onSkip={onSkip} />,
  },
  {
    key: 'benevole',
    label: 'Équipe',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="👥"
        color={TEAL}
        title="Votre équipe peut accéder à PetsMatch"
        description="Ajoutez un bénévole ou un employé pour qu'il puisse voir les animaux et valider ses tâches."
        primaryLabel="Ajouter un bénévole →"
        href="/association/benevoles"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Plus tard"
      />
    ),
  },
];

export function registerAssociationOnboarding() {
  onboardingRegistry.association = steps;
}
