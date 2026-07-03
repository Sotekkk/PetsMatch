'use client';
import { useAuth } from '@/lib/auth-context';
import { ACTIVE_PROFILE_TYPE_KEY } from '@/hooks/useActiveProfile';

/**
 * Détermine si le profil actif est bien "pension", en tenant compte du profil
 * sélectionné dans le switcher (activeProfileId) plutôt que de se fier
 * uniquement à userData — qui peut représenter un autre profil du compte
 * (ex : compte ayant à la fois un profil pension et un profil particulier).
 * Même logique que Header.tsx (resolvedProfileType).
 */
export function usePensionAccess() {
  const { user, userData, loading, availableProfiles, activeProfileId } = useAuth();

  const activeProfile = availableProfiles.find(p => p.id === activeProfileId) ?? null;
  const cachedProfileType = typeof window !== 'undefined' ? localStorage.getItem(ACTIVE_PROFILE_TYPE_KEY) : null;
  const resolvedProfileType = activeProfile?.profile_type
    ?? (activeProfileId && !activeProfile ? cachedProfileType : null);

  const isPension = resolvedProfileType
    ? resolvedProfileType === 'pension'
    : (userData?.isPro === true && userData?.catPro === 'pension');

  return { user, userData, isPension, loading };
}
