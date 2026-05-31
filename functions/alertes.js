const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const https = require("https");

const SUPABASE_URL = "https://zyvpngcvzrkdytypjlyq.supabase.co";
const SUPABASE_SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" +
    ".eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5dnBuZ2N2enJrZHl0eXBqbHlxIiwi" +
    "cm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTM2NDY1NSwiZXhwIjoyMDk0OT" +
    "QwNjU1fQ.1U96V3c7nHG3T08dboBcxTd05k8A_JQfnyrJTbJ0HgQ";

/**
 * Fetch rows from a Supabase table via REST API (GET).
 * @param {string} table - Table name.
 * @param {Object} params - Query params, e.g. {statut: 'eq.perdu', lat: 'not.is.null'}.
 * @return {Promise<Array>}
 */
async function supabaseFetch(table, params) {
    return new Promise((resolve, reject) => {
        const qs = Object.entries(params).map(([k, v]) => `${k}=${v}`).join("&");
        const options = {
            hostname: new URL(SUPABASE_URL).hostname,
            path: `/rest/v1/${table}${qs ? "?" + qs : ""}`,
            method: "GET",
            headers: {
                "apikey": SUPABASE_SERVICE_KEY,
                "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
                "Accept": "application/json",
            },
        };
        const req = https.request(options, (res) => {
            let data = "";
            res.on("data", (chunk) => data += chunk);
            res.on("end", () => {
                if (res.statusCode >= 200 && res.statusCode < 300) {
                    try {
                        resolve(JSON.parse(data));
                    } catch (e) {
                        reject(e);
                    }
                } else {
                    reject(new Error(`Supabase fetch ${table}: ${res.statusCode}`));
                }
            });
        });
        req.on("error", reject);
        req.end();
    });
}

/**
 * Insert rows into a Supabase table via REST API.
 * @param {string} table - Table name.
 * @param {Array} rows - Array of row objects.
 * @return {Promise<void>}
 */
async function supabaseInsert(table, rows) {
    return new Promise((resolve, reject) => {
        const body = JSON.stringify(rows);
        const url = new URL(`${SUPABASE_URL}/rest/v1/${table}`);
        const options = {
            hostname: url.hostname,
            path: url.pathname,
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
                if (res.statusCode >= 200 && res.statusCode < 300) {
                    resolve();
                } else {
                    reject(new Error(`Supabase insert failed: ${res.statusCode}`));
                }
            });
        });
        req.on("error", reject);
        req.write(body);
        req.end();
    });
}

/**
 * Haversine distance in km between two lat/lng points.
 * @param {number} lat1 - Latitude of point 1.
 * @param {number} lon1 - Longitude of point 1.
 * @param {number} lat2 - Latitude of point 2.
 * @param {number} lon2 - Longitude of point 2.
 * @return {number} Distance in kilometers.
 */
function haversineKm(lat1, lon1, lat2, lon2) {
    const R = 6371;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

exports.notifyUsersNearLostAnimal = functions
    .region("europe-west1")
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError(
                "unauthenticated",
                "Authentication required",
            );
        }

        const {lat, lng, nomAnimal, espece, alerteId, proprietaireUid} = data;

        if (lat == null || lng == null) {
            return {sent: 0, reason: "no_coordinates"};
        }

        const usersSnap = await admin.firestore().collection("users").get();

        const fcmMessages = [];
        const notifRows = [];
        const especeLabel = espece ? ` (${espece})` : "";
        const notifTitle = "🐾 Animal perdu près de chez vous";
        const notifBody =
            `${nomAnimal}${especeLabel} a été signalé perdu dans votre secteur`;

        for (const doc of usersSnap.docs) {
            const user = doc.data();
            if (doc.id === proprietaireUid) continue;
            if (user.lat == null || user.lng == null) continue;

            const dist = haversineKm(lat, lng, user.lat, user.lng);
            if (dist <= 20) {
                notifRows.push({
                    uid: doc.id,
                    type: "alerte_perdu",
                    title: notifTitle,
                    body: notifBody,
                    data: {alerteId: alerteId || ""},
                    read: false,
                });
                if (user.fcmToken) {
                    fcmMessages.push({
                        token: user.fcmToken,

                        notification: {
                            title: notifTitle,
                            body: notifBody,
                        },

                        data: {
                            type: "alerte_perdu",
                            alerteId: alerteId || "",
                        },

                        android: {
                            priority: "high",
                            notification: {
                                channelId: "alertes_perdus",
                                sound: "default",
                            },
                        },

                        apns: {
                            headers: {
                                "apns-priority": "10",
                            },
                            payload: {
                                aps: {
                                    alert: {
                                        title: notifTitle,
                                        body: notifBody,
                                    },
                                    sound: "default",
                                    badge: 1,
                                },
                            },
                        },
                    });
                }
            }
        }

        // Write in-app notifications to Supabase (batches of 500)
        for (let i = 0; i < notifRows.length; i += 500) {
            try {
                await supabaseInsert("notifications", notifRows.slice(i, i + 500));
            } catch (e) {
                console.error("Supabase insert error:", e);
            }
        }

        // Send FCM push notifications (batches of 500)
        let sent = 0;
        for (let i = 0; i < fcmMessages.length; i += 500) {
            try {
                const res = await admin.messaging().sendEach(fcmMessages.slice(i, i + 500));
                sent += res.successCount;
            } catch (e) {
                console.error("FCM batch error:", e);
            }
        }

        console.log(
            `notifyUsersNearLostAnimal: ${sent} FCM + ${notifRows.length}` +
            ` in-app notifs for alerte ${alerteId}`,
        );
        return {sent, inApp: notifRows.length};
    });

/**
 * Callable: envoie un push FCM de like à l'éleveur via Firebase Admin SDK.
 */
exports.sendLikeNotification = functions
    .region("europe-west1")
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Auth required");
        }

        const {receiverUid, annonceId, bebeIndex, nomAnimal, senderName} = data;
        if (!receiverUid) return {sent: false, reason: "no_receiverUid"};

        const userDoc = await admin.firestore().collection("users").doc(receiverUid).get();
        const fcmToken = userDoc.exists ? userDoc.data().fcmToken : null;
        if (!fcmToken) return {sent: false, reason: "no_fcmToken"};

        const title = "❤️ Nouveau like sur votre annonce";
        const body = `${senderName || "Quelqu'un"} a aimé "${nomAnimal || "votre animal"}"`;

        const message = {
            token: fcmToken,
            notification: {title, body},
            data: {
                type: "like",
                annonceId: annonceId || "",
                bebeIndex: bebeIndex != null ? String(bebeIndex) : "",
            },
            android: {
                priority: "high",
                notification: {channelId: "high_importance_channel", sound: "default"},
            },
            apns: {
                headers: {"apns-priority": "10"},
                payload: {aps: {alert: {title, body}, sound: "default", badge: 1}},
            },
        };

        try {
            await admin.messaging().send(message);
            console.log(`sendLikeNotification: push envoyé à ${receiverUid}`);
            return {sent: true};
        } catch (e) {
            console.error("sendLikeNotification FCM error:", e);
            return {sent: false, reason: String(e)};
        }
    });

/**
 * Callable: quand un animal est trouvé, notifie les propriétaires d'alertes perdues
 * de même espèce dans un rayon de 20 km.
 */
exports.notifyNearFoundAnimal = functions
    .region("europe-west1")
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError(
                "unauthenticated",
                "Authentication required",
            );
        }

        const {lat, lng, espece, trouveId, declarantUid} = data;

        if (lat == null || lng == null) {
            return {sent: 0, reason: "no_coordinates"};
        }

        // Query matching lost animal alerts
        const params = {
            "statut": "eq.perdu",
            "lat": "not.is.null",
            "lng": "not.is.null",
            "select": "id,nom_animal,espece,lat,lng,uid_proprietaire",
        };
        if (espece && espece !== "autre") {
            params["espece"] = `eq.${espece}`;
        }

        let alertes = [];
        try {
            alertes = await supabaseFetch("alertes_perdus", params);
        } catch (e) {
            console.error("notifyNearFoundAnimal: fetch error:", e);
            return {sent: 0, reason: "fetch_error"};
        }

        const notifTitle = "🐾 Animal trouvé près de chez vous";
        const seenUids = new Set();
        if (declarantUid) seenUids.add(declarantUid);

        const notifRows = [];
        const fcmMessages = [];

        for (const alerte of alertes) {
            if (!alerte.lat || !alerte.lng) continue;
            if (!alerte.uid_proprietaire) continue;
            if (seenUids.has(alerte.uid_proprietaire)) continue;

            const dist = haversineKm(lat, lng, alerte.lat, alerte.lng);
            if (dist > 20) continue;

            seenUids.add(alerte.uid_proprietaire);

            const especeLabel = alerte.espece ? ` (${alerte.espece})` : "";
            const notifBody =
                `Un animal${especeLabel} a été trouvé à ${Math.round(dist)} km` +
                ` de votre alerte "${alerte.nom_animal || "animal perdu"}"`;

            notifRows.push({
                uid: alerte.uid_proprietaire,
                type: "animal_trouve_proximite",
                title: notifTitle,
                body: notifBody,
                data: {trouveId: trouveId || "", alerteId: String(alerte.id || "")},
                read: false,
            });

            const userDoc = await admin.firestore()
                .collection("users").doc(alerte.uid_proprietaire).get();
            const fcmToken = userDoc.exists ? userDoc.data().fcmToken : null;
            if (fcmToken) {
                fcmMessages.push({
                    token: fcmToken,
                    notification: {title: notifTitle, body: notifBody},
                    data: {
                        type: "animal_trouve_proximite",
                        trouveId: trouveId || "",
                        alerteId: String(alerte.id || ""),
                    },
                    android: {
                        priority: "high",
                        notification: {channelId: "alertes_perdus", sound: "default"},
                    },
                    apns: {
                        headers: {"apns-priority": "10"},
                        payload: {aps: {
                            alert: {title: notifTitle, body: notifBody},
                            sound: "default",
                            badge: 1,
                        }},
                    },
                });
            }
        }

        // Write in-app notifications (batches of 500)
        for (let i = 0; i < notifRows.length; i += 500) {
            try {
                await supabaseInsert("notifications", notifRows.slice(i, i + 500));
            } catch (e) {
                console.error("Supabase insert error:", e);
            }
        }

        // Send FCM push (batches of 500)
        let sent = 0;
        for (let i = 0; i < fcmMessages.length; i += 500) {
            try {
                const res = await admin.messaging().sendEach(fcmMessages.slice(i, i + 500));
                sent += res.successCount;
            } catch (e) {
                console.error("FCM batch error:", e);
            }
        }

        console.log(
            `notifyNearFoundAnimal: ${sent} FCM + ${notifRows.length}` +
            ` in-app notifs for trouve ${trouveId}`,
        );
        return {sent, inApp: notifRows.length};
    });

/**
 * Callable: notifie directement le propriétaire connu d'un animal déclaré trouvé.
 */
exports.notifyAnimalOwner = functions
    .region("europe-west1")
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Auth required");
        }

        const {ownerUid, trouveId, espece} = data;
        if (!ownerUid) return {sent: false, reason: "no_ownerUid"};

        const userDoc = await admin.firestore().collection("users").doc(ownerUid).get();
        const fcmToken = userDoc.exists ? userDoc.data().fcmToken : null;
        if (!fcmToken) return {sent: false, reason: "no_fcmToken"};

        const title = "🐾 Votre animal a peut-être été trouvé !";
        const body = `Un ${espece || "animal"} correspondant à l'un de vos animaux a été signalé trouvé.`;

        const message = {
            token: fcmToken,
            notification: {title, body},
            data: {
                type: "animal_trouve_proprietaire",
                trouveId: trouveId || "",
            },
            android: {
                priority: "high",
                notification: {channelId: "high_importance_channel", sound: "default"},
            },
            apns: {
                headers: {"apns-priority": "10"},
                payload: {aps: {alert: {title, body}, sound: "default", badge: 1}},
            },
        };

        try {
            await admin.messaging().send(message);
            console.log(`notifyAnimalOwner: push envoyé à ${ownerUid}`);

            try {
                await supabaseInsert("notifications", [{
                    uid: ownerUid,
                    type: "animal_trouve_proprietaire",
                    titre: title,
                    corps: body,
                    lien_id: trouveId || null,
                    lu: false,
                }]);
            } catch (e) {
                console.error("notifyAnimalOwner: Supabase insert error:", e);
            }

            return {sent: true};
        } catch (e) {
            console.error("notifyAnimalOwner FCM error:", e);
            return {sent: false, reason: String(e)};
        }
    });
