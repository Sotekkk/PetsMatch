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

  const isGerant = actorUid && actorUid === doc.uid_eleveur;
  let isCogerant = false;
  if (!isGerant && actorUid) {
    const { data: cog } = await supabase.from('elevage_cogerants').select('id')
      .eq('uid_gerant', doc.uid_eleveur).eq('uid_cogerant', actorUid)
      .eq('statut', 'actif').is('date_fin', null).maybeSingle();
    isCogerant = !!cog;
  }
  if (!isGerant && !isCogerant) {
    return NextResponse.json({ error: 'Non autorisé à annuler ce contrat' }, { status: 403 });
  }

  const now = new Date().toISOString();
  await supabase.from('documents_animaux').update({
    statut: 'annule',
    cancelled_at: now,
    ...(reason ? { rejection_reason: reason } : {}),
  }).eq('id', doc.id);

  await supabase.rpc('log_contract_action', {
    p_document_id: doc.id,
    p_action:      'cancelled',
    p_actor_uid:   actorUid,
    p_actor_role:  'eleveur',
    p_details:     reason ? { reason } : {},
  });

  return NextResponse.json({ success: true });
}
