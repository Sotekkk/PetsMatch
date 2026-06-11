import { NextRequest, NextResponse } from 'next/server';
import Stripe from 'stripe';
import { stripe } from '@/lib/stripe';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

export async function POST(req: NextRequest) {
  const body = await req.text();
  const sig = req.headers.get('stripe-signature');
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;

  if (!sig || !webhookSecret) {
    return NextResponse.json({ error: 'Webhook secret manquant' }, { status: 400 });
  }

  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(body, sig, webhookSecret);
  } catch (err) {
    console.error('[webhook] Signature invalide:', err);
    return NextResponse.json({ error: 'Signature invalide' }, { status: 400 });
  }

  try {
    switch (event.type) {

      // ── Checkout terminé (abonnement ou paiement ponctuel) ────────────────
      case 'checkout.session.completed': {
        const session = event.data.object as Stripe.Checkout.Session;
        const uid = session.metadata?.uid;
        if (!uid) break;

        if (session.mode === 'subscription' && session.subscription) {
          const plan = session.metadata?.plan ?? 'pro';
          const periodicite = session.metadata?.periodicite ?? 'mensuel';
          const subId = typeof session.subscription === 'string' ? session.subscription : session.subscription.id;

          const sub = await stripe.subscriptions.retrieve(subId, { expand: ['items'] });
          const periodEnd = sub.items.data[0]?.current_period_end ?? null;
          const dateFin = periodEnd ? new Date(periodEnd * 1000).toISOString() : null;

          // Désactiver l'ancien abonnement actif avant d'insérer le nouveau
          await supabase.from('abonnements')
            .update({ statut: 'annule', updated_at: new Date().toISOString() })
            .eq('uid', uid).eq('statut', 'actif');

          await supabase.from('abonnements').insert({
            uid,
            profil_type: 'eleveur',
            plan_code: plan,
            periodicite,
            statut: 'actif',
            stripe_subscription_id: subId,
            stripe_customer_id: typeof session.customer === 'string' ? session.customer : session.customer?.id,
            date_debut: new Date().toISOString(),
            date_fin: dateFin,
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          });

          await supabase.from('users').update({
            plan_code: plan,
            is_premium: plan === 'premium',
          }).eq('uid', uid);
        }

        if (session.mode === 'payment') {
          const { produit_code, annonce_id } = session.metadata ?? {};
          if (produit_code) {
            const { data: produit } = await supabase.from('produits_ponctuels').select('id, duree_heures').eq('code', produit_code).maybeSingle();
            if (produit) {
              const expiration = produit.duree_heures
                ? new Date(Date.now() + produit.duree_heures * 3600_000).toISOString()
                : null;
              await supabase.from('achats_ponctuels').insert({
                uid, produit_id: produit.id, annonce_id: annonce_id || null,
                stripe_payment_intent_id: typeof session.payment_intent === 'string' ? session.payment_intent : null,
                statut: 'paye', date_expiration: expiration,
              });
              if (annonce_id && expiration) {
                await supabase.from('annonces').update({ boost_until: expiration }).eq('id', annonce_id);
              }
            }
          }
        }
        break;
      }

      // ── Abonnement renouvelé ───────────────────────────────────────────────
      case 'customer.subscription.updated': {
        const sub = event.data.object as Stripe.Subscription;
        const periodEnd = sub.items.data[0]?.current_period_end ?? null;
        const dateFin = periodEnd ? new Date(periodEnd * 1000).toISOString() : null;
        const statut = sub.status === 'active' ? 'actif' : sub.status === 'past_due' ? 'grace' : 'annule';
        await supabase.from('abonnements')
          .update({ statut, date_fin: dateFin, updated_at: new Date().toISOString() })
          .eq('stripe_subscription_id', sub.id);
        break;
      }

      // ── Abonnement annulé ─────────────────────────────────────────────────
      case 'customer.subscription.deleted': {
        const sub = event.data.object as Stripe.Subscription;
        const uid = sub.metadata?.uid;
        await supabase.from('abonnements')
          .update({ statut: 'annule', updated_at: new Date().toISOString() })
          .eq('stripe_subscription_id', sub.id);
        if (uid) {
          await supabase.from('users').update({ plan_code: 'free', is_premium: false }).eq('uid', uid);
        }
        break;
      }
    }
  } catch (err) {
    console.error('[webhook] Erreur traitement event:', event.type, err);
  }

  return NextResponse.json({ received: true });
}
