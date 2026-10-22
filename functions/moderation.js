const functions = require("firebase-functions/v1");
const {SUPABASE_URL, SUPABASE_AUTH_HEADERS} = require("./config");

// Levée automatique des suspensions arrivées à échéance (sanctions décidées
// depuis les signalements de l'admin du site, table sanctions_moderation) :
// le compte redevient actif sur tous ses profils et la personne est prévenue.
// Un blocage (fin_le vide) n'est jamais levé ici.

async function sb(path, options = {}) {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
        ...options,
        headers: {"Content-Type": "application/json", ...SUPABASE_AUTH_HEADERS, ...(options.headers || {})},
    });
    if (!r.ok) throw new Error(`${r.status} ${await r.text()}`);
    const t = await r.text();
    return t ? JSON.parse(t) : null;
}

exports.leverSuspensionsExpirees = functions
    .region("europe-west1")
    .pubsub.schedule("every 60 minutes")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        const maintenant = new Date().toISOString();
        const echues = await sb(
            "sanctions_moderation?type=eq.suspension&leve_le=is.null" +
            `&fin_le=lt.${encodeURIComponent(maintenant)}&select=id,uid`,
        );
        for (const s of echues || []) {
            try {
                // Une autre suspension / un blocage encore en cours garde le compte suspendu.
                const enCours = await sb(
                    `sanctions_moderation?uid=eq.${encodeURIComponent(s.uid)}` +
                    `&leve_le=is.null&id=neq.${s.id}` +
                    `&or=(type.eq.blocage,fin_le.gt.${encodeURIComponent(maintenant)})&select=id`,
                );
                await sb(`sanctions_moderation?id=eq.${s.id}`, {
                    method: "PATCH", body: JSON.stringify({leve_le: maintenant}),
                });
                if ((enCours || []).length) continue;
                await sb(`user_profiles?uid=eq.${encodeURIComponent(s.uid)}&statut_pro=eq.suspendu`, {
                    method: "PATCH", body: JSON.stringify({statut_pro: "actif"}),
                });
                await sb("notifications", {
                    method: "POST",
                    body: JSON.stringify({
                        uid: s.uid, type: "moderation", read: false,
                        title: "Votre compte est de nouveau actif",
                        body: "La suspension de votre compte est terminée. " +
                            "Merci de respecter les règles de la communauté.",
                    }),
                });
            } catch (e) {
                console.error(`[moderation] levée ${s.id}:`, e.message);
            }
        }
        return null;
    });
