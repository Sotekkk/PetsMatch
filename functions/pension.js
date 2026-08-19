const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const https = require("https");

const SUPABASE_URL = "https://zyvpngcvzrkdytypjlyq.supabase.co";
const SUPABASE_SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" +
    ".eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5dnBuZ2N2enJrZHl0eXBqbHlxIiwi" +
    "cm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTM2NDY1NSwiZXhwIjoyMDk0OT" +
    "QwNjU1fQ.1U96V3c7nHG3T08dboBcxTd05k8A_JQfnyrJTbJ0HgQ";

// ─── Supabase helpers ─────────────────────────────────────────────────────────

function supabaseRequest(method, path, body, extraHeaders = {}) {
    return new Promise((resolve, reject) => {
        const bodyStr = body ? JSON.stringify(body) : null;
        const url = new URL(`${SUPABASE_URL}/rest/v1/${path}`);
        const options = {
            hostname: url.hostname,
            path: url.pathname + (url.search || ""),
            method,
            headers: {
                "Content-Type": "application/json",
                "apikey": SUPABASE_SERVICE_KEY,
                "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
                "Prefer": method === "GET" ? "" : "return=minimal",
                ...extraHeaders,
            },
        };
        if (bodyStr) options.headers["Content-Length"] = Buffer.byteLength(bodyStr);

        const req = https.request(options, (res) => {
            let data = "";
            res.on("data", (chunk) => data += chunk);
            res.on("end", () => {
                try {
                    resolve({status: res.statusCode, body: JSON.parse(data)});
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

async function supabaseSelect(table, query) {
    const res = await supabaseRequest("GET", `${table}?${query}&select=*`);
    return Array.isArray(res.body) ? res.body : [];
}

async function supabaseInsert(table, rows) {
    const res = await supabaseRequest("POST", table, rows, {"Prefer": "return=minimal"});
    if (res.status < 200 || res.status >= 300) {
        throw new Error(`Supabase insert ${table}: HTTP ${res.status} — ${JSON.stringify(res.body)}`);
    }
    return res.status;
}

// ─── FCM helper ───────────────────────────────────────────────────────────────

async function sendPush(uid, title, body, data = {}) {
    try {
        const doc = await admin.firestore().collection("users").doc(uid).get();
        if (!doc.exists) return false;
        const userData = doc.data();
        const tokens = [userData.fcmToken, userData.webFcmToken].filter(Boolean);
        if (!tokens.length) return false;

        let sent = false;
        for (const token of tokens) {
            try {
                await admin.messaging().send({
                    token,
                    data: {type: "pension_sortie", title, body, ...data},
                    android: {
                        priority: "high",
                    },
                    apns: {
                        headers: {"apns-priority": "10"},
                        payload: {aps: {alert: {title, body}, sound: "default", badge: 1}},
                    },
                });
                sent = true;
            } catch (e) {
                console.warn(`sendPush token error for ${uid}:`, e.message);
            }
        }
        return sent;
    } catch (e) {
        console.error(`sendPush error for ${uid}:`, e);
        return false;
    }
}

// ─── Rappels sortie de pension en retard ───────────────────────────────────────

/**
 * Schedulée chaque jour à 8h (heure de Paris).
 * Pour chaque séjour en pension dont la date de sortie prévue est dépassée
 * sans qu'une sortie effective ait été loggée, envoie un rappel CHAQUE JOUR
 * tant que la pension n'a pas :
 *   - loggé la sortie effective (date_sortie_effective), ou
 *   - explicitement coupé le rappel (notifs_sent : pension_sortie_muted_<id>).
 */
exports.sendPensionSortieReminders = functions
    .region("europe-west1")
    .pubsub.schedule("0 8 * * *")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        const now = new Date(new Date().toLocaleString("en-US", {timeZone: "Europe/Paris"}));
        const y = now.getFullYear();
        const mo = String(now.getMonth() + 1).padStart(2, "0");
        const d = String(now.getDate()).padStart(2, "0");
        const todayStr = `${y}-${mo}-${d}`;

        const entrees = await supabaseSelect("pension_entrees",
            "statut=eq.en_pension" +
            "&date_sortie_effective=is.null" +
            "&date_sortie_prevue=not.is.null" +
            `&date_sortie_prevue=lt.${todayStr}`);

        if (!entrees.length) {
            console.log("sendPensionSortieReminders: aucune sortie en retard.");
            return null;
        }

        let sent = 0;
        let inApp = 0;

        for (const e of entrees) {
            if (!e.pro_uid) continue;

            const muteKey = `pension_sortie_muted_${e.id}`;
            const muted = await supabaseSelect("notifs_sent", `key=eq.${encodeURIComponent(muteKey)}`);
            if (muted.length > 0) continue;

            const dedupKey = `pension_sortie_overdue_${e.id}_${todayStr}`;
            const existing = await supabaseSelect("notifs_sent", `key=eq.${encodeURIComponent(dedupKey)}`);
            if (existing.length > 0) continue;

            const nom = e.animal_nom || "L'animal";
            const dateSortie = new Date(e.date_sortie_prevue).toLocaleDateString("fr-FR", {
                day: "numeric", month: "long",
            });
            const joursRetard = Math.round(
                (new Date(todayStr) - new Date(e.date_sortie_prevue)) / 86400000,
            );

            const title = `⚠️ Sortie de pension en retard — ${nom}`;
            const joursTxt = `${joursRetard} jour${joursRetard > 1 ? "s" : ""}`;
            const body = `${nom} devait sortir le ${dateSortie} (${joursTxt} de retard). Toujours en pension ?`;

            const pushed = await sendPush(e.pro_uid, title, body, {entreeId: String(e.id)});
            if (pushed) sent++;

            try {
                await supabaseInsert("notifications", [{
                    uid: e.pro_uid,
                    type: "pension_sortie",
                    title,
                    body,
                    data: {entreeId: String(e.id), animalId: e.animal_id, overdue: true},
                    read: false,
                    ...(e.pro_profile_id ? {profile_id: e.pro_profile_id} : {}),
                }]);
                inApp++;
            } catch (err) {
                console.error(`notifications insert error (pension_entrees ${e.id}):`, err.message);
            }

            try {
                await supabaseInsert("notifs_sent", [{key: dedupKey, sent_at: new Date().toISOString()}]);
            } catch (err) {
                console.error(`notifs_sent insert error (${dedupKey}):`, err.message);
            }
        }

        console.log(`sendPensionSortieReminders: ${sent} push FCM + ${inApp} notifs in-app.`);
        return null;
    });
