// Adresse e-mail du propriétaire PetsMatch d'un animal, résolue côté serveur
// (jamais renvoyée au professionnel). Partagé par l'envoi de documents et
// les liens sécurisés.
import { admin } from '@/lib/galeries-server';

/** Propriétaire PetsMatch d'un animal : adresse de son compte, résolue ici
 *  (jamais renvoyée au professionnel), si l'appelant a accès à l'animal —
 *  partage actif (animal_access) avec un de ses profils, ou employé actif du
 *  profil qui a l'accès. null : pas de compte / pas d'accès / pas d'adresse. */
export async function emailProprietaire(animalId: string, appelant: string): Promise<{ email: string; nom: string } | null> {
  const { data: acces } = await admin.from('animal_access').select('pro_profile_id').eq('animal_id', animalId).eq('statut', 'active');
  const profils = [...new Set((acces ?? []).map(a => String(a.pro_profile_id)).filter(Boolean))];
  if (!profils.length) return null;
  const [{ data: miens }, { data: emp }] = await Promise.all([
    admin.from('user_profiles').select('id').in('id', profils).eq('uid', appelant),
    admin.from('employes').select('eleveur_profile_id').in('eleveur_profile_id', profils).eq('uid_employe', appelant).eq('actif', true),
  ]);
  if (!miens?.length && !emp?.length) return null;
  const { data: prop } = await admin.from('animaux_proprietes').select('uid_proprio, profile_id_proprio')
    .eq('animal_id', animalId).eq('role_proprio', 'principal').eq('statut', 'actif').is('date_fin', null).limit(1).maybeSingle();
  let uid = prop?.uid_proprio as string | undefined;
  if (!uid) {
    const { data: a } = await admin.from('animaux').select('uid_proprietaire').eq('id', animalId).maybeSingle();
    uid = (a?.uid_proprietaire as string | null) ?? undefined;
  }
  if (!uid) return null;
  const [{ data: profil }, { data: u }] = await Promise.all([
    prop?.profile_id_proprio
      ? admin.from('user_profiles').select('email_contact, firstname, lastname, nom').eq('id', prop.profile_id_proprio).maybeSingle()
      : Promise.resolve({ data: null }),
    admin.from('users').select('email, firstname, lastname').eq('uid', uid).maybeSingle(),
  ]);
  const email = String(profil?.email_contact || u?.email || '').trim();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return null;
  const nom = `${profil?.firstname ?? u?.firstname ?? ''} ${profil?.lastname ?? u?.lastname ?? ''}`.trim() || String(profil?.nom ?? '');
  return { email, nom };
}
