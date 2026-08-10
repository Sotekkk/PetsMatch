'use client';

export function OnboardingReminderBanner({ remaining, onClick }: { remaining: number; onClick: () => void }) {
  const label = remaining === 1 ? '1 étape restante' : `${remaining} étapes restantes`;
  return (
    <button
      onClick={onClick}
      className="fixed top-2 left-1/2 -translate-x-1/2 z-50 flex items-center gap-2 bg-[#6E9E57] text-white text-sm font-semibold px-4 py-2.5 rounded-xl shadow-lg hover:opacity-90 transition-opacity max-w-[calc(100%-2rem)]"
    >
      <span>🚩</span>
      <span>Finalisez votre profil — {label}</span>
      <span>→</span>
    </button>
  );
}
