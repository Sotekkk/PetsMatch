import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

export async function POST(req: NextRequest) {
  try {
    const { token, statut } = await req.json() as { token: string; statut: 'accepte' | 'refuse' };
    if (!token || (statut !== 'accepte' && statut !== 'refuse')) {
      return NextResponse.json({ error: 'token et statut (accepte|refuse) requis' }, { status: 400 });
    }

    const { data: devis } = await supabase
      .from('devis')
      .select('id, pro_uid, pro_profile_id, animal_id, nom_client, prenom_client, total_ttc, statut')
      .eq('token_acceptation', token)
      .maybeSingle();

    if (!devis) return NextResponse.json({ error: 'Devis introuvable' }, { status: 404 });
    if (devis.statut !== 'envoye') {
      return NextResponse.json({ error: 'Ce devis a déjà été traité' }, { status: 400 });
    }

    const nowIso = new Date().toISOString();

    const { error } = await supabase
      .from('devis')
      .update({ statut, date_reponse: nowIso, updated_at: nowIso })
      .eq('id', devis.id)
      .eq('statut', 'envoye');

    if (error) return NextResponse.json({ error: error.message }, { status: 500 });

    try {
      await supabase.from('notifications').insert({
        uid: devis.pro_uid,
        type: statut === 'accepte' ? 'devis_accepte' : 'devis_refuse',
        title: statut === 'accepte' ? 'Devis accepté' : 'Devis refusé',
        body: `${devis.prenom_client ?? ''} ${devis.nom_client} a ${statut === 'accepte' ? 'accepté' : 'refusé'} le devis de ${Number(devis.total_ttc).toFixed(2)} €.`,
        ...(devis.pro_profile_id ? { profile_id: devis.pro_profile_id } : {}),
        data: { devis_id: devis.id },
        read: false,
      });
    } catch { /* notif best-effort */ }

    if (devis.animal_id) {
      try {
        const docStatut = statut === 'accepte' ? 'signe' : 'refuse';
        const { data: existing } = await supabase.from('documents_animaux').select('id')
          .eq('animal_id', devis.animal_id).eq('type', 'devis').contains('metadata', { devis_id: devis.id }).maybeSingle();
        if (existing) await supabase.from('documents_animaux').update({ statut: docStatut }).eq('id', existing.id);
      } catch { /* best-effort */ }
    }

    return NextResponse.json({ ok: true, statut, date_reponse: nowIso });
  } catch (err) {
    console.error('[devis/respond]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
