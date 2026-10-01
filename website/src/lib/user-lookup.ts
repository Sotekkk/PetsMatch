// Recherche d'utilisateurs sans exposer les e-mails / téléphones des autres.
//
// La vue `users_complet` masque l'e-mail de connexion et le téléphone d'un
// particulier : un filtre `.eq('email', …)` dessus ne trouve donc plus
// personne. La correspondance passe par la fonction SQL
// `pm_trouver_utilisateur` : e-mail / téléphone EXACTS uniquement, identité
// publique seulement. Plus de recherche « contient » sur les e-mails (qui
// permettait de les énumérer) : avec un « @ » → e-mail exact ; sinon → nom.
import { supabase } from '@/lib/supabase';

export interface UtilisateurTrouve {
  uid: string;
  firstname: string | null;
  lastname: string | null;
  name_elevage: string | null;
  profile_picture_url: string | null;
  is_elevage: boolean | null;
  is_pro: boolean | null;
  is_association: boolean | null;
  /** E-mail cherché (renvoyé seulement pour une recherche par e-mail). */
  email?: string;
}

/** Utilisateur dont l'e-mail est exactement `email` (casse indifférente), ou null. */
export async function trouverUtilisateurParEmail(email: string): Promise<UtilisateurTrouve | null> {
  const e = email.trim();
  if (!e) return null;
  const { data } = await supabase.rpc('pm_trouver_utilisateur', { p_email: e });
  const first = (data as UtilisateurTrouve[] | null)?.[0];
  return first ? { ...first, email: e.toLowerCase() } : null;
}

/** Recherche pendant la frappe : e-mail exact si « @ », sinon prénom / nom / élevage. */
export async function rechercherUtilisateurs(
  query: string,
  opts: { exclureUid?: string; limit?: number } = {},
): Promise<UtilisateurTrouve[]> {
  const q = query.trim();
  if (!q) return [];
  if (q.includes('@')) {
    const u = await trouverUtilisateurParEmail(q);
    return u && u.uid !== opts.exclureUid ? [u] : [];
  }
  const safe = q.replace(/[,()%*]/g, ' ');
  let req = supabase.from('users_complet')
    .select('uid, firstname, lastname, name_elevage, profile_picture_url, is_elevage, is_pro, is_association')
    .or(`firstname.ilike.%${safe}%,lastname.ilike.%${safe}%,name_elevage.ilike.%${safe}%`);
  if (opts.exclureUid) req = req.neq('uid', opts.exclureUid);
  const { data } = await req.limit(opts.limit ?? 6);
  return (data ?? []) as UtilisateurTrouve[];
}
