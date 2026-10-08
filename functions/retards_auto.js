const functions = require("firebase-functions/v1");
const {createClient} = require("@supabase/supabase-js");
const {sendPush} = require("./push_helpers");
const {SUPABASE_URL, SUPABASE_SERVICE_KEY} = require("./config");

function getSupabase() {
    // Push envoyé ici : pas de second push par le webhook notify_push.
    return createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {global: {headers: {"x-pm-push": "serveur"}}});
}

const SEUIL_MIN = 30; // premier avertissement du client
const PAS_MIN = 15; // nouvel avertissement si le retard augmente d'autant
const OUBLI_MIN = 120; // RDV non clôturé 2 h après l'heure de fin : « oublié »

/**
 * Retards en cascade d'une journée, par praticien (même calcul que l'appli :
 * lib/utils/retards_rdv.dart, et le site : website/src/lib/retards-rdv.ts).
 * rdvs : RDV du jour (confirmés / terminés) d'un même praticien, triés.
 * Renvoie { rdvId: retardMinutes } pour les RDV à venir.
 */
function retardsEnCascade(rdvs, now) {
    const out = {};
    let curseur = null; // fin réelle / estimée du RDV précédent
    for (const r of rdvs) {
        const debut = new Date(r.date_heure).getTime();
        const duree = (r.duree_minutes || 30) * 60000;
        const finPrevue = debut + duree;
        if (r.statut === "termine") {
            curseur = r.termine_at ? new Date(r.termine_at).getTime() : finPrevue;
            continue;
        }
        if (debut <= now) {
            // En cours (ou pas encore clôturé) : se termine au plus tôt maintenant.
            const debutReel = Math.max(debut, curseur || debut);
            let fin = Math.max(debutReel + duree, now);
            if (now - finPrevue > OUBLI_MIN * 60000) fin = finPrevue; // clôture oubliée
            curseur = fin;
            continue;
        }
        const debutEstime = Math.max(debut, curseur || debut);
        const retard = Math.round((debutEstime - debut) / 60000);
        if (retard > 0) out[r.id] = retard;
        curseur = debutEstime + duree;
    }
    return out;
}

const fmtHeure = (iso) => new Date(iso).toLocaleTimeString("fr-FR",
    {hour: "2-digit", minute: "2-digit", timeZone: "Europe/Paris"});

/**
 * Toutes les 5 min : pour chaque profil vétérinaire ayant activé l'alerte
 * automatique, calcule les retards en cascade du jour et prévient les
 * clients concernés (≥ 30 min, puis +15 min).
 */
exports.sendRetardsAutomatiques = functions
    .region("europe-west1")
    .pubsub.schedule("*/5 7-21 * * *")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        const supa = getSupabase();
        const {data: profils} = await supa.from("user_profiles")
            .select("id, uid, nom").eq("retard_alerte_auto", true).eq("profile_type", "veterinaire");
        if (!profils || profils.length === 0) return null;

        const now = Date.now();
        const paris = new Date(new Date().toLocaleString("en-US", {timeZone: "Europe/Paris"}));
        const decalage = now - paris.getTime();
        const debutJour = new Date(paris.getFullYear(), paris.getMonth(), paris.getDate()).getTime() + decalage;
        const finJour = debutJour + 86400000;
        let notifies = 0;

        for (const p of profils) {
            const {data: rdvs} = await supa.from("rdv")
                .select("id, client_uid, client_profile_id, date_heure, duree_minutes, statut, " +
                    "termine_at, instructeur_profile_id, retard_notifie_min, motif")
                .eq("pro_profile_id", p.id)
                .in("statut", ["confirme", "termine"])
                .gte("date_heure", new Date(debutJour).toISOString())
                .lt("date_heure", new Date(finJour).toISOString())
                .order("date_heure", {ascending: true});
            if (!rdvs || rdvs.length === 0) continue;

            // Par praticien (titulaire = sans praticien).
            const groupes = {};
            for (const r of rdvs) {
                const k = r.instructeur_profile_id || "";
                if (!groupes[k]) groupes[k] = [];
                groupes[k].push(r);
            }

            const noms = {};
            for (const [praticien, liste] of Object.entries(groupes)) {
                const retards = retardsEnCascade(liste, now);
                for (const r of liste) {
                    const retard = retards[r.id] || 0;
                    if (retard < SEUIL_MIN || !r.client_uid) continue;
                    if (r.retard_notifie_min != null && retard < r.retard_notifie_min + PAS_MIN) continue;

                    if (noms[praticien] === undefined) {
                        noms[praticien] = (p.nom || "").trim() || "Votre vétérinaire";
                        if (praticien) {
                            const {data: v} = await supa.from("user_profiles")
                                .select("firstname, lastname").eq("id", praticien).maybeSingle();
                            const n = `${v?.firstname || ""} ${v?.lastname || ""}`.trim();
                            if (n) noms[praticien] = `Dr ${n} (${noms[praticien]})`;
                        }
                    }
                    const estime = new Date(new Date(r.date_heure).getTime() + retard * 60000).toISOString();
                    const titre = `Retard d'environ ${retard} min`;
                    const corps = `${noms[praticien]} a environ ${retard} min de retard : votre RDV de ` +
                        `${fmtHeure(r.date_heure)} devrait commencer vers ${fmtHeure(estime)}. Votre RDV est maintenu.`;
                    try {
                        await supa.from("notifications").insert({
                            uid: r.client_uid, type: "rdv_retard", title: titre, body: corps,
                            data: {pro_uid: p.uid, rdv_id: r.id, retard_min: retard}, read: false,
                            ...(r.client_profile_id ? {profile_id: r.client_profile_id} : {}),
                        });
                        await sendPush(r.client_uid, titre, corps,
                            {type: "rdv_retard", pro_uid: p.uid, rdv_id: r.id},
                            {profileId: r.client_profile_id || null});
                        await supa.from("rdv").update({retard_notifie_min: retard}).eq("id", r.id);
                        notifies++;
                    } catch (e) {
                        console.error("sendRetardsAutomatiques", r.id, e.message);
                    }
                }
            }
        }
        console.log(`sendRetardsAutomatiques : ${notifies} client(s) prévenu(s)`);
        return null;
    });

exports.retardsEnCascade = retardsEnCascade;
