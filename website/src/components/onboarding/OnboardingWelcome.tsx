'use client';

export function OnboardingWelcome({
  firstName,
  onStart,
  onSkip,
}: {
  firstName?: string;
  onStart: () => void;
  onSkip: () => void;
}) {
  const name = firstName?.trim();
  return (
    <div className="flex flex-col items-center text-center gap-4 w-full max-w-md mx-auto">
      <div className="w-28 h-28 rounded-full bg-[#6E9E571A] flex items-center justify-center text-5xl">🐾</div>
      <h1 className="font-['Galey'] text-2xl font-bold text-[#1F2A2E]">
        {name ? `Bienvenue sur PetsMatch, ${name} !` : 'Bienvenue sur PetsMatch !'}
      </h1>
      <p className="text-gray-600 leading-relaxed">
        Votre essai gratuit de 30 jours commence aujourd&apos;hui.
        <br />
        Accès complet à toutes les fonctionnalités — aucune CB requise.
      </p>
      <div className="w-full flex flex-col gap-3 mt-4">
        <button
          onClick={onStart}
          className="w-full rounded-xl px-6 py-3 text-white font-semibold bg-[#0C5C6C] hover:opacity-90 transition-opacity"
        >
          Commencer la configuration →
        </button>
        <button onClick={onSkip} className="text-sm text-gray-400 font-medium hover:text-gray-600">
          Passer pour l&apos;instant
        </button>
      </div>
    </div>
  );
}
