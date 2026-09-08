import { NextRequest, NextResponse } from 'next/server';
import { stripe } from '@/lib/stripe';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);

export async function POST(req: NextRequest) {
  try {
    const { pack_id, uid } = await req.json();
    if (!pack_id || !uid) {
      return NextResponse.json({ error: 'pack_id et uid requis' }, { status: 400 });
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

    return NextResponse.json({ clientSecret: paymentIntent.client_secret });
  } catch (err) {
    console.error('[stripe/credits]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
