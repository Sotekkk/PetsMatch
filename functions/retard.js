const functions = require("firebase-functions/v1");
const {createClient} = require("@supabase/supabase-js");
const {sendPush} = require("./push_helpers");
const {SUPABASE_URL, SUPABASE_SERVICE_KEY} = require("./config");

function getSupabase() {
    // Push envoyé ici : pas de second push par le webhook notify_push.
    return createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {global: {headers: {"x-pm-push": "serveur"}}});
}

/**
 * VET07 — Alerte retard agenda pro.
 * Notifie les clients ayant un RDV confirmé dans les 3h prochaines.
 *
 * Paramètres (data) :
 *   delaiMinutes, message ;
 *   proProfileId : profil pro concerné (multi-profil — sinon les clients de
 *     TOUS les profils du compte étaient prévenus) ;
 *   praticienProfileId : clinique — '' = titulaire, id = vétérinaire employé,
 *     '*' = toute la clinique. Absent = tous les RDV du profil.
 * Appelant autorisé : titulaire du profil, ou employé actif de ce profil
 * (ASV / praticien qui le signale au nom de la clinique).
 */
exports.sendRetardNotification = functions
    .region("europe-west1")
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Auth requise");
        }
        const callerUid = context.auth.uid;
        const delaiMinutes = parseInt(data.delaiMinutes) || 15;
        const message = (data.message || "").trim();
        const proProfileId = (data.proProfileId || "").trim() || null;
        const praticien = data.praticienProfileId === undefined || data.praticienProfileId === null ?
            "*" : String(data.praticienProfileId);

        const supa = getSupabase();

        // Compte pro concerné : celui du profil (titulaire), contrôle d'accès.
        let proUid = callerUid;
        let proName = null;
        if (proProfileId) {
            const {data: prof} = await supa.from("user_profiles")
                .select("uid, nom, firstname, lastname").eq("id", proProfileId).maybeSingle();
            if (!prof) throw new functions.https.HttpsError("not-found", "Profil introuvable");
            if (prof.uid !== callerUid) {
                const {data: emp} = await supa.from("employes").select("id")
                    .eq("eleveur_profile_id", proProfileId).eq("uid_employe", callerUid)
                    .eq("actif", true).maybeSingle();
                if (!emp) throw new functions.https.HttpsError("permission-denied", "Accès refusé");
            }
            proUid = prof.uid;
            proName = (prof.nom || "").trim() ||
                `${prof.firstname || ""} ${prof.lastname || ""}`.trim() || null;
        }
        if (!proName) {
            const {data: proData} = await supa
                .from("users")
                .select("firstname, lastname, name_elevage, profession_pro")
                .eq("uid", proUid)
                .maybeSingle();
            proName = (proData?.name_elevage?.trim()) ||
                `${proData?.firstname || ""} ${proData?.lastname || ""}`.trim() ||
                proData?.profession_pro || "Votre praticien";
        }

        // Clinique : nom du vétérinaire en retard (« Dr X — Clinique Y »).
        if (praticien && praticien !== "*" && praticien !== "") {
            const {data: p} = await supa.from("user_profiles")
                .select("firstname, lastname").eq("id", praticien).maybeSingle();
            const n = `${p?.firstname || ""} ${p?.lastname || ""}`.trim();
            if (n) proName = `Dr ${n} (${proName})`;
        }

        // RDVs confirmés dans les 3h
        const now = new Date();
        const in3h = new Date(now.getTime() + 3 * 60 * 60 * 1000);

        let q = supa
            .from("rdv")
            .select("id, client_uid, client_profile_id, date_heure, motif")
            .eq("pro_uid", proUid)
            .eq("statut", "confirme")
            .gte("date_heure", now.toISOString())
            .lte("date_heure", in3h.toISOString());
        if (proProfileId) q = q.eq("pro_profile_id", proProfileId);
        if (praticien === "") q = q.is("instructeur_profile_id", null);
        else if (praticien !== "*") q = q.eq("instructeur_profile_id", praticien);
        const {data: rdvs} = await q;

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
        const profileIdByClient = {};
        for (const r of rdvs) {
            if (r.client_uid && r.client_profile_id && !profileIdByClient[r.client_uid]) {
                profileIdByClient[r.client_uid] = r.client_profile_id;
            }
        }
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
                    ...(profileIdByClient[clientUid] ? {profile_id: profileIdByClient[clientUid]} : {}),
                });
            } catch (_) {/* noop */}

            // Push FCM
            try {
                const retardTitle = `Retard de ${delaiText}`;
                const sent = await sendPush(clientUid, retardTitle, body,
                    {type: "rdv_retard", pro_uid: proUid},
                    {profileId: profileIdByClient[clientUid] || null});
                if (sent) notified++;
            } catch (_) {/* noop */}
        }

        return {success: true, notified};
    });
