import { NextRequest, NextResponse } from 'next/server';
import { stripe } from '@/lib/stripe';
import { createClient } from '@supabase/supabase-js';
import { requireUser } from '@/lib/server-auth';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

export async function POST(req: NextRequest) {
  try {
    // Portail de facturation de l'appelant UNIQUEMENT (jeton Firebase vérifié).
    const auth = await requireUser(req);
    if (auth instanceof NextResponse) return auth;
    const uid = auth.uid;
    const { returnPath } = await req.json().catch(() => ({})) as { returnPath?: string };

    const { data: userData } = await supabase.from('users').select('stripe_customer_id').eq('uid', uid).maybeSingle();
    const customerId = userData?.stripe_customer_id as string | undefined;
    if (!customerId) return NextResponse.json({ error: 'Aucun abonnement trouvé' }, { status: 404 });

    const origin = req.headers.get('origin') ?? 'http://localhost:3000';
    const session = await stripe.billingPortal.sessions.create({
      customer: customerId,
      return_url: `${origin}${(returnPath as string | undefined) ?? '/abonnement'}`,
    });

    return NextResponse.json({ url: session.url });
  } catch (err) {
    console.error('[stripe/portal]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
