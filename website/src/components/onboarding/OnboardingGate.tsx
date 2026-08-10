'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { useAuth } from '@/lib/auth-context';
import { registerAllOnboardingFlows } from '@/lib/onboarding/bootstrap';
import { onboardingRegistry } from '@/lib/onboarding/registry';
import * as OnboardingService from '@/lib/onboarding/service';
import { OnboardingModal } from './OnboardingModal';
import { OnboardingReminderBanner } from './OnboardingReminderBanner';

registerAllOnboardingFlows();

/**
 * Déclenche l'onboarding métier du profil actif à la première connexion et
 * affiche le bandeau de rappel tant qu'il n'est pas complété — miroir de
 * BottomNav._checkOnboarding + OnboardingReminderBanner (app Flutter), monté
 * une seule fois pour tout le site (comme CookieBanner dans SiteShell).
 */
export default function OnboardingGate() {
  const { user, userData, activeProfileId, loading } = useAuth();
  const [open, setOpen] = useState(false);
  const [resume, setResume] = useState(false);
  const [remaining, setRemaining] = useState(0);
  // Simple garde anti-double-check, pas un état d'affichage : ref pour éviter
  // de déclencher un second rendu depuis l'effet (react-hooks/set-state-in-effect).
  const checkedProfileIdRef = useRef('');

  const profileType = userData?.profileType ?? '';
  const supported = profileType in onboardingRegistry;

  const refreshRemaining = useCallback(async () => {
    if (!supported || !activeProfileId) {
      setRemaining(0);
      return;
    }
    const row = await OnboardingService.getProgress(activeProfileId);
    if (!row) {
      setRemaining(0);
      return;
    }
    const r = await OnboardingService.remainingSteps(activeProfileId, profileType);
    setRemaining(r);
  }, [supported, activeProfileId, profileType]);

  useEffect(() => {
    if (loading || !user || !activeProfileId || !supported) return;
    if (checkedProfileIdRef.current === activeProfileId) return; // déjà vérifié pour ce profil actif
    checkedProfileIdRef.current = activeProfileId;
    OnboardingService.shouldAutoLaunch(activeProfileId, profileType).then((launch) => {
      if (launch) {
        setResume(false);
        setOpen(true);
      } else {
        refreshRemaining();
      }
    });
  }, [loading, user, activeProfileId, supported, profileType, refreshRemaining]);

  const handleClose = useCallback(() => {
    setOpen(false);
    refreshRemaining();
  }, [refreshRemaining]);

  if (!user || !supported || !activeProfileId) return null;

  return (
    <>
      {open && (
        <OnboardingModal
          profileId={activeProfileId}
          profileType={profileType}
          firstName={userData?.firstname}
          resume={resume}
          onClose={handleClose}
        />
      )}
      {!open && remaining > 0 && (
        <OnboardingReminderBanner
          remaining={remaining}
          onClick={() => {
            setResume(true);
            setOpen(true);
          }}
        />
      )}
    </>
  );
}
