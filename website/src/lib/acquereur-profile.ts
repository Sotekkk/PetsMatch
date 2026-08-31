import { supabase } from './supabase';

/**
 * Résout le `user_profiles.id` qui doit recevoir un animal cédé.
 * Priorité : profil correspondant à la qualité (particulier / éleveur /
 * association) — jamais un profil pro (pension, garde…). Repli `is_main`.
 * Miroir de `_acquereurProfileId` (app, contrat_finalize.dart).
 */
export async function resolveAcquereurProfileId(
  acqUid: string | null | undefined,
  qualite: string | null | undefined,
  storedProfileId?: string | null,
): Promise<string | null> {
  if (storedProfileId) return storedProfileId;
  if (!acqUid) return null;
  const wanted =
    qualite === 'eleveur' ? 'eleveur'
    : qualite === 'refuge' || qualite === 'association' ? 'association'
    : 'particulier';
  const { data: byType } = await supabase.from('user_profiles')
    .select('id').eq('uid', acqUid).eq('profile_type', wanted).maybeSingle();
  if (byType?.id) return byType.id as string;
  const { data: main } = await supabase.from('user_profiles')
    .select('id').eq('uid', acqUid).eq('is_main', true).maybeSingle();
  return (main?.id as string | undefined) ?? null;
}
