// Tests phase 2a Storage (chacun ne liste / remplace / supprime que SES
// fichiers) sur le STAGING, via la vraie API.
// Usage : node scripts/staging/storage_test_phase2.js <nom_fichier_ancien>
//   <nom_fichier_ancien> : un objet media SANS owner_id dans le dossier de
//   Natacha (profiles/<uid Natacha>/…), créé au préalable en SQL — simule
//   les fichiers déposés avant le 22/09.
// Réf. : supabase/migration_storage_policies_phase2a.sql
const { as } = require('./sb');

const NAT = 'YF9kR7jSTObnnw9lVj8gCl031rS2';            // Natacha (élevage)
const NAT_PART = 'd27a7bcb-f396-463f-aa01-65e69fb80cd0'; // son profil particulier
const EMP = 'IfhRVwY55KUXW12lBG4D0bs0V383';            // employé de Natacha
const TIERS = 'PZltNeW1M4cmEmOdRlbvOVmUNyB2';
const LEGACY = process.argv[2];
const TS = Date.now();

let ok = 0, ko = 0;
function check(label, cond, r) {
  if (cond) ok++; else ko++;
  console.log(`${cond ? 'OK ' : 'KO '} ${label}${cond ? '' : '  → ' + r.status + ' ' + r.body.slice(0, 160)}`);
}
const has = (r, s) => r.body.includes(s);

(async () => {
  const nat = await as(NAT), emp = await as(EMP), tiers = await as(TIERS), anon = await as(null);
  const DIR = `test_sec/${TS}`, IMG = `${DIR}/nat.jpg`, DOC = `${DIR}/doc.txt`;
  for (const [b, n] of [['media', IMG], ['documents', DOC]]) {
    const r = await nat.upload(b, n);
    if (r.status !== 200) { console.error(`Dépôt témoin ${b}/${n} impossible : ${r.status} ${r.body}`); process.exit(1); }
  }

  console.log('── Liste');
  let r = await nat.list('media', DIR);
  check('Natacha voit son fichier', has(r, 'nat.jpg'), r);
  r = await tiers.list('media', DIR);
  check('Tiers ne voit pas le fichier de Natacha', !has(r, 'nat.jpg'), r);
  r = await emp.list('documents', DIR);
  check('Employé ne liste pas les documents de Natacha', !has(r, 'doc.txt'), r);
  r = await anon.list('media', DIR);
  check('Non connecté ne voit rien', !has(r, 'nat.jpg'), r);

  console.log('── Remplacement (upsert)');
  r = await nat.upload('media', IMG, true);
  check('Natacha remplace son fichier', r.status === 200, r);
  r = await tiers.upload('media', IMG, true);
  check('Tiers ne peut pas l\'écraser', r.status >= 400, r);
  r = await emp.upload('documents', DOC, true);
  check('Employé ne peut pas écraser un document de Natacha', r.status >= 400, r);
  r = await emp.upload('documents', `${DIR}/emp_doc.txt`, true);
  check('Employé dépose un NOUVEAU document (upsert)', r.status === 200, r);
  r = await emp.upload('documents', `${DIR}/emp_doc.txt`, true);
  check('Employé remplace SON document', r.status === 200, r);
  r = await emp.upload('media', `animaux/${NAT}/${TS}.jpg`, true);
  check('Employé dépose une photo dans le dossier de Natacha', r.status === 200, r);

  if (LEGACY) {
    console.log('── Ancien fichier sans propriétaire (avant le 22/09)');
    r = await tiers.upload('media', LEGACY, true);
    check('Tiers ne peut pas l\'écraser', r.status >= 400, r);
    r = await nat.upload('media', LEGACY, true);
    check('Natacha le remplace (il est dans son dossier)', r.status === 200, r);
  } else {
    console.log('--  pas de fichier ancien fourni : cas « sans propriétaire » non testé');
  }

  console.log('── Suppression');
  r = await tiers.remove('media', [IMG]);
  check('Tiers ne supprime pas le fichier de Natacha', !has(r, 'nat.jpg'), r);
  r = await emp.remove('documents', [DOC]);
  check('Employé ne supprime pas le document de Natacha', !has(r, 'doc.txt'), r);
  r = await nat.remove('media', [IMG]);
  check('Natacha supprime son fichier', has(r, 'nat.jpg'), r);
  const BALADE = `${NAT}/balade_${TS}.jpg`;
  r = await nat.upload('social', BALADE);
  r = await nat.remove('social', [BALADE]);
  check('Natacha supprime sa photo de balade (social)', has(r, `balade_${TS}`), r);
  const S = `${NAT_PART}/story_${TS}.txt`;
  await nat.upload('stories', S);
  r = await tiers.remove('stories', [S]);
  check('Tiers ne supprime pas la story de Natacha', !has(r, `story_${TS}`), r);
  r = await nat.remove('stories', [S]);
  check('Natacha supprime sa story', has(r, `story_${TS}`), r);

  console.log('── Contrats (fenêtre « Finaliser », avec le jeton de l\'éleveur)');
  const C = `contrat_5e9284bd-87cb-411a-8b70-f3ea1adb0486_${TS}.html`;
  r = await nat.upload('contrats', C, true);
  check('Éleveur connecté : dépôt du contrat (x-upsert)', r.status === 200, r);
  r = await tiers.list('contrats', '');
  check('Tiers ne liste pas le contrat', !has(r, String(TS)), r);
  r = await tiers.upload('contrats', C, true);
  check('Tiers ne peut pas l\'écraser', r.status >= 400, r);
  r = await anon.upload('contrats', `contrat_5e9284bd-87cb-411a-8b70-f3ea1adb0486_${TS + 1}.html`, true);
  check('Non connecté : dépôt refusé', r.status >= 400, r);

  console.log('── Preuves influenceur');
  r = await nat.upload('influencer-proofs', `${NAT}/${TS}_0.png`, true, 'image/png');
  check('Dépôt de preuve (upsert)', r.status === 200, r);
  r = await anon.upload('influencer-proofs', `web/${TS}_x.png`, true, 'image/png');
  check('Non connecté : dépôt de preuve refusé', r.status >= 400, r);

  console.log(`\n${ok} OK / ${ko} KO`);
  process.exit(ko ? 1 : 0);
})().catch((e) => { console.error(e.message); process.exit(1); });
