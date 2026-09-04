import { supabase } from '@/lib/supabase';

export interface OwnerContactData {
  prenom?: string;
  nom?: string;
  tel?: string;
  email?: string;
}

export interface OwnerContactResult {
  contact: OwnerContactData;
  /** true si le propriétaire n'a pas (ou plus) de compte PetsMatch actif : les
   * coordonnées peuvent alors être corrigées à la main par le pro. */
  editable: boolean;
}

/**
 * Coordonnées du propriétaire actuel d'un animal suivi par un pro (éducateur,
 * comportementaliste…). Priorité : profil particulier live (à jour, qu'il
 * maîtrise) → correction manuelle du pro
 * (`animaux.proprietaire_contact_manuel`, si pas de compte actif). Même
 * logique que l'app, `lib/pages/pro/owner_contact.dart`.
 */
export async function fetchOwnerContact(animalId: string, ownerUid: string | null): Promise<OwnerContactResult> {
  const c: OwnerContactData = {};
  const put = (k: keyof OwnerContactData, v: unknown) => {
    const s = (v ?? '').toString().trim();
    if (s && !c[k]) c[k] = s;
  };

  let hasLiveProfile = false;
  if (ownerUid) {
    const { data: p } = await supabase.from('user_profiles')
      .select('firstname, lastname, phone_number, email_contact')
      .eq('uid', ownerUid).eq('profile_type', 'particulier').maybeSingle();
    if (p) {
      hasLiveProfile = true;
      put('prenom', p.firstname); put('nom', p.lastname);
      put('tel', p.phone_number); put('email', p.email_contact);
    }
  }

  if (!hasLiveProfile) {
    const { data: row } = await supabase.from('animaux')
      .select('proprietaire_contact_manuel').eq('id', animalId).maybeSingle();
    const manuel = row?.proprietaire_contact_manuel as OwnerContactData | null;
    if (manuel) {
      put('prenom', manuel.prenom); put('nom', manuel.nom);
      put('tel', manuel.tel); put('email', manuel.email);
    }
  }

  return { contact: c, editable: !hasLiveProfile };
}

/** Enregistre la correction manuelle du pro (pertinent seulement quand le
 * propriétaire n'a pas de compte PetsMatch actif). */
export async function saveOwnerContactManuel(animalId: string, data: OwnerContactData) {
  await supabase.from('animaux').update({ proprietaire_contact_manuel: data }).eq('id', animalId);
}

/** Téléphone au format international sans « + » pour wa.me (France par défaut). */
export function waPhone(raw: string): string {
  let d = raw.replace(/[^0-9]/g, '');
  if (d.startsWith('00')) d = d.slice(2);
  if (d.startsWith('0')) d = '33' + d.slice(1);
  return d;
}

/**
 * Ouvre (ou crée) la conversation entre le pro connecté et le propriétaire,
 * taguée pour que les deux la retrouvent dans /messages. Retourne l'id de
 * conversation à passer à `/messages?conv=<id>`.
 */
export async function openOrCreateOwnerConversation(
  myUid: string, myProfileId: string | null, otherUid: string,
): Promise<string> {
  const sorted = [myUid, otherUid].sort().join('_');
  const proProfileId = myProfileId;
  const { data: consumerProfile } = await supabase.from('user_profiles')
    .select('id').eq('uid', otherUid).eq('profile_type', 'particulier').maybeSingle();
  const consumerProfileId = consumerProfile?.id ?? null;

  const { data: existing } = await supabase.from('conversations')
    .select('id, pro_profile_id, consumer_profile_id, categorie, deleted_for')
    .eq('participant_ids', sorted).or('type.eq.direct,type.is.null').maybeSingle();
  if (existing) {
    const patch: Record<string, unknown> = {};
    if (!existing.pro_profile_id && proProfileId) patch.pro_profile_id = proProfileId;
    if (!existing.consumer_profile_id && consumerProfileId) patch.consumer_profile_id = consumerProfileId;
    if (!existing.categorie || existing.categorie === 'elevage') patch.categorie = 'contact-elevage';
    if (existing.deleted_for && Object.keys(existing.deleted_for as Record<string, unknown>).length) patch.deleted_for = {};
    if (Object.keys(patch).length) await supabase.from('conversations').update(patch).eq('id', existing.id);
    return existing.id;
  }

  const { data: me } = await supabase.from('user_profiles')
    .select('firstname, lastname, nom, avatar_url').eq('uid', myUid).eq('is_main', true).maybeSingle();
  const { data: other } = await supabase.from('user_profiles')
    .select('firstname, lastname, nom, avatar_url').eq('uid', otherUid).eq('is_main', true).maybeSingle();
  const myName = (me?.nom || `${me?.firstname ?? ''} ${me?.lastname ?? ''}`.trim()) || 'Professionnel';
  const otherName = `${other?.firstname ?? ''} ${other?.lastname ?? ''}`.trim() || (other?.nom ?? 'Utilisateur');
  const { data: created } = await supabase.from('conversations').insert({
    type: 'direct',
    participants: [myUid, otherUid],
    participant_ids: sorted,
    participants_info: {
      [myUid]: { name: myName, ...(me?.avatar_url ? { photo: me.avatar_url } : {}) },
      [otherUid]: { name: otherName, ...(other?.avatar_url ? { photo: other.avatar_url } : {}) },
    },
    last_message: '',
    unread_count: { [myUid]: 0, [otherUid]: 0 },
    updated_at: new Date().toISOString(),
    categorie: 'contact-elevage',
    ...(proProfileId ? { pro_profile_id: proProfileId } : {}),
    ...(consumerProfileId ? { consumer_profile_id: consumerProfileId } : {}),
  }).select('id').single();
  return created!.id;
}
