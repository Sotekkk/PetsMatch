import { NextRequest, NextResponse } from 'next/server';
import { stripe } from '@/lib/stripe';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

export async function POST(req: NextRequest) {
  try {
    const { sessionId, uid } = await req.json();
    if (!sessionId || !uid) {
      return NextResponse.json({ error: 'sessionId et uid requis' }, { status: 400 });
    }

    // Vérifier la session Stripe côté serveur
    const session = await stripe.checkout.sessions.retrieve(sessionId, {
      expand: ['subscription', 'subscription.items'],
    });

    if (session.payment_status !== 'paid' && session.status !== 'complete') {
      return NextResponse.json({ error: 'Session non complète' }, { status: 400 });
    }

    // Vérifier que l'uid correspond bien à celui de la session
    if (session.metadata?.uid !== uid) {
      return NextResponse.json({ error: 'uid invalide' }, { status: 403 });
    }

    if (session.mode !== 'subscription' || !session.subscription) {
      return NextResponse.json({ ok: true, skipped: true });
    }

    const plan = session.metadata?.plan ?? 'pro';
    const periodicite = session.metadata?.periodicite ?? 'mensuel';
    const profileId = session.metadata?.profile_id ?? null;
    const profilType = session.metadata?.profil_type ?? 'eleveur';
    const sub = session.subscription as import('stripe').Stripe.Subscription & {
      items: { data: Array<{ current_period_end: number }> };
    };
    const subId = sub.id;
    const periodEnd = sub.items.data[0]?.current_period_end ?? null;
    const dateFin = periodEnd ? new Date(periodEnd * 1000).toISOString() : null;
    const customerId = typeof session.customer === 'string' ? session.customer : (session.customer as { id: string })?.id ?? null;

    // Si cet abonnement Stripe est déjà enregistré et actif → idempotent
    const { data: existing } = await supabase
      .from('abonnements').select('plan_code').eq('stripe_subscription_id', subId).eq('statut', 'actif').maybeSingle();
    if (existing) return NextResponse.json({ ok: true, plan: existing.plan_code });

    // Désactiver les anciens abonnements actifs pour ce profil — scopé par profil_type
    // pour ne pas annuler un abonnement éleveur en activant un abonnement pension (et
    // inversement) sur le même compte.
    const cancelQ = supabase.from('abonnements').update({ statut: 'annule', updated_at: new Date().toISOString() })
      .eq('uid', uid).eq('statut', 'actif').eq('profil_type', profilType);
    if (profileId) await cancelQ.eq('profile_id', profileId);
    else await cancelQ;

    // Insérer le nouvel abonnement
    const { error: insertErr } = await supabase.from('abonnements').insert({
      uid,
      profile_id: profileId,
      profil_type: profilType,
      plan_code: plan,
      periodicite,
      statut: 'actif',
      stripe_subscription_id: subId,
      stripe_customer_id: customerId,
      date_debut: new Date().toISOString(),
      date_fin: dateFin,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    });

    if (insertErr) {
      console.error('[activate] insert error:', insertErr);
      return NextResponse.json({ error: insertErr.message }, { status: 500 });
    }

    // Mettre à jour user_profiles pour le profil concerné
    if (profileId) {
      await supabase.from('user_profiles').update({
        plan_code: plan, is_premium: plan === 'premium', plan_until: dateFin,
      }).eq('id', profileId);
    } else {
      await supabase.from('user_profiles').update({
        plan_code: plan, is_premium: plan === 'premium', plan_until: dateFin,
      }).eq('uid', uid).eq('is_main', true);
    }

    // Sync users table
    await supabase.from('users').update({
      plan_code: plan,
      is_premium: plan === 'premium',
      stripe_customer_id: customerId,
    }).eq('uid', uid);

    return NextResponse.json({ ok: true, plan });
  } catch (err) {
    console.error('[stripe/activate]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
