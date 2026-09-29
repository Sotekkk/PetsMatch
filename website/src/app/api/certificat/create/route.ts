import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { requireUser } from '@/lib/server-auth';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

export async function POST(req: NextRequest) {
  try {
    // Cédant = appelant (jeton Firebase vérifié), jamais un uid du corps ;
    // les colonnes d'identité / de sécurité ne sont pas fixables par le client.
    const auth = await requireUser(req);
    if (auth instanceof NextResponse) return auth;
    const uid = auth.uid;
    const body = await req.json();
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const { uid: _ignored, id: _id, cedant_uid: _c, token_signature: _t, ...fields } = body;

    const { data, error } = await supabase
      .from('certificats_engagement')
      .insert({ cedant_uid: uid, ...fields })
      .select()
      .single();

    if (error) return NextResponse.json({ error: error.message }, { status: 500 });

    return NextResponse.json({ ok: true, token: data.token_signature, certificat: data });
  } catch (err) {
    console.error('[certificat/create]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
