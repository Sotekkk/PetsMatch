const admin = require("firebase-admin");
const https = require("https");

// Même pattern supabaseSelect que chaleurs.js/agenda.js/sante.js (dupliqué
// par fichier dans tout functions/ — on suit la convention existante).
const SUPABASE_URL = "https://zyvpngcvzrkdytypjlyq.supabase.co";
const SUPABASE_SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" +
    ".eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5dnBuZ2N2enJrZHl0eXBqbHlxIiwi" +
    "cm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTM2NDY1NSwiZXhwIjoyMDk0OT" +
    "QwNjU1fQ.1U96V3c7nHG3T08dboBcxTd05k8A_JQfnyrJTbJ0HgQ";

function supabaseRequest(method, path) {
    return new Promise((resolve, reject) => {
        const url = new URL(`${SUPABASE_URL}/rest/v1/${path}`);
        const options = {
            hostname: url.hostname,
            path: url.pathname + (url.search || ""),
            method,
            headers: {
                "Content-Type": "application/json",
                "apikey": SUPABASE_SERVICE_KEY,
                "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
            },
        };
        const req = https.request(options, (res) => {
            let data = "";
            res.on("data", (chunk) => data += chunk);
            res.on("end", () => {
                try {
                    resolve({status: res.statusCode, body: JSON.parse(data)});
                } catch (_) {
                    resolve({status: res.statusCode, body: []});
                }
            });
        });
        req.on("error", reject);
        req.end();
    });
}

async function supabaseSelect(table, query) {
    const res = await supabaseRequest("GET", `${table}?${query}&select=*`);
    return Array.isArray(res.body) ? res.body : [];
}

// Reprend _socialTypeLabel (lib/pages/particulier/social_feed_page.dart) pour
// que le libellé affiché dans les push corresponde à celui vu dans l'app.
const TYPE_LABELS = {
    eleveur: "Éleveur",
    association: "Association",
    veterinaire: "Vétérinaire",
    sante: "Ostéo/Vétérinaire",
    education: "Éducateur",
    garde: "Pet Sitter",
    toilettage: "Toiletteur",
    photographe: "Photographe",
    pension: "Pension",
};

/**
 * Nom court d'un profil pour préfixer le titre d'une notification push.
 * @param {string} profileId - id de user_profiles.
 * @return {Promise<string|null>} le libellé, ou null si non résolu.
 */
async function profileLabel(profileId) {
    if (!profileId) return null;
    try {
        const rows = await supabaseSelect("user_profiles",
            `id=eq.${encodeURIComponent(profileId)}&select=profile_type,nom,firstname,lastname`);
        const p = rows[0];
        if (!p) return null;
        if (p.profile_type === "particulier") {
            const n = `${p.firstname || ""} ${p.lastname || ""}`.trim();
            return n || "Particulier";
        }
        return p.nom || TYPE_LABELS[p.profile_type] || "Professionnel";
    } catch (_) {
        return null;
    }
}

/**
 * Profil d'un uid le plus pertinent à notifier quand on n'a pas de
 * profile_id sous la main. Jamais bloquant (retourne null en cas d'échec).
 * @param {string} uid - uid Firebase.
 * @param {string} [preferType] - 'particulier' : uniquement le profil
 *   particulier (null si absent). 'pro' : profil principal (is_main) s'il
 *   n'est pas particulier, sinon le premier profil pro trouvé — ne bascule
 *   jamais un pro vers son profil particulier. Par défaut : particulier
 *   s'il existe, sinon is_main.
 * @return {Promise<string|null>}
 */
async function resolveProfileId(uid, preferType) {
    if (!uid) return null;
    try {
        const rows = await supabaseSelect("user_profiles",
            `uid=eq.${encodeURIComponent(uid)}&select=id,profile_type,is_main`);
        if (!rows.length) return null;
        if (preferType === "particulier") {
            const part = rows.find((r) => r.profile_type === "particulier");
            return part ? part.id : null;
        }
        if (preferType === "pro") {
            const main = rows.find((r) => r.is_main === true && r.profile_type !== "particulier");
            if (main) return main.id;
            const pro = rows.find((r) => r.profile_type !== "particulier");
            return pro ? pro.id : null;
        }
        const part = rows.find((r) => r.profile_type === "particulier");
        if (part) return part.id;
        const main = rows.find((r) => r.is_main === true);
        return main ? main.id : rows[0].id;
    } catch (_) {
        return null;
    }
}

/**
 * Envoie un push data-only à un uid (Firestore users/{uid}.fcmToken +
 * webFcmToken). `opts.profileId`, si fourni, préfixe le titre
 * (« <nom du profil> · <titre> ») et ajoute `recipient_profile_id` aux
 * données — lu par lib/main.dart _handleNotifNavigation pour basculer sur ce
 * profil au tap, avant d'ouvrir la page de notifications.
 * @param {string} uid - destinataire.
 * @param {string} title - titre (avant préfixe éventuel).
 * @param {string} body - corps du message.
 * @param {object} [data] - données additionnelles (type, ids…).
 * @param {{profileId?: string}} [opts] - profil concerné, pour le préfixe +
 *   la bascule au tap.
 * @return {Promise<boolean>} true si au moins un token a reçu l'envoi.
 */
async function sendPush(uid, title, body, data = {}, opts = {}) {
    try {
        const doc = await admin.firestore().collection("users").doc(uid).get();
        if (!doc.exists) return false;
        const userData = doc.data();
        const tokens = [userData.fcmToken, userData.webFcmToken].filter(Boolean);
        if (!tokens.length) return false;

        let finalTitle = title;
        if (opts.profileId) {
            const label = await profileLabel(opts.profileId);
            if (label) finalTitle = `${label} · ${title}`;
        }

        let sent = false;
        for (const token of tokens) {
            try {
                await admin.messaging().send({
                    token,
                    data: {
                        ...data,
                        type: data.type || "generic",
                        title: finalTitle,
                        body,
                        ...(opts.profileId ? {recipient_profile_id: opts.profileId} : {}),
                    },
                    android: {priority: "high"},
                    apns: {
                        headers: {"apns-priority": "10"},
                        payload: {aps: {alert: {title: finalTitle, body}, sound: "default", badge: 1}},
                    },
                });
                sent = true;
            } catch (e) {
                console.warn(`sendPush token error uid=${uid}:`, e.message);
            }
        }
        return sent;
    } catch (e) {
        console.error(`sendPush error uid=${uid}:`, e.message);
        return false;
    }
}

module.exports = {sendPush, profileLabel, resolveProfileId};
