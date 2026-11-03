import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/server-auth';
import { admin } from '@/lib/galeries-server';
import { accesClinique } from '@/lib/liens-documents-server';

// Révocation d'un lien sécurisé : le lien n'ouvre plus le document, immédiatement.
export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const { id } = await req.json().catch(() => ({})) as { id?: string };
  if (!id) return NextResponse.json({ error: 'Lien manquant' }, { status: 400 });
  const { data: l } = await admin.from('liens_documents').select('pro_uid, pro_profile_id, revoque_le').eq('id', id).maybeSingle();
  if (!l || !(await accesClinique(auth.uid, String(l.pro_uid), (l.pro_profile_id as string | null) ?? null))) {
    return NextResponse.json({ error: 'Accès refusé' }, { status: 403 });
  }
  if (l.revoque_le) return NextResponse.json({ success: true });
  const { error } = await admin.from('liens_documents').update({ revoque_le: new Date().toISOString(), revoque_par_uid: auth.uid }).eq('id', id);
  if (error) return NextResponse.json({ error: 'Révocation impossible' }, { status: 500 });
  return NextResponse.json({ success: true });
}
