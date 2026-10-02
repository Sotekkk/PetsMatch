// Tests de l'Edge Function lien-document (STAGING) — stockage privé.
// Prérequis : migration_storage_prive_phase2b.sql appliquée sur le staging,
// fonction déployée (supabase functions deploy lien-document --no-verify-jwt).
// Usage : node scripts/staging/lien_document_test.js
// Crée puis supprime : 1 fichier dans `documents`, 1 ordonnance.
const { as } = require('./sb');
const { STAGING } = require('./config');
const { idToken } = require('./token');

const VETO = 'G59EC6CC61OUFQdVPMmw8e9Gp8v2';   // dépose l'ordonnance (non admin)
const PROPRIO = 'WQvZxEM9KDdhtSi34tkUgVvZh5d2'; // propriétaire de l'animal (non admin)
const TIERS = 'RIOWjkshiibFwwJpkSzf2P4kDKH2';   // sans lien (non admin)
const ANIMAL = '1786093435841';
const CHEMIN = `ordonnances/${VETO}/test_rls_${Date.now()}.pdf`;
const URL_DOC = `${STAGING.supabaseUrl}/storage/v1/object/public/documents/${CHEMIN}`;

let ok = 0, ko = 0;
function check(label, cond, detail = '') {
  if (cond) ok++; else ko++;
  console.log(`${cond ? 'OK ' : 'KO '} ${label}${cond ? '' : '  → ' + detail}`);
}
async function lien(uid, url, extra = {}) {
  const h = { apikey: STAGING.supabasePublishableKey, 'Content-Type': 'application/json', ...extra };
  if (uid) h.Authorization = 'Bearer ' + (await idToken(uid));
  const r = await fetch(`${STAGING.supabaseUrl}/functions/v1/lien-document`, { method: 'POST', headers: h, body: JSON.stringify({ url }) });
  let body = {}; try { body = await r.json(); } catch { /* vide */ }
  return { status: r.status, url: body.url };
}

(async () => {
  const veto = await as(VETO);
  const pdf = Buffer.from('%PDF-1.4\n%test_rls\n');
  let r = await veto.upload('documents', CHEMIN, false, 'application/pdf', pdf);
  check('Véto : dépôt dans le stockage privé', r.status === 200, `${r.status} ${String(r.body).slice(0, 120)}`);

  r = await fetch(URL_DOC);
  check('Lien public direct → refusé (bucket privé)', r.status >= 400, `${r.status}`);

  let l = await lien(VETO, URL_DOC);
  check('Déposant (avant toute fiche) → lien temporaire', l.status === 200 && !!l.url, `${l.status}`);
  if (l.url) {
    const g = await fetch(l.url);
    check('Le lien temporaire ouvre le fichier', g.status === 200, `${g.status}`);
  }

  l = await lien(PROPRIO, URL_DOC);
  check('Propriétaire, sans fiche qui référence le document → refusé', l.status === 403, `${l.status}`);

  r = await veto.insertMin('ordonnances', { pro_uid: VETO, animal_id: ANIMAL, owner_uid: PROPRIO, doc_url: URL_DOC, notes: 'test_rls' });
  check('Véto : ordonnance enregistrée', r.status === 201, `${r.status} ${String(r.body).slice(0, 120)}`);

  l = await lien(PROPRIO, URL_DOC);
  check('Propriétaire de l\'animal → lien temporaire', l.status === 200 && !!l.url, `${l.status}`);
  l = await lien(TIERS, URL_DOC);
  check('Tiers → refusé', l.status === 403, `${l.status}`);
  l = await lien(null, URL_DOC);
  check('Non connecté → refusé', l.status === 401, `${l.status}`);
  l = await lien(null, URL_DOC, { 'x-pm-token': 'jeton-bidon' });
  check('Lien secret invalide → refusé', l.status === 403, `${l.status}`);
  l = await lien(TIERS, 'https://exemple.org/photo.jpg');
  check('Lien externe → renvoyé tel quel', l.status === 200 && l.url === 'https://exemple.org/photo.jpg', `${l.status}`);

  // Ménage
  await veto.delMin(`ordonnances?doc_url=eq.${encodeURIComponent(URL_DOC)}`);
  await veto.remove('documents', [CHEMIN]);

  console.log(`\n${ok} OK / ${ko} KO`);
  process.exit(ko ? 1 : 0);
})().catch((e) => { console.error(e.message); process.exit(1); });
