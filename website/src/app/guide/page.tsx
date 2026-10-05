'use client';

// « Guide de démarrage » (menu) — miroir appli relancerGuideDemarrage :
// réinitialise la progression de l'onboarding du profil actif puis recharge
// l'accueil, où OnboardingGate relance alors le guide depuis le début.
import { useEffect } from 'react';
import { useAuth } from '@/lib/auth-context';
import * as OnboardingService from '@/lib/onboarding/service';

export default function GuidePage() {
  const { user, activeProfileId, loading } = useAuth();

  useEffect(() => {
    if (loading) return;
    if (!user || !activeProfileId) { window.location.href = '/'; return; }
    OnboardingService.resetProgress(activeProfileId).finally(() => { window.location.href = '/'; });
  }, [loading, user, activeProfileId]);

  return (
    <div className="flex justify-center py-32">
      <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
    </div>
  );
}
