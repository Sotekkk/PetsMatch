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

const {SUPABASE_URL, SUPABASE_AUTH_HEADERS, INTERNAL_API_SECRET} = require("./config");
const SITE_URL = process.env.SITE_URL || "https://petsmatchapp.com";

// Lien de validation valable 10 minutes : Firebase ne permet pas de régler la
// durée de ses liens (environ 3 jours). L'e-mail contient donc un lien PetsMatch
// (petsmatchapp.com/api/inscription/lien?t=…) qui retient son heure d'envoi :
// validerLienInscription redirige vers le lien Firebase dans les 10 minutes,
// sinon vers la page de validation (« lien expiré », nouveau lien possible).
const DUREE_LIEN_MS = 10 * 60 * 1000;
const crypto = require("crypto");

async function lienValidation(uid, email) {
    const lienFirebase = await admin.auth().generateEmailVerificationLink(email);
    const jeton = crypto.randomBytes(24).toString("hex");
    await admin.firestore().collection("liens_validation").doc(jeton).set({
        uid, email, lien: lienFirebase, expire: Date.now() + DUREE_LIEN_MS,
    });
    return `${SITE_URL}/api/inscription/lien?t=${jeton}`;
}

/** E-mail de validation envoyé par le site (gabarit PetsMatch), lien généré ici. */
function envoyerValidation(email, lien, jeton) {
    return new Promise((resolve) => {
        const data = JSON.stringify({email, lien});
        const u = new URL(`${SITE_URL}/api/inscription/email-validation`);
        const req = https.request({
            hostname: u.hostname, path: u.pathname, method: "POST",
            headers: {
                "Content-Type": "application/json", "Content-Length": Buffer.byteLength(data),
                // Jeton Firebase de la personne (route accessible à un utilisateur connecté),
                // + secret serveur s'il est configuré.
                "Authorization": `Bearer ${jeton}`,
                ...(INTERNAL_API_SECRET ? {"x-internal-secret": INTERNAL_API_SECRET} : {}),
            },
        }, (res) => {
            res.on("data", () => {});
            res.on("end", () => {
                if (res.statusCode !== 200) console.error(`[inscription] envoi validation HTTP ${res.statusCode}`);
                resolve(res.statusCode === 200);
            });
        });
        req.on("error", () => resolve(false));
        req.write(data);
        req.end();
    });
}

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

function supabasePatch(path, body) {
    return new Promise((resolve) => {
        const url = new URL(`${SUPABASE_URL}${path}`);
        const data = JSON.stringify(body);
        const req = https.request({
            hostname: url.hostname, path: url.pathname + (url.search || ""), method: "PATCH",
            headers: {
                "Content-Type": "application/json", "Content-Length": Buffer.byteLength(data), ...SUPABASE_AUTH_HEADERS,
            },
        }, (res) => {
            res.on("data", () => {}); res.on("end", () => resolve(res.statusCode));
        });
        req.on("error", () => resolve(0));
        req.write(data);
        req.end();
    });
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

// Adresse mal saisie à l'inscription (compte pas encore validé) : l'adresse est
// changée tout de suite sur le MÊME compte (toutes les informations gardées),
// puis l'appli / le site renvoie l'e-mail de validation à la nouvelle adresse.
// Appelant identifié par son jeton Firebase (Authorization: Bearer).
exports.changerEmailInscription = functions
    .region("europe-west1")
    .https.onRequest(async (req, res) => {
        res.set("Access-Control-Allow-Origin", "*");
        res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
        res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
        if (req.method === "OPTIONS") {
            res.status(204).send(""); return;
        }
        if (req.method !== "POST") {
            res.status(405).json({error: "POST attendu"}); return;
        }
        const m = String(req.headers.authorization || "").match(/^Bearer\s+(.+)$/i);
        const email = String((req.body && req.body.email) || "").trim().toLowerCase();
        if (!m) {
            res.status(401).json({error: "Session expirée : reconnectez-vous."}); return;
        }
        if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
            res.status(400).json({error: "Cette adresse n'est pas valide."}); return;
        }
        try {
            const {uid} = await admin.auth().verifyIdToken(m[1]);
            const moi = await admin.auth().getUser(uid);
            if (!estAbandonne(moi)) {
                res.status(400).json({error: "Ce compte est déjà validé."}); return;
            }
            if ((moi.email || "").toLowerCase() === email) {
                // Même adresse : simple renvoi du lien de validation.
                const lien = await lienValidation(uid, email);
                const envoye = await envoyerValidation(email, lien, m[1]);
                res.json({ok: true, envoye}); return;
            }
            try {
                const autre = await admin.auth().getUserByEmail(email);
                if (autre.uid !== uid) {
                    if (!estAbandonne(autre)) {
                        res.status(409).json({error: "Cette adresse est déjà utilisée par un autre compte."}); return;
                    }
                    await supprimerCompte(autre);
                }
            } catch (e) {
                if (e.code !== "auth/user-not-found") throw e;
            }
            await admin.auth().updateUser(uid, {email, emailVerified: false});
            await supabasePatch(`/rest/v1/users?uid=eq.${encodeURIComponent(uid)}`, {email});
            // Le lien de validation part d'ici : la session du navigateur / de
            // l'appli porte encore l'ancienne adresse juste après le changement.
            const lien = await lienValidation(uid, email);
            const envoye = await envoyerValidation(email, lien, m[1]);
            // Changer l'adresse ferme la session en cours (Firebase) : jeton de
            // reconnexion automatique, pour ne pas faire se reconnecter quelqu'un
            // en pleine création de compte.
            let customToken = null;
            try {
                customToken = await admin.auth().createCustomToken(uid);
            } catch (e) {
                console.error("[inscription] jeton de reconnexion:", e.message);
            }
            console.log(`[inscription] adresse corrigée avant validation uid=${uid} envoi=${envoye}`);
            res.json({ok: true, envoye, customToken});
        } catch (e) {
            console.error("[inscription] changerEmailInscription:", e.message);
            res.status(500).json({error: "Changement impossible. Réessayez."});
        }
    });

function supabaseGet(path) {
    return new Promise((resolve) => {
        const url = new URL(`${SUPABASE_URL}${path}`);
        const req = https.request({
            hostname: url.hostname, path: url.pathname + (url.search || ""), method: "GET",
            headers: {...SUPABASE_AUTH_HEADERS},
        }, (res) => {
            let d = "";
            res.on("data", (c) => d += c);
            res.on("end", () => {
                try {
                    resolve(JSON.parse(d));
                } catch (e) {
                    resolve(null);
                }
            });
        });
        req.on("error", () => resolve(null));
        req.end();
    });
}

// Admin : comptes dont l'inscription n'est pas finalisée (e-mail / mot de passe
// jamais validé). Le site n'a pas l'Admin SDK : le module admin interroge ici
// pour marquer ces comptes « E-mail non validé ». Réservé aux admins.
exports.inscriptionsNonValidees = functions
    .region("europe-west1")
    .https.onRequest(async (req, res) => {
        res.set("Access-Control-Allow-Origin", "*");
        res.set("Access-Control-Allow-Methods", "GET, OPTIONS");
        res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
        if (req.method === "OPTIONS") {
            res.status(204).send(""); return;
        }
        const m = String(req.headers.authorization || "").match(/^Bearer\s+(.+)$/i);
        if (!m) {
            res.status(401).json({error: "Non connecté"}); return;
        }
        try {
            const {uid} = await admin.auth().verifyIdToken(m[1]);
            const rows = await supabaseGet(`/rest/v1/users?uid=eq.${encodeURIComponent(uid)}&select=is_admin`);
            if (!Array.isArray(rows) || rows[0]?.is_admin !== true) {
                res.status(403).json({error: "Réservé aux admins"}); return;
            }
            const uids = [];
            let page;
            do {
                const r = await admin.auth().listUsers(1000, page);
                r.users.forEach((u) => {
                    if (estAbandonne(u)) uids.push(u.uid);
                });
                page = r.pageToken;
            } while (page);
            res.json({uids});
        } catch (e) {
            console.error("[inscription] inscriptionsNonValidees:", e.message);
            res.status(500).json({error: "Erreur serveur"});
        }
    });

// Ouverture d'un lien de validation PetsMatch (voir lienValidation) : valable
// 10 minutes, ensuite « lien expiré » sur la page de validation.
exports.validerLienInscription = functions
    .region("europe-west1")
    .https.onRequest(async (req, res) => {
        const jeton = String((req.query && req.query.t) || "");
        const expire = `${SITE_URL}/verifier-email?lien=expire`;
        if (!/^[a-f0-9]{48}$/.test(jeton)) {
            res.redirect(302, expire); return;
        }
        try {
            const doc = await admin.firestore().collection("liens_validation").doc(jeton).get();
            const d = doc.exists ? doc.data() : null;
            if (!d || !d.lien || Date.now() > d.expire) {
                // Adresse transmise : la page propose un nouveau lien même
                // ouverte dans un autre navigateur (boîte mail), sans session.
                res.redirect(302, d && d.email ? `${expire}&email=${encodeURIComponent(d.email)}` : expire); return;
            }
            res.redirect(302, d.lien);
        } catch (e) {
            console.error("[inscription] validerLienInscription:", e.message);
            res.redirect(302, expire);
        }
    });
