// Messagerie multi-profil : à quel profil du compte appartient une conversation ?
// Chaque côté est marqué par un profil (pro_profile_id = celui qui a ouvert la
// conversation, consumer_profile_id = le destinataire). Un côté non marqué
// (anciennes conversations, destinataire inconnu) revient au profil PRINCIPAL
// de ce participant. Même règle pour la liste et la bulle de messages non lus.
// Miroir appli : MessagingHelper.visiblePourProfilActif (lib/utils/messaging_helper.dart).

export interface ProfilCompte { id: string; is_main?: boolean | null; uid?: string | null }

/** Seuls MES profils comptent (la liste du compte contient aussi les profils
 *  partagés en cogérance / par un employeur). */
export function profilsPropres(profils: ProfilCompte[], monUid?: string | null): ProfilCompte[] {
  return monUid ? profils.filter(p => !p.uid || p.uid === monUid) : profils;
}

export function profilPrincipal(profils: ProfilCompte[]): string {
  return (profils.find(p => p.is_main) ?? profils[0])?.id ?? '';
}

/** Mon profil dans la conversation (marqué, sinon mon profil principal). */
export function monProfilDansConversation(
  conv: { pro_profile_id?: string | null; consumer_profile_id?: string | null },
  profils: ProfilCompte[],
): string {
  const miens = new Set(profils.map(p => p.id));
  if (conv.pro_profile_id && miens.has(conv.pro_profile_id)) return conv.pro_profile_id;
  if (conv.consumer_profile_id && miens.has(conv.consumer_profile_id)) return conv.consumer_profile_id;
  return '';
}

/** La conversation s'affiche-t-elle dans la messagerie du profil actif ('' = principal) ? */
export function conversationVisible(
  conv: { type?: string | null; pro_profile_id?: string | null; consumer_profile_id?: string | null },
  profilActif: string | null | undefined,
  profils: ProfilCompte[],
): boolean {
  if (conv.type === 'groupe') return true;
  if (!profils.length) return true;
  const actif = profilActif || profilPrincipal(profils);
  // Mon côté (profil que je possède), sinon le profil partagé actif s'il est
  // dans la conversation (cogérance), sinon mon profil principal.
  const mien = monProfilDansConversation(conv, profils)
    || (actif && (conv.pro_profile_id === actif || conv.consumer_profile_id === actif) ? actif : profilPrincipal(profils));
  return mien === actif;
}
