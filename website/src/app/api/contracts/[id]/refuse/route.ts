import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const { reason, actorEmail } = await req.json().catch(() => ({}));

  const { data: doc, error } = await supabase
    .from('documents_animaux')
    .select('id, statut, type, metadata')
    .eq('id', id)
    .single();

  if (error || !doc) return NextResponse.json({ error: 'Document introuvable' }, { status: 404 });
  if (['signe', 'annule', 'refuse'].includes(doc.statut)) {
    return NextResponse.json({ error: `Impossible de refuser un contrat en statut "${doc.statut}"` }, { status: 400 });
  }

  await supabase.from('documents_animaux').update({
    statut: 'refuse',
    rejection_reason: reason ?? null,
  }).eq('id', id);

  await supabase.rpc('log_contract_action', {
    p_document_id: id,
    p_action:      'refused',
    p_actor_email: actorEmail ?? null,
    p_actor_role:  'acquereur',
    p_details:     reason ? { reason } : {},
  });

  // Devis d'éducation lié : le refus du contrat vaut refus du devis.
  if (doc.type === 'contrat_education') {
    const devisId = (doc.metadata as Record<string, unknown> | null)?.devis_id as string | undefined;
    if (devisId) {
      try {
        await supabase.from('devis')
          .update({ statut: 'refuse', date_reponse: new Date().toISOString() })
          .eq('id', devisId).eq('statut', 'envoye');
      } catch { /* best-effort */ }
    }
  }

  return NextResponse.json({ success: true });
}
