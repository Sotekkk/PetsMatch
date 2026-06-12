import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { uid, ...fields } = body;
    if (!uid) return NextResponse.json({ error: 'uid requis' }, { status: 400 });

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
