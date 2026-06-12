import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

export async function POST(req: NextRequest) {
  try {
    const { token, action } = await req.json() as { token: string; action: 'signe' | 'refuse' | 'lu' };
    if (!token || !action) return NextResponse.json({ error: 'token et action requis' }, { status: 400 });

    const { data: cert } = await supabase
      .from('certificats_engagement')
      .select('id, statut, date_limite_signature, espece')
      .eq('token_signature', token)
      .maybeSingle();

    if (!cert) return NextResponse.json({ error: 'Certificat introuvable' }, { status: 404 });
    if (cert.statut === 'signe' || cert.statut === 'refuse') {
      return NextResponse.json({ error: 'Certificat déjà traité' }, { status: 400 });
    }

    // Vérifier le délai légal pour chien/chat
    if (action === 'signe' && cert.date_limite_signature) {
      const now = new Date();
      const limite = new Date(cert.date_limite_signature);
      if (now < limite) {
        const jours = Math.ceil((limite.getTime() - now.getTime()) / 86400_000);
        return NextResponse.json({
          error: `Délai légal non écoulé. Signature possible dans ${jours} jour(s) (${limite.toLocaleDateString('fr-FR')}).`,
          code: 'DELAI_NON_ECOULE',
        }, { status: 400 });
      }
    }

    const update: Record<string, unknown> = { statut: action, updated_at: new Date().toISOString() };
    if (action === 'signe') update.date_signature_acquereur = new Date().toISOString();
    if (action === 'lu' && cert.statut === 'envoye') update.statut = 'lu';

    const { error } = await supabase
      .from('certificats_engagement')
      .update(update)
      .eq('token_signature', token);

    if (error) return NextResponse.json({ error: error.message }, { status: 500 });

    return NextResponse.json({ ok: true, statut: action });
  } catch (err) {
    console.error('[certificat/sign]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
