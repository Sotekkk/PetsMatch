const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const https = require("https");

const SUPABASE_URL = "https://zyvpngcvzrkdytypjlyq.supabase.co";
const SUPABASE_SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" +
    ".eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5dnBuZ2N2enJrZHl0eXBqbHlxIiwi" +
    "cm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTM2NDY1NSwiZXhwIjoyMDk0OT" +
    "QwNjU1fQ.1U96V3c7nHG3T08dboBcxTd05k8A_JQfnyrJTbJ0HgQ";

// ─── Supabase helpers ─────────────────────────────────────────────────────────

/**
 * Exécute une requête HTTP vers l'API REST Supabase.
 * @param {string} method - Méthode HTTP (GET, POST, PATCH…).
 * @param {string} path - Chemin relatif (table + query string).
 * @param {object|null} body - Corps JSON optionnel.
 * @return {Promise<Array|object>}
 */
function supabaseRequest(method, path, body) {
    return new Promise((resolve, reject) => {
        const bodyStr = body ? JSON.stringify(body) : null;
        const fullPath = `${SUPABASE_URL}/rest/v1/${path}`;
        const url = new URL(fullPath);
        const options = {
            hostname: url.hostname,
            path: url.pathname + (url.search || ""),
            method,
            headers: {
                "Content-Type": "application/json",
                "apikey": SUPABASE_SERVICE_KEY,
                "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
                "Prefer": method === "GET" ? "" : "return=minimal",
            },
        };
        if (bodyStr) options.headers["Content-Length"] = Buffer.byteLength(bodyStr);

        const req = https.request(options, (res) => {
            let data = "";
            res.on("data", (chunk) => data += chunk);
            res.on("end", () => {
                try {
                    resolve(JSON.parse(data));
                } catch (_) {
                    resolve([]);
                }
            });
        });
        req.on("error", reject);
        if (bodyStr) req.write(bodyStr);
        req.end();
    });
}

/**
 * Met à jour une ligne Supabase par son id.
 * @param {string} table - Nom de la table.
 * @param {number|string} id - Identifiant de la ligne.
 * @param {object} update - Champs à mettre à jour.
 * @return {Promise<void>}
 */
async function supabasePatch(table, id, update) {
    await supabaseRequest("PATCH", `${table}?id=eq.${id}`, update);
}

async function supabaseInsert(table, rows) {
    await supabaseRequest("POST", table, rows);
}

/**
 * Sélectionne des lignes Supabase avec filtres PostgREST.
 * @param {string} table - Nom de la table.
 * @param {string} query - Filtres (sans '?'), ex: "id=eq.1&select=*".
 * @return {Promise<Array>}
 */
async function supabaseSelect(table, query) {
    const rows = await supabaseRequest("GET", `${table}?${query}&select=*`);
    return Array.isArray(rows) ? rows : [];
}

/**
 * Récupère le nom d'un animal depuis Supabase.
 * @param {number|string|null} animalId - ID de l'animal.
 * @return {Promise<string|null>}
 */
async function getAnimalNom(animalId) {
    if (!animalId) return null;
    const rows = await supabaseSelect("animaux", `id=eq.${animalId}`);
    return rows[0] ? (rows[0].nom || null) : null;
}

/**
 * Récupère le prénom ou nom de structure d'un utilisateur depuis Supabase.
 * @param {string|null} uid - UID Firebase de l'utilisateur.
 * @return {Promise<string|null>}
 */
async function getUserNom(uid) {
    if (!uid) return null;
    const rows = await supabaseSelect("users", `uid=eq.${uid}`);
    if (!rows[0]) return null;
    const u = rows[0];
    return u.name_elevage || u.firstname || null;
}

// ─── FCM helper ───────────────────────────────────────────────────────────────

/**
 * Envoie une notification FCM à un utilisateur via son fcmToken Firestore.
 * @param {string} uid - UID Firebase de l'utilisateur.
 * @param {string} title - Titre de la notification.
 * @param {string} body - Corps de la notification.
 * @param {object} data - Données supplémentaires FCM.
 * @return {Promise<boolean>}
 */
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
                    notification: {title, body},
                    data: {type: "rdv_reminder", ...data},
                    android: {
                        priority: "high",
                        notification: {channelId: "high_importance_channel", sound: "default"},
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

// ─── Notification nouvelle demande RDV ───────────────────────────────────────

/**
 * Callable : notifie le pro quand un client envoie une demande de RDV.
 * @param {object} data - Données : proUid, clientName, dateStr.
 * @param {object} context - Contexte Firebase.
 * @return {Promise<object>}
 */
exports.notifyProNewRdv = functions
    .region("europe-west1")
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Auth required");
        }

        const {proUid, clientName, dateStr} = data;
        if (!proUid) return {sent: false, reason: "no_proUid"};

        const doc = await admin.firestore().collection("users").doc(proUid).get();
        const fcmToken = doc.exists ? doc.data().fcmToken : null;
        if (!fcmToken) return {sent: false, reason: "no_fcmToken"};

        const title = "📅 Nouvelle demande de RDV";
        const motifPart = data.motif ? ` — motif : ${data.motif}` : "";
        const body = dateStr ?
            `${clientName || "Un client"} souhaite un RDV le ${dateStr}${motifPart}` :
            `${clientName || "Un client"} souhaite prendre un RDV avec vous${motifPart}`;

        await sendPush(proUid, title, body, {type: "rdv_demande"});
        console.log(`notifyProNewRdv: push envoyé à ${proUid}`);
        return {sent: true};
    });

// ─── Fonction principale ──────────────────────────────────────────────────────

/**
 * Schedulée toutes les 30 minutes.
 * Envoie des rappels FCM 48h, 24h (la veille) et 1h avant chaque RDV confirmé
 * au client ET au professionnel, avec le nom de l'animal concerné.
 * SQL requis : ALTER TABLE rdv ADD COLUMN IF NOT EXISTS reminder_48h_sent boolean DEFAULT false;
 */
exports.sendRdvReminders = functions
    .region("europe-west1")
    .pubsub.schedule("every 30 minutes")
    .onRun(async () => {
        const now = new Date();

        // ── Rappel 48h ────────────────────────────────────────────────────────
        const from48 = new Date(now.getTime() + 47 * 3600 * 1000).toISOString();
        const to48 = new Date(now.getTime() + 49 * 3600 * 1000).toISOString();

        const rdvs48 = await supabaseSelect("rdv",
            `statut=in.(confirme,demande)&reminder_48h_sent=eq.false` +
            `&date_heure=gte.${encodeURIComponent(from48)}` +
            `&date_heure=lte.${encodeURIComponent(to48)}`);

        let sent48 = 0;
        for (const rdv of rdvs48) {
            const dateStr = new Date(rdv.date_heure).toLocaleString("fr-FR", {
                weekday: "long", day: "numeric", month: "long",
                hour: "2-digit", minute: "2-digit",
            });
            const [animalNom, proNom] = await Promise.all([
                getAnimalNom(rdv.animal_id),
                getUserNom(rdv.pro_uid),
            ]);
            const animalPart = animalNom ? ` pour ${animalNom}` : "";
            const rdvData = {rdvId: String(rdv.id), type: "rdv_confirme"};
            const prestataire = proNom || "votre prestataire";

            // → Client uniquement (rappel 48h)
            await sendPush(
                rdv.client_uid,
                "📅 Rappel RDV — dans 2 jours",
                `Votre RDV${animalPart} chez ${prestataire} est prévu le ${dateStr}`,
                rdvData,
            );
            await supabasePatch("rdv", rdv.id, {reminder_48h_sent: true});
            sent48++;
        }

        // ── Rappel 24h (la veille) ────────────────────────────────────────────
        let sent24 = 0;
        const from24 = new Date(now.getTime() + 23 * 3600 * 1000).toISOString();
        const to24 = new Date(now.getTime() + 25 * 3600 * 1000).toISOString();

        const rdvs24 = await supabaseSelect("rdv",
            `statut=in.(confirme,demande)&reminder_24h_sent=eq.false` +
            `&date_heure=gte.${encodeURIComponent(from24)}` +
            `&date_heure=lte.${encodeURIComponent(to24)}`);

        for (const rdv of rdvs24) {
            const dateStr = new Date(rdv.date_heure).toLocaleString("fr-FR", {
                weekday: "long", day: "numeric", month: "long",
                hour: "2-digit", minute: "2-digit",
            });

            const [animalNom, proNom, clientNom] = await Promise.all([
                getAnimalNom(rdv.animal_id),
                getUserNom(rdv.pro_uid),
                getUserNom(rdv.client_uid),
            ]);

            const animalPart = animalNom ? ` pour ${animalNom}` : "";
            const rdvData = {rdvId: String(rdv.id)};

            // → Client
            await sendPush(
                rdv.client_uid,
                "⏰ Rappel RDV — demain",
                `Votre RDV${animalPart} chez ${proNom || "votre prestataire"} est prévu le ${dateStr}`,
                rdvData,
            );

            // → Pro
            await sendPush(
                rdv.pro_uid,
                "⏰ RDV demain",
                `RDV avec ${clientNom || "un client"}${animalPart} — le ${dateStr}`,
                rdvData,
            );

            await supabasePatch("rdv", rdv.id, {reminder_24h_sent: true});
            sent24++;
        }

        // ── Rappel 1h ─────────────────────────────────────────────────────────
        const from1h = new Date(now.getTime() + 45 * 60 * 1000).toISOString();
        const to1h = new Date(now.getTime() + 75 * 60 * 1000).toISOString();

        const rdvs2h = await supabaseSelect("rdv",
            `statut=in.(confirme,demande)&reminder_2h_sent=eq.false` +
            `&date_heure=gte.${encodeURIComponent(from1h)}` +
            `&date_heure=lte.${encodeURIComponent(to1h)}`);

        let sent2h = 0;
        for (const rdv of rdvs2h) {
            const timeStr = new Date(rdv.date_heure).toLocaleString("fr-FR", {
                hour: "2-digit", minute: "2-digit",
            });
            const [animalNom, proNom, clientNom] = await Promise.all([
                getAnimalNom(rdv.animal_id),
                getUserNom(rdv.pro_uid),
                getUserNom(rdv.client_uid),
            ]);
            const animalPart = animalNom ? ` pour ${animalNom}` : "";
            const rdvData = {rdvId: String(rdv.id), type: "rdv_confirme"};

            // → Client
            await sendPush(rdv.client_uid,
                "⏰ Rappel RDV — dans 1 heure",
                `Votre RDV${animalPart} chez ${proNom || "votre prestataire"} est à ${timeStr}`,
                rdvData);
            // → Pro
            await sendPush(rdv.pro_uid,
                "⏰ RDV dans 1 heure",
                `RDV avec ${clientNom || "un client"}${animalPart} — à ${timeStr}`,
                rdvData);

            await supabasePatch("rdv", rdv.id, {reminder_2h_sent: true});
            sent2h++;
        }

        // ── Rappel 30min ──────────────────────────────────────────────────────
        const from30 = new Date(now.getTime() + 10 * 60 * 1000).toISOString();
        const to30 = new Date(now.getTime() + 50 * 60 * 1000).toISOString();

        const rdvs30 = await supabaseSelect("rdv",
            `statut=in.(confirme,demande)&reminder_30min_sent=eq.false` +
            `&date_heure=gte.${encodeURIComponent(from30)}` +
            `&date_heure=lte.${encodeURIComponent(to30)}`);

        let sent30 = 0;
        for (const rdv of rdvs30) {
            const timeStr = new Date(rdv.date_heure).toLocaleString("fr-FR", {
                hour: "2-digit", minute: "2-digit",
            });
            const [animalNom, proNom, clientNom] = await Promise.all([
                getAnimalNom(rdv.animal_id),
                getUserNom(rdv.pro_uid),
                getUserNom(rdv.client_uid),
            ]);
            const animalPart = animalNom ? ` pour ${animalNom}` : "";
            const rdvData = {rdvId: String(rdv.id), type: "rdv_confirme"};

            await sendPush(rdv.client_uid,
                "⏰ Rappel RDV — dans 30 minutes",
                `Votre RDV${animalPart} chez ${proNom || "votre prestataire"} commence bientôt (${timeStr})`,
                rdvData);
            await sendPush(rdv.pro_uid,
                "⏰ RDV dans 30 minutes",
                `RDV avec ${clientNom || "un client"}${animalPart} — à ${timeStr}`,
                rdvData);

            await supabasePatch("rdv", rdv.id, {reminder_30min_sent: true});
            sent30++;
        }

        console.log(
            `sendRdvReminders: ${sent48}×48h, ${sent24}×24h, ${sent2h}×1h, ${sent30}×30min`,
        );
        return null;
    });

// ─── Rappels mise-bas ─────────────────────────────────────────────────────────
// Migration SQL requise (une fois) :
//   ALTER TABLE gestations
//     ADD COLUMN IF NOT EXISTS reminder_j7_sent boolean DEFAULT false,
//     ADD COLUMN IF NOT EXISTS reminder_j3_sent boolean DEFAULT false,
//     ADD COLUMN IF NOT EXISTS reminder_j1_sent boolean DEFAULT false;

/**
 * Schedulée quotidiennement à 8h.
 * Envoie un rappel FCM J-7, J-3 et J-1 avant la mise-bas prévue
 * à l'éleveur propriétaire de la femelle.
 */
exports.sendMiseBasReminders = functions
    .region("europe-west1")
    .pubsub.schedule("0 8 * * *")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        const now = new Date();
        let sent = 0;

        const paliers = [
            {days: 30, field: "reminder_j30_sent", label: "dans 30 jours", emoji: "🗓️"},
            {days: 7,  field: "reminder_j7_sent",  label: "dans 7 jours",  emoji: "📅"},
            {days: 3,  field: "reminder_j3_sent",  label: "dans 3 jours",  emoji: "⏳"},
            {days: 1,  field: "reminder_j1_sent",  label: "demain",        emoji: "🐣"},
        ];

        for (const {days, field, label} of paliers) {
            const target = new Date(now);
            target.setDate(target.getDate() + days);
            const dateStr = target.toISOString().split("T")[0]; // YYYY-MM-DD

            const gestations = await supabaseSelect("gestations",
                `gestation_confirmee=eq.true` +
                `&${field}=eq.false` +
                `&date_prevue=eq.${encodeURIComponent(dateStr)}`);

            for (const g of gestations) {
                const animals = await supabaseSelect("animaux", `id=eq.${g.animal_id}`);
                const animal = animals[0];
                if (!animal || !animal.uid_eleveur) continue;

                const animalNom = animal.nom || "votre femelle";
                const miseBas = new Date(g.date_prevue).toLocaleDateString("fr-FR", {
                    day: "numeric", month: "long",
                });

                const title = `${emoji} Mise-bas prévue ${label}`;
                const body = `${animalNom} devrait mettre bas le ${miseBas}. Préparez la maternité !`;

                await sendPush(
                    animal.uid_eleveur,
                    title,
                    body,
                    {type: "mise_bas", animalId: String(g.animal_id)},
                );

                try {
                    await supabaseInsert("notifications", [{
                        uid: animal.uid_eleveur,
                        type: "mise_bas",
                        title,
                        body,
                        data: {animalId: String(g.animal_id)},
                        read: false,
                    }]);
                } catch (e) {
                    console.error(`notifications insert error for gestation ${g.id}:`, e.message);
                }

                await supabasePatch("gestations", g.id, {[field]: true});
                sent++;
            }
        }

        console.log(`sendMiseBasReminders: ${sent} rappels envoyés`);
        return null;
    });
