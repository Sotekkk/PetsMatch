'use client';

import { useEffect, useState } from 'react';
import { onboardingDiscoveryRegistry, onboardingRegistry } from '@/lib/onboarding/registry';
import * as OnboardingService from '@/lib/onboarding/service';
import type { OnboardingStepDef } from '@/lib/onboarding/types';
import { OnboardingComplete } from './OnboardingComplete';
import { OnboardingDiscovery } from './OnboardingDiscovery';
import { OnboardingProgressBar } from './OnboardingProgressBar';
import { OnboardingWelcome } from './OnboardingWelcome';

type Phase = 'resolving' | 'welcome' | 'steps' | 'complete' | 'discovery';

/**
 * Orchestre le parcours complet d'un profil : bienvenue → étapes métier
 * (registre par profile_type) → écran de fin → raccourcis "Découvrez aussi"
 * optionnels. Miroir de lib/pages/onboarding/onboarding_flow_page.dart
 * (app Flutter) — modal plein écran avec navigation prev/next au lieu d'une
 * pile de pages dédiées.
 */
export function OnboardingModal({
  profileId,
  profileType,
  firstName,
  resume,
  onClose,
}: {
  profileId: string;
  profileType: string;
  firstName?: string;
  resume: boolean;
  onClose: () => void;
}) {
  const steps: OnboardingStepDef[] = onboardingRegistry[profileType] ?? [];
  const discoveryItems = onboardingDiscoveryRegistry[profileType] ?? [];

  const [phase, setPhase] = useState<Phase>(resume ? 'resolving' : 'welcome');
  const [stepIndex, setStepIndex] = useState(0);
  const [achievements, setAchievements] = useState<string[]>([]);

  useEffect(() => {
    if (!resume) return;
    let cancelled = false;
    OnboardingService.getProgress(profileId).then((row) => {
      if (cancelled) return;
      const completed = new Set(row?.completed_steps ?? []);
      if (completed.size === 0 || steps.length === 0) {
        setPhase(steps.length === 0 ? 'complete' : 'welcome');
        return;
      }
      const nextIndex = steps.findIndex((s) => !completed.has(s.key));
      if (nextIndex === -1) {
        setPhase('complete');
        return;
      }
      setStepIndex(nextIndex);
      setPhase('steps');
    });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [resume, profileId]);

  async function skipAll() {
    await OnboardingService.markSkipped(profileId);
    onClose();
  }

  async function completeStep(step: OnboardingStepDef, skipped: boolean) {
    await OnboardingService.markStepCompleted(profileId, step.key);
    if (!skipped) setAchievements((prev) => [...prev, step.label]);
    if (stepIndex < steps.length - 1) {
      setStepIndex((i) => i + 1);
    } else {
      setPhase('complete');
    }
  }

  function afterComplete() {
    if (discoveryItems.length === 0) {
      finish();
    } else {
      setPhase('discovery');
    }
  }

  async function finish() {
    await OnboardingService.markCompleted(profileId);
    onClose();
  }

  function goBack() {
    if (phase === 'steps' && stepIndex > 0) setStepIndex((i) => i - 1);
  }

  const currentStep = phase === 'steps' ? steps[stepIndex] : undefined;

  return (
    <div className="fixed inset-0 z-[100] bg-[#F5F7F0] overflow-y-auto">
      <div className="min-h-full flex flex-col max-w-2xl mx-auto px-6 py-8">
        {phase === 'resolving' && (
          <div className="flex-1 flex items-center justify-center">
            <div className="w-8 h-8 border-2 border-[#6E9E57] border-t-transparent rounded-full animate-spin" />
          </div>
        )}

        {phase === 'welcome' && (
          <div className="flex-1 flex items-center justify-center">
            <OnboardingWelcome
              firstName={firstName}
              onStart={() => setPhase(steps.length === 0 ? 'complete' : 'steps')}
              onSkip={skipAll}
            />
          </div>
        )}

        {phase === 'steps' && currentStep && (
          <>
            <div className="flex items-center gap-4 mb-8">
              {stepIndex > 0 && (
                <button onClick={goBack} className="text-gray-400 hover:text-gray-600 text-sm shrink-0">
                  ← Retour
                </button>
              )}
              <div className="flex-1">
                <OnboardingProgressBar current={stepIndex + 1} labels={steps.map((s) => s.label)} />
              </div>
              <button onClick={skipAll} className="text-sm text-gray-400 font-medium hover:text-gray-600 shrink-0">
                Passer
              </button>
            </div>
            <div className="flex-1 flex items-center justify-center">
              {currentStep.render({
                profileId,
                onNext: () => completeStep(currentStep, false),
                onSkip: () => completeStep(currentStep, true),
              })}
            </div>
          </>
        )}

        {phase === 'complete' && (
          <div className="flex-1 flex items-center justify-center">
            <OnboardingComplete achievements={achievements} onFinish={afterComplete} />
          </div>
        )}

        {phase === 'discovery' && <OnboardingDiscovery items={discoveryItems} onFinish={finish} />}
      </div>
    </div>
  );
}
