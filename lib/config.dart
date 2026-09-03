// URL du site web PetsMatch
// Tests locaux : IP réseau de la machine qui fait tourner `npm run dev`
// Production  : remplacer par l'URL finale (ex. https://petsmatch.com)
const kSiteBaseUrl = 'https://petsmatchapp.com';

// ── Accès privé pendant la phase de test ─────────────────────────────────────
// Portail mot de passe au lancement (cf. lib/pages/beta_gate.dart), équivalent
// de l'accès bêta du site. Passer à `false` pour ouvrir l'app à tous.
const kBetaGateEnabled = true;

// Mot de passe de repli, utilisé si Supabase (`app_config` -> `beta_password`)
// est injoignable ou vide. Le mot de passe en base a priorité : le changer là
// évite de republier l'app.
const kBetaPassword = 'petsmatch-beta-2026';
