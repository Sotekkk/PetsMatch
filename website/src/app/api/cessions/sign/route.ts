import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

export async function POST(req: NextRequest) {
  try {
    const { token, signature } = await req.json() as { token: string; signature: string };
    if (!token || !signature) {
      return NextResponse.json({ error: 'token et signature requis' }, { status: 400 });
    }

    const { data: cession } = await supabase
      .from('cessions')
      .select('id, animal_id, uid_eleveur, nom_acquereur, signature_acquereur')
      .eq('token', token)
      .maybeSingle();

    if (!cession) return NextResponse.json({ error: 'Lien invalide ou expiré' }, { status: 404 });
    if (cession.signature_acquereur) {
      return NextResponse.json({ error: 'Cette cession a déjà été signée' }, { status: 400 });
    }

    const nowIso = new Date().toISOString();

    const { error } = await supabase
      .from('cessions')
      .update({
        signature_acquereur: signature,
        statut: 'signe_acquereur',
        signed_acquereur_at: nowIso,
      })
      .eq('id', cession.id)
      .is('signature_acquereur', null);

    if (error) return NextResponse.json({ error: error.message }, { status: 500 });

    try {
      const { data: animal } = await supabase.from('animaux').select('nom').eq('id', cession.animal_id).maybeSingle();
      if (cession.uid_eleveur) {
        const { data: eleveurProfile } = await supabase.from('user_profiles')
          .select('id').eq('uid', cession.uid_eleveur).eq('profile_type', 'eleveur').maybeSingle();
        await supabase.from('notifications').insert({
          uid: cession.uid_eleveur,
          type: 'cession_signee_acquereur',
          title: `✍️ ${cession.nom_acquereur} a signé — ${animal?.nom ?? 'Animal'}`,
          body: `L'acquéreur a signé le contrat de cession. Vous pouvez maintenant confirmer le transfert.`,
          ...(eleveurProfile?.id ? { profile_id: eleveurProfile.id } : {}),
          data: { animalId: cession.animal_id, token },
          read: false,
        });
      }
    } catch { /* notif best-effort */ }

    return NextResponse.json({ ok: true, signed_acquereur_at: nowIso });
  } catch (err) {
    console.error('[cessions/sign]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
