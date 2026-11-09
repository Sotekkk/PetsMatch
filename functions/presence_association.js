const functions = require("firebase-functions/v1");
const https = require("https");

const {SUPABASE_URL, SUPABASE_AUTH_HEADERS} = require("./config");

// ─── Supabase helpers (même convention que chaleurs.js / protocoles.js) ───────

function supabaseRequest(method, path, body, prefer) {
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
                ...(method === "GET" ? {} : {"Prefer": prefer || "return=minimal"}),
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

const HORS = ["sorti", "adopte", "transfere", "decede"];
const TRANCHES = {matin: "Matin", midi: "Midi", apres_midi: "Après-midi", soir: "Soir"};
// Libellés des actions codées (miroir ACTES_SUGGERES*, lib/protocoles.ts).
const ACTES = {
    vermifuge: "Vermifuge", vaccination: "Vaccination", antiparasitaire: "Antiparasitaire",
    traitement: "Traitement", visite: "Visite vétérinaire", alimentaire: "Alimentaire",
    toilettage: "Toilettage", nettoyage: "Désinfection", promenade: "Promenade / Socialisation",
    repas: "Repas", eau: "Eau fraîche", litiere: "Nettoyage de la litière", jeux: "Jeux / câlins",
    brossage: "Brossage", medicament: "Donner le traitement",
};

function norm(s) {
    return (s || "").toString().toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").trim();
}

/** Espèce de l'animal (« Chien », « chiens »…) parmi les espèces cochées (clés). */
function especeOk(cibles, espece) {
    if (!cibles || !cibles.length) return true;
    const e = norm(espece);
    if (!e) return true;
    return cibles.some((c) => {
        const k = norm(c);
        return e === k || e.startsWith(k) || k.startsWith(e);
    });
}

function tranchesDe(v) {
    return (v || "").toString().split(",").map((x) => x.trim()).filter(Boolean);
}

/**
 * Association — protocoles « Présence au refuge (automatique) »
 * (plan_templates.reference_event = 'sejour', profil_source = 'association').
 * Chaque matin à 5 h (Paris, avant le récapitulatif de 8 h) : les tâches du
 * jour sont créées pour les animaux présents dans un enclos (périmètre animal)
 * ou une par enclos occupé (périmètre locaux), selon le ciblage du protocole
 * (pension_cible : espèces, races, enclos / types, individuels / partagés).
 * Étapes : « chaque jour », ou « jour de l'entrée + n » (animaux.date_entree).
 * Un animal sorti, adopté, transféré, décédé ou sans enclos n'en reçoit plus.
 * Une tâche par créneau coché (matin, soir…). Jamais de doublon.
 * Miroir pension : lib/pension-protocoles.ts (appliqué à l'arrivée).
 */
exports.genererTachesPresenceAssociation = functions
    .region("europe-west1")
    .runWith({timeoutSeconds: 540, memory: "512MB"})
    .pubsub.schedule("0 5 * * *")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        const now = new Date(new Date().toLocaleString("en-US", {timeZone: "Europe/Paris"}));
        const today = isoJour(now);
        const templates = await supabaseSelect("plan_templates",
            "select=*,plan_template_etapes(*)&reference_event=eq.sejour&profil_source=eq.association");
        let total = 0;
        const animauxParUid = new Map();
        const enclosParUid = new Map();

        for (const tp of templates) {
            const etapes = Array.isArray(tp.plan_template_etapes) ? tp.plan_template_etapes : [];
            if (!etapes.length || !tp.uid_eleveur) continue;
            const uid = tp.uid_eleveur;
            const pid = tp.eleveur_profile_id || null;
            const cible = tp.pension_cible || {};
            const locaux = tp.cible_type === "locaux";

            if (!animauxParUid.has(uid)) {
                animauxParUid.set(uid, await supabaseSelect("animaux",
                    `select=id,nom,espece,race,enclos_id,date_entree,profile_id,is_association,statut` +
                    `&uid_eleveur=eq.${encodeURIComponent(uid)}&enclos_id=not.is.null`));
            }
            if (!enclosParUid.has(uid)) {
                const lgs = await supabaseSelect("enclos_chenil",
                    `select=id,nom,type,capacite,profile_id,is_association&uid_eleveur=eq.${encodeURIComponent(uid)}`);
                enclosParUid.set(uid, new Map(lgs.map((l) => [String(l.id), l])));
            }
            const enclos = enclosParUid.get(uid);
            // Animaux présents de CE profil (anciens sans profil : ceux de l'association).
            const presents = animauxParUid.get(uid).filter((a) =>
                !HORS.includes(a.statut || "") &&
                (a.profile_id ? (!pid || a.profile_id === pid) : a.is_association === true));

            const races = (cible.races || []).map(norm);
            const ids = (cible.logement_ids || []).map(String);
            const types = (cible.logement_types || []).map(String);
            const concernes = presents.filter((a) => {
                const l = enclos.get(String(a.enclos_id));
                if (!l) return false;
                if (!especeOk(cible.especes, a.espece)) return false;
                if (!locaux && tp.espece && !especeOk([tp.espece], a.espece)) return false;
                if (races.length && !races.includes(norm(a.race))) return false;
                if (ids.length && !ids.includes(String(l.id))) return false;
                if (types.length && !types.includes(String(l.type || ""))) return false;
                const places = Number(l.capacite) || 1;
                if (cible.places === "individuel" && places > 1) return false;
                if (cible.places === "partage" && places <= 1) return false;
                return true;
            });
            if (!concernes.length) continue;

            const entreeIlYa = (a) => {
                if (!a.date_entree) return null;
                const d = new Date(`${String(a.date_entree).slice(0, 10)}T12:00:00`);
                return Math.round((new Date(`${today}T12:00:00`) - d) / 86400000);
            };

            const taches = [];
            for (const et of etapes) {
                const moment = et.sejour_moment || "chaque_jour";
                if (moment === "depart") continue; // sortie inconnue à l'avance
                const off = Number(et.jour_offset) || 0;
                const duJour = (a) => moment === "chaque_jour" || entreeIlYa(a) === off;
                const acte = ACTES[et.type_acte] || et.type_acte || et.description || "Tâche";
                const base = [acte, et.produit, et.dosage ? `(${et.dosage})` : ""].filter(Boolean).join(" ");
                const cibles = locaux ?
                    // Une tâche par enclos occupé (un occupant concerné aujourd'hui suffit).
                    [...new Map(concernes.filter(duJour)
                        .map((a) => [String(a.enclos_id), {enclos: enclos.get(String(a.enclos_id))}])).values()] :
                    concernes.filter(duJour).map((a) => ({animal: a, enclos: enclos.get(String(a.enclos_id))}));
                for (const c of cibles) {
                    const tr = tranchesDe(et.tranche_horaire);
                    for (const k of tr.length ? tr : [null]) {
                        const lib = locaux ? `${base} — ${c.enclos.nom}` : base;
                        taches.push({
                            etape_id: et.id, uid_eleveur: uid, profile_id: pid,
                            ...(pid ? {eleveur_profile_id: pid} : {}),
                            animal_id: c.animal ? c.animal.id : null,
                            animal_nom: c.animal ? c.animal.nom : null,
                            type_acte: et.type_acte || null, lieu: c.enclos ? c.enclos.nom : (et.lieu || null),
                            box_id: c.enclos ? c.enclos.id : null,
                            tranche_horaire: k, profil_source: "association",
                            label: tr.length > 1 ? `${lib} — ${TRANCHES[k] || k}` : lib,
                            date_prevue: today, jour_traitement: 1, total_jours: 1,
                        });
                    }
                }
            }
            if (!taches.length) continue;

            // Doublons : déjà créées aujourd'hui (relance, ou création à la main).
            const etapeIds = [...new Set(taches.map((t) => t.etape_id))];
            const deja = await supabaseSelect("plan_taches",
                `select=etape_id,animal_id,box_id,tranche_horaire&date_prevue=eq.${today}` +
                `&etape_id=in.(${etapeIds.join(",")})`);
            const cle = (t) => `${t.etape_id}|${t.animal_id || ""}|${t.box_id || ""}|${t.tranche_horaire || ""}`;
            const existe = new Set(deja.map(cle));
            const aCreer = taches.filter((t) => !existe.has(cle(t)));
            if (!aCreer.length) continue;

            // Un plan actif par protocole, réutilisé chaque jour.
            let planId = null;
            const plans = await supabaseSelect("plans_actifs",
                `select=id&template_id=eq.${tp.id}&type_declencheur=eq.sejour&limit=1`);
            if (plans[0]) {
                planId = plans[0].id;
            } else {
                const r = await supabaseRequest("POST", "plans_actifs", [{
                    template_id: tp.id, uid_eleveur: uid, ...(pid ? {eleveur_profile_id: pid} : {}),
                    type_declencheur: "sejour", date_reference: today,
                    reference_label: "Présence au refuge", profil_source: "association",
                }], "return=representation");
                planId = Array.isArray(r.body) && r.body[0] ? r.body[0].id : null;
            }
            if (!planId) continue;
            const res = await supabaseRequest("POST", "plan_taches", aCreer.map((t) => ({...t, plan_id: planId})));
            if (res.status >= 200 && res.status < 300) total += aCreer.length;
            else console.error(`presence asso insert ${tp.id}:`, JSON.stringify(res.body));
        }
        console.log(`genererTachesPresenceAssociation: ${total} tâches créées (${templates.length} protocoles).`);
        return null;
    });
