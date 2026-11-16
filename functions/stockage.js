/**
 * Admin — relevé quotidien du stockage (16/11/2026) : taille de la base,
 * fichiers par espace, volume des galeries photo → table stockage_releves
 * (RPC admin_stockage_releve, réservée à service_role). Alimente la tendance
 * de l'onglet admin « Stockage ». Migration : supabase/migration_admin_stockage.sql.
 */
const functions = require("firebase-functions/v1");
const https = require("https");
const {SUPABASE_URL, SUPABASE_AUTH_HEADERS} = require("./config");

function rpc(nom) {
    return new Promise((resolve, reject) => {
        const body = "{}";
        const req = https.request({
            hostname: new URL(SUPABASE_URL).hostname,
            path: `/rest/v1/rpc/${nom}`,
            method: "POST",
            headers: {
                ...SUPABASE_AUTH_HEADERS,
                "Content-Type": "application/json",
                "Content-Length": Buffer.byteLength(body),
            },
        }, (res) => {
            let data = "";
            res.on("data", (c) => data += c);
            res.on("end", () => (res.statusCode >= 200 && res.statusCode < 300 ?
                resolve() : reject(new Error(`${nom}: ${res.statusCode} — ${data}`))));
        });
        req.on("error", reject);
        req.write(body);
        req.end();
    });
}

exports.sendStockageReleve = functions
    .region("europe-west1")
    .pubsub.schedule("every day 03:30")
    .timeZone("Europe/Paris")
    .onRun(async () => {
        try {
            await rpc("admin_stockage_releve");
            console.log("sendStockageReleve: relevé enregistré");
        } catch (e) {
            console.error("sendStockageReleve:", e.message);
        }
        return null;
    });
