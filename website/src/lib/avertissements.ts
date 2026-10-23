'use client';

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';

// Décisions de modération visant le compte (sanctions_moderation, écrite par
// l'API admin). Page : /profil/avertissements (Paramètres → Sécurité & aide) ;
// la notification « moderation » y mène. Miroir appli : avertissements_page.dart.

export const AVERTISSEMENTS_VUS_EVENT = 'pm:avertissements-vus';

/** Nombre de sanctions pas encore vues (vue_le null) : bulle rouge. */
export function useAvertissementsNonVus(uid: string | null | undefined): number {
  const [n, setN] = useState(0);
  useEffect(() => {
    if (!uid) { setN(0); return; }
    let annule = false;
    const charger = () => {
      supabase.from('sanctions_moderation').select('id', { count: 'exact', head: true })
        .eq('uid', uid).is('vue_le', null)
        // Erreur (colonne vue_le absente tant que la migration n'est pas passée) : pas de bulle.
        .then(({ count, error }) => { if (!annule) setN(error ? 0 : count ?? 0); });
    };
    charger();
    const vus = () => setN(0);
    window.addEventListener(AVERTISSEMENTS_VUS_EVENT, vus);
    return () => { annule = true; window.removeEventListener(AVERTISSEMENTS_VUS_EVENT, vus); };
  }, [uid]);
  return n;
}

export async function marquerAvertissementsVus() {
  await supabase.rpc('marquer_sanctions_vues');
  window.dispatchEvent(new Event(AVERTISSEMENTS_VUS_EVENT));
}
