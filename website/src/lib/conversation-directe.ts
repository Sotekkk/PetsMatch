// Ouvre (ou crée) une conversation directe entre MON profil (actif, sinon
// principal) et le profil contacté (sinon son profil principal), dans la
// messagerie Supabase. Une conversation relie deux profils précis.
// Miroir appli : MessagingHelper.openOrCreateConversation (lib/utils/messaging_helper.dart).
import { supabase } from '@/lib/supabase';

type Info = { firstname?: string | null; lastname?: string | null; nom?: string | null; profile_type?: string | null; avatar_url?: string | null };

function nomAffiche(p?: Info | null): string {
  if (!p) return 'Utilisateur';
  const perso = `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim();
  return (p.profile_type && p.profile_type !== 'particulier' && p.nom?.trim()) || perso || p.nom || 'Utilisateur';
}

async function profil(uid: string, profileId: string | null): Promise<(Info & { id: string }) | null> {
  const q = supabase.from('user_profiles_complet').select('id, firstname, lastname, nom, profile_type, avatar_url').eq('uid', uid);
  const { data } = profileId ? await q.eq('id', profileId).maybeSingle() : await q.eq('is_main', true).maybeSingle();
  return (data as (Info & { id: string }) | null) ?? null;
}

export async function ouvrirConversationDirecte({ myUid, myProfileId, otherUid, otherProfileId, categorie }: {
  myUid: string; myProfileId?: string | null; otherUid: string; otherProfileId?: string | null; categorie?: string;
}): Promise<string> {
  const sorted = [myUid, otherUid].sort().join('_');
  const [moi, autre] = await Promise.all([profil(myUid, myProfileId ?? null), profil(otherUid, otherProfileId ?? null)]);
  const monId = moi?.id ?? myProfileId ?? null;
  const sonId = autre?.id ?? otherProfileId ?? null;

  let q = supabase.from('conversations').select('id, deleted_for').eq('participant_ids', sorted).eq('type', 'direct');
  if (monId && sonId) {
    q = q.or(`and(pro_profile_id.eq.${monId},consumer_profile_id.eq.${sonId}),and(pro_profile_id.eq.${sonId},consumer_profile_id.eq.${monId})`);
  } else if (monId) {
    q = q.or(`pro_profile_id.eq.${monId},consumer_profile_id.eq.${monId}`);
  }
  const { data: existante } = await q.limit(1).maybeSingle();
  if (existante) {
    if (existante.deleted_for && Object.keys(existante.deleted_for as Record<string, unknown>).length) {
      await supabase.from('conversations').update({ deleted_for: {} }).eq('id', existante.id);
    }
    return existante.id as string;
  }

  const { data: creee, error } = await supabase.from('conversations').insert({
    type: 'direct',
    participants: [myUid, otherUid],
    participant_ids: sorted,
    participants_info: {
      [myUid]: { name: nomAffiche(moi), ...(moi?.avatar_url ? { photo: moi.avatar_url } : {}) },
      [otherUid]: { name: nomAffiche(autre), ...(autre?.avatar_url ? { photo: autre.avatar_url } : {}) },
    },
    last_message: '',
    unread_count: { [myUid]: 0, [otherUid]: 0 },
    updated_at: new Date().toISOString(),
    ...(categorie ? { categorie } : {}),
    ...(monId ? { pro_profile_id: monId } : {}),
    ...(sonId ? { consumer_profile_id: sonId } : {}),
  }).select('id').single();
  if (error || !creee) throw error ?? new Error('Création de la conversation impossible');
  return creee.id as string;
}
