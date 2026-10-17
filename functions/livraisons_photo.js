const functions = require("firebase-functions/v1");
const https = require("https");

// Livraisons photo (galeries privées) — stockage TEMPORAIRE des ZIP de
// fichiers finaux (bucket privé « livraisons », table album_livraisons) :
//  • la veille de l'expiration : le client (s'il a un compte) et le
//    photographe sont prévenus une seule fois (rappel_envoye) ;
//  • à l'expiration : ZIP supprimés du stockage + lignes supprimées.
// Les aperçus de la galerie ne sont jamais touchés. Règle annoncée au client
// (date d'expiration affichée sur sa galerie) et au photographe.

const {SUPABASE_URL, SUPABASE_AUTH_HEADERS} = require("./config");

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
                ...SUPABASE_AUTH_HEADERS,
                "Prefer": "return=representation",
                // Notifications insérées ici : push envoyé par le webhook
                // (pas de doublon, cf. migration_notify_push_sans_doublon.sql).
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

const fmt = (iso) => new Date(iso).toLocaleDateString("fr-FR", {timeZone: "Europe/Paris"});

exports.purgerLivraisonsPhoto = functions
    .region("europe-west1")
    .pubsub.schedule("15 3 * * *") // chaque nuit à 3 h 15
    .timeZone("Europe/Paris")
    .onRun(async () => {
        const maintenant = new Date();
        // Livraisons courtes (3 à 14 jours) : rappel la veille de la suppression.
        const demain = new Date(maintenant.getTime() + 86400000).toISOString();

        // 1. Rappels la veille (une fois par galerie).
        const aRappeler = await httpRequest("GET",
            `/rest/v1/album_livraisons?rappel_envoye=eq.false&expire_le=lt.${encodeURIComponent(demain)}` +
            `&expire_le=gt.${encodeURIComponent(maintenant.toISOString())}&select=id,album_id,expire_le`);
        const rappels = Array.isArray(aRappeler.body) ? aRappeler.body : [];
        const albumsRappel = [...new Set(rappels.map((r) => r.album_id))];
        for (const albumId of albumsRappel) {
            const exp = rappels.find((r) => r.album_id === albumId).expire_le;
            const a = await httpRequest("GET",
                `/rest/v1/albums_photo?id=eq.${albumId}` +
                "&select=titre,pro_uid,pro_profile_id,client_uid,client_profile_id,partage_client");
            const album = Array.isArray(a.body) ? a.body[0] : null;
            if (album) {
                const titre = album.titre || "Séance photo";
                const notifs = [{
                    uid: album.pro_uid, type: "galerie_expiration", title: "Livraison bientôt expirée",
                    body: `Les fichiers livrés de « ${titre} » seront supprimés le ${fmt(exp)}. ` +
                        "Vous pouvez prolonger la livraison.",
                    ...(album.pro_profile_id ? {profile_id: album.pro_profile_id} : {}),
                    data: {albumId}, read: false,
                }];
                if (album.client_uid && album.partage_client) {
                    notifs.push({
                        uid: album.client_uid, type: "galerie_expiration", title: "Pensez à télécharger vos photos",
                        body: `Vos photos « ${titre} » restent téléchargeables jusqu'au ${fmt(exp)}.`,
                        ...(album.client_profile_id ? {profile_id: album.client_profile_id} : {}),
                        data: {albumId}, read: false,
                    });
                }
                await httpRequest("POST", "/rest/v1/notifications", notifs);
            }
            await httpRequest("PATCH", `/rest/v1/album_livraisons?album_id=eq.${albumId}`, {rappel_envoye: true});
        }

        // 2. Suppression des livraisons expirées.
        const expirees = await httpRequest("GET",
            `/rest/v1/album_livraisons?expire_le=lt.${encodeURIComponent(maintenant.toISOString())}` +
            "&select=id,storage_path");
        const rows = Array.isArray(expirees.body) ? expirees.body : [];
        if (rows.length > 0) {
            try {
                await httpRequest("DELETE", "/storage/v1/object/livraisons",
                    {prefixes: rows.map((r) => r.storage_path)});
            } catch (e) {
                console.error("[livraisons_photo] suppression storage échouée:", e.message);
            }
            const ids = rows.map((r) => `"${r.id}"`).join(",");
            await httpRequest("DELETE", `/rest/v1/album_livraisons?id=in.(${ids})`);
        }
        // 3. Sélection non confirmée : rappel au client (compte PetsMatch) tous
        //    les 3 jours tant que la galerie est partagée sans sélection
        //    confirmée (relance_selection_le, partagée avec le bouton du pro).
        const ilYa3j = new Date(maintenant.getTime() - 3 * 86400000).toISOString();
        const enAttente = await httpRequest("GET",
            "/rest/v1/albums_photo?statut=eq.partagee&selection_confirmee_le=is.null&partage_client=eq.true" +
            `&client_uid=not.is.null&partagee_le=lt.${encodeURIComponent(ilYa3j)}` +
            `&or=(relance_selection_le.is.null,relance_selection_le.lt.${encodeURIComponent(ilYa3j)})` +
            "&select=id,titre,client_uid,client_profile_id");
        const aRelancer = Array.isArray(enAttente.body) ? enAttente.body : [];
        for (const album of aRelancer) {
            await httpRequest("POST", "/rest/v1/notifications", [{
                uid: album.client_uid, type: "galerie_disponible", title: "Votre sélection de photos",
                body: `« ${album.titre || "Séance photo"} » — choisissez vos photos puis confirmez votre sélection ` +
                    "pour que votre photographe lance la retouche.",
                ...(album.client_profile_id ? {profile_id: album.client_profile_id} : {}),
                data: {albumId: album.id}, read: false,
            }]);
            await httpRequest("PATCH", `/rest/v1/albums_photo?id=eq.${album.id}`,
                {relance_selection_le: maintenant.toISOString()});
        }
        console.log(`[livraisons_photo] ${albumsRappel.length} rappel(s), ${rows.length} ZIP supprimé(s), ` +
            `${aRelancer.length} relance(s) de sélection`);
        return null;
    });
