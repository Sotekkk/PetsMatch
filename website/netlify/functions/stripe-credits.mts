import Stripe from 'stripe';
import { createClient } from '@supabase/supabase-js';

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);
const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);

export default async function handler(req: Request): Promise<Response> {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Méthode non autorisée' }), { status: 405 });
  }

  try {
    const { pack_id, uid } = await req.json();
    if (!pack_id || !uid) {
      return new Response(JSON.stringify({ error: 'pack_id et uid requis' }), { status: 400 });
    }

    const { data: pack, error } = await supabase
      .from('credit_packs')
      .select('id, nom, credits, prix_euros')
      .eq('id', pack_id)
      .eq('actif', true)
      .maybeSingle();

    if (error || !pack) {
      return new Response(JSON.stringify({ error: 'Pack introuvable' }), { status: 404 });
    }

    const montantCentimes = Math.round((pack.prix_euros as number) * 100);

    const paymentIntent = await stripe.paymentIntents.create({
      amount: montantCentimes,
      currency: 'eur',
      metadata: {
        uid,
        pack_id: pack.id as string,
        credits: String(pack.credits),
        nom: pack.nom as string,
      },
      automatic_payment_methods: { enabled: true },
    });

    return new Response(JSON.stringify({ clientSecret: paymentIntent.client_secret }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error('[stripe-credits]', err);
    return new Response(JSON.stringify({ error: 'Erreur serveur' }), { status: 500 });
  }
}
