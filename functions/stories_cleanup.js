const functions = require("firebase-functions/v1");
const https = require("https");

// Suppression des Stories Pets Social expirées (24h) — fichiers Storage
// (photo/vidéo) + lignes en base, pour limiter le volume utilisé. Tourne
// toutes les heures : une story ne reste jamais visible après son
// `expires_at` côté client, mais sans cette purge les fichiers resteraient
// indéfiniment dans Storage.

const SUPABASE_URL = "https://zyvpngcvzrkdytypjlyq.supabase.co";
const SUPABASE_SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" +
    ".eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5dnBuZ2N2enJrZHl0eXBqbHlxIiwi" +
    "cm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTM2NDY1NSwiZXhwIjoyMDk0OT" +
    "QwNjU1fQ.1U96V3c7nHG3T08dboBcxTd05k8A_JQfnyrJTbJ0HgQ";

function httpRequest(method, path, body) {
    return new Promise((resolve, reject) => {
        const bodyStr = body ? JSON.stringify(body) : null;
        const url = new URL(`${SUPABASE_URL}${path}`);
        const options = {
            hostname: url.hostname,
            path: url.pathname + (url.search || ""),
            method,
            headers: {
                "Content-Type": "application/json",
                "apikey": SUPABASE_SERVICE_KEY,
                "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
                "Prefer": "return=representation",
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

// Chemin de l'objet Storage à partir de l'URL publique
// (…/storage/v1/object/public/stories/<path>).
function storagePathFromUrl(url, bucket) {
    const marker = `/storage/v1/object/public/${bucket}/`;
    const i = url.indexOf(marker);
    return i === -1 ? null : url.slice(i + marker.length);
}

exports.cleanupExpiredStories = functions
    .region("europe-west1")
    .pubsub.schedule("0 * * * *") // toutes les heures
    .timeZone("Europe/Paris")
    .onRun(async () => {
        const nowIso = new Date().toISOString();
        const expired = await httpRequest(
            "GET",
            `/rest/v1/stories?expires_at=lt.${encodeURIComponent(nowIso)}&select=id,media_url`,
        );
        const rows = Array.isArray(expired.body) ? expired.body : [];
        if (rows.length === 0) {
            console.log("[stories_cleanup] rien à purger");
            return null;
        }

        const paths = rows.map((r) => storagePathFromUrl(r.media_url, "stories")).filter(Boolean);
        if (paths.length > 0) {
            try {
                await httpRequest("DELETE", "/storage/v1/object/stories", {prefixes: paths});
            } catch (e) {
                console.error("[stories_cleanup] suppression storage échouée:", e.message);
            }
        }

        const ids = rows.map((r) => r.id);
        const idsList = ids.map((id) => `"${id}"`).join(",");
        await httpRequest("DELETE", `/rest/v1/stories?id=in.(${idsList})`);

        console.log(`[stories_cleanup] ${rows.length} story(ies) expirée(s) supprimée(s)`);
        return null;
    });
