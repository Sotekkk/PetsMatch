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
    const res = await supabaseRequest("GET", `${table}?${query}&select=*`);
    return Array.isArray(res.body) ? res.body : [];
}

async function supabaseInsert(table, rows) {
    const res = await supabaseRequest("POST", table, rows, {"Prefer": "return=minimal"});
    if (res.status < 200 || res.status >= 300) {
        throw new Error(`Supabase insert ${table}: HTTP ${res.status} — ${JSON.stringify(res.body)}`);
    }
    return res.status;
}

// ─── FCM helper (partagé — préfixe le profil concerné + bascule au tap) ──────

const {animalPourRappel} = require("./animal_destinataire");
const {employesAbonnes, sendPush} = require("./push_helpers");

// ─── Domaine : chaleurs ───────────────────────────────────────────────────────

// Âge de retraite (années) par espèce — même convention que la fiche animal
// (bannière « Bientôt à la retraite »). Une femelle à/après cet âge n'a plus
// de cycle de chaleurs à suivre.
const AGES_RETRAITE = {
    chien: 7, chat: 8, lapin: 5,
    cheval: 18, ovin: 8, caprin: 8, porcin: 5, ane: 15,
};

// Fenêtre post mise-bas (jours) pendant laquelle le cycle est suspendu —
// même seuil que « lactation récente » utilisé ailleurs dans l'app (< 8 sem).
const JOURS_LACTATION = 56;

function intervalChaleurs(espece) {
    switch ((espece || "").toLowerCase()) {
    case "chien": return 182;
    case "chat": return 21;
    case "lapin": return 14;
    case "ovin": return 17;
    case "caprin": return 21;
    case "porcin": return 21;
    case "cheval": return 21;
    default: return 0;
    }
}

function emojiEspece(espece) {
    switch ((espece || "").toLowerCase()) {
    case "chien": return "🐕";
    case "chat": return "🐈";
    case "cheval": return "🐴";
    case "lapin": return "🐰";
    case "ovin": return "🐑";
    case "caprin": return "🐐";
    case "porcin": return "🐷";
    default: return "🐾";
    }
}

// ─── Fonction principale ──────────────────────────────────────────────────────

/**
 * Schedulée chaque jour à 8h (heure de Paris).
 * Pour chaque femelle éleveuse dont les prochaines chaleurs arrivent dans ≤ 7 jours,
 * envoie un push FCM + notif in-app Supabase — une seule fois par cycle.
 */
exports.sendChaleursNotifications = functions
    .region("europe-west1")
    // Traitement de toute la base en une passe quotidienne : la limite par
    // défaut de 60 s coupait la fonction en plein milieu (timeout du
    // 29/09/2026 → rappels sautés pour une partie des animaux).
    .runWith({timeoutSeconds: 540, memory: "512MB"})
    .pubsub.schedule("0 8 * * *")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        // Utilise l'heure locale Paris pour éviter les décalages UTC minuit
        const now = new Date(new Date().toLocaleString("en-US", {timeZone: "Europe/Paris"}));
        const y = now.getFullYear();
        const mo = String(now.getMonth() + 1).padStart(2, "0");
        const d = String(now.getDate()).padStart(2, "0");
        const todayStr = `${y}-${mo}-${d}`;
        let sent = 0;
        let inApp = 0;
        const empCache = new Map();
        // Un seul rappel par destinataire et par run (regroupé si plusieurs femelles).
        const rappels = new Map();
        // Tâches agenda « chaleurs à vérifier » regroupées par élevage.
        const agenda = new Map();
        const ajouterRappel = (uid, profileId, item) => {
            if (!uid) return;
            const k = `${uid}|${profileId || ""}`;
            if (!rappels.has(k)) rappels.set(k, {uid, profileId: profileId || null, items: []});
            const r = rappels.get(k);
            if (!r.items.some((i) => i.animalId === item.animalId)) r.items.push(item);
        };

        // 1. Fetch all female animals (not departed/deceased, not stérilisées —
        // une femelle stérilisée n'a plus de cycle de chaleurs à suivre)
        const animaux = await supabaseSelect("animaux",
            "sexe=eq.femelle" +
            "&sterilise=eq.false" +
            "&statut=not.in.(sorti,decede,patient_clinique)" +
            "&select=id,nom,race,espece,uid_eleveur,intervalle_chaleurs_jours,date_naissance," +
            "chaleurs_responsable_uid,chaleurs_responsable_profile_id,profile_id," +
            "uid_proprietaire,cree_par_pro_profile_id,client_clinique_id");

        if (!animaux.length) {
            console.log("sendChaleursNotifications: aucune femelle active.");
            return null;
        }

        const femIds = animaux.map((a) => a.id);

        // 2. Fetch last chaleur per animal (sorted desc, one per animal)
        const chaleursRaw = await supabaseSelect("chaleurs",
            `animal_id=in.(${femIds.join(",")})&order=date.desc`);

        // Protocoles chaleur par race (configurés par l'éleveur) — priment sur
        // le défaut par espèce, mais restent en dessous d'un override par animal.
        const eleveurUids = [...new Set(animaux.map((a) => a.uid_eleveur).filter(Boolean))];
        let raceProtocoles = [];
        if (eleveurUids.length) {
            raceProtocoles = await supabaseSelect("protocoles_chaleur_race",
                `uid_eleveur=in.(${eleveurUids.join(",")})`);
        }
        // Correspondance souple (sous-chaîne dans les deux sens) : la race
        // stockée sur l'animal vient souvent du sélecteur officiel (ex.
        // "Spitz Allemand") alors que l'éleveur tape un raccourci dans le
        // protocole (ex. "Spitz") — une correspondance exacte les manquerait.
        function raceIntervalFor(uidEleveur, espece, race) {
            const e = (espece || "").toLowerCase().trim();
            const r = (race || "").toLowerCase().trim();
            if (!r) return null;
            for (const p of raceProtocoles) {
                if (p.uid_eleveur !== uidEleveur) continue;
                if ((p.espece || "").toLowerCase().trim() !== e) continue;
                const pr = (p.race || "").toLowerCase().trim();
                if (pr && (pr.includes(r) || r.includes(pr))) return p.intervalle_jours;
            }
            return null;
        }

        // Résolution du profil propriétaire courant (animaux.profile_id n'est pas fiable —
        // voir migration_fix_animaux_proprietes_unique_constraint.sql)
        const proprietesRaw = await supabaseSelect("animaux_proprietes",
            `animal_id=in.(${femIds.join(",")})&date_fin=is.null`);
        const profileIdByAnimal = {};
        for (const p of proprietesRaw) {
            if (p.profile_id_proprio) profileIdByAnimal[p.animal_id] = p.profile_id_proprio;
        }
        // Sans ligne de propriété : profil de l'élevage de l'animal (sinon la
        // notification, sans profil, s'affiche dans TOUS les profils du compte).
        for (const a of animaux) {
            if (!profileIdByAnimal[a.id] && a.profile_id) profileIdByAnimal[a.id] = a.profile_id;
        }

        const lastChaleur = {};
        for (const c of chaleursRaw) {
            if (!lastChaleur[c.animal_id]) {
                const d = c.date ? new Date(c.date) : null;
                if (d && !isNaN(d.getTime())) lastChaleur[c.animal_id] = d;
            }
        }

        // Dernière mise-bas par animal — cycle suspendu pendant l'allaitement.
        // Gestation confirmée sans mise bas saisie : date estimée (date_prevue,
        // sinon fin de fenêtre) ; future = gestante, cycle suspendu aussi.
        // Miroir appli/site : miseBasDeReference (chaleurs_etat).
        const gestationsRaw = await supabaseSelect("gestations",
            `animal_id=in.(${femIds.join(",")})` +
            "&or=(date_naissance.not.is.null,gestation_confirmee.eq.true)");
        const lastMiseBas = {};
        for (const g of gestationsRaw) {
            const brut = g.date_naissance ||
                (g.gestation_confirmee ? (g.date_prevue || g.date_prevue_fin) : null);
            const d = brut ? new Date(brut) : null;
            if (!d || isNaN(d.getTime())) continue;
            const prev = lastMiseBas[g.animal_id];
            if (!prev || d.getTime() > prev.getTime()) lastMiseBas[g.animal_id] = d;
        }

        // 3. Process each animal
        for (const ligneAnimal of animaux) {
            const animal = animalPourRappel(ligneAnimal);
            if (!animal) continue;
            // Retraite : au-delà de l'âge de reproduction, plus de cycle à suivre.
            const naissance = animal.date_naissance ? new Date(animal.date_naissance) : null;
            const ageRetraite = AGES_RETRAITE[(animal.espece || "").toLowerCase()];
            if (naissance && !isNaN(naissance.getTime()) && ageRetraite) {
                const dateRetraite = new Date(naissance.getTime());
                dateRetraite.setFullYear(dateRetraite.getFullYear() + ageRetraite);
                if (now.getTime() >= dateRetraite.getTime()) continue;
            }

            // Mise-bas récente : cycle suspendu pendant l'allaitement.
            const miseBas = lastMiseBas[animal.id];
            if (miseBas) {
                const joursDepuis = Math.trunc((now.getTime() - miseBas.getTime()) / 86400000);
                if (joursDepuis < JOURS_LACTATION) continue;
            }

            // Une mise-bas postérieure à la dernière chaleur enregistrée
            // redémarre le cycle : sans ça, une femelle qui vient de mettre
            // bas retombe, une fois la lactation passée, sur sa dernière
            // chaleur d'AVANT la gestation, largement dépassée.
            const last = lastChaleur[animal.id];
            const effectiveLast = (miseBas && (!last || miseBas.getTime() > last.getTime())) ?
                miseBas : last;
            if (!effectiveLast) continue;

            const interval = animal.intervalle_chaleurs_jours ||
                raceIntervalFor(animal.uid_eleveur, animal.espece, animal.race) ||
                intervalChaleurs(animal.espece);
            if (!interval) continue;

            const nextHeat = new Date(effectiveLast.getTime() + interval * 86400000);
            const diffMs = nextHeat.getTime() - now.getTime();
            const diff = Math.trunc(diffMs / 86400000);

            // Notify only if within 7 days ahead or overdue (up to 60 days)
            if (diff > 7 || diff < -60) continue;

            const isOverdue = diff <= 0;
            // Avant l'échéance : un seul rappel par cycle (nextHeatKey). Une
            // fois échue/dépassée : un rappel CHAQUE JOUR tant que l'éleveur
            // n'a pas loggé un nouveau cycle (lastChaleur avance alors
            // automatiquement) ou coupé le rappel (notifs_sent
            // chaleur_muted_<animalId>).
            const nextHeatKey = nextHeat.toISOString().slice(0, 10);
            const key = isOverdue ?
                `chaleur_overdue_${animal.id}_${todayStr}` :
                `chaleur_${animal.id}_${nextHeatKey}`;

            if (isOverdue) {
                const muteKey = `chaleur_muted_${animal.id}`;
                const muted = await supabaseSelect("notifs_sent", `key=eq.${encodeURIComponent(muteKey)}`);
                if (muted.length > 0) continue;
            }

            // Check if already sent this cycle / today
            const existing = await supabaseSelect("notifs_sent", `key=eq.${encodeURIComponent(key)}`);
            if (existing.length > 0) continue;

            // Build notification content
            const nom = animal.nom || "Animal";
            const race = animal.race;
            const espece = animal.espece || "";
            const subtitle = [race, espece].filter((s) => s && s.trim()).join(" · ");
            const em = emojiEspece(espece);

            let title; let body;
            if (diff < 0) {
                title = `🌸 Chaleurs probables — ${nom}`;
                body = `${em} ${nom} (${subtitle}) est probablement en chaleurs (${-diff} j de retard).`;
            } else if (diff === 0) {
                title = `🌸 Chaleurs aujourd'hui — ${nom}`;
                body = `${em} ${nom} (${subtitle}) est attendue en chaleurs aujourd'hui.`;
            } else if (diff === 1) {
                title = `🌸 Chaleurs demain — ${nom}`;
                body = `${em} ${nom} (${subtitle}) sera en chaleurs demain.`;
            } else {
                title = `🌸 Chaleurs dans ${diff} jours — ${nom}`;
                body = `${em} ${nom} (${subtitle}) sera en chaleurs dans ${diff} jours.`;
            }

            // Suivi confié à un employé (fiche animale → onglet Chaleurs) :
            // il reçoit les mêmes rappels que le propriétaire, tant que
            // l'attribution est en place. La retirer (colonne remise à null)
            // le coupe dès le run suivant.
            const assigneA = animal.chaleurs_responsable_uid || null;
            const assigneProfileId = animal.chaleurs_responsable_profile_id || null;

            // Regroupement : UNE notification par destinataire et par run
            // (« Chaleurs : Aiko (aujourd'hui) · Vaïna (3 j de retard) »), au
            // tap la liste s'ouvre et on choisit la chienne. Propriétaire,
            // employé à qui le suivi est confié, employés abonnés « Chaleurs ».
            const court = diff < 0 ? `${-diff} j de retard` : diff === 0 ? "aujourd'hui" :
                diff === 1 ? "demain" : `dans ${diff} j`;
            const item = {animalId: String(animal.id), nom, detail: court, title, body};
            ajouterRappel(animal.uid_eleveur, profileIdByAnimal[animal.id] || null, item);
            if (assigneA) ajouterRappel(assigneA, assigneProfileId, item);
            const abonnes = await employesAbonnes({
                eleveurUid: animal.uid_eleveur,
                eleveurProfileId: profileIdByAnimal[animal.id] || null,
                permission: "notif_chaleurs", cache: empCache,
            });
            for (const e of abonnes) {
                if (e.uid !== assigneA) ajouterRappel(e.uid, e.profileId, item);
            }

            // Agenda : UNE tâche par jour et par élevage (« Chaleurs à vérifier :
            // Aiko, Vaïna, Utha »), refaite chaque matin avec les femelles encore
            // concernées — celle de la veille non validée est retirée.
            if (diff <= 0) {
                const pid = profileIdByAnimal[animal.id] || null;
                const k = `${animal.uid_eleveur}|${pid || ""}|${assigneA || ""}`;
                if (!agenda.has(k)) {
                    agenda.set(k, {uid: animal.uid_eleveur, profileId: pid, assigneA, assigneProfileId, animaux: []});
                }
                agenda.get(k).animaux.push({id: animal.id, nom, court});
            }

            // Mark as sent (after push + notif, so a failure here won't block future runs)
            try {
                await supabaseInsert("notifs_sent", [{key, sent_at: now.toISOString()}]);
            } catch (e) {
                console.error(`notifs_sent insert error for ${key}:`, e.message);
            }
        }

        // Tâches de la veille (non validées) retirées, puis celle du jour.
        const vides = new Set();
        for (const g of agenda.values()) {
            const ok = `${g.uid}|${g.profileId || ""}`;
            if (vides.has(ok)) continue;
            vides.add(ok);
            try {
                const titres = encodeURIComponent("(titre.ilike.🌸 Chaleurs*,titre.ilike.Chaleurs à vérifier*)");
                let del = `taches_elevage?uid_eleveur=eq.${encodeURIComponent(g.uid)}&statut=eq.a_faire&or=${titres}`;
                del += g.profileId ? `&eleveur_profile_id=eq.${g.profileId}` : "&eleveur_profile_id=is.null";
                await supabaseRequest("DELETE", del);
            } catch (e) {
                console.error(`taches_elevage chaleurs purge ${g.uid}:`, e.message);
            }
        }
        // Une tâche PAR femelle (clic → son suivi des chaleurs, validée une à
        // une) ; celle de la veille non validée a été retirée juste au-dessus.
        for (const g of agenda.values()) {
            try {
                await supabaseInsert("taches_elevage", g.animaux.map((x) => ({
                    uid_eleveur: g.uid,
                    titre: `Chaleurs à vérifier — ${x.nom}`,
                    date: todayStr,
                    heure: "08:00",
                    notes: `${x.nom} : ${x.court}`,
                    statut: "a_faire",
                    profil_source: "eleveur",
                    animal_nom: x.nom,
                    animal_id: x.id,
                    ...(g.assigneA ? {assigne_a: g.assigneA} : {}),
                    ...(g.assigneProfileId ? {assigne_profile_id: g.assigneProfileId} : {}),
                    ...(g.profileId ? {profile_id: g.profileId, eleveur_profile_id: g.profileId} : {}),
                })));
            } catch (e) {
                console.error(`taches_elevage chaleurs insert ${g.uid}:`, e.message);
            }
        }

        for (const r of rappels.values()) {
            const seul = r.items.length === 1 ? r.items[0] : null;
            const title = seul ? seul.title :
                `Chaleurs à vérifier : ${r.items.length} femelles`;
            // Lisible en entier : les 3 premières, puis « et N autres » ; la liste
            // complète s'ouvre au tap (page « Chaleurs à vérifier »).
            const noms = r.items.map((i) => i.nom);
            let body = seul ? seul.body :
                noms.slice(0, 3).join(", ") +
                (noms.length > 3 ? ` et ${noms.length - 3} autre${noms.length > 4 ? "s" : ""}` : "") +
                " — touchez pour voir chaque femelle.";
            if (body.length > 220) body = `${body.slice(0, 219)}…`;
            const type = seul ? "chaleur" : "chaleurs_groupe";
            const data = seul ? {animalId: seul.animalId} :
                {sections: [{items: r.items.map((i) => ({animalId: i.animalId, nom: i.nom, detail: i.detail}))}]};
            try {
                // Rappel groupé de la veille non lu : remplacé, jamais empilé.
                let del = `notifications?uid=eq.${encodeURIComponent(r.uid)}&type=eq.chaleurs_groupe&read=eq.false`;
                del += r.profileId ? `&profile_id=eq.${encodeURIComponent(r.profileId)}` : "&profile_id=is.null";
                await supabaseRequest("DELETE", del);
                await supabaseInsert("notifications", [{
                    uid: r.uid, type, title, body, data, read: false,
                    ...(r.profileId ? {profile_id: r.profileId} : {}),
                }]);
                inApp++;
            } catch (e) {
                console.error(`notifications insert error ${r.uid}:`, e.message);
            }
            const ok = await sendPush(r.uid, title, body,
                seul ? {type: "chaleur", animalId: seul.animalId} : {type: "chaleurs_groupe"},
                {profileId: r.profileId,
                    tag: seul ? undefined : `chaleurs_groupe_${r.profileId || r.uid}`.slice(0, 60)});
            if (ok) sent++;
        }
        console.log(`sendChaleursNotifications: ${sent} push FCM + ${inApp} notifs in-app.`);
        return null;
    });
