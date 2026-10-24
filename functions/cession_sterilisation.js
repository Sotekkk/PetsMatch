const functions = require("firebase-functions/v1");
const https = require("https");

const {SUPABASE_URL, SUPABASE_AUTH_HEADERS} = require("./config");

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
                ...SUPABASE_AUTH_HEADERS,
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

// ─── FCM helper (partagé) ──────────────────────────────────────────────────────

const {sendPush} = require("./push_helpers");

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
    {key: "j14", days: 14, phrase: "dans 2 semaines"},
    {key: "j7", days: 7, phrase: "dans 1 semaine"},
    {key: "j2", days: 2, phrase: "dans 48 h"},
    {key: "j0", days: 0, phrase: "aujourd'hui"},
];

/**
 * Schedulée chaque jour à 8h (Paris).
 * Pour chaque animal cédé avec `sterilisation_requise=true` et non validée,
 * mêmes paliers par rapport à `sterilisation_echeance` — J-30, J-14, J-7,
 * J-2, Jour J, puis chaque jour tant que l'échéance est dépassée :
 *   - si la stérilisation a été DÉCLARÉE (animaux.sterilise=true) mais pas
 *     encore validée : rappel à l'éleveur seul (« à valider »).
 *   - sinon : rappel au propriétaire (automatique s'il utilise l'appli,
 *     uid résolu via uid_acquereur ou animaux_proprietes) ET à l'éleveur.
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

            // Fenêtre de rappel commune (déclarée ou non) : J-30/J-14/J-7/J-2,
            // puis chaque jour à partir de l'échéance tant que ce n'est pas
            // validé. Sans ce filtre, une stérilisation déclarée très en
            // avance sur l'échéance déclenchait un rappel "à valider" tous
            // les jours dès la déclaration — bien trop tôt.
            const ech = a.sterilisation_echeance ? new Date(`${a.sterilisation_echeance}T00:00:00`) : null;
            if (!ech || isNaN(ech.getTime())) continue;
            const diffDays = Math.round((ech - today) / 86400000);
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
                continue; // hors fenêtre de rappel ce jour
            }

            // Cession jamais aboutie (révoquée, ou pas encore signée) : l'éleveur
            // est toujours le propriétaire principal → aucun rappel. Avant : une
            // cession révoquée laissait uid_acquereur + sterilisation_requise et
            // les deux comptes recevaient « stérilisation en retard » chaque jour.
            const principal = await supabaseSelect(
                "animaux_proprietes",
                `animal_id=eq.${a.id}&date_fin=is.null&role_proprio=eq.principal&select=uid_proprio&limit=1`,
            );
            if (Array.isArray(principal) && principal[0] && principal[0].uid_proprio === eleveurUid) continue;

            // Propriétaire courant : uid_acquereur sinon animaux_proprietes.
            // Automatique dès lors qu'il utilise l'appli (uid résolu) — mêmes
            // paliers que l'éleveur, cf. notifications ci-dessous.
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

            const acquereur = a.destinataire_nom || "l'acquéreur";

            // ── Stérilisation déclarée, pas encore validée → l'éleveur valide,
            // sur la même cadence que le rappel d'échéance ci-dessous.
            if (a.sterilise === true) {
                const key = `steril_valider_${a.id}_${palierKey}`;
                if (await alreadySent(key)) continue;
                const title = overdue ?
                    `⚠️ À valider — ${nom} (en retard)` :
                    `✂️ À valider — ${nom}`;
                const body = `Le propriétaire de ${nom} a déclaré la stérilisation ` +
                    `(échéance ${echStr}, ${phrase}). Validez-la dans le suivi des cessions.`;
                if (await sendPush(eleveurUid, title, body,
                    {type: "sterilisation_a_valider", animalId: String(a.id), tab: "suivi_cessions"},
                    {profileId: eleveurProfileId})) sent++;
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

            // ── Rappels d'échéance (pas encore déclarée) — propriétaire + éleveur.
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
                if (await sendPush(proprioUid, titleProprio, bodyProprio,
                    {type: "sterilisation_rappel", animalId: String(a.id)},
                    {profileId: proprioProfileId})) sent++;
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
                {type: "sterilisation_rappel", animalId: String(a.id), tab: "suivi_cessions"},
                {profileId: eleveurProfileId},
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
            if (await sendPush(eleveurUid, title, body,
                {type: "cession_anniversaire", animalId: String(a.id), tab: "suivi_cessions"},
                {profileId: eleveurProfileId})) sent++;
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
                            {type: "message", conversationId: String(convId)},
                            {profileId: acqProfileId},
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

/**
 * Schedulée chaque jour à 9h (Paris).
 * « 🎂 Joyeux anniversaire <nom> ! » aux propriétaires PARTICULIERS d'un
 * animal vivant dont c'est l'anniversaire (date de naissance connue — pas
 * une date estimée). Propriétaires = animaux_proprietes actifs (principal et
 * co-propriétaires), notif rattachée à leur profil particulier.
 * Dédup via notifs_sent (clé annuelle par animal et par propriétaire).
 */
exports.sendAnimalBirthdayParticulier = functions
    .region("europe-west1")
    .pubsub.schedule("0 9 * * *")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        let sent = 0;
        const today = parisNow();
        const mm = String(today.getMonth() + 1).padStart(2, "0");
        const dd = String(today.getDate()).padStart(2, "0");
        const year = today.getFullYear();

        // Propriétés actives rattachées à un profil particulier.
        const proprietes = await supabaseSelect(
            "animaux_proprietes",
            "date_fin=is.null&statut=eq.actif&select=animal_id,uid_proprio,profile_id_proprio",
        );
        if (!proprietes.length) return null;
        const profileIds = [...new Set(proprietes.map((p) => p.profile_id_proprio).filter(Boolean))];
        const particuliers = new Set();
        for (let i = 0; i < profileIds.length; i += 100) {
            const rows = await supabaseSelect("user_profiles",
                `id=in.(${profileIds.slice(i, i + 100).join(",")})&profile_type=eq.particulier&select=id`);
            rows.forEach((r) => particuliers.add(r.id));
        }
        const props = proprietes.filter((p) => particuliers.has(p.profile_id_proprio));
        if (!props.length) return null;

        // Animaux concernés dont c'est l'anniversaire aujourd'hui.
        const animalIds = [...new Set(props.map((p) => p.animal_id))];
        const anniv = new Map();
        for (let i = 0; i < animalIds.length; i += 100) {
            const ids = animalIds.slice(i, i + 100).map((id) => `"${id}"`).join(",");
            const rows = await supabaseSelect("animaux",
                `id=in.(${encodeURIComponent(ids)})&date_naissance=not.is.null` +
                "&select=id,nom,date_naissance,age_estime,statut");
            for (const a of rows) {
                if (a.age_estime === true || a.statut === "decede") continue;
                const dn = new Date(`${a.date_naissance}T00:00:00`);
                if (isNaN(dn.getTime())) continue;
                if (String(dn.getMonth() + 1).padStart(2, "0") !== mm ||
                    String(dn.getDate()).padStart(2, "0") !== dd) continue;
                const age = year - dn.getFullYear();
                if (age < 1) continue;
                anniv.set(String(a.id), {nom: a.nom || "votre compagnon", age});
            }
        }

        for (const p of props) {
            const a = anniv.get(String(p.animal_id));
            if (!a) continue;
            const key = `anniv_animal_${p.animal_id}_${p.uid_proprio}_${year}`;
            if (await alreadySent(key)) continue;
            const title = `🎂 Joyeux anniversaire ${a.nom} !`;
            const body = `${a.nom} fête ses ${a.age} an${a.age > 1 ? "s" : ""} aujourd'hui. 🐾`;
            if (await sendPush(p.uid_proprio, title, body,
                {type: "animal_anniversaire", animalId: String(p.animal_id)},
                {profileId: p.profile_id_proprio})) sent++;
            try {
                await supabaseInsert("notifications", [{
                    uid: p.uid_proprio,
                    type: "animal_anniversaire",
                    title, body,
                    data: {animalId: String(p.animal_id)},
                    read: false,
                    profile_id: p.profile_id_proprio,
                }]);
            } catch (e) {
                console.error(`notifications insert error (anniv particulier ${p.animal_id}):`, e.message);
            }
            await markSent(key);
        }

        console.log(`sendAnimalBirthdayParticulier: ${sent} vœux envoyés.`);
        return null;
    });

/**
 * Supprime un fichier du stockage à partir de son URL Supabase (publique ou
 * signée). Sans effet si l'URL n'est pas un fichier de ce projet.
 * @param {string} url - URL du fichier.
 * @return {Promise<void>}
 */
function supprimerFichierStockage(url) {
    const m = String(url || "").match(/\/storage\/v1\/object\/(?:public|sign|authenticated)\/([^/]+)\/([^?]+)/);
    if (!m || !String(url).startsWith(SUPABASE_URL)) return Promise.resolve();
    const body = JSON.stringify({prefixes: [decodeURIComponent(m[2])]});
    const u = new URL(`${SUPABASE_URL}/storage/v1/object/${m[1]}`);
    return new Promise((resolve) => {
        const req = https.request({
            hostname: u.hostname, path: u.pathname, method: "DELETE",
            headers: {"Content-Type": "application/json", ...SUPABASE_AUTH_HEADERS,
                "Content-Length": Buffer.byteLength(body)},
        }, (res) => {
            res.resume(); res.on("end", resolve);
        });
        req.on("error", () => resolve());
        req.write(body);
        req.end();
    });
}

/**
 * Documents de la fiche animal (animaux.documents, JSONB) avec une date
 * d'expiration : retirés AUTOMATIQUEMENT de la fiche le jour de l'expiration
 * (fichier supprimé du stockage, rappel d'agenda supprimé). Le(s)
 * propriétaire(s) sont prévenus à J-30, J-7 et la veille, puis du retrait.
 * Destinataires : propriétaires actifs (animaux_proprietes : principal et
 * co-propriétaires), chacun sur SON profil ; à défaut le propriétaire de la
 * fiche (uid_proprietaire / uid_eleveur, profil de l'animal).
 */
exports.sendDocumentExpiryReminders = functions
    .region("europe-west1")
    .pubsub.schedule("30 8 * * *")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        let sent = 0;
        let retires = 0;
        const today = parisNow();
        today.setHours(0, 0, 0, 0);
        const todayStr = ymd(today);

        const animaux = [];
        for (let offset = 0; ; offset += 1000) {
            const rows = await supabaseSelect("animaux",
                "documents=not.is.null&statut=neq.decede" +
                "&select=id,nom,documents,uid_proprietaire,uid_eleveur,profile_id" +
                `&order=id&limit=1000&offset=${offset}`);
            animaux.push(...rows);
            if (rows.length < 1000) break;
        }

        for (const a of animaux) {
            const docs = Array.isArray(a.documents) ? a.documents : [];
            const aPrevenir = []; // {doc, phrase, retire}
            const restants = [];
            for (const d of docs) {
                const exp = d && d.date_expiration ?
                    new Date(`${String(d.date_expiration).slice(0, 10)}T00:00:00`) : null;
                if (!exp || isNaN(exp.getTime())) {
                    restants.push(d);
                    continue;
                }
                const jours = Math.round((exp - today) / 86400000);
                const le = exp.toLocaleDateString("fr-FR");
                if (jours <= 0) {
                    aPrevenir.push({doc: d, retire: true,
                        phrase: `a expiré le ${le} : il a été retiré de la fiche.`});
                    continue; // retiré
                }
                restants.push(d);
                if (jours === 30 || jours === 7 || jours === 1) {
                    aPrevenir.push({doc: d, retire: false,
                        phrase: `expire le ${le} : il sera retiré automatiquement de la fiche ce jour-là.` +
                            " Pensez à ajouter le nouveau."});
                }
            }
            if (!aPrevenir.length) continue;

            // Retrait des documents expirés (fiche, fichier, rappel d'agenda).
            if (restants.length !== docs.length) {
                const st = await supabasePatch("animaux", `id=eq.${encodeURIComponent(a.id)}`, {documents: restants});
                if (st >= 200 && st < 300) {
                    for (const x of aPrevenir.filter((p) => p.retire)) {
                        retires++;
                        await supprimerFichierStockage(x.doc.url);
                        try {
                            await supabaseRequest("DELETE",
                                `agenda_events?animal_id=eq.${encodeURIComponent(a.id)}` +
                                `&titre=eq.${encodeURIComponent(`Document à renouveler : ${x.doc.nom || ""}`)}`);
                        } catch (_) {
                            // rappel d'agenda déjà absent
                        }
                    }
                } else {
                    console.error(`sendDocumentExpiryReminders: retrait impossible (${a.id}) HTTP ${st}`);
                    continue;
                }
            }

            let dest = await supabaseSelect("animaux_proprietes",
                `animal_id=eq.${encodeURIComponent(a.id)}&date_fin=is.null` +
                "&select=uid_proprio,profile_id_proprio,statut");
            dest = dest.filter((p) => p.uid_proprio && (!p.statut || p.statut === "actif"))
                .map((p) => ({uid: p.uid_proprio, profileId: p.profile_id_proprio || null}));
            if (!dest.length) {
                const uid = a.uid_proprietaire || a.uid_eleveur;
                if (uid) dest = [{uid, profileId: a.profile_id || null}];
            }

            const nomAnimal = a.nom || "votre animal";
            for (const x of aPrevenir) {
                const nomDoc = x.doc.nom || "Un document";
                const title = x.retire ? `Document retiré — ${nomAnimal}` : `Document bientôt retiré — ${nomAnimal}`;
                const body = `« ${nomDoc} » ${x.phrase}`;
                for (const p of dest) {
                    const key = `doc_exp_${a.id}_${nomDoc}_${x.doc.date_expiration}_${p.uid}_${todayStr}`.slice(0, 250);
                    if (await alreadySent(key)) continue;
                    if (await sendPush(p.uid, title, body,
                        {type: "document_expiration", animalId: String(a.id)},
                        {profileId: p.profileId})) sent++;
                    try {
                        await supabaseInsert("notifications", [{
                            uid: p.uid, type: "document_expiration", title, body, read: false,
                            data: {animalId: String(a.id), document: nomDoc,
                                date_expiration: x.doc.date_expiration, retire: x.retire},
                            ...(p.profileId ? {profile_id: p.profileId} : {}),
                        }]);
                    } catch (e) {
                        console.error(`notifications insert error (document ${a.id}):`, e.message);
                    }
                    await markSent(key);
                }
            }
        }
        console.log(`sendDocumentExpiryReminders: ${sent} notifications, ${retires} documents retirés.`);
        return null;
    });
