'use client';
import { useAuth } from '@/lib/auth-context';
import { ACTIVE_PROFILE_TYPE_KEY } from '@/hooks/useActiveProfile';

/**
 * Détermine si le profil actif est "sante" (ostéopathe/kinésithérapeute
 * animalier), en tenant compte du profil sélectionné dans le switcher plutôt
 * que de se fier uniquement à userData. Même logique que
 * useEducationAccess()/usePensionAccess()/Header.tsx.
 */
export function useSanteAccess() {
  const { user, userData, loading, availableProfiles, activeProfileId } = useAuth();

  const activeProfile = availableProfiles.find(p => p.id === activeProfileId) ?? null;
  const cachedProfileType = typeof window !== 'undefined' ? localStorage.getItem(ACTIVE_PROFILE_TYPE_KEY) : null;
  const resolvedProfileType = activeProfile?.profile_type
    ?? (activeProfileId && !activeProfile ? cachedProfileType : null);

  const isSante = resolvedProfileType
    ? resolvedProfileType === 'sante'
    : (userData?.isPro === true && userData?.catPro === 'sante');

  return { user, userData, isSante, loading };
}
