const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const https = require("https");

const SUPABASE_URL = "https://zyvpngcvzrkdytypjlyq.supabase.co";
const SUPABASE_SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" +
    ".eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5dnBuZ2N2enJrZHl0eXBqbHlxIiwi" +
    "cm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTM2NDY1NSwiZXhwIjoyMDk0OT" +
    "QwNjU1fQ.1U96V3c7nHG3T08dboBcxTd05k8A_JQfnyrJTbJ0HgQ";

// ─── Tables avec date_rappel ──────────────────────────────────────────────────

const TABLES = [
    {table: "vaccinations", label: "Vaccin", emoji: "💉", nomField: "vaccin"},
    {table: "vermifuges", label: "Vermifuge", emoji: "💊", nomField: "produit"},
    {table: "antiparasitaires", label: "Antiparasitaire", emoji: "🛡️", nomField: "produit"},
];

// Paliers J-7, J-1, J-0
const PALIERS = [
    {key: "j7", days: 7, phrase: "dans 7 jours"},
    {key: "j1", days: 1, phrase: "demain"},
    {key: "j0", days: 0, phrase: "aujourd'hui"},
];

// ─── Helpers Supabase ─────────────────────────────────────────────────────────

function supabaseGet(path) {
    return new Promise((resolve, reject) => {
        const url = new URL(`${SUPABASE_URL}/rest/v1/${path}`);
        const options = {
            hostname: url.hostname,
            path: url.pathname + url.search,
            method: "GET",
            headers: {
                "Content-Type": "application/json",
                "apikey": SUPABASE_SERVICE_KEY,
                "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
            },
        };
        const req = https.request(options, (res) => {
            let data = "";
            res.on("data", (c) => data += c);
            res.on("end", () => {
                try {
                    resolve(JSON.parse(data));
                } catch (_) {
                    resolve([]);
                }
            });
        });
        req.on("error", reject);
        req.end();
    });
}

async function supabaseInsert(table, rows) {
    return new Promise((resolve, reject) => {
        const bodyStr = JSON.stringify(rows);
        const options = {
            hostname: new URL(SUPABASE_URL).hostname,
            path: `/rest/v1/${table}`,
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "apikey": SUPABASE_SERVICE_KEY,
                "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
                "Prefer": "return=minimal",
                "Content-Length": Buffer.byteLength(bodyStr),
            },
        };
        const req = https.request(options, (res) => {
            let d = "";
            res.on("data", (c) => d += c);
            res.on("end", () => resolve(res.statusCode));
        });
        req.on("error", reject);
        req.write(bodyStr);
        req.end();
    });
}

// ─── FCM helper ───────────────────────────────────────────────────────────────

async function sendPush(uid, title, body, data = {}) {
    try {
        const doc = await admin.firestore().collection("users").doc(uid).get();
        const token = doc.exists ? doc.data().fcmToken : null;
        if (!token) return false;

        // Pas de bloc `notification` top-level ni `android.notification` :
        // sur Android, le système affichait automatiquement CETTE notif en
        // plus de celle affichée manuellement par l'app (onMessage/
        // onBackgroundMessage) — doublon constaté en prod. title/body
        // passent par `data` ; l'app les affiche elle-même sur Android.
        // iOS inchangé (apns.payload.aps.alert), aucun doublon rapporté
        // dessus, et l'app ne réaffiche pas manuellement côté iOS en
        // arrière-plan (voir _firebaseMessagingBackgroundHandler).
        await admin.messaging().send({
            token,
            data: {type: "sante", title, body, ...data},
            android: {
                priority: "high",
            },
            apns: {
                headers: {"apns-priority": "10"},
                payload: {aps: {alert: {title, body}, sound: "default", badge: 1}},
            },
        });
        return true;
    } catch (e) {
        console.error(`sendPush error uid=${uid}:`, e.message);
        return false;
    }
}

// ─── Date helper (heure locale Paris pour éviter les décalages UTC) ───────────

function dateStr(daysFromNow) {
    // Utilise l'heure locale Paris pour que la date soit toujours la bonne
    // même si le Cloud Scheduler tourne à minuit UTC (= 2h Paris en été)
    const paris = new Date(new Date().toLocaleString("en-US", {timeZone: "Europe/Paris"}));
    paris.setDate(paris.getDate() + daysFromNow);
    const y = paris.getFullYear();
    const m = String(paris.getMonth() + 1).padStart(2, "0");
    const d = String(paris.getDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
}

// ─── Fonction principale ──────────────────────────────────────────────────────

/**
 * Schedulée chaque jour à 8h (heure de Paris).
 * Envoie des rappels FCM J-7, J-1 et Jour J pour :
 *   - vaccinations   (date_rappel)
 *   - vermifuges     (date_rappel)
 *   - antiparasitaires (date_rappel)
 * Dédup via la table notifs_sent.
 */
exports.sendSanteReminders = functions
    .region("europe-west1")
    .pubsub.schedule("0 8 * * *")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        let sent = 0;

        for (const {table, label, emoji, nomField} of TABLES) {
            for (const {key: palierKey, days, phrase} of PALIERS) {
                const targetDate = dateStr(days);

                // Récupère les rappels du jour avec les infos de l'animal (éleveur ou particulier)
                const rows = await supabaseGet(
                    `${table}?date_rappel=eq.${targetDate}` +
                    `&select=*,animaux!inner(nom,espece,uid_eleveur,uid_proprietaire)`,
                );
                if (!Array.isArray(rows) || rows.length === 0) continue;

                for (const row of rows) {
                    const animal = row.animaux;
                    const uid = animal?.uid_eleveur || animal?.uid_proprietaire;
                    if (!animal || !uid) continue;
                    const nomAnimal = animal.nom || "Votre animal";
                    const produit = row[nomField] || label;
                    const dedupKey = `sante_${table}_${palierKey}_${row.id}`;

                    // Résolution du profil propriétaire courant (animaux.profile_id n'est pas
                    // fiable — voir migration_fix_animaux_proprietes_unique_constraint.sql)
                    let profileId = null;
                    try {
                        const propRows = await supabaseGet(
                            `animaux_proprietes?animal_id=eq.${row.animal_id}&uid_proprio=eq.${uid}` +
                            `&date_fin=is.null&select=profile_id_proprio&limit=1`,
                        );
                        if (Array.isArray(propRows) && propRows[0]) profileId = propRows[0].profile_id_proprio;
                    } catch (_) {/* pas bloquant */}

                    // Dédup
                    const existing = await supabaseGet(
                        `notifs_sent?key=eq.${encodeURIComponent(dedupKey)}`,
                    );
                    if (Array.isArray(existing) && existing.length > 0) continue;

                    const title = `${emoji} ${label} — ${nomAnimal}`;
                    const body = `Rappel ${phrase} : ${produit} pour ${nomAnimal}.`;

                    const pushed = await sendPush(uid, title, body, {
                        animalId: String(row.animal_id),
                        table,
                    });
                    if (pushed) sent++;

                    // Notification en base
                    try {
                        await supabaseInsert("notifications", [{
                            uid,
                            type: "sante",
                            title,
                            body,
                            data: {animalId: String(row.animal_id), table, palier: palierKey},
                            read: false,
                            ...(profileId ? {profile_id: profileId} : {}),
                        }]);
                    } catch (e) {
                        console.error(`notifications insert error (${table} ${row.id}):`, e.message);
                    }

                    // Tâche agenda à 8h le jour J uniquement
                    if (palierKey === "j0") {
                        try {
                            await supabaseInsert("taches_elevage", [{
                                uid_eleveur: uid,
                                titre: `${emoji} ${label} — ${nomAnimal}`,
                                date: targetDate,
                                heure: "08:00",
                                notes: produit !== label ? produit : null,
                                statut: "a_faire",
                                profil_source: animal.uid_eleveur ? "eleveur" : "particulier",
                                animal_nom: nomAnimal,
                                ...(profileId ? {profile_id: profileId, eleveur_profile_id: profileId} : {}),
                            }]);
                        } catch (e) {
                            console.error(`taches_elevage insert error (${table} ${row.id}):`, e.message);
                        }
                    }

                    // Dédup insert
                    try {
                        await supabaseInsert("notifs_sent", [{
                            key: dedupKey,
                            sent_at: new Date().toISOString(),
                        }]);
                    } catch (e) {
                        console.error(`notifs_sent insert error (${dedupKey}):`, e.message);
                    }
                }
            }
        }

        console.log(`sendSanteReminders: ${sent} notifications envoyées.`);

        const overdueSent = await sendOverdueSanteReminders();
        console.log(`sendOverdueSanteReminders: ${overdueSent} notifications envoyées.`);
        return null;
    });

// ─── Rappels quotidiens pour les retards non résolus ──────────────────────────

/**
 * Appelée à la suite de sendSanteReminders (même run, 8h Paris).
 * Pour vaccinations/vermifuges/antiparasitaires : si le dernier rappel connu
 * d'un animal est dépassé (date_rappel < aujourd'hui), renvoie un rappel
 * CHAQUE JOUR tant que l'éleveur n'a pas :
 *   - loggé un traitement plus récent pour cet animal (date_rappel plus
 *     récente prend le relais automatiquement), ou
 *   - explicitement coupé le rappel depuis l'app/le site (notifs_sent avec
 *     la clé sante_<table>_muted_<id>).
 */
async function sendOverdueSanteReminders() {
    let sent = 0;
    const todayStr = dateStr(0);

    for (const {table, label, nomField} of TABLES) {
        // Pas de filtre date_rappel=lt ici : un vaccin fraîchement refait a un
        // date_rappel dans le FUTUR, donc invisible à ce filtre — sans
        // récupérer aussi les lignes non en retard, on ne peut jamais détecter
        // qu'un enregistrement plus récent a déjà pris le relais de l'ancien.
        const rows = await supabaseGet(
            `${table}?date_rappel=not.is.null` +
            `&select=*,animaux!inner(nom,espece,uid_eleveur,uid_proprietaire)`,
        );
        if (!Array.isArray(rows) || rows.length === 0) continue;

        // Un traitement plus récent déjà loggé pour le même animal annule le
        // retard de l'ancien enregistrement — groupé par (animal, catégorie)
        // pour les vaccins : deux types de vaccin différents (ex: Rage vs
        // CHPPI) ont des échéances indépendantes, un rappel Rage à jour ne
        // doit pas masquer un rappel CHPPI réellement en retard (et
        // inversement le forcer sur un autre type de vaccin non pertinent).
        const latestByGroup = new Map();
        for (const row of rows) {
            const key = table === "vaccinations" ?
                `${row.animal_id}|${row.categorie || row[nomField] || ""}` :
                row.animal_id;
            const prev = latestByGroup.get(key);
            if (!prev || row.date_rappel > prev.date_rappel) latestByGroup.set(key, row);
        }

        for (const row of latestByGroup.values()) {
            // Le dernier enregistrement du groupe n'est plus en retard —
            // rien à signaler pour ce (animal, catégorie).
            if (!(row.date_rappel < todayStr)) continue;
            const animal = row.animaux;
            const uid = animal?.uid_eleveur || animal?.uid_proprietaire;
            if (!animal || !uid) continue;

            const muteKey = `sante_${table}_muted_${row.id}`;
            const muted = await supabaseGet(`notifs_sent?key=eq.${encodeURIComponent(muteKey)}`);
            if (Array.isArray(muted) && muted.length > 0) continue;

            const dedupKey = `sante_${table}_overdue_${row.id}_${todayStr}`;
            const existing = await supabaseGet(`notifs_sent?key=eq.${encodeURIComponent(dedupKey)}`);
            if (Array.isArray(existing) && existing.length > 0) continue;

            const nomAnimal = animal.nom || "Votre animal";
            const produit = row[nomField] || label;
            const joursRetard = Math.round((new Date(todayStr) - new Date(row.date_rappel)) / 86400000);

            let profileId = null;
            try {
                const propRows = await supabaseGet(
                    `animaux_proprietes?animal_id=eq.${row.animal_id}&uid_proprio=eq.${uid}` +
                    `&date_fin=is.null&select=profile_id_proprio&limit=1`,
                );
                if (Array.isArray(propRows) && propRows[0]) profileId = propRows[0].profile_id_proprio;
            } catch (_) {/* pas bloquant */}

            const title = `⚠️ ${label} en retard — ${nomAnimal}`;
            const body = `${produit} pour ${nomAnimal} devait être fait il y a ${joursRetard} ` +
                `jour${joursRetard > 1 ? "s" : ""}.`;

            // Si la tâche d'origine (créée au palier j0) a depuis été
            // attribuée à un employé, le relancer aussi tant qu'elle est en retard.
            let assigneA = null;
            let assigneProfileId = null;
            try {
                const linkedTasks = await supabaseGet(
                    `taches_elevage?uid_eleveur=eq.${uid}&animal_nom=eq.${encodeURIComponent(nomAnimal)}` +
                    `&titre=ilike.${encodeURIComponent(`${label}%`)}&assigne_a=not.is.null` +
                    "&order=date.desc&limit=1&select=assigne_a,assigne_profile_id",
                );
                if (Array.isArray(linkedTasks) && linkedTasks[0]) {
                    assigneA = linkedTasks[0].assigne_a || null;
                    assigneProfileId = linkedTasks[0].assigne_profile_id || null;
                }
            } catch (_) {/* pas bloquant */}

            const pushed = await sendPush(uid, title, body, {
                animalId: String(row.animal_id), table, overdue: true,
            });
            if (pushed) sent++;
            if (assigneA) {
                await sendPush(assigneA, title, body, {animalId: String(row.animal_id), table, overdue: true});
            }

            try {
                await supabaseInsert("notifications", [{
                    uid,
                    type: "sante",
                    title,
                    body,
                    data: {animalId: String(row.animal_id), table, overdue: true, recordId: row.id},
                    read: false,
                    ...(profileId ? {profile_id: profileId} : {}),
                }]);
            } catch (e) {
                console.error(`notifications insert error overdue (${table} ${row.id}):`, e.message);
            }
            if (assigneA) {
                try {
                    await supabaseInsert("notifications", [{
                        uid: assigneA,
                        type: "sante",
                        title,
                        body,
                        data: {animalId: String(row.animal_id), table, overdue: true, recordId: row.id},
                        read: false,
                        ...(assigneProfileId ? {profile_id: assigneProfileId} : {}),
                    }]);
                } catch (e) {
                    console.error(`notifications insert error overdue assignee (${table} ${row.id}):`, e.message);
                }
            }

            try {
                await supabaseInsert("notifs_sent", [{key: dedupKey, sent_at: new Date().toISOString()}]);
            } catch (e) {
                console.error(`notifs_sent insert error (${dedupKey}):`, e.message);
            }
        }
    }

    return sent;
}

// ─── Rappels récurrents de traitement ──────────────────────────────────────────

/**
 * Schedulée toutes les 15 minutes.
 * Envoie un rappel PREAVIS_MIN minutes avant chaque heure programmée
 * (rappel_heures, ex: ["08:00","20:00"]) d'un traitement actif
 * (rappel_actif=true), pour laisser le temps de préparer le soin avant de
 * l'administrer, ET dont le jour courant est un "jour dû" selon
 * rappel_frequence_jours (répétition tous les N jours depuis la date de
 * début), dans la fenêtre [date ; rappel_fin].
 * Dédup via notifs_sent (clé par traitement + date + heure).
 */
const PREAVIS_MIN = 15;
exports.sendTraitementReminders = functions
    .region("europe-west1")
    .pubsub.schedule("*/15 * * * *")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        let sent = 0;
        const paris = new Date(new Date().toLocaleString("en-US", {timeZone: "Europe/Paris"}));
        const todayStr = dateStr(0);
        const bucketStart = paris.getHours() * 60 +
            Math.floor(paris.getMinutes() / 15) * 15;

        const rows = await supabaseGet(
            "traitements?rappel_actif=eq.true" +
            `&date=lte.${todayStr}&rappel_fin=gte.${todayStr}` +
            "&select=*,animaux!inner(nom,espece,uid_eleveur,uid_proprietaire)",
        );
        if (!Array.isArray(rows) || rows.length === 0) return null;

        for (const row of rows) {
            const animal = row.animaux;
            const uid = animal?.uid_eleveur || animal?.uid_proprietaire;
            if (!animal || !uid || !Array.isArray(row.rappel_heures)) continue;

            const debut = new Date(`${row.date}T00:00:00`);
            const today = new Date(`${todayStr}T00:00:00`);
            const joursEcoules = Math.round((today - debut) / 86400000);
            const frequence = row.rappel_frequence_jours || 1;
            if (joursEcoules < 0 || joursEcoules % frequence !== 0) continue;

            const heureDue = row.rappel_heures.find((h) => {
                const [hh, mm] = String(h).split(":").map((v) => parseInt(v, 10));
                if (Number.isNaN(hh) || Number.isNaN(mm)) return false;
                const minutesAvantRappel = hh * 60 + mm - PREAVIS_MIN;
                return minutesAvantRappel >= bucketStart && minutesAvantRappel < bucketStart + 15;
            });
            if (!heureDue) continue;

            const nomAnimal = animal.nom || "Votre animal";
            const dedupKey = `traitement_${row.id}_${todayStr}_${heureDue}`;
            const existing = await supabaseGet(
                `notifs_sent?key=eq.${encodeURIComponent(dedupKey)}`,
            );
            if (Array.isArray(existing) && existing.length > 0) continue;

            let profileId = null;
            try {
                const propRows = await supabaseGet(
                    `animaux_proprietes?animal_id=eq.${row.animal_id}&uid_proprio=eq.${uid}` +
                    "&date_fin=is.null&select=profile_id_proprio&limit=1",
                );
                if (Array.isArray(propRows) && propRows[0]) profileId = propRows[0].profile_id_proprio;
            } catch (_) {/* pas bloquant */}

            const title = `💊 Dans ${PREAVIS_MIN} min — ${nomAnimal}`;
            const body = `${row.nom || "Traitement"} à ${heureDue} pour ${nomAnimal}` +
                (row.posologie ? ` — ${row.posologie}` : "");

            const pushed = await sendPush(uid, title, body, {
                animalId: String(row.animal_id),
                table: "traitements",
            });
            if (pushed) sent++;

            try {
                await supabaseInsert("notifications", [{
                    uid,
                    type: "sante",
                    title,
                    body,
                    data: {animalId: String(row.animal_id), table: "traitements", heure: heureDue},
                    read: false,
                    ...(profileId ? {profile_id: profileId} : {}),
                }]);
            } catch (e) {
                console.error(`notifications insert error (traitement ${row.id}):`, e.message);
            }

            // Tâche agenda cochable — sans elle, le rappel n'était qu'un push
            // qui disparaissait sans laisser de trace validable/visible.
            try {
                await supabaseInsert("taches_elevage", [{
                    uid_eleveur: uid,
                    titre: `💊 ${row.nom || "Traitement"} — ${nomAnimal}`,
                    date: todayStr,
                    heure: heureDue,
                    notes: row.posologie || null,
                    statut: "a_faire",
                    profil_source: animal.uid_eleveur ? "eleveur" : "particulier",
                    animal_nom: nomAnimal,
                    ...(profileId ? {profile_id: profileId, eleveur_profile_id: profileId} : {}),
                }]);
            } catch (e) {
                console.error(`taches_elevage insert error (traitement ${row.id}):`, e.message);
            }

            try {
                await supabaseInsert("notifs_sent", [{
                    key: dedupKey,
                    sent_at: new Date().toISOString(),
                }]);
            } catch (e) {
                console.error(`notifs_sent insert error (${dedupKey}):`, e.message);
            }
        }

        console.log(`sendTraitementReminders: ${sent} notifications envoyées.`);
        return null;
    });

// ─── Rappels de stock bas (inventaire) ─────────────────────────────────────────

/**
 * Schedulée quotidiennement à 8h (heure de Paris).
 * Renvoie un rappel CHAQUE JOUR pour tout article dont le stock est toujours
 * sous son seuil d'alerte, tant que l'éleveur n'a pas réapprovisionné (la
 * quantité repasse au-dessus du seuil) ou désactivé l'alerte pour cet
 * article (inventaire_items.alerte_active=false, réglable depuis la fiche
 * article — c'est le mécanisme d'annulation manuel).
 * Dédup via notifs_sent (clé par article + date).
 */
exports.sendInventaireReminders = functions
    .region("europe-west1")
    .pubsub.schedule("0 8 * * *")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        let sent = 0;
        const todayStr = dateStr(0);

        const items = await supabaseGet("inventaire_items?alerte_active=eq.true");
        if (!Array.isArray(items) || items.length === 0) return null;

        for (const item of items) {
            const seuil = item.quantite_alerte;
            if (seuil == null || Number(item.quantite) > Number(seuil)) continue;
            if (!item.uid_eleveur) continue;

            const dedupKey = `inventaire_overdue_${item.id}_${todayStr}`;
            const existing = await supabaseGet(`notifs_sent?key=eq.${encodeURIComponent(dedupKey)}`);
            if (Array.isArray(existing) && existing.length > 0) continue;

            const title = `⚠️ Stock bas : ${item.nom}`;
            const body = `Il ne reste que ${item.quantite} ${item.unite || ""} de ${item.nom}. ` +
                "Pensez à commander.";

            const pushed = await sendPush(item.uid_eleveur, title, body, {
                itemId: String(item.id), table: "inventaire_items",
            });
            if (pushed) sent++;

            try {
                await supabaseInsert("notifications", [{
                    uid: item.uid_eleveur,
                    type: "inventaire_alerte",
                    title,
                    body,
                    data: {itemId: item.id},
                    read: false,
                    ...(item.eleveur_profile_id ? {profile_id: item.eleveur_profile_id} : {}),
                }]);
            } catch (e) {
                console.error(`notifications insert error (inventaire ${item.id}):`, e.message);
            }

            try {
                await supabaseInsert("notifs_sent", [{key: dedupKey, sent_at: new Date().toISOString()}]);
            } catch (e) {
                console.error(`notifs_sent insert error (${dedupKey}):`, e.message);
            }
        }

        console.log(`sendInventaireReminders: ${sent} notifications envoyées.`);
        return null;
    });
