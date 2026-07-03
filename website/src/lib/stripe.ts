import Stripe from 'stripe';

export const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: '2026-05-27.dahlia',
});

export const PLAN_CONFIG: Record<string, { maxAnnonces: number; dureeDays: number; autoPublish: boolean }> = {
  free:    { maxAnnonces: 3,  dureeDays: 30, autoPublish: false },
  pro:     { maxAnnonces: 10, dureeDays: 45, autoPublish: true  },
  premium: { maxAnnonces: -1, dureeDays: 60, autoPublish: true  },
};

// Les Stripe Price IDs viennent de plans_tarifaires (scopé profil_type+plan_code,
// éditable depuis /admin → Tarification) — voir api/stripe/checkout/route.ts.
// Ne pas réintroduire de map hardcodée ici, ça recrée la collision entre profils.
