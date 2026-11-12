// Registre sanitaire : à quel registre une saisie appartient (profil actif) et
// qui l'a faite quand « Administré par » est laissé vide (la personne
// connectée). Miroir appli : RegistreHelper.writeActe / moiIntervenant
// (lib/pages/eleveur/admin/registre_sanitaire.dart).
import type { Profile, UserData } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';

export function sourceRegistre(profils: Profile[], activeProfileId: string | null | undefined, userData?: UserData | null): 'association' | 'pension' | 'eleveur' {
  const t = profils.find(p => p.id === activeProfileId)?.profile_type ?? (activeProfileId ? null : userData?.profileType ?? null);
  if (t === 'association') return 'association';
  if (t === 'pension') return 'pension';
  return 'eleveur';
}

export function moiIntervenant(userData?: UserData | null): string {
  return [userData?.firstname, userData?.lastname].map(x => (x ?? '').trim()).filter(Boolean).join(' ');
}

/** Registre où inscrire un soin sur un animal de `ownerUid` : le profil actif
 *  quand c'est le sien ; employé / cogérant : le profil de l'élevage où il
 *  travaille (jamais son propre profil — RLS can_access_registre_sanitaire). */
export async function cibleRegistre(ownerUid: string, myUid: string, activeProfileId: string | null, profilAnimal?: string | null)
  : Promise<{ profileId: string | null; source: 'association' | 'pension' | 'eleveur' }> {
  let profileId: string | null = activeProfileId;
  if (ownerUid && ownerUid !== myUid) {
    const { data: e } = await supabase.from('employes').select('eleveur_profile_id')
      .eq('uid_eleveur', ownerUid).eq('uid_employe', myUid).eq('actif', true).limit(1).maybeSingle();
    let p = (e as { eleveur_profile_id?: string | null } | null)?.eleveur_profile_id ?? null;
    if (!p) {
      const { data: c } = await supabase.from('elevage_cogerants').select('elevage_profile_id')
        .eq('uid_gerant', ownerUid).eq('uid_cogerant', myUid).eq('statut', 'actif').is('date_fin', null).limit(1).maybeSingle();
      p = (c as { elevage_profile_id?: string | null } | null)?.elevage_profile_id ?? null;
    }
    profileId = p ?? profilAnimal ?? null;
  }
  let source: 'association' | 'pension' | 'eleveur' = 'eleveur';
  if (profileId) {
    const { data: pr } = await supabase.from('user_profiles').select('profile_type').eq('id', profileId).maybeSingle();
    const t = (pr as { profile_type?: string } | null)?.profile_type;
    if (t === 'association' || t === 'pension') source = t;
  }
  return { profileId, source };
}
