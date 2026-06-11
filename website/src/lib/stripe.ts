import Stripe from 'stripe';

export const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: '2026-05-27.dahlia',
});

export const PLAN_CONFIG: Record<string, { maxAnnonces: number; dureeDays: number; autoPublish: boolean }> = {
  free:    { maxAnnonces: 3,  dureeDays: 30, autoPublish: false },
  pro:     { maxAnnonces: 10, dureeDays: 45, autoPublish: true  },
  premium: { maxAnnonces: -1, dureeDays: 60, autoPublish: true  },
};

export const STRIPE_PRICES: Record<string, { mensuel?: string; annuel?: string }> = {
  pro:     { mensuel: process.env.STRIPE_PRICE_ELEVEUR_PRO_MENSUEL,     annuel: process.env.STRIPE_PRICE_ELEVEUR_PRO_ANNUEL     },
  premium: { mensuel: process.env.STRIPE_PRICE_ELEVEUR_PREMIUM_MENSUEL, annuel: process.env.STRIPE_PRICE_ELEVEUR_PREMIUM_ANNUEL },
};
