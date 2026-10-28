'use client';
import { useEffect, useRef } from 'react';

/** Rappelle [maj] toutes les [ms] (onglet visible) et au retour sur l'onglet :
 *  nouvelles demandes de RDV, notifications… visibles sans recharger la page
 *  (le temps réel Supabase ne remonte pas toujours avec le jeton Firebase). */
export function useActualisationAuto(maj: (() => void) | null | undefined, ms = 30000) {
  const ref = useRef(maj);
  useEffect(() => { ref.current = maj; }, [maj]);
  useEffect(() => {
    const tick = () => { if (document.visibilityState === 'visible') ref.current?.(); };
    const t = setInterval(tick, ms);
    document.addEventListener('visibilitychange', tick);
    window.addEventListener('focus', tick);
    return () => {
      clearInterval(t);
      document.removeEventListener('visibilitychange', tick);
      window.removeEventListener('focus', tick);
    };
  }, [ms]);
}
