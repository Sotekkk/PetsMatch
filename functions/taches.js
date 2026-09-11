const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const {sendPush, resolveProfileId} = require("./push_helpers");

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
            const tacheTitle = "Nouvelle tâche assignée";
            const sent = await sendPush(assigneUid, tacheTitle, titre,
                {type: "tache", click_action: "FLUTTER_NOTIFICATION_CLICK"},
                {profileId: await resolveProfileId(assigneUid, "pro")});
            if (!sent) return {success: false, reason: "no_fcm_token"};
            return {success: true};
        } catch (e) {
            console.error("notifyTacheAssignee error:", e);
            return {success: false, reason: String(e)};
        }
    });
