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
                try { resolve({ status: res.statusCode, body: JSON.parse(data) }); }
                catch (_) { resolve({ status: res.statusCode, body: [] }); }
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

async function supabaseInsert(table, rows, onConflict = null) {
    const prefer = onConflict
        ? `resolution=ignore-duplicates,return=minimal`
        : "return=minimal";
    const res = await supabaseRequest("POST", table, rows, { "Prefer": prefer });
    return res.status;
}

// ─── FCM helper ───────────────────────────────────────────────────────────────

async function sendPush(uid, title, body, data = {}) {
    try {
        const doc = await admin.firestore().collection("users").doc(uid).get();
        const token = doc.exists ? doc.data().fcmToken : null;
        if (!token) return false;

        await admin.messaging().send({
            token,
            notification: { title, body },
            data: { type: "chaleur", ...data },
            android: {
                priority: "high",
                notification: { channelId: "chaleurs_channel", sound: "default" },
            },
            apns: {
                headers: { "apns-priority": "10" },
                payload: { aps: { alert: { title, body }, sound: "default", badge: 1 } },
            },
        });
        return true;
    } catch (e) {
        console.error(`sendPush error for ${uid}:`, e);
        return false;
    }
}

// ─── Domaine : chaleurs ───────────────────────────────────────────────────────

function intervalChaleurs(espece) {
    switch ((espece || "").toLowerCase()) {
        case "chien":  return 182;
        case "chat":   return 21;
        case "lapin":  return 14;
        case "ovin":   return 17;
        case "caprin": return 21;
        case "porcin": return 21;
        case "cheval": return 21;
        default:       return 0;
    }
}

function emojiEspece(espece) {
    switch ((espece || "").toLowerCase()) {
        case "chien":  return "🐕";
        case "chat":   return "🐈";
        case "cheval": return "🐴";
        case "lapin":  return "🐰";
        case "ovin":   return "🐑";
        case "caprin": return "🐐";
        case "porcin": return "🐷";
        default:       return "🐾";
    }
}

// ─── Fonction principale ──────────────────────────────────────────────────────

/**
 * Schedulée chaque jour à 8h (heure de Paris).
 * Pour chaque femelle éleveuse dont les prochaines chaleurs arrivent dans ≤ 7 jours,
 * envoie un push FCM + notif in-app Supabase — une seule fois par cycle.
 */
exports.sendChaleursNotifications = functions
    .region("europe-west1")
    .pubsub.schedule("0 8 * * *")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        const now = new Date();
        let sent = 0;
        let inApp = 0;

        // 1. Fetch all female animals (not departed/deceased)
        const animaux = await supabaseSelect("animaux",
            "sexe=eq.femelle" +
            "&statut=not.in.(sorti,decede)" +
            "&select=id,nom,race,espece,uid_eleveur,intervalle_chaleurs_jours");

        if (!animaux.length) {
            console.log("sendChaleursNotifications: aucune femelle active.");
            return null;
        }

        const femIds = animaux.map((a) => a.id);

        // 2. Fetch last chaleur per animal (sorted desc, one per animal)
        const chaleursRaw = await supabaseSelect("chaleurs",
            `animal_id=in.(${femIds.join(",")})&order=date.desc`);

        const lastChaleur = {};
        for (const c of chaleursRaw) {
            if (!lastChaleur[c.animal_id]) {
                const d = c.date ? new Date(c.date) : null;
                if (d && !isNaN(d.getTime())) lastChaleur[c.animal_id] = d;
            }
        }

        // 3. Process each animal
        for (const animal of animaux) {
            const last = lastChaleur[animal.id];
            if (!last) continue;

            const interval = animal.intervalle_chaleurs_jours || intervalChaleurs(animal.espece);
            if (!interval) continue;

            const nextHeat = new Date(last.getTime() + interval * 86400000);
            // Dart-compatible: Math.trunc = integer division towards zero (same as Duration.inDays)
            const diffMs = nextHeat.getTime() - now.getTime();
            const diff = Math.trunc(diffMs / 86400000);

            // Notify only if within 7 days ahead or overdue (up to 30 days)
            if (diff > 7 || diff < -30) continue;

            // Deduplication key: one notif per animal per heat cycle
            const nextHeatKey = nextHeat.toISOString().slice(0, 10);
            const key = `chaleur_${animal.id}_${nextHeatKey}`;

            // Check if already sent this cycle
            const existing = await supabaseSelect("notifs_sent", `key=eq.${encodeURIComponent(key)}`);
            if (existing.length > 0) continue;

            // Build notification content
            const nom = animal.nom || "Animal";
            const race = animal.race;
            const espece = animal.espece || "";
            const subtitle = [race, espece].filter((s) => s && s.trim()).join(" · ");
            const em = emojiEspece(espece);

            let title, body;
            if (diff < 0) {
                title = `🌸 Chaleurs probables — ${nom}`;
                body = `${em} ${nom} (${subtitle}) est probablement en chaleurs (${-diff} j de retard).`;
            } else if (diff === 0) {
                title = `🌸 Chaleurs aujourd'hui — ${nom}`;
                body = `${em} ${nom} (${subtitle}) est attendue en chaleurs aujourd'hui.`;
            } else if (diff === 1) {
                title = `🌸 Chaleurs demain — ${nom}`;
                body = `${em} ${nom} (${subtitle}) sera en chaleurs demain.`;
            } else {
                title = `🌸 Chaleurs dans ${diff} jours — ${nom}`;
                body = `${em} ${nom} (${subtitle}) sera en chaleurs dans ${diff} jours.`;
            }

            // Mark as sent FIRST to avoid duplicates if push/notif insert fails
            try {
                await supabaseInsert("notifs_sent", [{ key, sent_at: now.toISOString() }], "key");
            } catch (e) {
                console.error(`notifs_sent insert error for ${key}:`, e);
                continue; // skip if we can't mark it
            }

            // Send FCM push
            const pushed = await sendPush(
                animal.uid_eleveur,
                title,
                body,
                { animalId: String(animal.id) },
            );
            if (pushed) sent++;

            // Insert in-app notification into Supabase
            try {
                await supabaseInsert("notifications", [{
                    uid: animal.uid_eleveur,
                    type: "chaleur",
                    title,
                    body,
                    data: { animalId: String(animal.id) },
                    read: false,
                }]);
                inApp++;
            } catch (e) {
                console.error(`notifications insert error for animal ${animal.id}:`, e);
            }
        }

        console.log(`sendChaleursNotifications: ${sent} push FCM + ${inApp} notifs in-app.`);
        return null;
    });
