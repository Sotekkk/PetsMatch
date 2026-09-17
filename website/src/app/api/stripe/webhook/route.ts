import { NextRequest, NextResponse } from 'next/server';
import Stripe from 'stripe';
import { stripe } from '@/lib/stripe';
import { createClient } from '@supabase/supabase-js';
import { mailTransporter, MAIL_FROM } from '@/lib/mailer';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

async function sendAchatReceiptEmail({ email, produitLabel, prix, dateAchat }: {
  email: string; produitLabel: string; prix: number; dateAchat: string;
}) {
  const dateStr = new Date(dateAchat).toLocaleDateString('fr-FR', { dateStyle: 'long' });
  const html = `<!DOCTYPE html>
<html lang="fr">
<head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/></head>
<body style="margin:0;padding:0;background:#f5f7fa;font-family:'Segoe UI',Arial,sans-serif;">
  <div style="max-width:580px;margin:32px auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.08);">
    <div style="background:#0C5C6C;padding:28px 32px;text-align:center;">
      <p style="color:#ffffff;font-size:22px;font-weight:700;margin:0;letter-spacing:-0.3px;">PetsMatch</p>
      <p style="color:rgba(255,255,255,0.8);font-size:13px;margin:6px 0 0;">Reçu d'achat</p>
    </div>
    <div style="padding:32px;">
      <p style="font-size:14px;color:#4B5563;line-height:1.6;margin:0 0 24px;">
        Merci pour votre achat sur PetsMatch. Voici votre reçu.
      </p>
      <div style="background:#F0F9FF;border:1px solid #BAE6FD;border-radius:12px;padding:16px;margin-bottom:24px;">
        <table style="width:100%;border-collapse:collapse;font-size:13px;">
          <tr>
            <td style="color:#6B7280;padding:4px 0;">Produit</td>
            <td style="color:#1F2A2E;font-weight:600;text-align:right;">${produitLabel}</td>
          </tr>
          <tr>
            <td style="color:#6B7280;padding:4px 0;">Montant</td>
            <td style="color:#1F2A2E;font-weight:600;text-align:right;">${prix.toFixed(2)} €</td>
          </tr>
          <tr>
            <td style="color:#6B7280;padding:4px 0;">Date</td>
            <td style="color:#1F2A2E;font-weight:600;text-align:right;">${dateStr}</td>
          </tr>
        </table>
      </div>
      <p style="font-size:12px;color:#9CA3AF;text-align:center;margin:0;">
        Retrouvez l'historique de vos achats dans l'appli/le site, section « Mes achats ».
      </p>
    </div>
    <div style="background:#F9FAFB;border-top:1px solid #E5E7EB;padding:16px 32px;text-align:center;">
      <p style="font-size:11px;color:#9CA3AF;margin:0;">PetsMatch · petsmatch.contact@gmail.com</p>
    </div>
  </div>
</body>
</html>`;

  await mailTransporter.sendMail({
    from: MAIL_FROM,
    to: email,
    subject: `🧾 Reçu — ${produitLabel} · PetsMatch`,
    html,
  });
}

export async function POST(req: NextRequest) {
  const body = await req.text();
  const sig = req.headers.get('stripe-signature');
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;

  if (!sig || !webhookSecret) {
    return NextResponse.json({ error: 'Webhook secret manquant' }, { status: 400 });
  }

  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(body, sig, webhookSecret);
  } catch (err) {
    console.error('[webhook] Signature invalide:', err);
    return NextResponse.json({ error: 'Signature invalide' }, { status: 400 });
  }

  try {
    switch (event.type) {

      // ── Checkout terminé (abonnement ou paiement ponctuel) ────────────────
      case 'checkout.session.completed': {
        const session = event.data.object as Stripe.Checkout.Session;
        const uid = session.metadata?.uid;
        if (!uid) break;

        if (session.mode === 'subscription' && session.subscription) {
          const plan = session.metadata?.plan ?? 'pro';
          const periodicite = session.metadata?.periodicite ?? 'mensuel';
          const profileId = session.metadata?.profile_id ?? null;
          const subId = typeof session.subscription === 'string' ? session.subscription : session.subscription.id;

          const sub = await stripe.subscriptions.retrieve(subId, { expand: ['items'] });
          const periodEnd = sub.items.data[0]?.current_period_end ?? null;
          const dateFin = periodEnd ? new Date(periodEnd * 1000).toISOString() : null;

          // Désactiver l'ancien abonnement actif pour ce profil avant d'insérer le nouveau
          const cancelQ = supabase.from('abonnements')
            .update({ statut: 'annule', updated_at: new Date().toISOString() })
            .eq('uid', uid).eq('statut', 'actif');
          if (profileId) await cancelQ.eq('profile_id', profileId);
          else await cancelQ;

          await supabase.from('abonnements').insert({
            uid,
            profile_id: profileId,
            profil_type: 'eleveur',
            plan_code: plan,
            periodicite,
            statut: 'actif',
            stripe_subscription_id: subId,
            stripe_customer_id: typeof session.customer === 'string' ? session.customer : session.customer?.id,
            date_debut: new Date().toISOString(),
            date_fin: dateFin,
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          });

          // Mettre à jour le plan sur le profil concerné ET sur users (profil principal)
          if (profileId) {
            await supabase.from('user_profiles').update({
              plan_code: plan,
              is_premium: plan === 'premium',
              plan_until: dateFin,
            }).eq('id', profileId);
          } else {
            // Pas de profil secondaire → mettre à jour le profil principal
            await supabase.from('user_profiles').update({
              plan_code: plan,
              is_premium: plan === 'premium',
              plan_until: dateFin,
            }).eq('uid', uid).eq('is_main', true);
          }
          await supabase.from('users').update({
            plan_code: plan,
            is_premium: plan === 'premium',
          }).eq('uid', uid);
        }

        if (session.mode === 'payment') {
          const { produit_code, annonce_id } = session.metadata ?? {};
          if (produit_code) {
            const { data: produit } = await supabase.from('produits_ponctuels').select('id, label, prix, duree_heures').eq('code', produit_code).maybeSingle();
            if (produit) {
              const expiration = produit.duree_heures
                ? new Date(Date.now() + produit.duree_heures * 3600_000).toISOString()
                : null;
              await supabase.from('achats_ponctuels').insert({
                uid, produit_id: produit.id, annonce_id: annonce_id || null,
                stripe_payment_intent_id: typeof session.payment_intent === 'string' ? session.payment_intent : null,
                statut: 'paye', date_expiration: expiration,
              });
              if (annonce_id) {
                if (produit_code === 'annonce_cheval_particulier') {
                  // Publication payante d'une annonce cheval particulier : on
                  // sort le brouillon et on (re)cale l'expiration à +60 j.
                  const expiresAt = new Date(
                    Date.now() + (produit.duree_heures ?? 1440) * 3600_000,
                  ).toISOString();
                  await supabase.from('annonces').update({
                    statut: 'disponible', paiement_statut: 'paye', expires_at: expiresAt,
                  }).eq('id', annonce_id);
                } else if (expiration) {
                  await supabase.from('annonces').update({ boost_until: expiration }).eq('id', annonce_id);
                }
              }

              // Reçu par email — fire-and-forget, ne doit jamais faire échouer
              // le webhook (Stripe retente sinon). L'email vient du checkout
              // (Stripe le collecte toujours en mode 'payment' même sans
              // customer existant) ; repli sur users.email si absent.
              const recipientEmail = session.customer_details?.email
                ?? (await supabase.from('users').select('email').eq('uid', uid).maybeSingle()).data?.email;
              if (recipientEmail) {
                sendAchatReceiptEmail({
                  email: recipientEmail,
                  produitLabel: produit.label as string,
                  prix: produit.prix as number,
                  dateAchat: new Date().toISOString(),
                }).catch((e) => console.error('[webhook] Échec envoi reçu achat:', e));
              }
            }
          }
        }
        break;
      }

      // ── Abonnement renouvelé ───────────────────────────────────────────────
      case 'customer.subscription.updated': {
        const sub = event.data.object as Stripe.Subscription;
        const periodEnd = sub.items.data[0]?.current_period_end ?? null;
        const dateFin = periodEnd ? new Date(periodEnd * 1000).toISOString() : null;
        const statut = sub.status === 'active' ? 'actif' : sub.status === 'past_due' ? 'grace' : 'annule';
        await supabase.from('abonnements')
          .update({ statut, date_fin: dateFin, updated_at: new Date().toISOString() })
          .eq('stripe_subscription_id', sub.id);
        break;
      }

      // ── Paiement crédits Pets Social confirmé ────────────────────────────
      // Filet de sécurité : la confirmation principale se fait côté appli
      // via la Cloud Function confirmCreditPayment (juste après le Payment
      // Sheet), ce webhook couvre le cas où l'appli n'a pas pu confirmer
      // (app tuée, offline...). Metadata posée par createCreditPaymentIntent
      // (functions/stripe.js) : `packId` (pas `pack_id`), pas de `nom`
      // systématique. Idempotent sur pi.id (même ref_id que la Cloud
      // Function) pour ne jamais créditer deux fois le même paiement.
      case 'payment_intent.succeeded': {
        const pi = event.data.object as import('stripe').default.PaymentIntent;
        // Deux origines possibles, deux conventions de clé : l'appli
        // (functions/stripe.js createCreditPaymentIntent) pose `packId`,
        // le site (api/stripe/credits, netlify/functions/stripe-credits)
        // pose `pack_id` — on accepte les deux plutôt que d'en privilégier
        // une et de silencieusement ignorer l'autre origine.
        const { uid, credits, nom } = pi.metadata ?? {};
        const packId = pi.metadata?.packId || pi.metadata?.pack_id;
        if (!uid || !packId || !credits) break;

        const creditsInt = parseInt(credits, 10);
        if (isNaN(creditsInt) || creditsInt <= 0) break;

        const { data: already } = await supabase
          .from('credit_transactions')
          .select('id')
          .eq('ref_id', pi.id)
          .limit(1);
        if (already && already.length > 0) break;

        // Upsert wallet (ajoute les crédits au solde existant)
        const { data: wallet } = await supabase
          .from('credit_wallets')
          .select('solde, total_achete')
          .eq('uid', uid)
          .maybeSingle();

        const soldeActuel = (wallet?.solde as number) ?? 0;
        const totalAchetéActuel = (wallet?.total_achete as number) ?? 0;

        await supabase.from('credit_wallets').upsert({
          uid,
          solde: soldeActuel + creditsInt,
          total_achete: totalAchetéActuel + creditsInt,
          updated_at: new Date().toISOString(),
        }, { onConflict: 'uid' });

        await supabase.from('credit_transactions').insert({
          uid,
          montant: creditsInt,
          motif: `Achat pack ${nom || packId}`,
          ref_id: pi.id,
        });

        break;
      }

      // ── Abonnement annulé ─────────────────────────────────────────────────
      case 'customer.subscription.deleted': {
        const sub = event.data.object as Stripe.Subscription;
        const uid = sub.metadata?.uid;
        const profileId = sub.metadata?.profile_id ?? null;
        await supabase.from('abonnements')
          .update({ statut: 'annule', updated_at: new Date().toISOString() })
          .eq('stripe_subscription_id', sub.id);
        if (uid) {
          // Remettre le plan à free sur le profil concerné
          if (profileId) {
            await supabase.from('user_profiles').update({
              plan_code: 'free', is_premium: false, plan_until: null,
            }).eq('id', profileId);
          } else {
            await supabase.from('user_profiles').update({
              plan_code: 'free', is_premium: false, plan_until: null,
            }).eq('uid', uid).eq('is_main', true);
          }
          await supabase.from('users').update({ plan_code: 'free', is_premium: false }).eq('uid', uid);
        }
        break;
      }
    }
  } catch (err) {
    console.error('[webhook] Erreur traitement event:', event.type, err);
  }

  return NextResponse.json({ received: true });
}
