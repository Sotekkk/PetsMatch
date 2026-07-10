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

        await admin.messaging().send({
            token,
            notification: {title, body},
            data: {type: "sante", ...data},
            android: {
                priority: "high",
                notification: {channelId: "high_importance_channel", sound: "default"},
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
        return null;
    });
