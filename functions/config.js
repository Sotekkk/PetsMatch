// Configuration des Cloud Functions, par projet Firebase.
//
// Les valeurs viennent de functions/.env.<projectId> (NON versionné — modèle
// dans functions/.env.example), chargé automatiquement par le CLI Firebase au
// déploiement : le même code tourne en prod et en staging, et une clé se
// change sans toucher au code. Ne JAMAIS remettre de clé en dur dans functions/.

const SUPABASE_URL = process.env.SUPABASE_URL || "";
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY || "";
const STRIPE_SECRET_KEY = process.env.STRIPE_SECRET_KEY || "";

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
    console.error("config: SUPABASE_URL / SUPABASE_SERVICE_KEY manquants " +
        "(functions/.env.<projectId>) — tous les appels Supabase vont échouer.");
}

module.exports = {SUPABASE_URL, SUPABASE_SERVICE_KEY, STRIPE_SECRET_KEY};
