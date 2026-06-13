'use client';
import { useState, useEffect } from 'react';

export const ACTIVE_PROFILE_KEY = 'petsMatch_activeProfileId';

/**
 * Retourne l'ID du profil actif (secondaire) ou '' pour le profil primaire.
 * Initialisation synchrone depuis localStorage pour éviter un flash au premier rendu.
 */
export function useActiveProfile(): string {
  const [activeProfileId, setActiveProfileId] = useState<string>(() => {
    if (typeof window === 'undefined') return '';
    return localStorage.getItem(ACTIVE_PROFILE_KEY) ?? '';
  });

  useEffect(() => {
    const handler = (e: StorageEvent) => {
      if (e.key === ACTIVE_PROFILE_KEY) {
        setActiveProfileId(e.newValue ?? '');
      }
    };
    window.addEventListener('storage', handler);
    return () => window.removeEventListener('storage', handler);
  }, []);

  return activeProfileId;
}
