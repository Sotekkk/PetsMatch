const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const https = require("https");

const SUPABASE_URL = "https://zyvpngcvzrkdytypjlyq.supabase.co";
const SUPABASE_SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" +
    ".eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5dnBuZ2N2enJrZHl0eXBqbHlxIiwi" +
    "cm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTM2NDY1NSwiZXhwIjoyMDk0OT" +
    "QwNjU1fQ.1U96V3c7nHG3T08dboBcxTd05k8A_JQfnyrJTbJ0HgQ";

// ─── Supabase helpers ─────────────────────────────────────────────────────────

function supabaseRequest(method, path, body, extraHeaders = {}) {
    return new Promise((resolve, reject) => {
        const bodyStr = body ? JSON.stringify(body) : null;
        const url = new URL(`${SUPABASE_URL}/rest/v1/${path}`);
        const options = {
            hostname: url.hostname,
            path: url.pathname + (url.search || ""),
            method,
            headers: {
                "Content-Type": "application/json",
                "apikey": SUPABASE_SERVICE_KEY,
                "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
                "Prefer": method === "GET" ? "" : "return=minimal",
                ...extraHeaders,
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
    const res = await supabaseRequest("GET", `${table}?${query}`);
    return Array.isArray(res.body) ? res.body : [];
}

async function supabaseInsert(table, rows) {
    const res = await supabaseRequest("POST", table, rows, {"Prefer": "return=minimal"});
    if (res.status < 200 || res.status >= 300) {
        throw new Error(`Supabase insert ${table}: HTTP ${res.status} — ${JSON.stringify(res.body)}`);
    }
    return res.status;
}

async function supabaseInsertReturning(table, rows) {
    const res = await supabaseRequest("POST", table, rows, {"Prefer": "return=representation"});
    return Array.isArray(res.body) ? res.body : [];
}

async function supabasePatch(table, query, patch) {
    const res = await supabaseRequest("PATCH", `${table}?${query}`, patch, {"Prefer": "return=minimal"});
    return res.status;
}

// ─── FCM helper ───────────────────────────────────────────────────────────────

async function sendPush(uid, title, body, data = {}) {
    try {
        const doc = await admin.firestore().collection("users").doc(uid).get();
        if (!doc.exists) return false;
        const userData = doc.data();
        const tokens = [userData.fcmToken, userData.webFcmToken].filter(Boolean);
        if (!tokens.length) return false;

        let sent = false;
        for (const token of tokens) {
            try {
                await admin.messaging().send({
                    token,
                    data: {type: "cession_sterilisation", title, body, ...data},
                    android: {priority: "high"},
                    apns: {
                        headers: {"apns-priority": "10"},
                        payload: {aps: {alert: {title, body}, sound: "default", badge: 1}},
                    },
                });
                sent = true;
            } catch (e) {
                console.warn(`sendPush token error for ${uid}:`, e.message);
            }
        }
        return sent;
    } catch (e) {
        console.error(`sendPush error for ${uid}:`, e);
        return false;
    }
}

// ─── Date helpers (heure locale Paris) ────────────────────────────────────────

function parisNow() {
    return new Date(new Date().toLocaleString("en-US", {timeZone: "Europe/Paris"}));
}

function ymd(d) {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, "0");
    const day = String(d.getDate()).padStart(2, "0");
    return `${y}-${m}-${day}`;
}

// ─── Dédup notifs_sent ────────────────────────────────────────────────────────

async function alreadySent(key) {
    const rows = await supabaseSelect("notifs_sent", `key=eq.${encodeURIComponent(key)}&select=key`);
    return Array.isArray(rows) && rows.length > 0;
}

async function markSent(key) {
    try {
        await supabaseInsert("notifs_sent", [{key, sent_at: new Date().toISOString()}]);
    } catch (e) {
        console.error(`notifs_sent insert error (${key}):`, e.message);
    }
}

// Résout le profil principal (is_main) d'un uid.
async function mainProfile(uid) {
    if (!uid) return null;
    const rows = await supabaseSelect(
        "user_profiles",
        `uid=eq.${uid}&is_main=eq.true&select=id,firstname,lastname,nom,` +
            "avatar_url,cession_anniv_auto,cession_anniv_texte",
    );
    return Array.isArray(rows) && rows[0] ? rows[0] : null;
}

function profileName(p) {
    if (!p) return "Utilisateur";
    const n = (p.nom && p.nom.trim()) ||
        `${p.firstname || ""} ${p.lastname || ""}`.trim();
    return n || "Utilisateur";
}

// ─── 1. Rappels de stérilisation ──────────────────────────────────────────────

const PALIERS = [
    {key: "j30", days: 30, phrase: "dans 1 mois"},
    {key: "j7", days: 7, phrase: "dans 1 semaine"},
    {key: "j2", days: 2, phrase: "dans 48 h"},
    {key: "j0", days: 0, phrase: "aujourd'hui"},
];

/**
 * Schedulée chaque jour à 8h (Paris).
 * Pour chaque animal cédé avec `sterilisation_requise=true` et non validée :
 *   - si la stérilisation a été DÉCLARÉE (animaux.sterilise=true) mais pas
 *     encore validée : rappel quotidien à l'éleveur (« à valider »).
 *   - sinon : rappels au propriétaire ET à l'éleveur aux paliers J-30, J-7,
 *     J-48h, Jour J, puis chaque jour tant que l'échéance est dépassée.
 * Dédup via notifs_sent.
 */
exports.sendSterilisationReminders = functions
    .region("europe-west1")
    .pubsub.schedule("0 8 * * *")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        let sent = 0;
        const today = parisNow();
        today.setHours(0, 0, 0, 0);
        const todayStr = ymd(today);

        const animaux = await supabaseSelect(
            "animaux",
            "sterilisation_requise=eq.true&sterilisation_validee=eq.false" +
            "&select=id,nom,espece,race,date_naissance,sterilise,sterilisation_echeance," +
            "sterilisation_eleveur_uid,sterilisation_eleveur_profile_id,uid_acquereur,destinataire_nom",
        );
        if (!Array.isArray(animaux) || animaux.length === 0) return null;

        for (const a of animaux) {
            const eleveurUid = a.sterilisation_eleveur_uid;
            if (!eleveurUid) continue;
            const eleveurProfileId = a.sterilisation_eleveur_profile_id || null;
            const nom = a.nom || "l'animal";

            // Propriétaire courant : uid_acquereur sinon animaux_proprietes.
            let proprioUid = a.uid_acquereur || null;
            let proprioProfileId = null;
            if (!proprioUid) {
                const props = await supabaseSelect(
                    "animaux_proprietes",
                    `animal_id=eq.${a.id}&date_fin=is.null&select=uid_proprio,profile_id_proprio&limit=1`,
                );
                if (Array.isArray(props) && props[0]) {
                    proprioUid = props[0].uid_proprio;
                    proprioProfileId = props[0].profile_id_proprio || null;
                }
            } else {
                const p = await mainProfile(proprioUid);
                proprioProfileId = p && p.id ? p.id : null;
            }

            // ── Stérilisation déclarée, pas encore validée → l'éleveur valide.
            if (a.sterilise === true) {
                const key = `steril_valider_${a.id}_${todayStr}`;
                if (await alreadySent(key)) continue;
                const title = `✂️ À valider — ${nom}`;
                const body = `Le propriétaire de ${nom} a déclaré la stérilisation. ` +
                    "Validez-la dans le suivi des cessions.";
                if (await sendPush(eleveurUid, title, body, {animalId: String(a.id), tab: "suivi_cessions"})) sent++;
                try {
                    await supabaseInsert("notifications", [{
                        uid: eleveurUid,
                        type: "sterilisation_a_valider",
                        title, body,
                        data: {animalId: String(a.id), tab: "suivi_cessions"},
                        read: false,
                        ...(eleveurProfileId ? {profile_id: eleveurProfileId} : {}),
                    }]);
                } catch (e) {
                    console.error(`notifications insert error (steril valider ${a.id}):`, e.message);
                }
                await markSent(key);
                continue;
            }

            // ── Rappels d'échéance.
            const ech = a.sterilisation_echeance ? new Date(`${a.sterilisation_echeance}T00:00:00`) : null;
            if (!ech || isNaN(ech.getTime())) continue;
            const diffDays = Math.round((ech - today) / 86400000);

            const acquereur = a.destinataire_nom || "l'acquéreur";
            const echStr = new Date(ech).toLocaleDateString("fr-FR");
            let palierKey = null;
            let phrase = null;
            let overdue = false;

            const palier = PALIERS.find((p) => p.days === diffDays);
            if (palier) {
                palierKey = palier.key;
                phrase = palier.phrase;
            } else if (diffDays < 0) {
                overdue = true;
                palierKey = `overdue_${todayStr}`;
                phrase = `en retard de ${-diffDays} jour${diffDays < -1 ? "s" : ""}`;
            } else {
                continue; // rien à faire ce jour
            }

            const key = `steril_${a.id}_${palierKey}`;
            if (await alreadySent(key)) continue;

            const titleProprio = overdue ?
                `⚠️ Stérilisation en retard — ${nom}` :
                `✂️ Stérilisation — ${nom}`;
            const bodyProprio = overdue ?
                `La stérilisation de ${nom} devait être faite avant le ${echStr} (${phrase}).` :
                `Pensez à faire stériliser ${nom} avant le ${echStr} (${phrase}). ` +
                  "Activez « Stérilisé(e) » sur sa fiche une fois faite.";
            const titleEleveur = overdue ?
                `⚠️ Stérilisation en retard — ${nom} (${acquereur})` :
                `✂️ Stérilisation à suivre — ${nom} (${acquereur})`;
            const bodyEleveur = `Stérilisation de ${nom} cédé à ${acquereur} : échéance ${echStr} — ${phrase}.`;

            if (proprioUid) {
                if (await sendPush(proprioUid, titleProprio, bodyProprio, {animalId: String(a.id)})) sent++;
                try {
                    await supabaseInsert("notifications", [{
                        uid: proprioUid,
                        type: "sterilisation_rappel",
                        title: titleProprio, body: bodyProprio,
                        data: {animalId: String(a.id), palier: palierKey},
                        read: false,
                        ...(proprioProfileId ? {profile_id: proprioProfileId} : {}),
                    }]);
                } catch (e) {
                    console.error(`notifications insert error (steril proprio ${a.id}):`, e.message);
                }
            }

            const pushedElv = await sendPush(
                eleveurUid, titleEleveur, bodyEleveur,
                {animalId: String(a.id), tab: "suivi_cessions"},
            );
            if (pushedElv) sent++;
            try {
                await supabaseInsert("notifications", [{
                    uid: eleveurUid,
                    type: "sterilisation_rappel",
                    title: titleEleveur, body: bodyEleveur,
                    data: {animalId: String(a.id), palier: palierKey, tab: "suivi_cessions"},
                    read: false,
                    ...(eleveurProfileId ? {profile_id: eleveurProfileId} : {}),
                }]);
            } catch (e) {
                console.error(`notifications insert error (steril eleveur ${a.id}):`, e.message);
            }

            // Tâche cochable pour l'éleveur au jour J et en retard.
            if (palierKey === "j0" || overdue) {
                try {
                    await supabaseInsertReturning("taches_elevage", [{
                        uid_eleveur: eleveurUid,
                        titre: `✂️ Stérilisation à vérifier — ${nom}`,
                        date: todayStr,
                        heure: "08:00",
                        notes: `Animal cédé à ${acquereur}. Échéance ${echStr}.`,
                        statut: "a_faire",
                        profil_source: "eleveur",
                        animal_id: a.id,
                        animal_nom: nom,
                        ...(eleveurProfileId ?
                            {profile_id: eleveurProfileId, eleveur_profile_id: eleveurProfileId} : {}),
                    }]);
                } catch (e) {
                    console.error(`taches_elevage insert error (steril ${a.id}):`, e.message);
                }
            }

            await markSent(key);
        }

        console.log(`sendSterilisationReminders: ${sent} notifications envoyées.`);
        return null;
    });

// ─── 2. Anniversaires des chiots cédés ────────────────────────────────────────

/**
 * Trouve ou crée la conversation directe entre deux uid. Réplique
 * lib/utils/messaging_helper.dart (participant_ids trié, participants [a,b]).
 */
async function openOrCreateConversation(uidA, uidB, profA, profB) {
    const sorted = [uidA, uidB].sort().join("_");
    const existing = await supabaseSelect(
        "conversations",
        `participant_ids=eq.${sorted}&or=(type.eq.direct,type.is.null)&select=id&limit=1`,
    );
    if (Array.isArray(existing) && existing[0]) return existing[0].id;

    const nameA = profileName(profA);
    const nameB = profileName(profB);
    const participantsInfo = {
        [uidA]: {name: nameA, ...(profA && profA.avatar_url ? {photo: profA.avatar_url} : {})},
        [uidB]: {name: nameB, ...(profB && profB.avatar_url ? {photo: profB.avatar_url} : {})},
    };
    const created = await supabaseInsertReturning("conversations", [{
        type: "direct",
        participants: [uidA, uidB],
        participant_ids: sorted,
        participants_info: participantsInfo,
        last_message: "",
        unread_count: {[uidA]: 0, [uidB]: 0},
        updated_at: new Date().toISOString(),
    }]);
    return Array.isArray(created) && created[0] ? created[0].id : null;
}

/**
 * Schedulée chaque jour à 9h (Paris).
 * Pour chaque animal cédé (statut 'sorti') dont c'est l'anniversaire :
 *   - notifie l'éleveur (rappel + bouton « envoyer mes vœux » côté app).
 *   - si l'élevage a activé `cession_anniv_auto`, poste automatiquement un
 *     message de vœux dans la conversation avec l'acquéreur.
 * Dédup via notifs_sent (clé annuelle).
 */
exports.sendCessionBirthdayReminders = functions
    .region("europe-west1")
    .pubsub.schedule("0 9 * * *")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        let sent = 0;
        const today = parisNow();
        const mm = String(today.getMonth() + 1).padStart(2, "0");
        const dd = String(today.getDate()).padStart(2, "0");
        const year = today.getFullYear();

        const animaux = await supabaseSelect(
            "animaux",
            "statut=eq.sorti&date_naissance=not.is.null" +
            "&select=id,nom,date_naissance,uid_eleveur,uid_acquereur,destinataire_nom",
        );
        if (!Array.isArray(animaux) || animaux.length === 0) return null;

        for (const a of animaux) {
            const dn = new Date(`${a.date_naissance}T00:00:00`);
            if (isNaN(dn.getTime())) continue;
            const bMM = String(dn.getMonth() + 1).padStart(2, "0");
            const bDD = String(dn.getDate()).padStart(2, "0");
            if (bMM !== mm || bDD !== dd) continue;

            const key = `cession_anniv_${a.id}_${year}`;
            if (await alreadySent(key)) continue;

            const eleveurUid = a.uid_eleveur;
            if (!eleveurUid) continue;
            const nom = a.nom || "un chiot";
            const age = year - dn.getFullYear();
            const acquereur = a.destinataire_nom || "l'acquéreur";

            const eleveurProfile = await mainProfile(eleveurUid);
            const eleveurProfileId = eleveurProfile && eleveurProfile.id ? eleveurProfile.id : null;

            // Rappel à l'éleveur.
            const title = `🎂 Anniversaire de ${nom}`;
            const body = `${nom} a ${age} an${age > 1 ? "s" : ""} aujourd'hui — envoyez vos vœux à ${acquereur}.`;
            if (await sendPush(eleveurUid, title, body, {animalId: String(a.id), tab: "suivi_cessions"})) sent++;
            try {
                await supabaseInsert("notifications", [{
                    uid: eleveurUid,
                    type: "cession_anniversaire",
                    title, body,
                    data: {animalId: String(a.id), tab: "suivi_cessions"},
                    read: false,
                    ...(eleveurProfileId ? {profile_id: eleveurProfileId} : {}),
                }]);
            } catch (e) {
                console.error(`notifications insert error (anniv ${a.id}):`, e.message);
            }

            // Envoi automatique du message si activé.
            const autoOn = eleveurProfile && eleveurProfile.cession_anniv_auto === true;
            if (autoOn && a.uid_acquereur) {
                try {
                    const acqProfile = await mainProfile(a.uid_acquereur);
                    const convId = await openOrCreateConversation(
                        eleveurUid, a.uid_acquereur, eleveurProfile, acqProfile,
                    );
                    if (convId) {
                        const customTexte = eleveurProfile.cession_anniv_texte &&
                            eleveurProfile.cession_anniv_texte.trim();
                        const texte = customTexte ||
                            `Joyeux anniversaire ${nom} ! 🎂 ${profileName(eleveurProfile)} pense à lui aujourd'hui.`;
                        await supabaseInsert("messages", [{
                            conversation_id: convId,
                            sender_id: eleveurUid,
                            text: texte,
                            msg_type: "text",
                            is_read: false,
                        }]);
                        const convRows = await supabaseSelect(
                            "conversations",
                            `id=eq.${convId}&select=participants,unread_count`,
                        );
                        if (Array.isArray(convRows) && convRows[0]) {
                            const members = Array.isArray(convRows[0].participants) ? convRows[0].participants : [];
                            const unread = {...(convRows[0].unread_count || {})};
                            for (const m of members) {
                                if (m !== eleveurUid) unread[m] = (unread[m] || 0) + 1;
                            }
                            await supabasePatch("conversations", `id=eq.${convId}`, {
                                last_message: texte,
                                unread_count: unread,
                                updated_at: new Date().toISOString(),
                            });
                        }
                        const acqProfileId = acqProfile && acqProfile.id ? acqProfile.id : null;
                        await sendPush(
                            a.uid_acquereur, `💬 ${profileName(eleveurProfile)}`, texte,
                            {conversationId: String(convId)},
                        );
                        try {
                            await supabaseInsert("notifications", [{
                                uid: a.uid_acquereur,
                                type: "message",
                                title: `💬 ${profileName(eleveurProfile)}`,
                                body: texte,
                                data: {conversationId: String(convId)},
                                read: false,
                                ...(acqProfileId ? {profile_id: acqProfileId} : {}),
                            }]);
                        } catch (e) {
                            console.error(`notifications insert error (anniv msg ${a.id}):`, e.message);
                        }
                    }
                } catch (e) {
                    console.error(`anniv auto-message error (${a.id}):`, e.message);
                }
            }

            await markSent(key);
        }

        console.log(`sendCessionBirthdayReminders: ${sent} rappels envoyés.`);
        return null;
    });
