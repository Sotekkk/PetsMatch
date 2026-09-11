const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const {sendPush, resolveProfileId} = require("./push_helpers");

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
            const employeTitle = "Invitation à rejoindre un élevage";
            const employeBody = `Vous avez été ajouté à l'équipe de ${nomElevage}`;
            const sent = await sendPush(employeUid, employeTitle, employeBody,
                {type: "employee_invite", click_action: "FLUTTER_NOTIFICATION_CLICK"},
                {profileId: await resolveProfileId(employeUid, "pro")});
            if (!sent) return {success: false, reason: "no_fcm_token"};
            return {success: true};
        } catch (e) {
            console.error("notifyEmployeeAdded error:", e);
            return {success: false, reason: String(e)};
        }
    });
