const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const https = require("https");

if (!admin.apps.length) admin.initializeApp();

// Inscriptions jamais terminées (e-mail jamais validé) :
//  • libererEmailInscription (HTTPS, appli + site) : au moment de créer un
//    compte, si l'adresse est déjà prise par une inscription ABANDONNÉE
//    (compte e-mail / mot de passe jamais validé), ce compte et ses lignes
//    users / user_profiles sont supprimés pour que la nouvelle inscription
//    passe — plus de « e-mail déjà utilisé » pour quelqu'un qui n'a rien fini.
//    Un compte validé, ou Google / Apple, n'est jamais touché.
//  • purgerInscriptionsAbandonnees (tous les jours, 4 h) : même nettoyage pour
//    les comptes jamais validés de plus de 3 jours.

const {SUPABASE_URL, SUPABASE_AUTH_HEADERS} = require("./config");

function supabaseDelete(path) {
    return new Promise((resolve) => {
        const url = new URL(`${SUPABASE_URL}${path}`);
        const req = https.request({
            hostname: url.hostname, path: url.pathname + (url.search || ""), method: "DELETE",
            headers: {"Content-Type": "application/json", ...SUPABASE_AUTH_HEADERS},
        }, (res) => {
            res.on("data", () => {}); res.on("end", () => resolve(res.statusCode));
        });
        req.on("error", () => resolve(0));
        req.end();
    });
}

/** Compte abandonné = e-mail / mot de passe uniquement, e-mail jamais validé. */
function estAbandonne(user) {
    if (!user || user.emailVerified) return false;
    const fournisseurs = (user.providerData || []).map((p) => p.providerId);
    return fournisseurs.length === 0 || fournisseurs.every((p) => p === "password");
}

async function supprimerCompte(user) {
    const uid = encodeURIComponent(user.uid);
    await supabaseDelete(`/rest/v1/user_profiles?uid=eq.${uid}`);
    await supabaseDelete(`/rest/v1/users?uid=eq.${uid}`);
    await admin.auth().deleteUser(user.uid);
}

exports.libererEmailInscription = functions
    .region("europe-west1")
    .https.onRequest(async (req, res) => {
        res.set("Access-Control-Allow-Origin", "*");
        res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
        res.set("Access-Control-Allow-Headers", "Content-Type");
        if (req.method === "OPTIONS") {
            res.status(204).send(""); return;
        }
        if (req.method !== "POST") {
            res.status(405).json({error: "POST attendu"}); return;
        }
        const email = String((req.body && req.body.email) || "").trim().toLowerCase();
        if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
            res.status(400).json({error: "E-mail invalide"}); return;
        }
        try {
            let user;
            try {
                user = await admin.auth().getUserByEmail(email);
            } catch (e) {
                if (e.code === "auth/user-not-found") {
                    res.json({libere: true}); return;
                }
                throw e;
            }
            if (!estAbandonne(user)) {
                res.json({libere: false}); return;
            }
            await supprimerCompte(user);
            console.log(`[inscription] adresse libérée (inscription abandonnée) uid=${user.uid}`);
            res.json({libere: true});
        } catch (e) {
            console.error("[inscription] libererEmailInscription:", e.message);
            res.status(500).json({error: "Erreur serveur"});
        }
    });

exports.purgerInscriptionsAbandonnees = functions
    .region("europe-west1")
    .pubsub.schedule("0 4 * * *")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        const limite = Date.now() - 3 * 24 * 3600 * 1000;
        let page;
        let purges = 0;
        do {
            const r = await admin.auth().listUsers(1000, page);
            for (const u of r.users) {
                const cree = Date.parse(u.metadata.creationTime || "") || Date.now();
                if (cree < limite && estAbandonne(u)) {
                    try {
                        await supprimerCompte(u); purges++;
                    } catch (e) {
                        console.error(`[inscription] purge ${u.uid}:`, e.message);
                    }
                }
            }
            page = r.pageToken;
        } while (page);
        console.log(`[inscription] ${purges} inscription(s) abandonnée(s) purgée(s)`);
        return null;
    });
