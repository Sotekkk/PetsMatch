const functions = require("firebase-functions/v1");
const { createClient } = require("@supabase/supabase-js");
const Stripe = require("stripe");

const stripe = new Stripe(
    "sk_test_51Pagp22MpEB6OUl5N3RDJvFx7l8dpxO1Az9RIWYEe8acl9eLtRz9xdfKd8W5GZKFuwJx1EX4sxHUP3CxLcPO0l0N00VDQZrUkb",
);

// Lazy init pour éviter l'erreur "supabaseKey is required" au chargement du module
function getSupabase() {
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY ||
        (functions.config().supabase || {}).service_key || "";
    return createClient("https://zyvpngcvzrkdytypjlyq.supabase.co", key);
}

// Tarifs CPM/CPL par défaut (€)
const CPM = { banniere: 10, listing: 0 };
const CPL = { lead: 15 };

/**
 * Calcule et facture automatiquement chaque partenaire actif en fin de mois.
 * Planifié le 1er du mois à 6h (facture le mois précédent).
 */
exports.marketplaceBillingMonthly = functions
    .region("europe-west1")
    .pubsub.schedule("0 6 1 * *")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        const now = new Date();
        const year = now.getMonth() === 0 ? now.getFullYear() - 1 : now.getFullYear();
        const month = now.getMonth() === 0 ? 12 : now.getMonth(); // mois précédent (1-12)
        const firstDay = new Date(year, month - 1, 1).toISOString();
        const lastDay = new Date(year, month, 1).toISOString();

        functions.logger.info(`💰 Facturation Marketplace ${month}/${year}`);

        // Récupère tous les partenaires actifs
        const { data: partners, error: pErr } = await getSupabase()
            .from("marketplace_partners")
            .select("id, nom, contact_email, budget_mensuel, plan")
            .eq("statut", "actif");

        if (pErr || !partners) {
            functions.logger.error("Erreur chargement partenaires", pErr);
            return null;
        }

        for (const partner of partners) {
            try {
                await _billPartner(partner, firstDay, lastDay, month, year);
            } catch (err) {
                functions.logger.error(`Erreur facturation partenaire ${partner.nom}`, err);
                // Suspend le partenaire si erreur de paiement
                await supabase
                    .from("marketplace_partners")
                    .update({ statut: "suspendu" })
                    .eq("id", partner.id);
            }
        }

        return null;
    });

/**
 * Déclenchement manuel via HTTP (test / rattrapage).
 */
exports.marketplaceBillingManual = functions
    .region("europe-west1")
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Auth requise");
        }

        const now = new Date();
        const year = data.year || now.getFullYear();
        const month = data.month || now.getMonth() + 1;
        const firstDay = new Date(year, month - 1, 1).toISOString();
        const lastDay = new Date(year, month, 1).toISOString();

        const { data: partners } = await getSupabase()
            .from("marketplace_partners")
            .select("id, nom, contact_email, budget_mensuel, plan")
            .eq("statut", "actif");

        for (const partner of (partners || [])) {
            await _billPartner(partner, firstDay, lastDay, month, year);
        }

        return { success: true, partners: (partners || []).length };
    });

// ── Logique facturation par partenaire ────────────────────────────────────────

/**
 * @param {object} partner
 * @param {string} firstDay
 * @param {string} lastDay
 * @param {number} month
 * @param {number} year
 */
async function _billPartner(partner, firstDay, lastDay, month, year) {
    // Compte les événements du mois
    const { data: events } = await supabase
        .from("marketplace_events")
        .select("event_type, ad_id")
        .eq("partner_id", partner.id)
        .gte("created_at", firstDay)
        .lt("created_at", lastDay);

    if (!events || events.length === 0) {
        functions.logger.info(`Partenaire ${partner.nom} : 0 événement, pas de facture`);
        return;
    }

    let impressions = 0;
    let clics = 0;
    let leads = 0;
    for (const e of events) {
        if (e.event_type === "impression") impressions++;
        else if (e.event_type === "clic") clics++;
        else if (e.event_type === "lead") leads++;
    }

    // Calcul montant HT (centimes)
    const montantImpressions = Math.round((impressions / 1000) * CPM.banniere * 100);
    const montantLeads = leads * CPL.lead * 100;
    let montantHT = montantImpressions + montantLeads;

    // Plafond mensuel
    const plafond = (partner.budget_mensuel || 0) * 100;
    if (plafond > 0 && montantHT > plafond) {
        functions.logger.warn(`Plafond atteint pour ${partner.nom}: ${montantHT}c > ${plafond}c`);
        montantHT = plafond;
    }

    if (montantHT === 0) {
        functions.logger.info(`Partenaire ${partner.nom} : montant nul, pas de facture`);
        return;
    }

    const montantTVA = Math.round(montantHT * 0.20);
    const montantTTC = montantHT + montantTVA;

    functions.logger.info(`${partner.nom} : imp=${impressions} leads=${leads} → ${montantTTC / 100}€ TTC`);

    // Crée ou retrouve le customer Stripe
    let customerId = partner.stripe_customer_id;
    if (!customerId) {
        const customer = await stripe.customers.create({
            name: partner.nom,
            email: partner.contact_email || undefined,
            metadata: { partner_id: partner.id },
        });
        customerId = customer.id;
        await getSupabase()
            .from("marketplace_partners")
            .update({ stripe_customer_id: customerId })
            .eq("id", partner.id);
    }

    // Génère la facture Stripe
    const invoice = await stripe.invoices.create({
        customer: customerId,
        auto_advance: true,
        collection_method: "charge_automatically",
        description: `PetsMatch Marketplace — ${_monthLabel(month)} ${year}`,
        metadata: {
            partner_id: partner.id,
            impressions: impressions.toString(),
            leads: leads.toString(),
            month: `${month}/${year}`,
        },
    });

    // Ajoute les lignes
    if (montantImpressions > 0) {
        await stripe.invoiceItems.create({
            customer: customerId,
            invoice: invoice.id,
            amount: montantImpressions,
            currency: "eur",
            description: `Bannières — ${impressions} impressions (CPM ${CPM.banniere}€)`,
        });
    }
    if (montantLeads > 0) {
        await stripe.invoiceItems.create({
            customer: customerId,
            invoice: invoice.id,
            amount: montantLeads,
            currency: "eur",
            description: `Leads assurance — ${leads} leads (CPL ${CPL.lead}€)`,
        });
    }

    // Finalise et tente le paiement
    await stripe.invoices.finalizeInvoice(invoice.id);
    const paid = await stripe.invoices.pay(invoice.id);

    functions.logger.info(`✅ Facture ${paid.id} payée pour ${partner.nom} — ${montantTTC / 100}€ TTC`);
}

/**
 * @param {number} m
 * @return {string}
 */
function _monthLabel(m) {
    const labels = ["Jan", "Fév", "Mar", "Avr", "Mai", "Jun", "Jul", "Aoû", "Sep", "Oct", "Nov", "Déc"];
    return labels[m - 1] || m.toString();
}
