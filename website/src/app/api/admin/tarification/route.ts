import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { getDoc, doc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { stripe } from '@/lib/stripe';

const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

async function checkAdmin(uid: string): Promise<boolean> {
  try {
    const snap = await getDoc(doc(db, 'users', uid));
    return snap.exists() && snap.data()?.isAdmin === true;
  } catch { return false; }
}

// Crée un nouveau prix Stripe et archive l'ancien si le montant a changé
async function rotatePlanPrice(
  oldPriceId: string | null,
  newAmount: number,
  interval: 'month' | 'year',
  planCode: string,
): Promise<string | null> {
  if (!oldPriceId) return null;
  try {
    const oldPrice = await stripe.prices.retrieve(oldPriceId);
    if (oldPrice.unit_amount === newAmount) return null; // pas de changement

    const productId = typeof oldPrice.product === 'string' ? oldPrice.product : oldPrice.product.id;
    const newPrice = await stripe.prices.create({
      currency: 'eur',
      unit_amount: newAmount,
      recurring: { interval },
      product: productId,
      metadata: { plan: planCode, periodicite: interval === 'month' ? 'mensuel' : 'annuel' },
    });
    await stripe.prices.update(oldPriceId, { active: false });
    return newPrice.id;
  } catch (err) {
    console.error('[tarification/rotatePlanPrice]', err);
    return null;
  }
}

async function rotateProduitPrice(
  oldPriceId: string | null,
  newAmount: number,
  code: string,
): Promise<string | null> {
  if (!oldPriceId) return null;
  try {
    const oldPrice = await stripe.prices.retrieve(oldPriceId);
    if (oldPrice.unit_amount === newAmount) return null;

    const productId = typeof oldPrice.product === 'string' ? oldPrice.product : oldPrice.product.id;
    const newPrice = await stripe.prices.create({
      currency: 'eur',
      unit_amount: newAmount,
      product: productId,
      metadata: { code },
    });
    await stripe.prices.update(oldPriceId, { active: false });
    return newPrice.id;
  } catch (err) {
    console.error('[tarification/rotateProduitPrice]', err);
    return null;
  }
}

export async function PUT(req: NextRequest) {
  try {
    const body = await req.json();
    const { uid, type, id, data } = body as {
      uid: string;
      type: 'plan' | 'produit';
      id: string;
      data: Record<string, unknown>;
    };

    if (!uid || !type || !id || !data) {
      return NextResponse.json({ error: 'Paramètres manquants' }, { status: 400 });
    }
    if (!(await checkAdmin(uid))) {
      return NextResponse.json({ error: 'Non autorisé' }, { status: 403 });
    }

    const stripeUpdates: Record<string, unknown> = {};

    if (type === 'plan') {
      // Récupère la ligne actuelle pour comparer et avoir les price IDs
      const { data: current } = await supabaseAdmin
        .from('plans_tarifaires').select('*').eq('id', id).single();

      if (current) {
        // Sync mensuel si prix_mensuel change
        if (data.prix_mensuel !== undefined) {
          const newAmt = Math.round(Number(data.prix_mensuel) * 100);
          const newId = await rotatePlanPrice(
            current.stripe_price_id_mensuel,
            newAmt,
            'month',
            current.plan_code,
          );
          if (newId) stripeUpdates.stripe_price_id_mensuel = newId;
        }

        // Sync annuel si prix_annuel change
        if (data.prix_annuel !== undefined) {
          const newAmt = Math.round(Number(data.prix_annuel) * 100);
          const newId = await rotatePlanPrice(
            current.stripe_price_id_annuel,
            newAmt,
            'year',
            current.plan_code,
          );
          if (newId) stripeUpdates.stripe_price_id_annuel = newId;
        }
      }

      const { error } = await supabaseAdmin.from('plans_tarifaires')
        .update({ ...data, ...stripeUpdates, updated_at: new Date().toISOString() }).eq('id', id);
      if (error) return NextResponse.json({ error: error.message }, { status: 500 });

    } else {
      // Produit ponctuel : sync prix si changé
      const { data: current } = await supabaseAdmin
        .from('produits_ponctuels').select('*').eq('id', id).single();

      if (current && data.prix !== undefined) {
        const newAmt = Math.round(Number(data.prix) * 100);
        const newId = await rotateProduitPrice(current.stripe_price_id, newAmt, current.code);
        if (newId) stripeUpdates.stripe_price_id = newId;
      }

      const { error } = await supabaseAdmin.from('produits_ponctuels')
        .update({ ...data, ...stripeUpdates, updated_at: new Date().toISOString() }).eq('id', id);
      if (error) return NextResponse.json({ error: error.message }, { status: 500 });
    }

    return NextResponse.json({ ok: true, stripeUpdated: Object.keys(stripeUpdates).length > 0 });
  } catch (err) {
    console.error('[admin/tarification]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
