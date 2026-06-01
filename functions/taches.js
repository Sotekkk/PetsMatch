const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

if (!admin.apps.length) admin.initializeApp();

/**
 * Callable function — sends a push notification to an employee when a task is assigned.
 * The in-app notification (Supabase) is already inserted by the Flutter client.
 */
exports.notifyTacheAssignee = functions
    .region("europe-west1")
    .https.onCall(async (data) => {
        const {assigneUid, titre} = data;
        if (!assigneUid || !titre) return {success: false, reason: "missing_params"};

        try {
            const userDoc = await admin.firestore().collection("users").doc(assigneUid).get();
            const fcmToken = userDoc.exists ? userDoc.data()?.fcmToken : null;

            if (!fcmToken) return {success: false, reason: "no_fcm_token"};

            await admin.messaging().send({
                token: fcmToken,
                notification: {
                    title: "Nouvelle tâche assignée",
                    body: titre,
                },
                data: {
                    type: "tache",
                    click_action: "FLUTTER_NOTIFICATION_CLICK",
                },
                android: {
                    priority: "high",
                    notification: {
                        channelId: "taches",
                        sound: "default",
                    },
                },
                apns: {
                    headers: {"apns-priority": "10"},
                    payload: {aps: {sound: "default"}},
                },
            });

            return {success: true};
        } catch (e) {
            console.error("notifyTacheAssignee error:", e);
            return {success: false, reason: String(e)};
        }
    });
