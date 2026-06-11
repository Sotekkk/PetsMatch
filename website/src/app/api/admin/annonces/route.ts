import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { getDoc, doc } from 'firebase/firestore';
import { db } from '@/lib/firebase';

const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

async function checkAdmin(uid: string): Promise<boolean> {
  try {
    const snap = await getDoc(doc(db, 'users', uid));
    return snap.exists() && snap.data()?.isAdmin === true;
  } catch { return false; }
}

export async function POST(req: NextRequest) {
  try {
    const { uid, annonce_id, action } = await req.json() as {
      uid: string; annonce_id: string; action: 'approve' | 'reject';
    };
    if (!uid || !annonce_id || !action) {
      return NextResponse.json({ error: 'Paramètres manquants' }, { status: 400 });
    }
    if (!(await checkAdmin(uid))) {
      return NextResponse.json({ error: 'Non autorisé' }, { status: 403 });
    }

    const statut = action === 'approve' ? 'disponible' : 'refuse';
    const { error } = await supabaseAdmin.from('annonces').update({ statut }).eq('id', annonce_id);
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });

    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error('[admin/annonces]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
