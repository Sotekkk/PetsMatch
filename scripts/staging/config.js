// Configuration commune des outils staging.
// Valeurs publiques uniquement (déjà embarquées côté client) ; les secrets
// restent HORS du dépôt, dans le dossier utilisateur :
//   %USERPROFILE%\petsmatch-staging-sa.json  (compte de service Firebase staging)
//   %USERPROFILE%\petsmatch-prod-sa.json     (prod, lecture — copie Firestore seulement)
//   %USERPROFILE%\petsmatch-db.env           (PROD_DB_URL / STAGING_DB_URL, pour psql)
const path = require('path');
const fs = require('fs');

const HOME = process.env.USERPROFILE || process.env.HOME;

const STAGING = {
  firebaseProjectId: 'petsmatch-staging',
  firebaseWebApiKey: 'AIzaSyCmwr2rXqD4edjzcVqbtic7VWFimtplS1c',
  supabaseUrl: 'https://ozftswznayxzrbcfmher.supabase.co',
  supabasePublishableKey: 'sb_publishable_I63yWhGMxKQZQAiEsYIP3Q_UR6DiIdv',
};

// firebase-admin est déjà installé dans functions/ (npm ci dans functions/).
const admin = require(path.join(__dirname, '..', '..', 'functions', 'node_modules', 'firebase-admin'));

function serviceAccount(kind) {
  const file = process.env[`PM_${kind.toUpperCase()}_SA`]
    || path.join(HOME, `petsmatch-${kind}-sa.json`);
  if (!fs.existsSync(file)) {
    throw new Error(`Clé de compte de service introuvable : ${file} (voir scripts/staging/README.md)`);
  }
  const sa = JSON.parse(fs.readFileSync(file, 'utf8'));
  const expected = kind === 'staging' ? 'petsmatch-staging' : 'petsmatch-eb96d';
  if (sa.project_id !== expected) throw new Error(`${file} n'est pas une clé du projet ${expected}`);
  return sa;
}

function app(kind) {
  const name = `pm-${kind}`;
  return admin.apps.find((a) => a && a.name === name)
    || admin.initializeApp({ credential: admin.credential.cert(serviceAccount(kind)) }, name);
}

module.exports = { STAGING, admin, app };
