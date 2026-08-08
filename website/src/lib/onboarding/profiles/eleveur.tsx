import { OnboardingActionStep } from '@/components/onboarding/OnboardingActionStep';
import { onboardingDiscoveryRegistry, onboardingRegistry } from '../registry';
import type { OnboardingDiscoveryItem, OnboardingStepDef } from '../types';

// Onboarding éleveur — docs/PetsMatch_Specs_Onboarding_Anatomie.md §3.
// Sert de template pour les autres profils (miroir de
// lib/pages/onboarding/eleveur/eleveur_onboarding.dart côté app).

const TEAL = '#0C5C6C';
const GREEN = '#6E9E57';

function ProtocoleExample() {
  return (
    <div className="w-full bg-white border border-gray-200 rounded-2xl p-4 text-left mt-2">
      <p className="text-xs font-bold text-gray-700 mb-2">Exemple : protocole vermifuge chiots</p>
      <div className="space-y-1 text-xs text-gray-600">
        <div className="flex gap-2">
          <span className="w-28 shrink-0 font-semibold text-[#0C5C6C]">J+21 naissance</span>
          <span>Panacur® 5 jours</span>
        </div>
        <div className="flex gap-2">
          <span className="w-28 shrink-0 font-semibold text-[#0C5C6C]">J+42</span>
          <span>Rappel 3 jours</span>
        </div>
        <div className="flex gap-2">
          <span className="w-28 shrink-0 font-semibold text-[#0C5C6C]">J+56</span>
          <span>Rappel 3 jours</span>
        </div>
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
        icon="🏠"
        color={TEAL}
        title="Complétez votre profil élevage"
        description="Nom de l'élevage, SIRET, numéro DDPP, ACACED, espèces élevées, adresse... un profil complet inspire confiance aux futurs acquéreurs."
        primaryLabel="Compléter mon profil →"
        href="/elevage/profil"
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
        title="Créez votre premier animal"
        description="Nom, espèce, race, sexe, date de naissance, puce ou tatouage. Vous pourrez ajouter la généalogie, le suivi repro et le carnet santé depuis sa fiche."
        primaryLabel="Ajouter cet animal →"
        href="/mes-animaux/ajouter"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Passer cette étape"
      />
    ),
  },
  {
    key: 'certificat',
    label: 'Certificat',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="📄"
        color={TEAL}
        title="Le certificat d'engagement"
        description="Obligatoire depuis 2022 pour toute cession de chien ou chat. PetsMatch le génère automatiquement depuis la fiche de votre animal, pré-rempli avec vos informations."
        primaryLabel="Voir mes certificats →"
        href="/elevage/certificat-engagement"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Continuer"
      />
    ),
  },
  {
    key: 'protocoles',
    label: 'Protocoles',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="🗓️"
        color={GREEN}
        title="Planifiez vos protocoles sanitaires"
        description="Vermifuges, rappels, vaccins... créez-les une fois, ils s'appliquent automatiquement à chaque nouvelle portée, avec tâches et rappels générés."
        extra={<ProtocoleExample />}
        primaryLabel="Créer mon premier protocole →"
        href="/elevage/planning"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Plus tard"
      />
    ),
  },
];

const discoveryItems: OnboardingDiscoveryItem[] = [
  {
    icon: '📢',
    color: TEAL,
    title: 'Publier une annonce',
    subtitle: "Chiots, portées, saillies ou pensions — visibles par des milliers d'acquéreurs",
    href: '/annonces/creer',
  },
  {
    icon: '❤️',
    color: GREEN,
    title: 'Carnet de santé',
    subtitle: 'Vaccins, vermifuges et visites vétérinaires, animal par animal',
    href: '/mes-animaux',
  },
  {
    icon: '🔄',
    color: TEAL,
    title: 'Registre entrées / sorties',
    subtitle: 'Le registre légal de mouvement de vos animaux',
    href: '/elevage/registre-entree-sortie',
  },
  {
    icon: '🏥',
    color: GREEN,
    title: 'Registre sanitaire',
    subtitle: 'Suivi des actes vétérinaires et traitements du cheptel',
    href: '/elevage/registre-sanitaire',
  },
  {
    icon: '👥',
    color: TEAL,
    title: 'Votre équipe',
    subtitle: 'Ajoutez des employés et gérez leurs permissions',
    href: '/elevage/employes',
  },
];

export function registerEleveurOnboarding() {
  onboardingRegistry.eleveur = steps;
  onboardingDiscoveryRegistry.eleveur = discoveryItems;
}
