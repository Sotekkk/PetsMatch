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

// Récupère le produit Stripe existant du plan (via un de ses prix), ou en crée un
// nouveau — permet de saisir un tarif pour un profil qui n'a encore aucun produit
// Stripe (ex : pension) sans jamais ouvrir le dashboard Stripe.
async function getOrCreatePlanProduct(current: {
  stripe_price_id_mensuel: string | null;
  stripe_price_id_annuel: string | null;
  profil_type: string;
  plan_code: string;
  label: string;
}): Promise<string> {
  const existingPriceId = current.stripe_price_id_mensuel || current.stripe_price_id_annuel;
  if (existingPriceId) {
    const price = await stripe.prices.retrieve(existingPriceId);
    return typeof price.product === 'string' ? price.product : price.product.id;
  }
  const product = await stripe.products.create({
    name: `PetsMatch — ${current.profil_type} ${current.label}`,
    metadata: { profil_type: current.profil_type, plan_code: current.plan_code },
  });
  return product.id;
}

// Crée un nouveau prix Stripe et archive l'ancien si le montant a changé.
// Si aucun prix n'existe encore pour ce plan, crée le produit + le prix Stripe
// depuis zéro (ex : première tarification d'un nouveau profil comme la pension).
async function rotatePlanPrice(
  oldPriceId: string | null,
  newAmount: number,
  interval: 'month' | 'year',
  planCode: string,
  productId?: string,
): Promise<string | null> {
  try {
    if (!oldPriceId) {
      if (!productId || newAmount <= 0) return null;
      const newPrice = await stripe.prices.create({
        currency: 'eur',
        unit_amount: newAmount,
        recurring: { interval },
        product: productId,
        metadata: { plan: planCode, periodicite: interval === 'month' ? 'mensuel' : 'annuel' },
      });
      return newPrice.id;
    }

    const oldPrice = await stripe.prices.retrieve(oldPriceId);
    if (oldPrice.unit_amount === newAmount) return null; // pas de changement

    const resolvedProductId = typeof oldPrice.product === 'string' ? oldPrice.product : oldPrice.product.id;
    const newPrice = await stripe.prices.create({
      currency: 'eur',
      unit_amount: newAmount,
      recurring: { interval },
      product: resolvedProductId,
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
        // Un seul produit Stripe partagé entre le prix mensuel et annuel — réutilisé
        // s'il existe déjà (via l'un des deux prix), sinon créé au premier tarif
        // renseigné pour un plan qui n'a encore aucun produit (nouveau profil_type).
        const needsNewMensuel = data.prix_mensuel !== undefined && Number(data.prix_mensuel) > 0 && !current.stripe_price_id_mensuel;
        const needsNewAnnuel  = data.prix_annuel  !== undefined && Number(data.prix_annuel)  > 0 && !current.stripe_price_id_annuel;
        const productId = (needsNewMensuel || needsNewAnnuel)
          ? await getOrCreatePlanProduct({
              stripe_price_id_mensuel: current.stripe_price_id_mensuel,
              stripe_price_id_annuel: current.stripe_price_id_annuel,
              profil_type: current.profil_type,
              plan_code: current.plan_code,
              label: data.label as string ?? current.label,
            })
          : undefined;

        // Sync mensuel si prix_mensuel change
        if (data.prix_mensuel !== undefined) {
          const newAmt = Math.round(Number(data.prix_mensuel) * 100);
          const newId = await rotatePlanPrice(
            current.stripe_price_id_mensuel,
            newAmt,
            'month',
            current.plan_code,
            productId,
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
            productId,
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
