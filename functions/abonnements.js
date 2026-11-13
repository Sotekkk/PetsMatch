const functions = require("firebase-functions/v1");
const https = require("https");

const {SUPABASE_URL, SUPABASE_AUTH_HEADERS, STRIPE_SECRET_KEY, INTERNAL_API_SECRET} = require("./config");

// Site : e-mail + notification au pro (route /api/abonnement/email).
const SITE_URL = process.env.SITE_URL || "https://petsmatchapp.com";

/** Message d'abonnement au pro (notification + e-mail), via le site. */
function prevenirPro(abonnementId, type, extra = {}) {
    return new Promise((resolve) => {
        try {
            const body = JSON.stringify({abonnement_id: abonnementId, type, ...extra});
            const u = new URL(`${SITE_URL}/api/abonnement/email`);
            const req = https.request({
                hostname: u.hostname, path: u.pathname, method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "Content-Length": Buffer.byteLength(body),
                    ...(INTERNAL_API_SECRET ? {"x-internal-secret": INTERNAL_API_SECRET} : {}),
                },
            }, (res) => {
                res.on("data", () => {});
                res.on("end", () => resolve(res.statusCode === 200));
            });
            req.on("error", () => resolve(false));
            req.write(body);
            req.end();
        } catch (_) {
            resolve(false);
        }
    });
}

/** Une seule fois par clé (notifs_sent). */
async function uneFois(key, nowIso) {
    const deja = await supabaseGet(`notifs_sent?key=eq.${encodeURIComponent(key)}`);
    if (deja.length > 0) return false;
    await supabaseInsert("notifs_sent", [{key, sent_at: nowIso}]);
    return true;
}

// ─── Helpers Supabase (dupliqués par fichier — convention déjà suivie par
// annonces.js/agenda.js/chaleurs.js/etc., pas de module partagé à extraire) ──

function supabaseReq(method, path, body) {
    return new Promise((resolve, reject) => {
        const bodyStr = body ? JSON.stringify(body) : null;
        const url = new URL(`${SUPABASE_URL}/rest/v1/${path}`);
        const options = {
            hostname: url.hostname,
            path: url.pathname + url.search,
            method,
            headers: {
                "Content-Type": "application/json",
                ...SUPABASE_AUTH_HEADERS,
                "Prefer": "return=minimal",
            },
        };
        if (bodyStr) options.headers["Content-Length"] = Buffer.byteLength(bodyStr);
        const req = https.request(options, (res) => {
            let d = "";
            res.on("data", (c) => d += c);
            res.on("end", () => {
                try {
                    resolve({status: res.statusCode, body: JSON.parse(d)});
                } catch (_) {
                    resolve({status: res.statusCode, body: []});
                }
            });
        });
        req.on("error", reject);
        if (bodyStr) req.write(bodyStr);
        req.end();
    });
}

async function supabaseGet(path) {
    const res = await supabaseReq("GET", path);
    return Array.isArray(res.body) ? res.body : [];
}

async function supabasePatch(path, body) {
    return supabaseReq("PATCH", path, body);
}

async function supabaseInsert(table, rows) {
    return supabaseReq("POST", table, rows);
}

// ─── FCM helper (partagé) ──────────────────────────────────────────────────────

const {sendPush} = require("./push_helpers");

// ─── Helpers date ─────────────────────────────────────────────────────────────

function dayRange(daysFromNow) {
    const start = new Date();
    start.setDate(start.getDate() + daysFromNow);
    start.setHours(0, 0, 0, 0);
    const end = new Date(start);
    end.setDate(end.getDate() + 1);
    return {start: start.toISOString(), end: end.toISOString()};
}

// Statuts « actifs » comptant contre le quota — mêmes valeurs que
// lib/services/plan_service.dart:countActiveAnnonces et
// website/src/lib/subscription.ts:countActiveAnnonces.
const ACTIVE_ANNONCE_STATUTS = ["disponible", "en_attente", "pause", "reserve"];
// PLAN_CONFIG.free.maxAnnonces (website/src/lib/use-plan.ts, mirroir
// lib/services/plan_service.dart) — seul le métier éleveur a une table de
// contenu public quota-gérée aujourd'hui.
const FREE_MAX_ANNONCES = 3;

/**
 * Repasse en `quota_depasse` les annonces d'un éleveur excédant le quota du
 * plan gratuit, une fois son abonnement expiré. Les plus anciennes restent
 * visibles (cohérent avec le blocage déjà appliqué à la création : une
 * nouvelle annonce au-delà du quota est toujours celle refusée).
 */
async function blockExcessAnnonces(uid) {
    const rows = await supabaseGet(
        `annonces?uid_eleveur=eq.${uid}&profil_source=neq.association` +
        `&statut=in.(${ACTIVE_ANNONCE_STATUTS.join(",")})&select=id,created_at&order=created_at.asc`,
    );
    const excess = rows.slice(FREE_MAX_ANNONCES);
    for (const r of excess) {
        try {
            await supabasePatch(`annonces?id=eq.${r.id}`, {statut: "quota_depasse"});
        } catch (e) {
            console.error(`block annonce ${r.id}:`, e.message);
        }
    }
    return excess.length;
}

// ─── Fonction principale ──────────────────────────────────────────────────────

/**
 * Schedulée chaque jour à 8h (heure de Paris — décalée d'une heure par
 * rapport à sendAnnonceExpirationReminders pour ne pas cumuler les cold-starts).
 * 1. Relance J-7/J-1 des abonnements NON auto-renouvelables
 *    (stripe_subscription_id IS NULL — un abonnement Stripe se renouvelle
 *    seul et Stripe gère déjà les échecs de paiement, aucune relance requise).
 * 2. Expire tout abonnement (Stripe ou manuel) dont date_fin est dépassée,
 *    redescend le plan en gratuit, et bloque le surplus d'annonces éleveur.
 */
exports.processAbonnementsExpiration = functions
    .region("europe-west1")
    // Traitement de toute la base en une passe quotidienne : la limite par
    // défaut de 60 s coupait la fonction en plein milieu (timeout du
    // 29/09/2026 → rappels sautés pour une partie des animaux).
    .runWith({timeoutSeconds: 540, memory: "512MB"})
    .pubsub.schedule("0 8 * * *")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        const nowIso = new Date().toISOString();
        let reminders = 0;
        let expired = 0;
        let blocked = 0;

        // ── 1. Relances J-7 / J-1 ───────────────────────────────────────────
        // Essai gratuit 30 j (essai_gratuit, tous les pros) : message dédié
        // « votre essai se termine » au lieu de « votre abonnement expire ».

        const libellePlan = (code) => ({
            premium: "Premium", pro: "Pro", clinique: "Clinique", avance: "Avancé", essentiel: "Essentiel",
        })[code] || code;

        const paliers = [
            {key: "j7", days: 7, phrase: "dans 7 jours"},
            {key: "j1", days: 1, phrase: "demain"},
        ];

        for (const {key, days, phrase} of paliers) {
            const {start, end} = dayRange(days);
            const rows = await supabaseGet(
                `abonnements?date_fin=gte.${encodeURIComponent(start)}` +
                `&date_fin=lt.${encodeURIComponent(end)}` +
                `&statut=eq.actif&stripe_subscription_id=is.null` +
                `&select=id,uid,profile_id,profil_type,plan_code,essai_gratuit,date_fin`,
            );

            for (const a of rows) {
                const dedupKey = `abonnement_relance_${key}_${a.id}`;
                const existing = await supabaseGet(
                    `notifs_sent?key=eq.${encodeURIComponent(dedupKey)}`,
                );
                if (existing.length > 0) continue;

                const essai = a.essai_gratuit === true;
                const title = essai ?
                    `Votre essai ${libellePlan(a.plan_code)} se termine ${phrase}` :
                    `⏳ Votre abonnement expire ${phrase}`;
                const body = essai ?
                    `Votre essai gratuit ${libellePlan(a.plan_code)} se termine ${phrase}. ` +
                    "Choisissez votre formule pour conserver toutes vos fonctionnalités." :
                    `Votre abonnement ${a.plan_code} (${a.profil_type}) expire ${phrase}. ` +
                    "Renouvelez pour ne pas perdre vos avantages.";

                const pushed = await sendPush(a.uid, title, body,
                    {type: "abonnement_expiration", abonnementId: String(a.id)},
                    {profileId: a.profile_id || null});
                if (pushed) reminders++;

                try {
                    await supabaseInsert("notifications", [{
                        uid: a.uid,
                        type: "abonnement_expiration",
                        title,
                        body,
                        data: {abonnementId: String(a.id), palier: key, essai, profilType: a.profil_type},
                        read: false,
                        ...(a.profile_id ? {profile_id: a.profile_id} : {}),
                    }]);
                } catch (e) {
                    console.error(`notifications insert ${a.id}:`, e.message);
                }

                try {
                    await supabaseInsert("notifs_sent", [{key: dedupKey, sent_at: nowIso}]);
                } catch (e) {
                    console.error(`notifs_sent insert ${dedupKey}:`, e.message);
                }
            }
        }

        // ── 1 bis. Abonnements Stripe (prélèvement automatique) ──────────────
        // Gestion : page « Mon abonnement » (migration_abonnements_gestion.sql).
        const stripe = STRIPE_SECRET_KEY ? require("stripe")(STRIPE_SECRET_KEY) : null;
        const montantDe = async (subId) => {
            if (!stripe) return null;
            try {
                const sub = await stripe.subscriptions.retrieve(subId, {expand: ["items.data.price"]});
                const p = sub.items.data[0]?.price?.unit_amount;
                return p != null ? `${(p / 100).toFixed(2).replace(".", ",")} €` : null;
            } catch (_) {
                return null;
            }
        };
        let rappelsStripe = 0;
        // Renouvellement annuel : J-30 et J-7 (jamais pour le mensuel).
        for (const jours of [30, 7]) {
            const {start, end} = dayRange(jours);
            const rows = await supabaseGet(
                `abonnements?statut=eq.actif&periodicite=eq.annuel&stripe_subscription_id=not.is.null` +
                "&resiliation_prevue=eq.false" +
                `&date_fin=gte.${encodeURIComponent(start)}&date_fin=lt.${encodeURIComponent(end)}` +
                "&select=id,stripe_subscription_id,date_fin",
            );
            for (const a of rows) {
                const cle = `abonnement_renouvellement_j${jours}_${a.id}_${String(a.date_fin).slice(0, 10)}`;
                if (!await uneFois(cle, nowIso)) continue;
                const montant = await montantDe(a.stripe_subscription_id);
                await prevenirPro(a.id, "renouvellement", {date: a.date_fin, jours, montant});
                rappelsStripe++;
            }
        }
        // Résiliation demandée : fin d'accès dans 3 jours.
        {
            const {start, end} = dayRange(3);
            const rows = await supabaseGet(
                `abonnements?statut=in.(actif,grace)&resiliation_prevue=eq.true` +
                `&date_fin=gte.${encodeURIComponent(start)}&date_fin=lt.${encodeURIComponent(end)}&select=id,date_fin`,
            );
            for (const a of rows) {
                if (!await uneFois(`abonnement_fin_resiliation_${a.id}`, nowIso)) continue;
                await prevenirPro(a.id, "fin_resiliation", {date: a.date_fin});
                rappelsStripe++;
            }
        }
        // Prélèvement refusé, 7 jours de grâce dépassés : profil en gratuit
        // (données conservées) ; tout revient au paiement (webhook invoice.paid).
        {
            const rows = await supabaseGet(
                `abonnements?statut=eq.grace&grace_jusquau=lt.${encodeURIComponent(nowIso)}` +
                "&select=id,uid,profile_id,profil_type",
            );
            for (const a of rows) {
                try {
                    await supabasePatch(`abonnements?id=eq.${a.id}`, {statut: "suspendu", updated_at: nowIso});
                    const profilePatch = {plan_code: "free", is_premium: false, plan_until: null};
                    if (a.profile_id) await supabasePatch(`user_profiles?id=eq.${a.profile_id}`, profilePatch);
                    else await supabasePatch(`user_profiles?uid=eq.${a.uid}&is_main=eq.true`, profilePatch);
                    await supabasePatch(`users?uid=eq.${a.uid}`, {plan_code: "free", is_premium: false});
                    await prevenirPro(a.id, "suspendu");
                    rappelsStripe++;
                } catch (e) {
                    console.error(`suspension abonnement ${a.id}:`, e.message);
                }
            }
        }
        // Carte bientôt expirée (ce mois-ci ou le suivant) : une fois par mois.
        if (stripe && new Date().getDate() === 1) {
            const rows = await supabaseGet(
                "abonnements?statut=eq.actif&resiliation_prevue=eq.false&stripe_subscription_id=not.is.null" +
                "&select=id,stripe_subscription_id",
            );
            const now = new Date();
            const mois = now.getFullYear() * 12 + now.getMonth() + 1;
            for (const a of rows) {
                try {
                    const sub = await stripe.subscriptions.retrieve(a.stripe_subscription_id, {
                        expand: ["default_payment_method", "customer.invoice_settings.default_payment_method"],
                    });
                    const pm = sub.default_payment_method || sub.customer?.invoice_settings?.default_payment_method;
                    const c = pm && pm.card;
                    if (!c) continue;
                    const exp = c.exp_year * 12 + c.exp_month;
                    if (exp < mois || exp > mois + 1) continue;
                    if (!await uneFois(`abonnement_carte_${a.id}_${c.exp_year}${c.exp_month}`, nowIso)) continue;
                    await prevenirPro(a.id, "carte_expire");
                    rappelsStripe++;
                } catch (e) {
                    console.error(`carte abonnement ${a.id}:`, e.message);
                }
            }
        }
        reminders += rappelsStripe;

        // ── 2. Expiration ────────────────────────────────────────────────────

        const toExpire = await supabaseGet(
            `abonnements?statut=eq.actif&date_fin=lt.${encodeURIComponent(nowIso)}` +
            `&select=id,uid,profile_id,profil_type,plan_code,essai_gratuit`,
        );

        for (const a of toExpire) {
            try {
                await supabasePatch(`abonnements?id=eq.${a.id}`, {statut: "expire", updated_at: nowIso});

                const profilePatch = {plan_code: "free", is_premium: false, plan_until: null};
                if (a.profile_id) {
                    await supabasePatch(`user_profiles?id=eq.${a.profile_id}`, profilePatch);
                } else {
                    await supabasePatch(
                        `user_profiles?uid=eq.${a.uid}&profile_type=eq.${a.profil_type}`, profilePatch);
                }
                await supabasePatch(`users?uid=eq.${a.uid}`, {plan_code: "free", is_premium: false});
                expired++;

                // Fin d'essai gratuit : prévenir le pro (une seule fois).
                if (a.essai_gratuit === true) {
                    const dedupFin = `abonnement_essai_fin_${a.id}`;
                    const deja = await supabaseGet(`notifs_sent?key=eq.${encodeURIComponent(dedupFin)}`);
                    if (deja.length === 0) {
                        const title = `Votre essai ${libellePlan(a.plan_code)} est terminé`;
                        const body = "Votre compte est passé en formule Découverte. " +
                            "Choisissez une formule pour retrouver toutes vos fonctionnalités.";
                        await sendPush(a.uid, title, body,
                            {type: "abonnement_expiration", abonnementId: String(a.id)},
                            {profileId: a.profile_id || null});
                        try {
                            await supabaseInsert("notifications", [{
                                uid: a.uid, type: "abonnement_expiration", title, body,
                                data: {
                                    abonnementId: String(a.id), palier: "fin", essai: true,
                                    profilType: a.profil_type,
                                },
                                read: false,
                                ...(a.profile_id ? {profile_id: a.profile_id} : {}),
                            }]);
                            await supabaseInsert("notifs_sent", [{key: dedupFin, sent_at: nowIso}]);
                        } catch (e) {
                            console.error(`fin essai ${a.id}:`, e.message);
                        }
                    }
                }

                // Blocage rétroactif du surplus d'annonces — éleveur
                // uniquement, seul métier avec un contenu public quota-géré
                // aujourd'hui (garde/santé/etc. redescendent bien en gratuit
                // ci-dessus, mais n'ont pas d'équivalent d'annonce à bloquer).
                if (a.profil_type === "eleveur") {
                    blocked += await blockExcessAnnonces(a.uid);
                }
            } catch (e) {
                console.error(`expire abonnement ${a.id}:`, e.message);
            }
        }

        console.log(
            `processAbonnementsExpiration: ${reminders} relances, ${expired} expirés, ` +
            `${blocked} annonces bloquées.`,
        );
        return null;
    });
