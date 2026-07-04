'use client';
import { useAuth } from '@/lib/auth-context';
import { ACTIVE_PROFILE_TYPE_KEY } from '@/hooks/useActiveProfile';

/**
 * Détermine si le profil actif est "education" (éducateur/comportementaliste),
 * en tenant compte du profil sélectionné dans le switcher plutôt que de se
 * fier uniquement à userData. Même logique que usePensionAccess()/Header.tsx.
 */
export function useEducationAccess() {
  const { user, userData, loading, availableProfiles, activeProfileId } = useAuth();

  const activeProfile = availableProfiles.find(p => p.id === activeProfileId) ?? null;
  const cachedProfileType = typeof window !== 'undefined' ? localStorage.getItem(ACTIVE_PROFILE_TYPE_KEY) : null;
  const resolvedProfileType = activeProfile?.profile_type
    ?? (activeProfileId && !activeProfile ? cachedProfileType : null);

  const isEducation = resolvedProfileType
    ? resolvedProfileType === 'education'
    : (userData?.isPro === true && userData?.catPro === 'education');

  return { user, userData, isEducation, loading };
}
