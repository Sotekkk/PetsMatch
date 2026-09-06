import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

export async function POST(req: NextRequest) {
  try {
    const { token, action, signature, signataire_nom } = await req.json() as {
      token: string;
      action: 'signe' | 'refuse' | 'lu';
      signature?: string;      // data-URL PNG du tracé (action 'signe')
      signataire_nom?: string;
    };
    if (!token || !action) return NextResponse.json({ error: 'token et action requis' }, { status: 400 });

    const { data: cert } = await supabase
      .from('certificats_engagement')
      .select('id, cedant_uid, nom_animal, statut, date_limite_signature, acquereur_prenom, acquereur_nom')
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

    if (action === 'signe' && !signature) {
      return NextResponse.json({ error: 'Signature requise' }, { status: 400 });
    }

    const nowIso = new Date().toISOString();
    const update: Record<string, unknown> = { statut: action, updated_at: nowIso };
    if (action === 'signe') {
      update.date_signature_acquereur = nowIso;
      update.signe_le = nowIso;
      update.signature_acquereur = signature;
      if (signataire_nom) update.signataire_nom = signataire_nom;
    }
    if (action === 'lu' && cert.statut === 'envoye') update.statut = 'lu';

    const { error } = await supabase
      .from('certificats_engagement')
      .update(update)
      .eq('token_signature', token);

    if (error) return NextResponse.json({ error: error.message }, { status: 500 });

    // Notifier le cédant à la signature.
    if (action === 'signe' && cert.cedant_uid) {
      try {
        const { data: prof } = await supabase.from('user_profiles')
          .select('id').eq('uid', cert.cedant_uid).eq('is_main', true).maybeSingle();
        const who = (signataire_nom
          || `${cert.acquereur_prenom ?? ''} ${cert.acquereur_nom ?? ''}`.trim()
          || "L'acquéreur");
        await supabase.from('notifications').insert({
          uid: cert.cedant_uid,
          type: 'certificat_signe',
          title: `✅ Certificat d'engagement signé — ${cert.nom_animal ?? 'Animal'}`,
          body: `${who} a signé le certificat d'engagement.`,
          ...(prof?.id ? { profile_id: prof.id } : {}),
          data: { token, url: `https://www.petsmatchapp.com/certificat/${token}` },
          read: false,
        });
      } catch { /* notif best-effort */ }
    }

    return NextResponse.json({ ok: true, statut: action });
  } catch (err) {
    console.error('[certificat/sign]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
