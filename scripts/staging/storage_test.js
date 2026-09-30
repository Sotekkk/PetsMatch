// Tests des policies Storage sur le STAGING, par rôle, via la vraie API.
// Usage : node scripts/staging/storage_test.js
// Les fichiers témoins sont déposés sous test_sec/ (staging uniquement).
// Réf. : supabase/migration_storage_policies_phase1.sql
const { as } = require('./sb');

const NAT = 'YF9kR7jSTObnnw9lVj8gCl031rS2';            // Natacha (élevage)
const NAT_PART = 'd27a7bcb-f396-463f-aa01-65e69fb80cd0'; // son profil particulier (dossier des stories)
const EMP = 'IfhRVwY55KUXW12lBG4D0bs0V383';            // employé de Natacha
const TIERS = 'PZltNeW1M4cmEmOdRlbvOVmUNyB2';          // sans lien avec Natacha
// Contrat « ancien » à nom fixe : créé au 1er passage, ancien (> 1 min) ensuite.
const OLD_CONTRAT = 'contrat_00000000-0000-0000-0000-000000000000_1790770000001.html';
// Idem pour la photo déposée pendant l'inscription (avant le compte Firebase).
const OLD_PHOTO_INSCRIPTION = 'profiles/1790770000002.jpg';
const TS = Date.now();

let ok = 0, ko = 0;
function check(label, cond, r) {
  if (cond) ok++; else ko++;
  console.log(`${cond ? 'OK ' : 'KO '} ${label}${cond ? '' : '  → ' + r.status + ' ' + r.body.slice(0, 160)}`);
}
const has = (r, s) => r.body.includes(s);

(async () => {
  const nat = await as(NAT), emp = await as(EMP), tiers = await as(TIERS), anon = await as(null);

  // Fichiers témoins (déposés par Natacha, noms uniques à chaque passage).
  // Un sous-dossier par passage : les listes restent courtes et sans ambiguïté.
  const DIR = `test_sec/${TS}`, DOC = `${DIR}/doc.txt`, IMG = `${DIR}/nat.jpg`;
  const S1 = `${NAT_PART}/story1_${TS}.txt`, S2 = `${NAT_PART}/story2_${TS}.txt`;
  for (const [b, n] of [['documents', DOC], ['media', IMG], ['stories', S1], ['stories', S2]]) {
    const r = await nat.upload(b, n);
    if (r.status !== 200) { console.error(`Dépôt témoin ${b}/${n} impossible : ${r.status} ${r.body}`); process.exit(1); }
  }
  const oldC = await anon.upload('contrats', OLD_CONTRAT, true);
  const oldReady = oldC.status !== 200; // refusé → existe depuis plus d'1 min
  const oldP = await anon.upload('media', OLD_PHOTO_INSCRIPTION, true);
  const oldPhotoReady = oldP.status !== 200;

  console.log('── Non connecté');
  let r = await anon.list('media', DIR);
  check('liste media vide', r.status === 200 && !has(r, 'nat.jpg'), r);
  r = await anon.list('documents', DIR);
  check('liste documents vide', !has(r, 'doc.txt'), r);
  r = await anon.upload('media', `test_sec/anon_${TS}.jpg`);
  check('dépôt media refusé', r.status >= 400, r);
  r = await anon.upload('media', IMG, true);
  check('remplacement media refusé', r.status >= 400, r);
  r = await anon.remove('documents', [DOC]);
  check('suppression document sans effet', !has(r, DOC), r);
  r = await anon.remove('stories', [S1]);
  check('suppression story sans effet', !has(r, 'story1_'), r);
  // Accepté en phase 1 (fenêtre « Finaliser » sans jeton), refusé à partir
  // de la phase 2a (elle envoie le jeton de l'éleveur) : information seule.
  r = await anon.upload('contrats', `contrat_5e9284bd-87cb-411a-8b70-f3ea1adb0486_${TS}.html`, true);
  console.log(`--  dépôt contrat « Finaliser » sans jeton : ${r.status === 200 ? 'accepté (phase 1)' : 'refusé (phase 2a)'}`);
  r = await anon.upload('contrats', `pirate_${TS}.html`);
  check('autre nom dans contrats refusé', r.status >= 400, r);
  if (oldReady) {
    r = await anon.list('contrats', '');
    check('ancien contrat non listé', !has(r, '1790770000001'), r);
    r = await anon.upload('contrats', OLD_CONTRAT, true);
    check('ancien contrat non écrasable', r.status >= 400, r);
    r = await anon.remove('contrats', [OLD_CONTRAT]);
    check('ancien contrat non supprimable', !has(r, '1790770000001'), r);
  } else {
    console.log('--  contrat témoin créé il y a moins d\'1 min : relancer plus tard pour tester « ancien contrat »');
  }

  console.log('── Inscription (photo déposée avant le compte)');
  r = await anon.upload('media', `profiles/${TS}.jpg`, true);
  check('photo d\'inscription (x-upsert) acceptée', r.status === 200, r);
  r = await anon.upload('media', `profiles/pirate_${TS}.jpg`, true);
  check('autre nom sous profiles/ refusé', r.status >= 400, r);
  if (oldPhotoReady) {
    r = await anon.list('media', 'profiles');
    check('anciennes photos non listées', !has(r, '1790770000002'), r);
    r = await anon.upload('media', OLD_PHOTO_INSCRIPTION, true);
    check('ancienne photo non écrasable', r.status >= 400, r);
  } else {
    console.log('--  photo témoin créée il y a moins d\'1 min : relancer plus tard pour tester « ancienne photo »');
  }

  console.log('── Natacha (propriétaire)');
  r = await nat.list('media', DIR);
  check('liste media', has(r, 'nat.jpg'), r);
  r = await nat.upload('media', `test_sec/nat2_${TS}.jpg`);
  check('dépôt media', r.status === 200, r);
  r = await nat.upload('media', IMG, true);
  check('remplacement (upsert) media', r.status === 200, r);
  r = await nat.upload('media', `test_sec/f_${TS}.pdf`, true, 'application/pdf');
  check('dépôt PDF dans media', r.status === 200, r);
  r = await nat.upload('documents', `test_sec/doc2_${TS}.txt`, true);
  check('dépôt documents (upsert, nouveau)', r.status === 200, r);
  r = await nat.upload('promenades-photos', `test_sec/pp_${TS}.txt`);
  check('dépôt promenades-photos', r.status === 200, r);
  r = await nat.upload('social', `${NAT}/s_${TS}.txt`);
  check('dépôt social', r.status === 200, r);

  console.log('── Employé');
  r = await emp.upload('media', `test_sec/emp_${TS}.jpg`, true);
  check('dépôt media (upsert)', r.status === 200, r);
  r = await emp.upload('documents', `test_sec/emp_doc_${TS}.txt`, true);
  check('dépôt documents (upsert)', r.status === 200, r);

  console.log('── Tiers');
  r = await tiers.remove('stories', [S1]);
  check('suppression story de Natacha sans effet', !has(r, 'story1_'), r);
  r = await tiers.remove('documents', [DOC]);
  check('suppression document sans effet', !has(r, DOC), r);

  console.log('── Auteur de la story');
  r = await nat.remove('stories', [S2]);
  check('Natacha supprime sa story', has(r, 'story2_'), r);
  r = await nat.remove('stories', [S1]); // ménage + vérifie que S1 existait encore
  check('story 1 intacte jusque-là (tiers n\'a rien supprimé)', has(r, 'story1_'), r);

  console.log(`\n${ok} OK / ${ko} KO`);
  process.exit(ko ? 1 : 0);
})().catch((e) => { console.error(e.message); process.exit(1); });
