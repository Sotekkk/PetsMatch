'use client';
// Type du profil actif (association, eleveur, particulier, métier pro…),
// indépendant du menu : lit le profil sélectionné, sinon le compte principal.
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfileState, ACTIVE_PROFILE_TYPE_KEY } from '@/hooks/useActiveProfile';

export function useTypeProfilActif(): { type: string | null; pret: boolean } {
  const { user, userData, loading } = useAuth();
  const { id, loaded } = useActiveProfileState();
  const [secondaire, setSecondaire] = useState<{ id: string; type: string | null } | null>(null);

  useEffect(() => {
    if (!loaded || !id) return;
    let actif = true;
    supabase.from('user_profiles_complet').select('profile_type').eq('id', id).maybeSingle()
      .then(({ data }) => {
        if (!actif) return;
        let type = (data?.profile_type as string | undefined) ?? null;
        if (!type) { try { type = localStorage.getItem(ACTIVE_PROFILE_TYPE_KEY); } catch { /* */ } }
        setSecondaire({ id, type });
      });
    return () => { actif = false; };
  }, [id, loaded]);

  if (loading || !loaded || !user) return { type: null, pret: !loading && loaded && !user };
  if (id) {
    if (secondaire?.id !== id) return { type: null, pret: false };
    if (secondaire.type) return { type: secondaire.type, pret: true };
  }
  const type = userData?.isPro ? (userData?.catPro ?? 'sante')
    : userData?.isAssociation ? 'association'
    : userData?.isElevage ? 'eleveur' : 'particulier';
  return { type, pret: true };
}
