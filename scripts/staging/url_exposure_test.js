// Qui peut LIRE les colonnes qui contiennent des liens vers des fichiers
// sensibles ? (staging, via la vraie API REST, en non connecté et en tiers)
// Usage : node scripts/staging/url_exposure_test.js
const { as } = require('./sb');

const TIERS = 'PZltNeW1M4cmEmOdRlbvOVmUNyB2';
const REQUETES = [
  ['user_profiles : KBIS', 'user_profiles?select=uid&kbis_url=not.is.null'],
  ['user_profiles : ACACED', 'user_profiles?select=uid&acaced_doc_url=not.is.null'],
  ['user_profiles : diplôme', 'user_profiles?select=uid&diplome_url=not.is.null'],
  ['user_profiles : statuts asso', 'user_profiles?select=uid&statuts_url=not.is.null'],
  ['user_profiles : arrêté préfectoral', 'user_profiles?select=uid&arrete_prefectoral_url=not.is.null'],
  ['ordonnances : doc_url', 'ordonnances?select=id&doc_url=not.is.null'],
  ['animaux : pedigree_url', 'animaux?select=id&pedigree_url=not.is.null'],
  ['animaux : cession_contrat_url', 'animaux?select=id&cession_contrat_url=not.is.null'],
  ['messages : image_url (chat)', 'messages?select=id&image_url=not.is.null'],
  ['pension_updates : photo_url', 'pension_updates?select=id&photo_url=not.is.null'],
];

(async () => {
  const anon = await as(null), tiers = await as(TIERS);
  console.log('colonne'.padEnd(36), 'non connecté', ' tiers');
  for (const [label, q] of REQUETES) {
    const a = await anon.rest(q), t = await tiers.rest(q);
    const n = (r) => (r.status === 200 ? String(JSON.parse(r.body).length) : `HTTP ${r.status}`);
    console.log(label.padEnd(36), n(a).padStart(12), n(t).padStart(6));
  }
  process.exit(0);
})().catch((e) => { console.error(e.message); process.exit(1); });
