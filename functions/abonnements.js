const functions = require("firebase-functions/v1");
const https = require("https");

const SUPABASE_URL = "https://zyvpngcvzrkdytypjlyq.supabase.co";
const SUPABASE_SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" +
    ".eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5dnBuZ2N2enJrZHl0eXBqbHlxIiwi" +
    "cm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTM2NDY1NSwiZXhwIjoyMDk0OT" +
    "QwNjU1fQ.1U96V3c7nHG3T08dboBcxTd05k8A_JQfnyrJTbJ0HgQ";

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
                "apikey": SUPABASE_SERVICE_KEY,
                "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
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
    .pubsub.schedule("0 8 * * *")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        const nowIso = new Date().toISOString();
        let reminders = 0;
        let expired = 0;
        let blocked = 0;

        // ── 1. Relances J-7 / J-1 ───────────────────────────────────────────

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
                `&select=id,uid,profile_id,profil_type,plan_code`,
            );

            for (const a of rows) {
                const dedupKey = `abonnement_relance_${key}_${a.id}`;
                const existing = await supabaseGet(
                    `notifs_sent?key=eq.${encodeURIComponent(dedupKey)}`,
                );
                if (existing.length > 0) continue;

                const title = `⏳ Votre abonnement expire ${phrase}`;
                const body = `Votre abonnement ${a.plan_code} (${a.profil_type}) expire ${phrase}. ` +
                    `Renouvelez pour ne pas perdre vos avantages.`;

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
                        data: {abonnementId: String(a.id), palier: key},
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

        // ── 2. Expiration ────────────────────────────────────────────────────

        const toExpire = await supabaseGet(
            `abonnements?statut=eq.actif&date_fin=lt.${encodeURIComponent(nowIso)}` +
            `&select=id,uid,profile_id,profil_type,plan_code`,
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
