'use client';

import type { OnboardingDiscoveryItem } from '@/lib/onboarding/types';

export function OnboardingDiscovery({
  items,
  onFinish,
}: {
  items: OnboardingDiscoveryItem[];
  onFinish: () => void;
}) {
  return (
    <div className="flex-1 flex flex-col w-full max-w-md mx-auto">
      <h1 className="font-['Galey'] text-2xl font-bold text-[#1F2A2E] mb-2">Découvrez aussi</h1>
      <p className="text-sm text-gray-600 mb-6">Ces modules vous attendent quand vous serez prêt.</p>
      <div className="flex-1 space-y-3 overflow-y-auto">
        {items.map((item) => (
          <a
            key={item.href}
            href={item.href}
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-3 bg-white border border-gray-200 rounded-2xl p-4 hover:shadow-md transition-shadow"
          >
            <div
              className="w-11 h-11 rounded-full flex items-center justify-center text-xl shrink-0"
              style={{ backgroundColor: `${item.color}1A` }}
            >
              {item.icon}
            </div>
            <div className="flex-1 min-w-0">
              <div className="font-semibold text-sm text-[#1F2A2E]">{item.title}</div>
              <div className="text-xs text-gray-500">{item.subtitle}</div>
            </div>
            <span className="text-gray-400">→</span>
          </a>
        ))}
      </div>
      <button
        onClick={onFinish}
        className="w-full rounded-xl px-6 py-3 text-white font-semibold bg-[#6E9E57] hover:opacity-90 transition-opacity mt-6"
      >
        Accéder à mon tableau de bord →
      </button>
    </div>
  );
}
