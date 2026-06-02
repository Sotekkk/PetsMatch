const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const https = require("https");

const SUPABASE_URL = "https://zyvpngcvzrkdytypjlyq.supabase.co";
const SUPABASE_SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" +
    ".eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5dnBuZ2N2enJrZHl0eXBqbHlxIiwi" +
    "cm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTM2NDY1NSwiZXhwIjoyMDk0OT" +
    "QwNjU1fQ.1U96V3c7nHG3T08dboBcxTd05k8A_JQfnyrJTbJ0HgQ";

// ─── Helpers Supabase ─────────────────────────────────────────────────────────

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

// ─── FCM helper ───────────────────────────────────────────────────────────────

async function sendPush(uid, title, body, data = {}) {
    try {
        const doc = await admin.firestore().collection("users").doc(uid).get();
        const token = doc.exists ? doc.data().fcmToken : null;
        if (!token) return false;
        await admin.messaging().send({
            token,
            notification: {title, body},
            data: {type: "annonce_expiration", ...data},
            android: {
                priority: "high",
                notification: {channelId: "high_importance_channel", sound: "default"},
            },
            apns: {
                headers: {"apns-priority": "10"},
                payload: {aps: {alert: {title, body}, sound: "default", badge: 1}},
            },
        });
        return true;
    } catch (e) {
        console.error(`sendPush uid=${uid}:`, e.message);
        return false;
    }
}

// ─── Helpers date ─────────────────────────────────────────────────────────────

function dayRange(daysFromNow) {
    const start = new Date();
    start.setDate(start.getDate() + daysFromNow);
    start.setHours(0, 0, 0, 0);
    const end = new Date(start);
    end.setDate(end.getDate() + 1);
    return {start: start.toISOString(), end: end.toISOString()};
}

// ─── Fonction principale ──────────────────────────────────────────────────────

/**
 * Schedulée chaque jour à 7h (heure de Paris).
 * 1. Expire les annonces dont expires_at < maintenant
 * 2. Envoie des rappels FCM J-7 et J-1 avant expiration
 */
exports.sendAnnonceExpirationReminders = functions
    .region("europe-west1")
    .pubsub.schedule("0 7 * * *")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        const now = new Date().toISOString();
        let expired = 0;
        let reminders = 0;

        // ── 1. Expirer les annonces dépassées ─────────────────────────────────

        const toExpire = await supabaseGet(
            // eslint-disable-next-line max-len
            `annonces?expires_at=lt.${encodeURIComponent(now)}&statut=in.(disponible,pause,reserve)&select=id`,
        );

        for (const a of toExpire) {
            try {
                await supabasePatch(`annonces?id=eq.${a.id}`, {statut: "expiree"});
                expired++;
            } catch (e) {
                console.error(`expire annonce ${a.id}:`, e.message);
            }
        }

        // ── 2. Rappels J-7 et J-1 ────────────────────────────────────────────

        const paliers = [
            {key: "j7", days: 7, phrase: "dans 7 jours"},
            {key: "j1", days: 1, phrase: "demain"},
        ];

        for (const {key, days, phrase} of paliers) {
            const {start, end} = dayRange(days);
            const annonces = await supabaseGet(
                `annonces?expires_at=gte.${encodeURIComponent(start)}` +
                `&expires_at=lt.${encodeURIComponent(end)}` +
                `&statut=in.(disponible,pause)` +
                `&select=id,uid_eleveur,titre,espece,race`,
            );

            for (const a of annonces) {
                if (!a.uid_eleveur) continue;
                const dedupKey = `annonce_exp_${key}_${a.id}`;
                const existing = await supabaseGet(
                    `notifs_sent?key=eq.${encodeURIComponent(dedupKey)}`,
                );
                if (existing.length > 0) continue;

                const label = a.titre || [a.espece, a.race].filter(Boolean).join(" ") || "Annonce";
                const title = `⏳ Annonce expirant ${phrase}`;
                const body = `Votre annonce "${label}" expire ${phrase}. Renouvelez-la pour rester visible.`;

                const pushed = await sendPush(a.uid_eleveur, title, body, {annonceId: String(a.id)});
                if (pushed) reminders++;

                try {
                    await supabaseInsert("notifications", [{
                        uid: a.uid_eleveur,
                        type: "annonce_expiration",
                        title,
                        body,
                        data: {annonceId: String(a.id), palier: key},
                        read: false,
                    }]);
                } catch (e) {
                    console.error(`notifications insert ${a.id}:`, e.message);
                }

                try {
                    await supabaseInsert("notifs_sent", [{key: dedupKey, sent_at: now}]);
                } catch (e) {
                    console.error(`notifs_sent insert ${dedupKey}:`, e.message);
                }
            }
        }

        console.log(`sendAnnonceExpirationReminders: ${expired} expirées, ${reminders} rappels envoyés.`);
        return null;
    });
