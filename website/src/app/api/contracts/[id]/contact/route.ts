import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

// Correction des coordonnées de l'acquéreur par lui-même (lien token, pas
// forcément connecté) — cf. signer-contrat/[token]/page.tsx.
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const { nom, prenom, adresse, tel } = await req.json() as {
      nom?: string; prenom?: string; adresse?: string; tel?: string;
    };

    const { data: doc } = await supabase
      .from('documents_animaux')
      .select('id, statut, metadata')
      .eq('id', id)
      .maybeSingle();
    if (!doc) return NextResponse.json({ error: 'Contrat introuvable' }, { status: 404 });
    if (['signe', 'annule', 'refuse', 'expire'].includes(doc.statut)) {
      return NextResponse.json({ error: `Contrat déjà ${doc.statut}` }, { status: 400 });
    }

    const newMeta = {
      ...(doc.metadata ?? {}),
      acquereur_nom: (nom ?? '').trim(),
      acquereur_prenom: (prenom ?? '').trim(),
      acquereur_adresse: (adresse ?? '').trim(),
      acquereur_tel: (tel ?? '').trim(),
    };

    const { error } = await supabase.from('documents_animaux').update({ metadata: newMeta }).eq('id', doc.id);
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });

    return NextResponse.json({ ok: true, metadata: newMeta });
  } catch (err) {
    console.error('[contracts/contact]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
