import { NextRequest, NextResponse } from 'next/server';
import { stripe, STRIPE_PRICES } from '@/lib/stripe';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

export async function POST(req: NextRequest) {
  try {
    const { uid, email, plan, periodicite, annonce_id, produit_code } = await req.json();
    if (!uid || !email) return NextResponse.json({ error: 'uid et email requis' }, { status: 400 });

    const origin = req.headers.get('origin') ?? process.env.NEXT_PUBLIC_SITE_URL ?? 'http://localhost:3000';

    // ── Abonnement récurrent ──────────────────────────────────────────────────
    if (plan && periodicite) {
      const priceId = STRIPE_PRICES[plan]?.[periodicite as 'mensuel' | 'annuel'];
      if (!priceId || priceId.startsWith('price_REMPLACER')) {
        return NextResponse.json({ error: 'Price ID Stripe non configuré. Créez les produits dans le dashboard Stripe et renseignez les variables STRIPE_PRICE_* dans .env.local.' }, { status: 503 });
      }

      // Récupérer ou créer le customer Stripe
      const { data: userData } = await supabase.from('users').select('stripe_customer_id').eq('uid', uid).maybeSingle();
      let customerId = userData?.stripe_customer_id as string | undefined;

      if (!customerId) {
        const customer = await stripe.customers.create({ email, metadata: { uid } });
        customerId = customer.id;
        await supabase.from('users').update({ stripe_customer_id: customerId }).eq('uid', uid);
      }

      const session = await stripe.checkout.sessions.create({
        mode: 'subscription',
        customer: customerId,
        line_items: [{ price: priceId, quantity: 1 }],
        success_url: `${origin}/abonnement?success=1&plan=${plan}&session_id={CHECKOUT_SESSION_ID}`,
        cancel_url:  `${origin}/abonnement?cancelled=1`,
        metadata: { uid, plan, periodicite },
        subscription_data: { metadata: { uid, plan, periodicite } },
      });

      return NextResponse.json({ url: session.url });
    }

    // ── Achat ponctuel (boost) ────────────────────────────────────────────────
    if (produit_code) {
      const { data: produit } = await supabase
        .from('produits_ponctuels')
        .select('*')
        .eq('code', produit_code)
        .eq('actif', true)
        .maybeSingle();

      if (!produit) return NextResponse.json({ error: 'Produit introuvable' }, { status: 404 });

      const priceId = produit.stripe_price_id as string | null;
      if (!priceId) {
        return NextResponse.json({ error: 'Price ID boost non configuré dans la table produits_ponctuels.' }, { status: 503 });
      }

      const session = await stripe.checkout.sessions.create({
        mode: 'payment',
        line_items: [{ price: priceId, quantity: 1 }],
        success_url: `${origin}/mes-annonces?boost_success=1`,
        cancel_url:  `${origin}/mes-annonces`,
        metadata: { uid, produit_code, annonce_id: annonce_id ?? '' },
      });

      return NextResponse.json({ url: session.url });
    }

    return NextResponse.json({ error: 'Paramètres manquants (plan+periodicite ou produit_code)' }, { status: 400 });
  } catch (err) {
    console.error('[stripe/checkout]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
