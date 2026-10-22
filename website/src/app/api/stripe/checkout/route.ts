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
    // Paiement pour le compte de l'appelant uniquement (jeton Firebase vérifié) :
    // sinon on pouvait rattacher son propre client Stripe au compte d'un autre.
    const auth = await requireUser(req);
    if (auth instanceof NextResponse) return auth;
    const uid = auth.uid;
    const { email, plan, periodicite, annonce_id, produit_code, profile_id, profil_type, returnPath, publier_statut } = await req.json();
    if (!email) return NextResponse.json({ error: 'email requis' }, { status: 400 });
    if (profile_id) {
      // Le profil payé doit être à l'appelant — ou à un élevage qu'il co-gère.
      const { data: prof } = await supabase.from('user_profiles').select('uid').eq('id', profile_id).maybeSingle();
      let allowed = !!prof && prof.uid === uid;
      if (prof && !allowed) {
        const { data: cog } = await supabase.from('elevage_cogerants').select('id')
          .eq('uid_gerant', prof.uid).eq('uid_cogerant', uid).eq('statut', 'actif').is('date_fin', null)
          .limit(1).maybeSingle();
        allowed = !!cog;
      }
      if (!allowed) return NextResponse.json({ error: 'Profil non autorisé' }, { status: 403 });
    }

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

      // Retour paramétrable : la publication payante d'une annonce cheval
      // particulier revient sur /mes-annonces ; les boosts gardent leur retour.
      const ponctuelBack = (returnPath as string | undefined) ?? '/mes-annonces';
      const isAnnonceChevalParticulier = produit_code === 'annonce_cheval_particulier';

      // Boost choisi à la publication : l'annonce, complète, attend en
      // brouillon (paiement_statut « attente_boost ») ; elle n'est publiée
      // qu'à la confirmation du paiement (webhook). Paiement annulé : elle
      // reste en brouillon, rien n'est activé.
      const publication = publier_statut === 'disponible' || publier_statut === 'en_attente';
      if (publication) {
        if (!annonce_id || !(produit.duree_heures as number | null)) {
          return NextResponse.json({ error: 'Annonce ou offre de boost invalide.' }, { status: 400 });
        }
        const { data: a } = await supabase.from('annonces').select('uid_eleveur, statut, paiement_statut').eq('id', annonce_id).maybeSingle();
        if (!a) return NextResponse.json({ error: 'Annonce introuvable.' }, { status: 404 });
        let proprietaire = a.uid_eleveur === uid;
        if (!proprietaire) {
          const { data: cog } = await supabase.from('elevage_cogerants').select('id')
            .eq('uid_gerant', a.uid_eleveur).eq('uid_cogerant', uid).eq('statut', 'actif').is('date_fin', null)
            .limit(1).maybeSingle();
          proprietaire = !!cog;
        }
        if (!proprietaire) return NextResponse.json({ error: 'Annonce non autorisée.' }, { status: 403 });
        // Déjà publiée (paiement confirmé, retour arrière…) : pas de second paiement.
        if (a.statut !== 'brouillon' || a.paiement_statut !== 'attente_boost') {
          return NextResponse.json({ error: 'Cette annonce est déjà publiée.' }, { status: 409 });
        }
      }

      const session = await stripe.checkout.sessions.create({
        mode: 'payment',
        line_items: [{ price: priceId, quantity: 1 }],
        success_url: isAnnonceChevalParticulier
          ? `${origin}${ponctuelBack}?paye=1`
          : publication ? `${origin}/mes-annonces?publiee=${annonce_id}`
          : `${origin}/mes-annonces?boost_success=1`,
        cancel_url: isAnnonceChevalParticulier
          ? `${origin}${ponctuelBack}?paiement=annule`
          : publication ? `${origin}/annonces/creer?brouillon=${annonce_id}&paiement=annule`
          : `${origin}/mes-annonces`,
        metadata: { uid, produit_code, annonce_id: annonce_id ?? '', ...(publication ? { publier_statut } : {}) },
      // Clics répétés / retour depuis le paiement : même session Stripe, jamais deux paiements.
      }, publication ? { idempotencyKey: `publication-boost-${annonce_id}-${produit_code}` } : undefined);

      return NextResponse.json({ url: session.url });
    }

    return NextResponse.json({ error: 'Paramètres manquants (plan+periodicite ou produit_code)' }, { status: 400 });
  } catch (err) {
    console.error('[stripe/checkout]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
