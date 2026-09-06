import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

const SITE = 'https://www.petsmatchapp.com';

/// Transmet un certificat d'engagement au futur propriétaire :
/// notification in-app s'il a un compte PetsMatch + e-mail.
export async function POST(req: NextRequest) {
  try {
    const { token } = await req.json() as { token: string };
    if (!token) return NextResponse.json({ error: 'token requis' }, { status: 400 });

    const { data: cert } = await supabase
      .from('certificats_engagement')
      .select('id, nom_animal, acquereur_uid, acquereur_email')
      .eq('token_signature', token)
      .maybeSingle();
    if (!cert) return NextResponse.json({ error: 'Certificat introuvable' }, { status: 404 });

    const url = `${SITE}/certificat/${token}`;
    const animal = cert.nom_animal || 'Animal';
    const email = (cert.acquereur_email as string | null)?.trim() || null;

    // Résoudre l'uid de l'acquéreur.
    let acqUid = cert.acquereur_uid as string | null;
    if (!acqUid && email) {
      const { data: u } = await supabase.from('users').select('uid').eq('email', email.toLowerCase()).maybeSingle();
      acqUid = (u?.uid as string) ?? null;
      if (acqUid) {
        await supabase.from('certificats_engagement').update({ acquereur_uid: acqUid }).eq('id', cert.id);
      }
    }

    let notified = false;
    if (acqUid) {
      const { data: prof } = await supabase.from('user_profiles')
        .select('id').eq('uid', acqUid).eq('is_main', true).maybeSingle();
      await supabase.from('notifications').insert({
        uid: acqUid,
        type: 'certificat_a_signer',
        title: `📋 Certificat d'engagement à signer — ${animal}`,
        body: "Le cédant vous transmet le certificat d'engagement et de connaissance à lire et signer.",
        ...(prof?.id ? { profile_id: prof.id } : {}),
        data: { token, url },
        read: false,
      });
      notified = true;
    }

    let emailed = false;
    if (email) {
      try {
        const r = await fetch(`${SITE}/api/certificat/notify-email`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email, animal_nom: animal, signing_url: url }),
        });
        emailed = r.ok;
      } catch { /* best-effort */ }
    }

    return NextResponse.json({ ok: true, notified, emailed });
  } catch (err) {
    console.error('[certificat/send]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
