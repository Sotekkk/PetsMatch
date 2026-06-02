const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const https = require("https");

const SUPABASE_URL = "https://zyvpngcvzrkdytypjlyq.supabase.co";
const SUPABASE_SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" +
    ".eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5dnBuZ2N2enJrZHl0eXBqbHlxIiwi" +
    "cm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTM2NDY1NSwiZXhwIjoyMDk0OT" +
    "QwNjU1fQ.1U96V3c7nHG3T08dboBcxTd05k8A_JQfnyrJTbJ0HgQ";

// ─── Ages de retraite reproductive par espèce (en années) ────────────────────

const AGES_RETRAITE = {
    chien: 7,
    chat: 8,
    lapin: 5,
    cheval: 18,
    ovin: 8,
    caprin: 8,
    porcin: 5,
    ane: 15,
};

function emojiEspece(espece) {
    switch ((espece || "").toLowerCase()) {
    case "chien": return "🐕";
    case "chat": return "🐈";
    case "cheval": return "🐴";
    case "lapin": return "🐰";
    case "ovin": return "🐑";
    case "caprin": return "🐐";
    case "porcin": return "🐷";
    case "ane": return "🫏";
    default: return "🐾";
    }
}

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
            data: {type: "retraite", ...data},
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
        console.error(`sendPush error for ${uid}:`, e);
        return false;
    }
}

// ─── Fonction principale ──────────────────────────────────────────────────────

/**
 * Schedulée chaque jour à 8h (heure de Paris).
 * Notifie l'éleveur J-30 et J-0 quand une femelle non stérilisée
 * atteint l'âge de retraite reproductive selon son espèce.
 */
exports.sendRetraiteReminders = functions
    .region("europe-west1")
    .pubsub.schedule("0 8 * * *")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        const now = new Date();
        let sent = 0;

        // Femelles actives, non stérilisées, avec date de naissance
        const animaux = await supabaseSelect("animaux",
            "sexe=eq.femelle" +
            "&sterilise=eq.false" +
            "&statut=not.in.(sorti,decede)" +
            "&date_naissance=not.is.null");

        for (const animal of animaux) {
            if (!animal.uid_eleveur || !animal.date_naissance) continue;

            const ageRetraite = AGES_RETRAITE[(animal.espece || "").toLowerCase()];
            if (!ageRetraite) continue;

            const dateNaissance = new Date(animal.date_naissance);
            if (isNaN(dateNaissance.getTime())) continue;

            // Date anniversaire de retraite
            const retraiteBirthday = new Date(
                dateNaissance.getFullYear() + ageRetraite,
                dateNaissance.getMonth(),
                dateNaissance.getDate(),
            );

            const diffDays = Math.trunc(
                (retraiteBirthday.getTime() - now.getTime()) / 86400000,
            );

            // Paliers : J-30 et J-0 (jusqu'à 30 j après)
            let palier = null;
            if (diffDays >= 28 && diffDays <= 32) palier = "j30";
            else if (diffDays >= -30 && diffDays <= 2) palier = "j0";
            if (!palier) continue;

            const retirementYear = retraiteBirthday.getFullYear();
            const key = `retraite_${palier}_${animal.id}_${retirementYear}`;

            const existing = await supabaseSelect("notifs_sent", `key=eq.${encodeURIComponent(key)}`);
            if (existing.length > 0) continue;

            const nom = animal.nom || "Votre femelle";
            const em = emojiEspece(animal.espece);
            const dateStr = retraiteBirthday.toLocaleDateString("fr-FR", {
                day: "numeric", month: "long", year: "numeric",
            });

            let title;
            let body;
            if (palier === "j30") {
                title = `⚠️ Retraite reproductive dans 1 mois — ${nom}`;
                // eslint-disable-next-line max-len
                body = `${em} ${nom} approche de l'âge de retraite reproductive (${ageRetraite} ans le ${dateStr}). Pensez à prévoir sa mise en retraite.`;
            } else {
                title = `🏁 Retraite reproductive atteinte — ${nom}`;
                // eslint-disable-next-line max-len
                body = `${em} ${nom} a atteint l'âge de retraite reproductive (${ageRetraite} ans). Il est recommandé d'arrêter la reproduction.`;
            }

            const pushed = await sendPush(
                animal.uid_eleveur,
                title, body,
                {animalId: String(animal.id)},
            );
            if (pushed) sent++;

            try {
                await supabaseInsert("notifications", [{
                    uid: animal.uid_eleveur,
                    type: "retraite",
                    title, body,
                    data: {animalId: String(animal.id)},
                    read: false,
                }]);
            } catch (e) {
                console.error(`notifications insert error for animal ${animal.id}:`, e.message);
            }

            try {
                await supabaseInsert("notifs_sent", [{key, sent_at: now.toISOString()}]);
            } catch (e) {
                console.error(`notifs_sent insert error for ${key}:`, e.message);
            }
        }

        console.log(`sendRetraiteReminders: ${sent} notifications envoyées.`);
        return null;
    });
