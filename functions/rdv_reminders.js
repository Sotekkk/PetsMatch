const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const https = require("https");

if (!admin.apps.length) admin.initializeApp();

// Même clé service_role que alertes.js / agenda.js (hardcodée par cohérence —
// functions.config().supabase.service_key n'est PAS défini sur ce projet, donc
// le repli "" faisait échouer TOUS les GET Supabase en 401 → aucun rappel).
const SUPABASE_URL = "https://zyvpngcvzrkdytypjlyq.supabase.co";
const SUPABASE_SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" +
    ".eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5dnBuZ2N2enJrZHl0eXBqbHlxIiwi" +
    "cm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTM2NDY1NSwiZXhwIjoyMDk0" +
    "OTQwNjU1fQ.1U96V3c7nHG3T08dboBcxTd05k8A_JQfnyrJTbJ0HgQ";

// Site pour l'email de rappel des clients sans compte PetsMatch.
const SITE_URL = process.env.SITE_URL ||
    (functions.config().site || {}).url ||
    "https://petsmatchapp.com";

/** POST JSON vers une route du site (ex. /api/rdv/reminder-email). */
function sitePost(path, payload) {
    return new Promise((resolve) => {
        try {
            const body = JSON.stringify(payload);
            const u = new URL(`${SITE_URL}${path}`);
            const req = https.request({
                hostname: u.hostname,
                path: u.pathname + u.search,
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "Content-Length": Buffer.byteLength(body),
                },
            }, (res) => {
                res.on("data", () => {});
                res.on("end", resolve);
            });
            req.on("error", () => resolve());
            req.write(body);
            req.end();
        } catch (e) {
            resolve();
        }
    });
}

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

        // Fenêtres de rappel : 24 h, 1 h, 30 min avant le RDV.
        const windows = [
            {
                label: "24h",
                echeance: "24h",
                from: fmtISO(new Date(now.getTime() + (24 * 60 - 5) * 60 * 1000)),
                to: fmtISO(new Date(now.getTime() + (24 * 60 + 5) * 60 * 1000)),
                sentField: "reminder_24h_sent",
                title: "RDV demain",
                body: (proName, motif) =>
                    `Rappel : votre RDV avec ${proName} est demain${motif ? ` — ${motif}` : ""}.`,
                proTitle: "Visite demain",
                proBody: (who, extra) =>
                    `Rappel : visite avec ${who} demain${extra ? ` — ${extra}` : ""}.`,
            },
            {
                label: "1h",
                echeance: "1h",
                from: fmtISO(new Date(now.getTime() + 55 * 60 * 1000)),
                to: fmtISO(new Date(now.getTime() + 65 * 60 * 1000)),
                sentField: "reminder_1h_sent",
                title: "RDV dans 1 heure",
                body: (proName, motif) =>
                    `Votre RDV avec ${proName} est dans 1 heure${motif ? ` — ${motif}` : ""}.`,
                proTitle: "Visite dans 1 heure",
                proBody: (who, extra) =>
                    `Visite avec ${who} dans 1 heure${extra ? ` — ${extra}` : ""}.`,
            },
            {
                label: "30min",
                echeance: "30min",
                from: fmtISO(new Date(now.getTime() + 25 * 60 * 1000)),
                to: fmtISO(new Date(now.getTime() + 35 * 60 * 1000)),
                sentField: "reminder_30min_sent",
                title: "RDV dans 30 minutes",
                body: (proName, motif) =>
                    `Votre RDV avec ${proName} commence dans 30 minutes${motif ? ` — ${motif}` : ""}.`,
                proTitle: "Visite dans 30 minutes",
                proBody: (who, extra) =>
                    `Visite avec ${who} dans 30 minutes${extra ? ` — ${extra}` : ""}.`,
            },
        ];

        for (const win of windows) {
            let rdvs;
            try {
                const cols = "id,client_uid,client_profile_id,client_email_manuel," +
                    "client_nom_manuel,pro_uid,pro_profile_id,animal_id,animal_nom_manuel," +
                    "motif,date_heure,duree_minutes,lieu";
                const qs = `statut=eq.confirme` +
                    `&date_heure=gte.${encodeURIComponent(win.from)}` +
                    `&date_heure=lte.${encodeURIComponent(win.to)}` +
                    `&${win.sentField}=eq.false&select=${cols}`;
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

                    const title = win.title;
                    const body = win.body(proName, rdv.motif);

                    if (rdv.client_uid) {
                        // Client avec compte : notif in-app + push FCM
                        const clientDoc = await admin.firestore()
                            .collection("users").doc(rdv.client_uid).get();
                        const fcmToken = clientDoc.exists ? clientDoc.data()?.fcmToken : null;

                        await supabaseInsert("notifications", [{
                            uid: rdv.client_uid,
                            type: "rdv_rappel",
                            title: title,
                            body: body,
                            data: {rdv_id: rdv.id, echeance: win.echeance},
                            read: false,
                            ...(rdv.client_profile_id ? {profile_id: rdv.client_profile_id} : {}),
                        }]);

                        if (fcmToken) {
                            await admin.messaging().send({
                                token: fcmToken,
                                data: {type: "rdv_rappel", title, body, rdv_id: rdv.id},
                                android: {priority: "high"},
                                apns: {
                                    headers: {"apns-priority": "10"},
                                    payload: {aps: {alert: {title, body}, sound: "default"}},
                                },
                            });
                        }
                    } else if (rdv.client_email_manuel) {
                        // Client sans compte : email de rappel
                        await sitePost("/api/rdv/reminder-email", {
                            email: rdv.client_email_manuel,
                            client_nom: rdv.client_nom_manuel || "",
                            pro_nom: proName,
                            date_heure: rdv.date_heure,
                            motif: rdv.motif || null,
                            duree_minutes: rdv.duree_minutes || null,
                            lieu: rdv.lieu || null,
                            echeance: win.echeance,
                        });
                    }

                    // ── Rappel au PRO (petsitter, véto, éducateur…) ──
                    try {
                        let who = rdv.client_nom_manuel || "";
                        if (!who && rdv.client_uid) {
                            const rows = await supabaseGet(
                                `user_profiles?uid=eq.${rdv.client_uid}&is_main=eq.true` +
                                `&select=firstname,lastname,nom&limit=1`);
                            const c = rows && rows[0];
                            if (c) {
                                who = (c.nom || `${c.firstname || ""} ${c.lastname || ""}`).trim();
                            }
                        }
                        who = who || "un client";

                        let animalNom = rdv.animal_nom_manuel || "";
                        if (!animalNom && rdv.animal_id) {
                            const arows = await supabaseGet(
                                `animaux?id=eq.${encodeURIComponent(rdv.animal_id)}&select=nom&limit=1`);
                            if (arows && arows[0]) animalNom = arows[0].nom || "";
                        }
                        const extra = [animalNom, rdv.lieu].filter(Boolean).join(" · ");

                        const proFcm = proDoc.exists ? proDoc.data()?.fcmToken : null;
                        const proTitle = win.proTitle || win.title;
                        const proBody = win.proBody
                            ? win.proBody(who, extra)
                            : `Rappel : visite avec ${who}${extra ? ` — ${extra}` : ""}.`;

                        await supabaseInsert("notifications", [{
                            uid: rdv.pro_uid,
                            type: "rdv_rappel",
                            title: proTitle,
                            body: proBody,
                            data: {rdv_id: rdv.id, echeance: win.echeance, role: "pro"},
                            read: false,
                            ...(rdv.pro_profile_id ? {profile_id: rdv.pro_profile_id} : {}),
                        }]);

                        if (proFcm) {
                            await admin.messaging().send({
                                token: proFcm,
                                data: {type: "rdv_rappel", title: proTitle, body: proBody, rdv_id: rdv.id},
                                android: {priority: "high"},
                                apns: {
                                    headers: {"apns-priority": "10"},
                                    payload: {aps: {alert: {title: proTitle, body: proBody}, sound: "default"}},
                                },
                            });
                        }
                    } catch (e) {
                        console.error(`sendRdvReminders [${win.label}] pro notif error ${rdv.id}:`, e);
                    }

                    // Marquer comme envoyé (évite les doublons)
                    await supabasePatch("rdv", rdv.id, {[win.sentField]: true});

                    const who = rdv.client_uid || rdv.client_email_manuel || "?";
                    console.log(`Rappel ${win.label} -> RDV ${rdv.id} (${who})`);
                } catch (e) {
                    console.error(`sendRdvReminders [${win.label}] error for RDV ${rdv.id}:`, e);
                }
            }
        }

        return null;
    });
