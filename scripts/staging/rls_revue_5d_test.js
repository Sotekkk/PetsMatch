// Tests de la revue 5d (STAGING) : tests génétiques, réponses des balades
// ludiques (vérification côté serveur), mot de passe bêta.
// Prérequis : fixtures_revue_5d.sql (action=creer).
// Usage : node scripts/staging/rls_revue_5d_test.js
// Réf. : supabase/migration_rls_revue_5d.sql
const { as } = require('./sb');
const { STAGING } = require('./config');
const { idToken } = require('./token');

const PROPRIO = 'WQvZxEM9KDdhtSi34tkUgVvZh5d2';   // propriétaire de l'animal privé, non admin
const CREATEUR = 'G59EC6CC61OUFQdVPMmw8e9Gp8v2';  // créateur de la balade de test, non admin
const JOUEUR = 'RIOWjkshiibFwwJpkSzf2P4kDKH2';    // non admin, sans lien
const ANIMAL_PRIVE = '1786093435841';
const ANIMAL_PUBLIC = 'XNH3Bl3ZqpfWB5yShw1e';
const BALADE = '00000000-0000-4000-8000-0000005d0b01';
const PT_QUESTION = '00000000-0000-4000-8000-0000005d0b02';
const PT_QR = '00000000-0000-4000-8000-0000005d0b03';

let ok = 0, ko = 0;
function check(label, cond, detail = '') {
  if (cond) ok++; else ko++;
  console.log(`${cond ? 'OK ' : 'KO '} ${label}${cond ? '' : '  → ' + detail}`);
}
const nb = (r) => (r.status === 200 ? JSON.parse(r.body).length : `HTTP ${r.status} ${r.body.slice(0, 100)}`);
async function rpc(uid, fn, body) {
  const h = { apikey: STAGING.supabasePublishableKey, 'Content-Type': 'application/json' };
  if (uid) h.Authorization = 'Bearer ' + (await idToken(uid));
  const r = await fetch(`${STAGING.supabaseUrl}/rest/v1/rpc/${fn}`, { method: 'POST', headers: h, body: JSON.stringify(body) });
  return r.status === 200 ? await r.json() : `HTTP ${r.status}`;
}

(async () => {
  const anon = await as(null), proprio = await as(PROPRIO), createur = await as(CREATEUR), joueur = await as(JOUEUR);

  console.log('── Tests génétiques');
  check('Non connecté : test d\'un animal privé masqué', nb(await anon.rest(`tests_genetiques?select=id&animal_id=eq.${ANIMAL_PRIVE}`)) === 0);
  check('Tiers : test d\'un animal privé masqué', nb(await joueur.rest(`tests_genetiques?select=id&animal_id=eq.${ANIMAL_PRIVE}`)) === 0);
  check('Propriétaire : voit le test de son animal', nb(await proprio.rest(`tests_genetiques?select=id&animal_id=eq.${ANIMAL_PRIVE}`)) === 1);
  check('Non connecté : test d\'un reproducteur public visible', nb(await anon.rest(`tests_genetiques?select=id&animal_id=eq.${ANIMAL_PUBLIC}`)) >= 1);

  console.log('── Balade ludique : réponses');
  let r = await joueur.rest(`balades_ludiques_points?select=id,question_reponse&balade_id=eq.${BALADE}`);
  check('Joueur : lecture directe des réponses refusée', r.status >= 400, `${r.status}`);
  r = await joueur.rest(`balades_ludiques_points_complet?select=id,question_texte,question_reponse,qr_code_value&balade_id=eq.${BALADE}&order=ordre`);
  const pts = r.status === 200 ? JSON.parse(r.body) : [];
  check('Joueur : voit les points (sans réponses)', pts.length === 2 && pts.every((p) => p.question_reponse === null && p.qr_code_value === null), r.body.slice(0, 120));
  r = await createur.rest(`balades_ludiques_points_complet?select=question_reponse,qr_code_value&balade_id=eq.${BALADE}&order=ordre`);
  const cpts = r.status === 200 ? JSON.parse(r.body) : [];
  check('Créateur : voit ses réponses (édition)', cpts[0]?.question_reponse === 'Bleu' && cpts[1]?.qr_code_value === 'PM-QR-TEST', r.body.slice(0, 120));
  check('Bonne réponse (casse / espaces indifférents) → acceptée', (await rpc(JOUEUR, 'pm_verifier_defi', { p_point_id: PT_QUESTION, p_reponse: '  bleu ' })) === true);
  check('Mauvaise réponse → refusée', (await rpc(JOUEUR, 'pm_verifier_defi', { p_point_id: PT_QUESTION, p_reponse: 'vert' })) === false);
  check('Bon QR code → accepté', (await rpc(JOUEUR, 'pm_verifier_defi', { p_point_id: PT_QR, p_reponse: 'PM-QR-TEST' })) === true);
  check('Mauvais QR code → refusé', (await rpc(JOUEUR, 'pm_verifier_defi', { p_point_id: PT_QR, p_reponse: 'autre' })) === false);

  console.log('── Mot de passe bêta');
  check('Non connecté : mot de passe illisible', nb(await anon.rest('app_config?select=value&key=eq.beta_password')) === 0);
  check('Mauvais code → refusé', (await rpc(null, 'pm_verifier_code_beta', { p_code: 'mauvais-code' })) === false);
  if (process.env.PM_BETA_CODE) {
    check('Bon code → accepté', (await rpc(null, 'pm_verifier_code_beta', { p_code: process.env.PM_BETA_CODE })) === true);
  } else {
    console.log('--  PM_BETA_CODE absent : bon code non testé');
  }

  console.log(`\n${ok} OK / ${ko} KO`);
  process.exit(ko ? 1 : 0);
})().catch((e) => { console.error(e.message); process.exit(1); });
