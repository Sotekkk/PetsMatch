const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const https = require("https");

if (!admin.apps.length) admin.initializeApp();

// Clé partagée avec alertes.js — à définir via :
//   firebase functions:config:set supabase.url="..." supabase.service_key="..."
// Ou laisser alertes.js comme source de vérité et importer depuis process.env.
const SUPABASE_URL = process.env.SUPABASE_URL ||
    (functions.config().supabase || {}).url ||
    "https://zyvpngcvzrkdytypjlyq.supabase.co";
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY ||
    (functions.config().supabase || {}).service_key ||
    "";

/** GET from Supabase via REST */
async function supabaseGet(path) {
    return new Promise((resolve, reject) => {
        const options = {
            hostname: new URL(SUPABASE_URL).hostname,
            path: `/rest/v1/${path}`,
            method: "GET",
            headers: {
                "apikey": SUPABASE_SERVICE_KEY,
                "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
                "Accept": "application/json",
            },
        };
        const req = https.request(options, (res) => {
            let data = "";
            res.on("data", (c) => data += c);
            res.on("end", () => {
                if (res.statusCode >= 200 && res.statusCode < 300) {
                    try {
                        resolve(JSON.parse(data));
                    } catch (e) {
                        reject(e);
                    }
                } else {
                    reject(new Error(`Supabase GET ${path}: ${res.statusCode} — ${data}`));
                }
            });
        });
        req.on("error", reject);
        req.end();
    });
}

/** PATCH a single row in Supabase */
async function supabasePatch(table, id, body) {
    return new Promise((resolve, reject) => {
        const bodyStr = JSON.stringify(body);
        const options = {
            hostname: new URL(SUPABASE_URL).hostname,
            path: `/rest/v1/${table}?id=eq.${id}`,
            method: "PATCH",
            headers: {
                "Content-Type": "application/json",
                "Content-Length": Buffer.byteLength(bodyStr),
                "apikey": SUPABASE_SERVICE_KEY,
                "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
                "Prefer": "return=minimal",
            },
        };
        const req = https.request(options, (res) => {
            res.resume();
            res.on("end", () => resolve());
        });
        req.on("error", reject);
        req.write(bodyStr);
        req.end();
    });
}

/** INSERT into Supabase */
async function supabaseInsert(table, rows) {
    return new Promise((resolve, reject) => {
        const body = JSON.stringify(rows);
        const options = {
            hostname: new URL(SUPABASE_URL).hostname,
            path: `/rest/v1/${table}`,
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "Content-Length": Buffer.byteLength(body),
                "apikey": SUPABASE_SERVICE_KEY,
                "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
                "Prefer": "return=minimal",
            },
        };
        const req = https.request(options, (res) => {
            res.resume();
            res.on("end", () => {
                if (res.statusCode >= 200 && res.statusCode < 300) resolve();
                else reject(new Error(`Supabase insert ${table}: ${res.statusCode}`));
            });
        });
        req.on("error", reject);
        req.write(body);
        req.end();
    });
}

/**
 * Envoie les rappels FCM + in-app pour les RDVs à venir.
 * Fenêtre 1h : entre now+55min et now+65min (reminder_1h_sent = false)
 * Fenêtre 15min : entre now+10min et now+20min (reminder_15min_sent = false)
 * Tourne toutes les 5 minutes.
 */
exports.sendRdvReminders = functions
    .region("europe-west1")
    .pubsub.schedule("every 5 minutes")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        const now = new Date();
        const fmtISO = (d) => d.toISOString();

        // Fenêtres de rappel
        const windows = [
            {
                label: "1h",
                from: fmtISO(new Date(now.getTime() + 55 * 60 * 1000)),
                to: fmtISO(new Date(now.getTime() + 65 * 60 * 1000)),
                sentField: "reminder_1h_sent",
                title: "RDV dans 1 heure",
                body: (proName, motif) =>
                    `Votre RDV avec ${proName} est dans 1 heure${motif ? ` — ${motif}` : ""}.`,
            },
            {
                label: "15min",
                from: fmtISO(new Date(now.getTime() + 10 * 60 * 1000)),
                to: fmtISO(new Date(now.getTime() + 20 * 60 * 1000)),
                sentField: "reminder_15min_sent",
                title: "RDV dans 15 minutes",
                body: (proName, motif) =>
                    `Votre RDV avec ${proName} commence dans 15 minutes${motif ? ` — ${motif}` : ""}.`,
            },
        ];

        for (const win of windows) {
            let rdvs;
            try {
                const qs = `statut=eq.confirme` +
                    `&date_heure=gte.${encodeURIComponent(win.from)}` +
                    `&date_heure=lte.${encodeURIComponent(win.to)}` +
                    `&${win.sentField}=eq.false` +
                    `&select=id,client_uid,pro_uid,motif,date_heure`;
                rdvs = await supabaseGet(`rdv?${qs}`);
            } catch (e) {
                console.error(`sendRdvReminders [${win.label}] fetch error:`, e);
                continue;
            }

            for (const rdv of rdvs) {
                try {
                    // Nom du pro depuis Firestore
                    const proDoc = await admin.firestore()
                        .collection("users").doc(rdv.pro_uid).get();
                    const proData = proDoc.exists ? proDoc.data() : {};
                    const proName = proData.nameElevage || proData.professionPro || "votre praticien";

                    // FCM token du client
                    const clientDoc = await admin.firestore()
                        .collection("users").doc(rdv.client_uid).get();
                    const fcmToken = clientDoc.exists ? clientDoc.data()?.fcmToken : null;

                    const title = win.title;
                    const body = win.body(proName, rdv.motif);

                    // Notification in-app
                    await supabaseInsert("notifications", [{
                        uid: rdv.client_uid,
                        type: `rdv_rappel_${win.label.replace("min", "m")}`,
                        title: title,
                        body: body,
                        data: {rdv_id: rdv.id},
                        read: false,
                    }]);

                    // Push FCM
                    if (fcmToken) {
                        await admin.messaging().send({
                            token: fcmToken,
                            notification: {title, body},
                            data: {type: "rdv_rappel", rdv_id: rdv.id},
                            android: {
                                priority: "high",
                                notification: {channelId: "rdv_rappels", sound: "default"},
                            },
                            apns: {
                                headers: {"apns-priority": "10"},
                                payload: {aps: {sound: "default"}},
                            },
                        });
                    }

                    // Marquer comme envoyé (évite les doublons)
                    await supabasePatch("rdv", rdv.id, {[win.sentField]: true});

                    console.log(`Rappel ${win.label} envoyé → RDV ${rdv.id} (client ${rdv.client_uid})`);
                } catch (e) {
                    console.error(`sendRdvReminders [${win.label}] error for RDV ${rdv.id}:`, e);
                }
            }
        }

        return null;
    });
