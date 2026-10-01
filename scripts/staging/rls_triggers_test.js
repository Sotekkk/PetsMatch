// Tests des triggers qui écrivent pour quelqu'un d'autre (STAGING) :
// confirmation d'un RDV par le pro (→ agenda du client), avis client
// (→ note du pro). Les valeurs modifiées sont remises en fin de test.
// Usage : node scripts/staging/rls_triggers_test.js
// Réf. : supabase/migration_rls_triggers_definer.sql
const { as } = require('./sb');

const PRO = '6kmGQ4s7vNYokWGK3eT8VikbhWz2';
const CLIENT = 'xoRHVSob5uTWm3sbl6lKWFuIgKF2';
const RDV = 'f74d3a7a-a522-44df-8b9b-c95b3e442011';   // statut d'origine : termine

let ok = 0, ko = 0;
function check(label, cond, detail) {
  if (cond) ok++; else ko++;
  console.log(`${cond ? 'OK ' : 'KO '} ${label}${cond ? '' : '  → ' + detail}`);
}
const rows = (r) => (r.status >= 200 && r.status < 300 && r.body ? JSON.parse(r.body) : []);

(async () => {
  const pro = await as(PRO), client = await as(CLIENT);

  console.log('── Le pro confirme un RDV (le trigger crée l\'événement du client)');
  let r = await pro.update(`rdv?id=eq.${RDV}`, { statut: 'confirme' });
  check('Confirmation acceptée', rows(r).length === 1, `${r.status} ${r.body.slice(0, 160)}`);
  r = await client.rest(`agenda_events?select=id&rdv_id=eq.${RDV}`);
  check('L\'événement apparaît dans l\'agenda du client', rows(r).length === 1, r.body.slice(0, 120));
  r = await pro.update(`rdv?id=eq.${RDV}`, { statut: 'annule' });
  check('Annulation par le pro acceptée', rows(r).length === 1, `${r.status} ${r.body.slice(0, 160)}`);
  r = await client.rest(`agenda_events?select=id&rdv_id=eq.${RDV}`);
  check('… l\'événement du client est retiré', rows(r).length === 0, r.body.slice(0, 120));
  await pro.update(`rdv?id=eq.${RDV}`, { statut: 'termine' });

  console.log(`\n${ok} OK / ${ko} KO`);
  process.exit(ko ? 1 : 0);
})().catch((e) => { console.error(e.message); process.exit(1); });
