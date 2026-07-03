import { NextRequest, NextResponse } from 'next/server';
import { stripe } from '@/lib/stripe';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

export async function POST(req: NextRequest) {
  try {
    const { uid, email, plan, periodicite, annonce_id, produit_code, profile_id, profil_type, returnPath } = await req.json();
    if (!uid || !email) return NextResponse.json({ error: 'uid et email requis' }, { status: 400 });

    const origin = req.headers.get('origin') ?? process.env.NEXT_PUBLIC_SITE_URL ?? 'http://localhost:3000';
    const type = (profil_type as string | undefined) ?? 'eleveur';
    const backPath = (returnPath as string | undefined) ?? '/abonnement';

    // ── Abonnement récurrent ──────────────────────────────────────────────────
    if (plan && periodicite) {
      // Le prix vient de plans_tarifaires, scopé par profil_type+plan_code — édité
      // depuis /admin sans déploiement, évite toute collision entre types de profil
      // (ex : plan_code 'pro' existe à la fois pour éleveur et pension, à des prix différents).
      const { data: planRow } = await supabase
        .from('plans_tarifaires')
        .select('stripe_price_id_mensuel, stripe_price_id_annuel')
        .eq('profil_type', type)
        .eq('plan_code', plan)
        .maybeSingle();
      const priceId = periodicite === 'annuel' ? planRow?.stripe_price_id_annuel : planRow?.stripe_price_id_mensuel;
      if (!priceId) {
        return NextResponse.json({ error: `Price ID Stripe non configuré pour ${type}/${plan}. Renseignez-le depuis /admin → Tarification.` }, { status: 503 });
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
        success_url: `${origin}${backPath}?success=1&plan=${plan}&session_id={CHECKOUT_SESSION_ID}`,
        cancel_url:  `${origin}${backPath}?cancelled=1`,
        metadata: { uid, plan, periodicite, profil_type: type, ...(profile_id ? { profile_id } : {}) },
        subscription_data: { metadata: { uid, plan, periodicite, profil_type: type, ...(profile_id ? { profile_id } : {}) } },
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
