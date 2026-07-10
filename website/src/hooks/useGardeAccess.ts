'use client';
import { useAuth } from '@/lib/auth-context';
import { ACTIVE_PROFILE_TYPE_KEY } from '@/hooks/useActiveProfile';

/**
 * Détermine si le profil actif est bien "garde" (petsitter/promeneur), en
 * tenant compte du profil sélectionné dans le switcher (activeProfileId)
 * plutôt que de se fier uniquement à userData — mirror de usePensionAccess.
 */
export function useGardeAccess() {
  const { user, userData, loading, availableProfiles, activeProfileId } = useAuth();

  const activeProfile = availableProfiles.find(p => p.id === activeProfileId) ?? null;
  const cachedProfileType = typeof window !== 'undefined' ? localStorage.getItem(ACTIVE_PROFILE_TYPE_KEY) : null;
  const resolvedProfileType = activeProfile?.profile_type
    ?? (activeProfileId && !activeProfile ? cachedProfileType : null);

  const isGarde = resolvedProfileType
    ? resolvedProfileType === 'garde'
    : (userData?.isPro === true && userData?.catPro === 'garde');

  return { user, userData, isGarde, loading };
}
