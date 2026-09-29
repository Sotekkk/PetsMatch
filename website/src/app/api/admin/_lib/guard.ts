import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { getDoc, doc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { requireUser } from '@/lib/server-auth';

/** Client Supabase avec la clé service role — bypasse toutes les RLS.
 *  À n'utiliser QUE dans les routes api/admin/*, jamais côté client. */
export const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);

/** Garde des routes admin : jeton Firebase vérifié (lib/server-auth.ts) PUIS
 *  statut admin de CET uid. Ne jamais appeler checkAdmin() avec un uid venu
 *  de la requête — c'était la faille (uid d'un admin = accès admin complet).
 *   const auth = await requireAdmin(req);
 *   if (auth instanceof NextResponse) return auth; */
export async function requireAdmin(req: NextRequest): Promise<{ uid: string } | NextResponse> {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  if (!(await checkAdmin(auth.uid))) {
    return NextResponse.json({ error: 'Non autorisé' }, { status: 403 });
  }
  return auth;
}

/** Vrai si le uid Firebase correspond à un admin (`users/{uid}.isAdmin === true`
 *  dans Firestore). L'app est en Firebase Auth : pas de JWT Supabase, donc la
 *  garde admin se fait ici, pas en RLS. uid = TOUJOURS un uid vérifié. */
export async function checkAdmin(uid: string | null | undefined): Promise<boolean> {
  if (!uid) return false;
  try {
    const snap = await getDoc(doc(db, 'users', uid));
    return snap.exists() && snap.data()?.isAdmin === true;
  } catch {
    return false;
  }
}
