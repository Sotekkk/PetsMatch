'use client';
import { useState, useEffect } from 'react';

export const ACTIVE_PROFILE_KEY = 'petsMatch_activeProfileId';

/**
 * Retourne l'ID du profil actif (secondaire) ou '' pour le profil primaire.
 * Se synchronise avec les changements de localStorage (changement d'onglet ou switchProfile).
 */
export function useActiveProfile(): string {
  const [activeProfileId, setActiveProfileId] = useState('');

  useEffect(() => {
    setActiveProfileId(localStorage.getItem(ACTIVE_PROFILE_KEY) ?? '');

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
