const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

if (!admin.apps.length) admin.initializeApp();

/**
 * Callable — sends a push notification to an employee when they are added to an élevage.
 * The in-app notification (Supabase) is already inserted by the Flutter client.
 */
exports.notifyEmployeeAdded = functions
    .region("europe-west1")
    .https.onCall(async (data) => {
        const {employeUid, nomElevage} = data;
        if (!employeUid || !nomElevage) return {success: false, reason: "missing_params"};

        try {
            const userDoc = await admin.firestore().collection("users").doc(employeUid).get();
            const fcmToken = userDoc.exists ? userDoc.data()?.fcmToken : null;

            if (!fcmToken) return {success: false, reason: "no_fcm_token"};

            await admin.messaging().send({
                token: fcmToken,
                notification: {
                    title: "Invitation à rejoindre un élevage",
                    body: `Vous avez été ajouté à l'équipe de ${nomElevage}`,
                },
                data: {
                    type: "employee_invite",
                    click_action: "FLUTTER_NOTIFICATION_CLICK",
                },
                android: {
                    priority: "high",
                    notification: {
                        channelId: "employes",
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
            console.error("notifyEmployeeAdded error:", e);
            return {success: false, reason: String(e)};
        }
    });
