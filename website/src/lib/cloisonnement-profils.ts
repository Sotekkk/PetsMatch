// Cloisonnement des profils d'un même compte (éleveur, association,
// pension…) dans l'agenda : un rappel ou une tâche d'un animal de l'élevage
// ne doit jamais apparaître dans l'agenda de l'association, et inversement.
// Miroir appli : lib/utils/cloisonnement_profils.dart.
import { supabase } from '@/lib/supabase';

/** Identifiants des profils du compte. */
export async function mesProfilsIds(uid: string | null | undefined): Promise<Set<string>> {
  if (!uid) return new Set();
  const { data } = await supabase.from('user_profiles_complet').select('id').eq('uid', uid);
  return new Set((data ?? []).map(r => String(r.id)));
}

/** Profil auquel rattacher un rappel lié à un animal : celui du compte qui
 *  possède l'animal, sinon le profil actif (animal d'un client…). */
export async function profilPourAnimal(animalId: string | number | null | undefined,
  uid: string | null | undefined, actif: string | null | undefined): Promise<string | null> {
  if (animalId != null && animalId !== '') {
    try {
      const { data } = await supabase.from('animaux').select('profile_id').eq('id', String(animalId)).maybeSingle();
      const pid = (data?.profile_id as string | null) ?? '';
      if (pid && pid !== actif && (await mesProfilsIds(uid)).has(pid)) return pid;
    } catch { /* repli sur le profil actif */ }
  }
  return actif || null;
}

/** Retire les éléments (événements ou tâches) rattachés à un AUTRE profil du
 *  même compte : animal de cet autre profil, ou eleveur_profile_id différent. */
export async function sansAutresProfils<T extends { animal_id?: unknown; eleveur_profile_id?: string | null }>(
  items: T[], pid: string | null | undefined, uid: string | null | undefined): Promise<T[]> {
  if (!pid || items.length === 0) return items;
  const propres = items.filter(i => !i.eleveur_profile_id || i.eleveur_profile_id === pid);
  const ids = [...new Set(propres.map(i => i.animal_id).filter(a => a != null && a !== '').map(String))];
  if (ids.length === 0) return propres;
  try {
    const [mes, { data }] = await Promise.all([
      mesProfilsIds(uid),
      supabase.from('animaux').select('id, profile_id').in('id', ids),
    ]);
    const autres = new Set((data ?? [])
      .filter(a => a.profile_id && a.profile_id !== pid && mes.has(String(a.profile_id)))
      .map(a => String(a.id)));
    return propres.filter(i => !autres.has(String(i.animal_id)));
  } catch {
    return propres;
  }
}
