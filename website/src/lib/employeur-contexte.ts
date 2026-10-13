// Vue employé (Mes employeurs) : contexte d'un élevage employeur, résolu
// STRICTEMENT par profil — eleveur_profile_id de la relation, jamais tout le
// compte de l'employeur (qui peut porter d'autres profils : particulier,
// pension, autre élevage…). Les relations employé sont toujours rattachées au
// profil particulier de l'employé (cf. mes-employeurs).
// Miroir appli : EmployeurAnimauxContexte (mes_animaux.dart).
import { supabase } from '@/lib/supabase';

export type EmployeurContexte = {
  /** uid Firebase du titulaire du profil élevage */
  uid: string;
  /** user_profiles.id du profil élevage employeur */
  profileId: string;
  /** autorisations de l'employé pour CE profil (write_animaux, write_sante…) */
  perms: string[];
  nom: string;
};

/** Profil particulier de l'employé (porte toutes ses relations employé). */
export async function profilParticulierDe(uid: string): Promise<string | null> {
  const { data } = await supabase.from('user_profiles_complet')
    .select('id').eq('uid', uid).eq('profile_type', 'particulier').maybeSingle();
  return (data?.id as string | undefined) ?? null;
}

/** Contexte employeur si l'utilisateur est employé actif de ce profil, sinon null. */
export async function resoudreEmployeur(eleveurProfileId: string, monUid: string): Promise<EmployeurContexte | null> {
  if (!eleveurProfileId) return null;
  const monProfil = await profilParticulierDe(monUid);
  if (!monProfil) return null;
  const { data: rel } = await supabase.from('employes')
    .select('id, uid_eleveur, type')
    .eq('eleveur_profile_id', eleveurProfileId)
    .eq('employe_profile_id', monProfil)
    .eq('actif', true)
    .limit(1).maybeSingle();
  if (!rel) return null;
  const [{ data: prof }, { data: permsRows }] = await Promise.all([
    supabase.from('user_profiles_complet').select('uid, nom, firstname, lastname').eq('id', eleveurProfileId).maybeSingle(),
    supabase.from('employe_permissions').select('permission')
      .eq('eleveur_profile_id', eleveurProfileId).eq('employe_profile_id', monProfil),
  ]);
  const uid = (prof?.uid as string | undefined) ?? (rel.uid_eleveur as string);
  const nom = ((prof?.nom as string | null) ?? '').trim()
    || `${prof?.firstname ?? ''} ${prof?.lastname ?? ''}`.trim() || 'Élevage';
  return { uid, profileId: eleveurProfileId, perms: (permsRows ?? []).map(r => r.permission as string), nom };
}
