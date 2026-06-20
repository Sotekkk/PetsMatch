import { NextRequest, NextResponse } from 'next/server';
import { supabase } from '@/lib/supabase';

export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const { reason, actorEmail } = await req.json().catch(() => ({}));

  const { data: doc, error } = await supabase
    .from('documents_animaux')
    .select('id, statut')
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

  return NextResponse.json({ success: true });
}
