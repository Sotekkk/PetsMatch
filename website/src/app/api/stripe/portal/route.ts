import { NextRequest, NextResponse } from 'next/server';
import { stripe } from '@/lib/stripe';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

export async function POST(req: NextRequest) {
  try {
    const { uid } = await req.json();
    if (!uid) return NextResponse.json({ error: 'uid requis' }, { status: 400 });

    const { data: userData } = await supabase.from('users').select('stripe_customer_id').eq('uid', uid).maybeSingle();
    const customerId = userData?.stripe_customer_id as string | undefined;
    if (!customerId) return NextResponse.json({ error: 'Aucun abonnement trouvé' }, { status: 404 });

    const origin = req.headers.get('origin') ?? 'http://localhost:3000';
    const session = await stripe.billingPortal.sessions.create({
      customer: customerId,
      return_url: `${origin}/abonnement`,
    });

    return NextResponse.json({ url: session.url });
  } catch (err) {
    console.error('[stripe/portal]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
