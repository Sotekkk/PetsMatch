'use client';

export function OnboardingComplete({
  achievements,
  onFinish,
}: {
  achievements: string[];
  onFinish: () => void;
}) {
  const trialEnd = new Date();
  trialEnd.setDate(trialEnd.getDate() + 30);
  const trialEndLabel = trialEnd.toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' });

  return (
    <div className="flex flex-col items-center text-center gap-2 w-full max-w-md mx-auto">
      <div className="w-24 h-24 rounded-full bg-[#6E9E571A] flex items-center justify-center text-5xl mb-2">✅</div>
      <h1 className="font-['Galey'] text-2xl font-bold text-[#1F2A2E]">Votre espace est prêt !</h1>
      <p className="text-sm text-gray-600 mt-2">Vous avez créé :</p>
      <ul className="text-left w-full mt-1 space-y-1.5">
        <li className="flex items-start gap-2 text-sm text-[#1F2A2E]">
          <span className="w-1.5 h-1.5 rounded-full bg-[#0C5C6C] mt-1.5 shrink-0" /> 1 profil vérifié
        </li>
        {achievements.map((a) => (
          <li key={a} className="flex items-start gap-2 text-sm text-[#1F2A2E]">
            <span className="w-1.5 h-1.5 rounded-full bg-[#0C5C6C] mt-1.5 shrink-0" /> {a}
          </li>
        ))}
      </ul>
      <p className="text-xs text-gray-500 mt-4">Votre essai se termine le {trialEndLabel}.</p>
      <button
        onClick={onFinish}
        className="w-full rounded-xl px-6 py-3 text-white font-semibold bg-[#6E9E57] hover:opacity-90 transition-opacity mt-6"
      >
        Accéder à mon tableau de bord →
      </button>
    </div>
  );
}
