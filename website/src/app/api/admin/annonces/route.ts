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
      uid: string; annonce_id: string; action: 'approve' | 'reject' | 'suspend' | 'restore';
    };
    if (!uid || !annonce_id || !action) {
      return NextResponse.json({ error: 'Paramètres manquants' }, { status: 400 });
    }
    if (!(await checkAdmin(uid))) {
      return NextResponse.json({ error: 'Non autorisé' }, { status: 403 });
    }

    const statut =
      action === 'approve'  ? 'disponible' :
      action === 'reject'   ? 'refuse'     :
      action === 'suspend'  ? 'suspendu'   :
      action === 'restore'  ? 'disponible' : 'refuse';

    const update: Record<string, unknown> = { statut };
    if (action === 'restore') update.is_suspect = false;

    const { error } = await supabaseAdmin.from('annonces').update(update).eq('id', annonce_id);
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });

    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error('[admin/annonces]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}

// GET /api/admin/annonces?type=suspectes|suspendues — lister les annonces à modérer
export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  const type = searchParams.get('type') ?? 'suspectes';

  let query = supabaseAdmin.from('annonces')
    .select('id, titre, espece, race, uid_eleveur, nom_eleveur, created_at, photos, type_vente, is_suspect, suspect_reasons, statut, vues, prix, prix_min_portee')
    .order('created_at', { ascending: false })
    .limit(100);

  if (type === 'suspectes') {
    query = query.eq('is_suspect', true).in('statut', ['disponible', 'en_attente', 'pause']);
  } else if (type === 'suspendues') {
    query = query.in('statut', ['suspendu', 'refuse']);
  }

  const { data, error } = await query;
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ annonces: data ?? [] });
}
