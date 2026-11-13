// « Mon abonnement » (site + appli) : état de l'abonnement du profil et
// actions du pro — pause du mensuel (1 à 3 mois), reprise, résiliation en fin
// de période, annulation de la résiliation. Changer de formule / carte et
// factures : pages existantes (formule du métier, portail Stripe).
// Jeton Firebase vérifié : uniquement les abonnements de l'appelant.
import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import type Stripe from 'stripe';
import { stripe } from '@/lib/stripe';
import { requireUser } from '@/lib/server-auth';
import { appliquerPlan, libellePlan, pageFormule, prevenirPro, type LigneAbonnement } from '@/lib/abonnement-gestion';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);

const MAX_MOIS_PAUSE = 3;

async function ligneDuProfil(uid: string, profileId?: string | null): Promise<LigneAbonnement | null> {
  let q = supabase.from('abonnements').select('*').eq('uid', uid).in('statut', ['actif', 'grace', 'pause', 'suspendu']);
  q = profileId ? q.eq('profile_id', profileId) : q;
  const { data } = await q.order('created_at', { ascending: false }).limit(1);
  return ((data ?? [])[0] as LigneAbonnement | undefined) ?? null;
}

export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const { action = 'infos', profile_id, mois } = await req.json().catch(() => ({})) as {
    action?: 'infos' | 'pause' | 'reprendre' | 'resilier' | 'annuler_resiliation'; profile_id?: string | null; mois?: number;
  };
  // Profil de l'appelant uniquement.
  if (profile_id) {
    const { data: p } = await supabase.from('user_profiles').select('uid').eq('id', profile_id).maybeSingle();
    if (!p || p.uid !== auth.uid) return NextResponse.json({ error: 'Profil inconnu' }, { status: 403 });
  }
  const a = await ligneDuProfil(auth.uid, profile_id);
  if (!a) {
    // Formule Découverte : la page des formules de ce métier.
    const q = supabase.from('user_profiles').select('profile_type').eq('uid', auth.uid);
    const { data: p } = await (profile_id ? q.eq('id', profile_id) : q.eq('is_main', true)).maybeSingle();
    return NextResponse.json({ abonnement: null, page_formule: pageFormule((p as { profile_type?: string } | null)?.profile_type) });
  }

  let sub: Stripe.Subscription | null = null;
  if (a.stripe_subscription_id) {
    try {
      sub = await stripe.subscriptions.retrieve(a.stripe_subscription_id, { expand: ['default_payment_method', 'items.data.price'] });
    } catch (e) { console.error('[abonnement] stripe', e); }
  }
  const mensuel = (a.periodicite ?? 'mensuel') !== 'annuel';

  if (action !== 'infos') {
    if (!sub) return NextResponse.json({ error: "Cet abonnement n'est pas géré en ligne : contactez PetsMatch." }, { status: 400 });
    const now = new Date().toISOString();
    if (action === 'pause') {
      if (!mensuel) return NextResponse.json({ error: "La pause n'est pas possible pour un abonnement annuel." }, { status: 400 });
      if (a.resiliation_prevue) return NextResponse.json({ error: 'Abonnement déjà résilié.' }, { status: 400 });
      const n = Math.min(MAX_MOIS_PAUSE, Math.max(1, Math.round(Number(mois) || 1)));
      const fin = new Date(); fin.setMonth(fin.getMonth() + n);
      sub = await stripe.subscriptions.update(sub.id, { pause_collection: { behavior: 'void', resumes_at: Math.floor(fin.getTime() / 1000) } });
      await supabase.from('abonnements').update({ statut: 'pause', pause_jusquau: fin.toISOString(), updated_at: now }).eq('id', a.id);
      await appliquerPlan(supabase, a, false);
      await prevenirPro(supabase, a, 'pause', { date: fin.toISOString() });
    } else if (action === 'reprendre') {
      sub = await stripe.subscriptions.update(sub.id, { pause_collection: null } as Stripe.SubscriptionUpdateParams);
      const fin = sub.items.data[0]?.current_period_end ? new Date(sub.items.data[0].current_period_end * 1000).toISOString() : a.date_fin;
      await supabase.from('abonnements').update({ statut: 'actif', pause_jusquau: null, date_fin: fin, updated_at: now }).eq('id', a.id);
      await appliquerPlan(supabase, a, true, fin);
      await prevenirPro(supabase, a, 'reprise');
    } else if (action === 'resilier') {
      sub = await stripe.subscriptions.update(sub.id, { cancel_at_period_end: true });
      const fin = sub.items.data[0]?.current_period_end ? new Date(sub.items.data[0].current_period_end * 1000).toISOString() : a.date_fin;
      await supabase.from('abonnements').update({ resiliation_prevue: true, date_fin: fin, updated_at: now }).eq('id', a.id);
      await prevenirPro(supabase, a, 'resiliation', { date: fin });
    } else if (action === 'annuler_resiliation') {
      sub = await stripe.subscriptions.update(sub.id, { cancel_at_period_end: false });
      await supabase.from('abonnements').update({ resiliation_prevue: false, updated_at: now }).eq('id', a.id);
    }
  }

  const ligne = (await ligneDuProfil(auth.uid, profile_id)) ?? a;
  const item = sub?.items.data[0];
  const prix = item?.price;
  const pm = sub?.default_payment_method as Stripe.PaymentMethod | null | undefined;
  return NextResponse.json({
    abonnement: {
      plan: libellePlan(ligne.plan_code), plan_code: ligne.plan_code, profil_type: ligne.profil_type,
      periodicite: mensuel ? 'mensuel' : 'annuel', statut: ligne.statut,
      prochaine_echeance: item?.current_period_end ? new Date(item.current_period_end * 1000).toISOString() : ligne.date_fin,
      montant: prix?.unit_amount != null ? prix.unit_amount / 100 : null,
      resiliation_prevue: sub ? sub.cancel_at_period_end : !!ligne.resiliation_prevue,
      pause_jusquau: sub?.pause_collection?.resumes_at ? new Date(sub.pause_collection.resumes_at * 1000).toISOString() : ligne.pause_jusquau,
      grace_jusquau: ligne.grace_jusquau ?? null,
      carte: pm?.card ? { marque: pm.card.brand, fin: pm.card.last4, expire: `${String(pm.card.exp_month).padStart(2, '0')}/${pm.card.exp_year}` } : null,
      en_ligne: !!sub,
      page_formule: pageFormule(ligne.profil_type),
      pause_max_mois: MAX_MOIS_PAUSE,
    },
  });
}
