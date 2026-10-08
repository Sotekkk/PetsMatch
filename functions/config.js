// Configuration des Cloud Functions, par projet Firebase.
//
// Les valeurs viennent de functions/.env.<projectId> (NON versionné — modèle
// dans functions/.env.example), chargé automatiquement par le CLI Firebase au
// déploiement : le même code tourne en prod et en staging, et une clé se
// change sans toucher au code. Ne JAMAIS remettre de clé en dur dans functions/.

const SUPABASE_URL = process.env.SUPABASE_URL || "";
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY || "";
const STRIPE_SECRET_KEY = process.env.STRIPE_SECRET_KEY || "";
// Secret partagé avec le site pour les appels serveur → serveur (ex. e-mail de
// rappel RDV) — même valeur que INTERNAL_API_SECRET côté hébergeur du site.
const INTERNAL_API_SECRET = process.env.INTERNAL_API_SECRET || "";

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
    console.error("config: SUPABASE_URL / SUPABASE_SERVICE_KEY manquants " +
        "(functions/.env.<projectId>) — tous les appels Supabase vont échouer.");
}

// En-têtes d'authentification des appels REST Supabase. Une clé secrète
// nouvelle génération (sb_secret_…) n'est PAS un JWT : elle ne doit partir
// que dans `apikey` (la passerelle Supabase la convertit elle-même en jeton
// service_role). L'ancienne clé service_role (JWT « eyJ… ») garde en plus
// l'en-tête Authorization — le même code fonctionne donc avec les deux,
// ce qui permet la rotation sans coupure (et un retour arrière immédiat).
const SUPABASE_AUTH_HEADERS = {
    // Les Cloud Functions envoient elles-mêmes le push des notifications
    // qu'elles enregistrent (préfixe du profil, regroupement) : le webhook
    // « notify_push » de la table notifications ne doit pas en renvoyer un
    // second (doublons « Chaleurs — Aiko », 08/10/2026) — migration
    // migration_notify_push_sans_doublon.sql.
    "x-pm-push": "serveur",
    "apikey": SUPABASE_SERVICE_KEY,
    ...(SUPABASE_SERVICE_KEY.startsWith("eyJ") ?
        {"Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`} : {}),
};

module.exports = {
    SUPABASE_URL, SUPABASE_SERVICE_KEY, SUPABASE_AUTH_HEADERS, STRIPE_SECRET_KEY, INTERNAL_API_SECRET,
};
