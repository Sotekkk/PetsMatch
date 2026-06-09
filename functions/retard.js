const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const {createClient} = require("@supabase/supabase-js");

function getSupabase() {
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY ||
        (functions.config().supabase || {}).service_key || "";
    return createClient("https://zyvpngcvzrkdytypjlyq.supabase.co", key);
}

/**
 * VET07 — Alerte retard agenda pro.
 * Notifie tous les clients ayant un RDV dans les 3h prochaines.
 */
exports.sendRetardNotification = functions
    .region("europe-west1")
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Auth requise");
        }
        const proUid = context.auth.uid;
        const delaiMinutes = parseInt(data.delaiMinutes) || 15;
        const message = (data.message || "").trim();

        const supa = getSupabase();

        // Nom du pro
        const {data: proData} = await supa
            .from("users")
            .select("firstname, lastname, name_elevage, profession_pro")
            .eq("uid", proUid)
            .maybeSingle();

        const proName = (proData?.name_elevage?.trim()) ||
            `${proData?.firstname || ""} ${proData?.lastname || ""}`.trim() ||
            proData?.profession_pro || "Votre praticien";

        // RDVs confirmés dans les 3h
        const now = new Date();
        const in3h = new Date(now.getTime() + 3 * 60 * 60 * 1000);

        const {data: rdvs} = await supa
            .from("rdv")
            .select("id, client_uid, date_heure, motif")
            .eq("pro_uid", proUid)
            .eq("statut", "confirme")
            .gte("date_heure", now.toISOString())
            .lte("date_heure", in3h.toISOString());

        if (!rdvs || rdvs.length === 0) {
            return {success: true, notified: 0};
        }

        // Log retard
        try {
            await supa.from("agenda_retards").insert({
                pro_uid: proUid,
                delai_minutes: delaiMinutes,
                message: message || null,
            });
        } catch (_) {/* noop */}

        const delaiText = delaiMinutes < 60 ?
            `${delaiMinutes} minutes` :
            `${Math.floor(delaiMinutes / 60)}h${delaiMinutes % 60 > 0 ? delaiMinutes % 60 : ""}`;

        const uniqueClients = [...new Set(rdvs.map((r) => r.client_uid).filter(Boolean))];
        let notified = 0;

        for (const clientUid of uniqueClients) {
            const body = message ?
                `${proName} a ${delaiText} de retard. ${message}` :
                `${proName} a ${delaiText} de retard. Vos RDV sont maintenus.`;

            // Notification in-app
            try {
                await supa.from("notifications").insert({
                    uid: clientUid,
                    type: "rdv_retard",
                    title: `Retard de ${delaiText}`,
                    body: body,
                    data: {pro_uid: proUid},
                    read: false,
                });
            } catch (_) {/* noop */}

            // Push FCM
            try {
                const tokenDoc = await admin.firestore()
                    .collection("users").doc(clientUid).get();
                const fcmToken = tokenDoc.data()?.fcmToken;
                if (fcmToken) {
                    await admin.messaging().send({
                        token: fcmToken,
                        notification: {title: `Retard de ${delaiText}`, body},
                        data: {type: "rdv_retard", pro_uid: proUid},
                        android: {priority: "high"},
                        apns: {payload: {aps: {sound: "default"}}},
                    });
                    notified++;
                }
            } catch (_) {/* noop */}
        }

        return {success: true, notified};
    });
