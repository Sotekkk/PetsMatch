'use client';

export function OnboardingReminderBanner({
  remaining,
  onClick,
  onDismiss,
}: {
  remaining: number;
  onClick: () => void;
  onDismiss: () => void;
}) {
  const label = remaining === 1 ? '1 étape restante' : `${remaining} étapes restantes`;
  return (
    <div className="fixed top-2 left-1/2 -translate-x-1/2 z-50 flex items-center gap-1 bg-[#6E9E57] text-white text-sm font-semibold pl-4 pr-2 py-2.5 rounded-xl shadow-lg max-w-[calc(100%-2rem)]">
      <button onClick={onClick} className="flex items-center gap-2 hover:opacity-90 transition-opacity">
        <span>🚩</span>
        <span>Finalisez votre profil — {label}</span>
        <span>→</span>
      </button>
      <button
        onClick={onDismiss}
        aria-label="Ne plus afficher"
        className="ml-1 w-6 h-6 flex items-center justify-center rounded-full text-white/70 hover:text-white hover:bg-white/15 transition-colors text-base leading-none"
      >
        ×
      </button>
    </div>
  );
}
