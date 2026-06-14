'use client';
import { useState, useEffect } from 'react';

export const ACTIVE_PROFILE_KEY = 'petsMatch_activeProfileId';
export const PROFILE_CHANGE_EVENT = 'petsMatchProfileChanged';

interface ActiveProfileState {
  loaded: boolean;
  id: string;
}

export function useActiveProfileState(): ActiveProfileState {
  const [state, setState] = useState<ActiveProfileState>({ loaded: false, id: '' });

  useEffect(() => {
    const read = () => setState({ loaded: true, id: localStorage.getItem(ACTIVE_PROFILE_KEY) ?? '' });
    read();

    const handleStorage = (e: StorageEvent) => { if (e.key === ACTIVE_PROFILE_KEY) read(); };
    const handleCustom = () => read();

    window.addEventListener('storage', handleStorage);
    window.addEventListener(PROFILE_CHANGE_EVENT, handleCustom);
    return () => {
      window.removeEventListener('storage', handleStorage);
      window.removeEventListener(PROFILE_CHANGE_EVENT, handleCustom);
    };
  }, []);

  return state;
}

export function useActiveProfile(): string {
  return useActiveProfileState().id;
}
