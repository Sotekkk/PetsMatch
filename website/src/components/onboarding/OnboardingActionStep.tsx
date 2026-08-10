'use client';

import type { ReactNode } from 'react';

/**
 * Contenu générique d'une étape métier — miroir de
 * lib/pages/onboarding/onboarding_action_step.dart (app Flutter).
 *
 * Le clic sur le bouton principal ouvre la vraie page de la fonctionnalité
 * dans un nouvel onglet (le modal onboarding reste ouvert dans l'onglet
 * courant) et fait avancer le parcours dès que l'utilisateur revient sur cet
 * onglet — équivalent web du `await Navigator.push(...)` de l'app.
 */
export function OnboardingActionStep({
  icon,
  color,
  title,
  description,
  extra,
  primaryLabel,
  href,
  onNext,
  secondaryLabel = 'Plus tard',
  onSkip,
}: {
  icon: string;
  color: string;
  title: string;
  description: string;
  extra?: ReactNode;
  primaryLabel: string;
  href: string;
  onNext: () => void;
  secondaryLabel?: string;
  onSkip: () => void;
}) {
  function openAndAdvance() {
    const win = window.open(href, '_blank', 'noopener');
    if (!win) {
      // Popup bloquée : on avance quand même plutôt que de bloquer le parcours.
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
      <div
        className="w-24 h-24 rounded-full flex items-center justify-center text-4xl mb-3"
        style={{ backgroundColor: `${color}1A` }}
      >
        {icon}
      </div>
      <h2 className="font-['Galey'] text-xl font-bold text-[#1F2A2E]">{title}</h2>
      <p className="text-sm text-gray-600 leading-relaxed">{description}</p>
      {extra}
      <div className="w-full flex flex-col gap-3 mt-6">
        <button
          onClick={openAndAdvance}
          className="w-full rounded-xl px-6 py-3 text-white font-semibold transition-opacity hover:opacity-90"
          style={{ backgroundColor: color }}
        >
          {primaryLabel}
        </button>
        <button onClick={onSkip} className="text-sm text-gray-400 font-medium hover:text-gray-600">
          {secondaryLabel}
        </button>
      </div>
    </div>
  );
}
