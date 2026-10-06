import { NextRequest, NextResponse } from 'next/server';
import { stripe } from '@/lib/stripe';
import { createClient } from '@supabase/supabase-js';
import { requireUser } from '@/lib/server-auth';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);

export async function POST(req: NextRequest) {
  try {
    // Crédits attribués au compte de l'appelant (jeton Firebase vérifié).
    const auth = await requireUser(req);
    if (auth instanceof NextResponse) return auth;
    const uid = auth.uid;
    const { pack_id, checkout } = await req.json();
    if (!pack_id) {
      return NextResponse.json({ error: 'pack_id requis' }, { status: 400 });
    }

    // Récupérer le pack depuis Supabase
    const { data: pack, error } = await supabase
      .from('credit_packs')
      .select('id, nom, credits, prix_euros')
      .eq('id', pack_id)
      .eq('actif', true)
      .maybeSingle();

    if (error || !pack) {
      return NextResponse.json({ error: 'Pack introuvable' }, { status: 404 });
    }

    const montantCentimes = Math.round((pack.prix_euros as number) * 100);
    const metadata = {
      uid,
      pack_id: pack.id as string,
      credits: String(pack.credits),
      nom: pack.nom as string,
    };

    // Achat depuis le site (« Achats & crédits ») : page de paiement Stripe
    // hébergée. Le crédit est versé par le webhook payment_intent.succeeded
    // (métadonnées recopiées sur le PaymentIntent), idempotent sur pi.id.
    if (checkout) {
      const origin = req.headers.get('origin') ?? process.env.NEXT_PUBLIC_SITE_URL ?? 'http://localhost:3000';
      const session = await stripe.checkout.sessions.create({
        mode: 'payment',
        line_items: [{
          quantity: 1,
          price_data: {
            currency: 'eur',
            unit_amount: montantCentimes,
            product_data: { name: `${pack.nom as string} — ${pack.credits} crédits Pets Social` },
          },
        }],
        payment_intent_data: { metadata },
        metadata,
        success_url: `${origin}/mes-achats?credits=ok`,
        cancel_url: `${origin}/mes-achats`,
      });
      return NextResponse.json({ url: session.url });
    }

    const paymentIntent = await stripe.paymentIntents.create({
      amount: montantCentimes,
      currency: 'eur',
      metadata,
      automatic_payment_methods: { enabled: true },
    });

    return NextResponse.json({ clientSecret: paymentIntent.client_secret });
  } catch (err) {
    console.error('[stripe/credits]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
