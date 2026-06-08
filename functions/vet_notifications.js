const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const https = require("https");

if (!admin.apps.length) admin.initializeApp();

const SUPABASE_URL = process.env.SUPABASE_URL ||
    (functions.config().supabase || {}).url ||
    "https://zyvpngcvzrkdytypjlyq.supabase.co";
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY ||
    (functions.config().supabase || {}).service_key ||
    "";

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
                    try { resolve(JSON.parse(data)); } catch (e) { reject(e); }
                } else {
                    reject(new Error(`Supabase GET ${path}: ${res.statusCode} — ${data}`));
                }
            });
        });
        req.on("error", reject);
        req.end();
    });
}

async function supabaseInsert(table, rows) {
    return new Promise((resolve, reject) => {
        const bodyStr = JSON.stringify(rows);
        const options = {
            hostname: new URL(SUPABASE_URL).hostname,
            path: `/rest/v1/${table}`,
            method: "POST",
            headers: {
                "apikey": SUPABASE_SERVICE_KEY,
                "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
                "Content-Type": "application/json",
                "Content-Length": Buffer.byteLength(bodyStr),
                "Prefer": "return=minimal",
            },
        };
        const req = https.request(options, (res) => {
            let data = "";
            res.on("data", (c) => data += c);
            res.on("end", () => {
                if (res.statusCode >= 200 && res.statusCode < 300) resolve(data);
                else reject(new Error(`Supabase POST ${table}: ${res.statusCode} — ${data}`));
            });
        });
        req.on("error", reject);
        req.write(bodyStr);
        req.end();
    });
}

/**
 * Notifie le propriétaire d'un animal quand un vétérinaire ajoute une entrée
 * dans le carnet de santé (vaccin, traitement, visite).
 * Appelé depuis l'app Flutter via Firebase Functions callable.
 */
exports.notifyOwnerVetEntry = functions
    .region("europe-west1")
    .https.onCall(async (data) => {
        const {animalId, vetName, typeActe} = data;
        if (!animalId || !vetName || !typeActe) return {ok: false, reason: "missing_params"};

        // Récupérer l'animal + propriétaire
        let animals;
        try {
            animals = await supabaseGet(
                `animaux?id=eq.${encodeURIComponent(animalId)}&select=nom,uid_eleveur,uid_proprietaire`,
            );
        } catch (e) {
            console.error("notifyOwnerVetEntry: fetch animal error", e);
            return {ok: false};
        }

        if (!animals?.length) return {ok: false, reason: "animal_not_found"};
        const animal = animals[0];
        const ownerUid = animal.uid_eleveur || animal.uid_proprietaire;
        if (!ownerUid) return {ok: false, reason: "no_owner"};

        const labels = {
            vaccin:     "une vaccination",
            traitement: "un traitement",
            visite:     "une visite vétérinaire",
        };
        const label = labels[typeActe] || `une entrée (${typeActe})`;
        const animalNom = animal.nom || "votre animal";
        const title = "Carnet de santé mis à jour";
        const body  = `${vetName} a enregistré ${label} pour ${animalNom}.`;

        // Notification in-app (Supabase)
        try {
            await supabaseInsert("notifications", [{
                uid:   ownerUid,
                type:  `vet_${typeActe}`,
                title: title,
                body:  body,
                data:  {animal_id: animalId, type_acte: typeActe},
                read:  false,
            }]);
        } catch (e) {
            console.error("notifyOwnerVetEntry: insert notification error", e);
        }

        // Push FCM
        try {
            const userDoc = await admin.firestore().collection("users").doc(ownerUid).get();
            const fcmToken = userDoc.exists ? userDoc.data()?.fcmToken : null;
            if (fcmToken) {
                await admin.messaging().send({
                    token: fcmToken,
                    notification: {title, body},
                    data: {type: "vet_entry", animal_id: animalId},
                    android: {
                        priority: "high",
                        notification: {channelId: "sante_rappels", sound: "default"},
                    },
                    apns: {
                        headers: {"apns-priority": "10"},
                        payload: {aps: {sound: "default"}},
                    },
                });
            }
        } catch (e) {
            console.error("notifyOwnerVetEntry: FCM error", e);
        }

        return {ok: true};
    });
