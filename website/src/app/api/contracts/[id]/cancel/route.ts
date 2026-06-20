import { NextRequest, NextResponse } from 'next/server';
import { ContractService } from '@/lib/ContractService';
import { supabase } from '@/lib/supabase';

export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const { reason, actorUid } = await req.json().catch(() => ({}));

  // Vérifier que le document existe et récupérer le token
  const { data: doc, error } = await supabase
    .from('documents_animaux')
    .select('id, token, statut, uid_eleveur')
    .eq('id', id)
    .single();

  if (error || !doc) {
    return NextResponse.json({ error: 'Document introuvable' }, { status: 404 });
  }

  if (['signe', 'annule', 'expire'].includes(doc.statut)) {
    return NextResponse.json({ error: `Impossible d'annuler un contrat en statut "${doc.statut}"` }, { status: 400 });
  }

  const service = new ContractService();
  await service.cancel(doc.id, doc.token, reason);

  if (actorUid) {
    await supabase.rpc('log_contract_action', {
      p_document_id: doc.id,
      p_action:      'cancelled',
      p_actor_uid:   actorUid,
      p_actor_role:  'eleveur',
      p_details:     reason ? { reason } : {},
    });
  }

  return NextResponse.json({ success: true });
}
