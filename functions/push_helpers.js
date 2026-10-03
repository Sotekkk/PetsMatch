const admin = require("firebase-admin");
const https = require("https");

// Même pattern supabaseSelect que chaleurs.js/agenda.js/sante.js (dupliqué
// par fichier dans tout functions/ — on suit la convention existante).
const {SUPABASE_URL, SUPABASE_AUTH_HEADERS} = require("./config");

function supabaseRequest(method, path, body) {
    return new Promise((resolve, reject) => {
        const bodyStr = body ? JSON.stringify(body) : null;
        const url = new URL(`${SUPABASE_URL}/rest/v1/${path}`);
        const options = {
            hostname: url.hostname,
            path: url.pathname + (url.search || ""),
            method,
            headers: {
                "Content-Type": "application/json",
                ...SUPABASE_AUTH_HEADERS,
                ...(method === "GET" ? {} : {"Prefer": "return=minimal"}),
            },
        };
        if (bodyStr) options.headers["Content-Length"] = Buffer.byteLength(bodyStr);
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
        if (bodyStr) req.write(bodyStr);
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

        // FCM refuse toute valeur non-string dans `data` (ex. overdue: true
        // passé par les rappels en retard → envoi rejeté en silence).
        const dataStr = {};
        for (const [k, v] of Object.entries(data)) {
            if (v !== null && v !== undefined) dataStr[k] = String(v);
        }

        let sent = false;
        for (const token of tokens) {
            try {
                await admin.messaging().send({
                    token,
                    data: {
                        ...dataStr,
                        type: data.type || "generic",
                        title: finalTitle,
                        body,
                        ...(opts.profileId ? {recipient_profile_id: opts.profileId} : {}),
                    },
                    // Bloc notification Android : affichée par le SYSTÈME même appli
                    // fermée. Les messages data-only étaient perdus sur les
                    // téléphones à économie de batterie agressive (Xiaomi / MIUI…) :
                    // rappel « chaleurs » envoyé sans erreur mais jamais affiché.
                    // L'appli (main.dart) n'affiche plus elle-même un message qui
                    // porte ce bloc, pour éviter un doublon.
                    android: {
                        priority: "high",
                        notification: {title: finalTitle, body, channelId: "high_importance_channel"},
                    },
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

// ─── Employés abonnés à une catégorie de notifications ───────────────────────

/**
 * Employés actifs d'un éleveur ayant coché la permission `notif_<catégorie>`
 * (Élevage → Employés → Accès → « Notifications reçues »). Ils reçoivent les
 * rappels récurrents de la catégorie sans qu'une tâche leur soit affectée.
 * Scopé au profil éleveur quand il est connu (multi-profil), sinon à l'uid.
 * @param {{eleveurUid?: string, eleveurProfileId?: string,
 *   permission: string, cache?: Map}} p - `cache` (optionnel, un par run)
 *   évite de refaire les mêmes requêtes pour chaque animal d'un même élevage.
 * @return {Promise<Array<{uid: string, profileId: string}>>}
 */
async function employesAbonnes({eleveurUid, eleveurProfileId, permission, cache}) {
    if (!eleveurUid && !eleveurProfileId) return [];
    const key = `${permission}|${eleveurProfileId || ""}|${eleveurUid || ""}`;
    if (cache && cache.has(key)) return cache.get(key);
    let result = [];
    try {
        const filtre = eleveurProfileId ?
            `eleveur_profile_id=eq.${encodeURIComponent(eleveurProfileId)}` :
            `uid_eleveur=eq.${encodeURIComponent(eleveurUid)}`;
        const employes = await supabaseSelect("employes",
            `${filtre}&actif=eq.true&employe_profile_id=not.is.null&uid_employe=not.is.null`);
        if (employes.length) {
            const perms = await supabaseSelect("employe_permissions",
                `permission=eq.${encodeURIComponent(permission)}` +
                `&employe_profile_id=in.(${employes.map((e) => e.employe_profile_id).join(",")})`);
            const ok = new Set(perms.map((p) => `${p.eleveur_profile_id}|${p.employe_profile_id}`));
            const seen = new Set();
            for (const e of employes) {
                if (!ok.has(`${e.eleveur_profile_id}|${e.employe_profile_id}`)) continue;
                if (e.uid_employe === eleveurUid || seen.has(e.uid_employe)) continue;
                seen.add(e.uid_employe);
                result.push({uid: e.uid_employe, profileId: e.employe_profile_id});
            }
        }
    } catch (e) {
        console.error(`employesAbonnes error (${permission}):`, e.message);
        result = [];
    }
    if (cache) cache.set(key, result);
    return result;
}

/**
 * Envoie push + notif in-app à chaque employé abonné (voir employesAbonnes).
 * @param {Array<{uid: string, profileId: string}>} employes - destinataires.
 * @param {{type: string, title: string, body: string, pushData?: object,
 *   notifData?: object, exclude?: Array<string>}} n - `exclude` : uids déjà
 *   notifiés par ailleurs (ex. employé assigné à la tâche), pour éviter un doublon.
 * @return {Promise<number>} nombre d'employés notifiés.
 */
async function notifyEmployes(employes, {type, title, body, pushData, notifData, exclude = []}) {
    let n = 0;
    for (const e of employes) {
        if (exclude.includes(e.uid)) continue;
        await sendPush(e.uid, title, body, {type, ...(pushData || {})}, {profileId: e.profileId});
        try {
            await supabaseRequest("POST", "notifications", [{
                uid: e.uid, type, title, body,
                data: notifData || {},
                read: false,
                profile_id: e.profileId,
            }]);
        } catch (err) {
            console.error(`notifyEmployes insert error uid=${e.uid}:`, err.message);
        }
        n++;
    }
    return n;
}

module.exports = {sendPush, profileLabel, resolveProfileId, employesAbonnes, notifyEmployes};
