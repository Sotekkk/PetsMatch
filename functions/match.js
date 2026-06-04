const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const https = require("https");

const SUPABASE_URL = "https://zyvpngcvzrkdytypjlyq.supabase.co";
const SUPABASE_SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" +
    ".eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5dnBuZ2N2enJrZHl0eXBqbHlxIiwi" +
    "cm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTM2NDY1NSwiZXhwIjoyMDk0OT" +
    "QwNjU1fQ.1U96V3c7nHG3T08dboBcxTd05k8A_JQfnyrJTbJ0HgQ";

// ─── Supabase helpers ─────────────────────────────────────────────────────────

function supabaseRequest(method, path, body) {
    return new Promise((resolve, reject) => {
        const url = new URL(`${SUPABASE_URL}${path}`);
        const bodyStr = body ? JSON.stringify(body) : null;
        const options = {
            hostname: url.hostname,
            path: url.pathname + url.search,
            method,
            headers: {
                "apikey": SUPABASE_SERVICE_KEY,
                "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
                "Accept": "application/json",
                "Content-Type": "application/json",
                "Prefer": "return=representation",
                ...(bodyStr ? {"Content-Length": Buffer.byteLength(bodyStr)} : {}),
            },
        };
        const req = https.request(options, (res) => {
            let data = "";
            res.on("data", (c) => data += c);
            res.on("end", () => {
                if (res.statusCode >= 200 && res.statusCode < 300) {
                    try {
                        resolve(data ? JSON.parse(data) : []);
                    } catch (_) {
                        resolve([]);
                    }
                } else {
                    reject(new Error(`Supabase ${method} ${path}: ${res.statusCode} ${data}`));
                }
            });
        });
        req.on("error", reject);
        if (bodyStr) req.write(bodyStr);
        req.end();
    });
}

async function supabaseGet(table, filters) {
    const qs = Object.entries(filters).map(([k, v]) => `${k}=${v}`).join("&");
    return supabaseRequest("GET", `/rest/v1/${table}${qs ? "?" + qs : ""}`, null);
}

/**
 * Insert into alertes_correspondances with duplicate-ignore on (alerte_id, trouve_id).
 * Returns true if the row was inserted (new match), false if it already existed.
 */
async function insertCorrespondance(alerteId, trouveId, score, scorePct) {
    const path = "/rest/v1/alertes_correspondances";
    const body = [{
        alerte_id: alerteId,
        trouve_id: trouveId,
        score,
        score_pct: scorePct,
        notifie: false,
    }];
    return new Promise((resolve, reject) => {
        const bodyStr = JSON.stringify(body);
        const options = {
            hostname: new URL(SUPABASE_URL).hostname,
            path: path,
            method: "POST",
            headers: {
                "apikey": SUPABASE_SERVICE_KEY,
                "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
                "Content-Type": "application/json",
                "Content-Length": Buffer.byteLength(bodyStr),
                "Prefer": "resolution=ignore-duplicates,return=minimal",
            },
        };
        const req = https.request(options, (res) => {
            res.resume();
            res.on("end", () => {
                if (res.statusCode === 201) resolve(true); // inserted
                else if (res.statusCode === 200) resolve(false); // duplicate ignored
                else reject(new Error(`insertCorrespondance: ${res.statusCode}`));
            });
        });
        req.on("error", reject);
        req.write(bodyStr);
        req.end();
    });
}

async function markNotified(alerteId, trouveId) {
    const qs = `alerte_id=eq.${alerteId}&trouve_id=eq.${trouveId}`;
    return new Promise((resolve, reject) => {
        const body = JSON.stringify({notifie: true});
        const options = {
            hostname: new URL(SUPABASE_URL).hostname,
            path: `/rest/v1/alertes_correspondances?${qs}`,
            method: "PATCH",
            headers: {
                "apikey": SUPABASE_SERVICE_KEY,
                "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
                "Content-Type": "application/json",
                "Content-Length": Buffer.byteLength(body),
                "Prefer": "return=minimal",
            },
        };
        const req = https.request(options, (res) => {
            res.resume();
            res.on("end", () => resolve());
        });
        req.on("error", reject);
        req.write(body);
        req.end();
    });
}

async function insertNotification(uid, title, body, data) {
    return new Promise((resolve) => {
        const payload = JSON.stringify([{uid, type: "matching_perdu_trouve", title, body, data, read: false}]);
        const options = {
            hostname: new URL(SUPABASE_URL).hostname,
            path: "/rest/v1/notifications",
            method: "POST",
            headers: {
                "apikey": SUPABASE_SERVICE_KEY,
                "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
                "Content-Type": "application/json",
                "Content-Length": Buffer.byteLength(payload),
                "Prefer": "return=minimal",
            },
        };
        const req = https.request(options, (res) => {
            res.resume();
            res.on("end", resolve);
        });
        req.on("error", resolve);
        req.write(payload);
        req.end();
    });
}

// ─── Haversine ────────────────────────────────────────────────────────────────

function haversineKm(lat1, lon1, lat2, lon2) {
    const R = 6371;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a =
        Math.sin(dLat / 2) ** 2 +
        Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
        Math.sin(dLon / 2) ** 2;
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// ─── Algorithme de score ──────────────────────────────────────────────────────
// Poids spec :
//   Espèce        : obligatoire (0 si différent)
//   Puce identique: 100 pts (match certain)
//   Race          : +30
//   Sexe          : +20
//   Zone ≤ 50 km  : +20
//   Dates compat. : +15  (date_trouvée ≥ date_perdue)
//   Couleur       : +10
//   Max (hors puce): 95

const MAX_SCORE = 95;

/**
 * @param {Object} perdu - Row from alertes_perdus
 * @param {Object} trouve - Row from animaux_trouves
 * @returns {{ score: number, pct: number, puceMatch: boolean }}
 */
function calcScore(perdu, trouve) {
    // Espèce : obligatoire
    if (!perdu.espece || !trouve.espece || perdu.espece !== trouve.espece) {
        return {score: 0, pct: 0, puceMatch: false};
    }

    // Puce : match certain
    const p = (perdu.identification || "").toLowerCase().replace(/\s/g, "");
    const t = (trouve.numero_puce || "").toLowerCase().replace(/\s/g, "");
    if (p && t && p === t) {
        return {score: 100, pct: 100, puceMatch: true};
    }

    let score = 0;

    // Race (+30)
    if (perdu.race && trouve.race &&
        perdu.race.toLowerCase().trim() === trouve.race.toLowerCase().trim()) {
        score += 30;
    }

    // Sexe (+20)
    if (perdu.sexe && trouve.sexe && perdu.sexe === trouve.sexe) score += 20;

    // Zone ≤ 50 km (+20)
    const pLat = parseFloat(perdu.lat);
    const pLng = parseFloat(perdu.lng);
    const tLat = parseFloat(trouve.lat);
    const tLng = parseFloat(trouve.lng);
    if (!isNaN(pLat) && !isNaN(pLng) && !isNaN(tLat) && !isNaN(tLng)) {
        if (haversineKm(pLat, pLng, tLat, tLng) <= 50) score += 20;
    }

    // Dates compatibles : date trouvée ≥ date perdue (+15)
    if (perdu.date_disparition && trouve.date_decouverte) {
        const dP = new Date(perdu.date_disparition);
        const dT = new Date(trouve.date_decouverte);
        if (!isNaN(dP) && !isNaN(dT) && dT >= dP) score += 15;
    }

    // Couleur similaire (+10) : contient l'un l'autre (simple)
    if (perdu.couleur && trouve.couleur) {
        const c1 = perdu.couleur.toLowerCase().trim();
        const c2 = trouve.couleur.toLowerCase().trim();
        if (c1 && c2 && (c1.includes(c2) || c2.includes(c1))) score += 10;
    }

    const pct = Math.round((score / MAX_SCORE) * 100);
    return {score, pct, puceMatch: false};
}

// ─── Envoi notification FCM + in-app ─────────────────────────────────────────

async function notify(ownerUid, title, body, extraData) {
    // In-app (Supabase)
    insertNotification(ownerUid, title, body, extraData).catch(() => {});

    // FCM push
    try {
        const doc = await admin.firestore().collection("users").doc(ownerUid).get();
        const token = doc.exists ? doc.data().fcmToken : null;
        if (!token) return;
        await admin.messaging().send({
            token,
            notification: {title, body},
            data: {...extraData, type: "matching_perdu_trouve"},
            android: {
                priority: "high",
                notification: {channelId: "alertes_perdus", sound: "default"},
            },
            apns: {
                headers: {"apns-priority": "10"},
                payload: {aps: {alert: {title, body}, sound: "default", badge: 1}},
            },
        });
    } catch (e) {
        console.error("notify FCM error:", e.message);
    }
}

// ─── Cloud Function ───────────────────────────────────────────────────────────

/**
 * matchLostFound — Callable
 *
 * data.alerteId : ID de l'alerte ou de l'animal trouvé
 * data.type     : 'perdu' | 'trouve'
 *
 * - type='perdu'  : cherche des correspondances dans animaux_trouves
 * - type='trouve' : cherche des correspondances dans alertes_perdus
 *
 * Pour chaque match avec score_pct ≥ 90 : push FCM + notif in-app au propriétaire.
 * Dédup via table alertes_correspondances (UNIQUE alerte_id + trouve_id).
 */
exports.matchLostFound = functions
    .region("europe-west1")
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Auth required");
        }

        const {alerteId, type} = data;
        if (!alerteId || !type) return {matches: 0};

        const cutoff30 = new Date(Date.now() - 30 * 86400 * 1000).toISOString();
        const cutoff90 = new Date(Date.now() - 90 * 86400 * 1000).toISOString();

        let notified = 0;
        let stored = 0;

        try {
            if (type === "perdu") {
                // Fetch the alerte perdue
                const perdus = await supabaseGet("alertes_perdus", {"id": `eq.${alerteId}`});
                if (!perdus.length) return {matches: 0};
                const perdu = perdus[0];

                // Candidates : animaux_trouves (30 derniers jours, même espèce, non clôturés)
                const candidats = await supabaseGet("animaux_trouves", {
                    "espece": `eq.${perdu.espece}`,
                    "created_at": `gte.${cutoff30}`,
                    "select": "id,espece,race,sexe,couleur,numero_puce,date_decouverte,lat,lng,statut,user_uid",
                });

                for (const trouve of candidats) {
                    if (["restitue", "cloture"].includes(trouve.statut)) continue;

                    const {score, pct} = calcScore(perdu, trouve);
                    if (pct < 70) continue;

                    // Store (dedup)
                    const isNew = await insertCorrespondance(alerteId, trouve.id, score, pct).catch(() => false);
                    stored++;

                    if (pct >= 90) {
                        const title = "🐾 Correspondance animaux perdu/trouvé";
                        const body = `Un animal trouvé correspond à ${pct}% à votre alerte`;
                        await notify(perdu.uid_proprietaire, title, body, {
                            alerteId,
                            trouveId: trouve.id,
                            scorePct: String(pct),
                        });
                        if (isNew) {
                            await markNotified(alerteId, trouve.id).catch(() => {});
                            notified++;
                        }
                    }
                }
            } else if (type === "trouve") {
                // Fetch the animal trouvé
                const trouves = await supabaseGet("animaux_trouves", {"id": `eq.${alerteId}`});
                if (!trouves.length) return {matches: 0};
                const trouve = trouves[0];

                // Candidates : alertes_perdus (90 derniers jours, même espèce, actives)
                const candidats = await supabaseGet("alertes_perdus", {
                    "espece": `eq.${trouve.espece}`,
                    "created_at": `gte.${cutoff90}`,
                    "select": "id,uid_proprietaire,espece,race,sexe,couleur," +
                        "identification,date_disparition,lat,lng,nom_animal",
                });

                for (const perdu of candidats) {
                    if (!["perdu", "apercu"].includes(perdu.statut || "perdu")) continue;

                    const {score, pct} = calcScore(perdu, trouve);
                    if (pct < 70) continue;

                    const isNew = await insertCorrespondance(perdu.id, trouve.id, score, pct).catch(() => false);
                    stored++;

                    if (pct >= 90) {
                        const nomAnimal = perdu.nom_animal || "Animal";
                        const title = "🐾 Correspondance animaux perdu/trouvé";
                        const body = `${nomAnimal} signalé perdu correspond à ${pct}% à un animal trouvé`;
                        await notify(perdu.uid_proprietaire, title, body, {
                            alerteId: perdu.id,
                            trouveId: trouve.id,
                            scorePct: String(pct),
                        });
                        if (isNew) {
                            await markNotified(perdu.id, trouve.id).catch(() => {});
                            notified++;
                        }
                    }
                }
            }
        } catch (e) {
            console.error("matchLostFound error:", e);
        }

        console.log(`matchLostFound [${type}/${alerteId}]: ${stored} stored, ${notified} notified`);
        return {matches: stored, notified};
    });
