import { createClient } from '@supabase/supabase-js';
import { getDoc, doc } from 'firebase/firestore';
import { db } from '@/lib/firebase';

/** Client Supabase avec la clé service role — bypasse toutes les RLS.
 *  À n'utiliser QUE dans les routes api/admin/*, jamais côté client. */
export const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);

/** Vrai si le uid Firebase correspond à un admin (`users/{uid}.isAdmin === true`
 *  dans Firestore). L'app est en Firebase Auth : pas de JWT Supabase, donc la
 *  garde admin se fait ici, pas en RLS. */
export async function checkAdmin(uid: string | null | undefined): Promise<boolean> {
  if (!uid) return false;
  try {
    const snap = await getDoc(doc(db, 'users', uid));
    return snap.exists() && snap.data()?.isAdmin === true;
  } catch {
    return false;
  }
}
