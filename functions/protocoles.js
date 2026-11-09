const functions = require("firebase-functions/v1");
const https = require("https");

const {SUPABASE_URL, SUPABASE_AUTH_HEADERS} = require("./config");
const {sendPush} = require("./push_helpers");

// ─── Supabase helpers (même convention que chaleurs.js / agenda.js) ───────────

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
    const res = await supabaseRequest("GET", `${table}?${query}`);
    return Array.isArray(res.body) ? res.body : [];
}

function isoJour(d) {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

/** « Vermifuge — Jour 2/5 », « Nettoyage — Box 1 », « Vermifuge (2e/4e) » → « Vermifuge ». */
function titreTache(t) {
    const brut = (t.label || t.type_acte || "Tâche").toString();
    return brut.split(" — ")[0]
        .replace(/\s*\(\d+e\/\d+e\)\s*$/u, "")
        .replace(/\s*\(mois \d+\/\d+\)\s*$/u, "")
        .trim() || "Tâche";
}

function couper(txt, max) {
    return txt.length > max ? `${txt.slice(0, max - 1)}…` : txt;
}

/**
 * Protocoles du jour — chaque matin à 8 h (Paris), UNE notification par
 * profil : les tâches de protocole du jour (et celles en retard, non cochées,
 * des 14 derniers jours) regroupées par tâche, avec les animaux / logements
 * concernés (« Vermifuge : Nala, Luna »). Au tap, la liste s'ouvre et on
 * choisit l'animal (lib/pages/notifications_page.dart, Header.tsx).
 * La notification de la veille non lue est remplacée : jamais d'empilement.
 * Destinataires : le profil propriétaire de la tâche, et l'employé à qui elle
 * est attribuée.
 */
exports.sendProtocolesDuJour = functions
    .region("europe-west1")
    .runWith({timeoutSeconds: 540, memory: "512MB"})
    .pubsub.schedule("0 8 * * *")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        const now = new Date(new Date().toLocaleString("en-US", {timeZone: "Europe/Paris"}));
        const today = isoJour(now);
        const debut = new Date(now);
        debut.setDate(debut.getDate() - 14);

        const taches = await supabaseSelect("plan_taches",
            "select=id,label,type_acte,etape_id,date_prevue,animal_id,animal_nom,lieu,uid_eleveur," +
            "eleveur_profile_id,profile_id,assigned_to,assigned_profile_id,profil_source" +
            "&statut=in.(en_attente,reporte)" +
            `&date_prevue=lte.${today}&date_prevue=gte.${isoJour(debut)}` +
            "&order=date_prevue.asc&limit=20000");
        if (!taches.length) {
            console.log("sendProtocolesDuJour: aucune tâche.");
            return null;
        }

        // Animaux des tâches : portée (un groupe par portée) et présence (un
        // petit cédé, adopté, sorti ou décédé n'est plus dans la notification).
        const HORS = ["sorti", "adopte", "transfere", "decede"];
        const ids = [...new Set(taches.map((t) => t.animal_id).filter(Boolean).map(String))];
        const animaux = new Map();
        const proprietes = new Map();
        for (let i = 0; i < ids.length; i += 150) {
            const lot = ids.slice(i, i + 150).map(encodeURIComponent).join(",");
            for (const a of await supabaseSelect("animaux", `select=id,statut,portee_id,nom_mere&id=in.(${lot})`)) {
                animaux.set(String(a.id), a);
            }
            for (const p of await supabaseSelect("animaux_proprietes",
                `select=animal_id,uid_proprio,date_fin&animal_id=in.(${lot})`)) {
                const k = String(p.animal_id);
                if (!proprietes.has(k)) proprietes.set(k, []);
                proprietes.get(k).push(p);
            }
        }
        const present = (t) => {
            if (!t.animal_id) return true;
            const a = animaux.get(String(t.animal_id));
            if (!a || HORS.includes(a.statut || "")) return false;
            const lignes = proprietes.get(String(t.animal_id)) || [];
            return !lignes.length || lignes.some((p) => p.uid_proprio === t.uid_eleveur && !p.date_fin);
        };

        // Destinataire (uid + profil) → tâches regroupées par titre (et par portée).
        const dest = new Map();
        const ajouter = (uid, profileId, t) => {
            if (!uid) return;
            const k = `${uid}|${profileId || ""}`;
            if (!dest.has(k)) {
                dest.set(k, {uid, profileId: profileId || null,
                    source: t.profil_source || "eleveur", groupes: new Map()});
            }
            const d = dest.get(k);
            const retard = t.date_prevue < today;
            const a = t.animal_id ? animaux.get(String(t.animal_id)) : null;
            const portee = a && a.portee_id ? (a.nom_mere ? `Portée de ${a.nom_mere}` : "Portée") : null;
            const titre = portee ? `${titreTache(t)} — ${portee}` : titreTache(t);
            const gk = `${titre}|${retard ? "r" : "j"}`;
            if (!d.groupes.has(gk)) d.groupes.set(gk, {titre, retard, items: [], vus: new Set()});
            const g = d.groupes.get(gk);
            // Un animal (ou un logement) une seule fois par tâche.
            const ik = t.animal_id ? `a${t.animal_id}` : `l${t.lieu || ""}`;
            if (g.vus.has(ik)) return;
            g.vus.add(ik);
            g.items.push(t.animal_id ?
                {animalId: String(t.animal_id), nom: t.animal_nom || "Animal"} :
                {nom: t.lieu || "Locaux"});
        };
        for (const t of taches) {
            if (!present(t)) continue;
            const pid = t.eleveur_profile_id || t.profile_id || null;
            ajouter(t.uid_eleveur, pid, t);
            if (t.assigned_to && t.assigned_to !== t.uid_eleveur) ajouter(t.assigned_to, t.assigned_profile_id, t);
        }

        let envoyes = 0;
        for (const d of dest.values()) {
            const groupes = [...d.groupes.values()].sort((a, b) => Number(a.retard) - Number(b.retard));
            const duJour = groupes.filter((g) => !g.retard);
            const enRetard = groupes.filter((g) => g.retard);
            const nbJour = duJour.reduce((n, g) => n + g.items.length, 0);
            const nbRetard = enRetard.reduce((n, g) => n + g.items.length, 0);
            const ligne = (g) => `${g.titre} : ${g.items.map((i) => i.nom).join(", ")}`;

            const title = nbJour ?
                `Protocoles du jour : ${duJour.length} tâche${duJour.length > 1 ? "s" : ""}` :
                `Protocoles : ${enRetard.length} tâche${enRetard.length > 1 ? "s" : ""} en retard`;
            let body = duJour.map(ligne).join(" · ");
            if (nbRetard) body = body ? `${body} · ${nbRetard} en retard` : enRetard.map(ligne).join(" · ");
            body = couper(body, 220);

            const data = {
                date: today,
                profil_source: d.source,
                sections: groupes.map((g) => ({
                    titre: g.retard ? `${g.titre} (en retard)` : g.titre,
                    items: g.items,
                })),
            };

            // Notification de la veille (non lue) remplacée : une seule à la fois.
            try {
                let del = `notifications?uid=eq.${encodeURIComponent(d.uid)}&type=eq.protocoles_jour&read=eq.false`;
                del += d.profileId ? `&profile_id=eq.${encodeURIComponent(d.profileId)}` : "&profile_id=is.null";
                await supabaseRequest("DELETE", del);
                await supabaseRequest("POST", "notifications", [{
                    uid: d.uid, type: "protocoles_jour", title, body, data, read: false,
                    ...(d.profileId ? {profile_id: d.profileId} : {}),
                }]);
            } catch (e) {
                console.error(`protocoles_jour notif ${d.uid}:`, e.message);
            }
            const ok = await sendPush(d.uid, title, body, {type: "protocoles_jour"},
                {profileId: d.profileId, tag: `protocoles_jour_${d.profileId || d.uid}`.slice(0, 60)});
            if (ok) envoyes++;
        }
        console.log(`sendProtocolesDuJour: ${dest.size} destinataires, ${envoyes} push.`);
        return null;
    });
