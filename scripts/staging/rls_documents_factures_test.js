// Tests RLS lecture : factures, pension_factures, devis, cessions,
// certificats_engagement, documents_animaux — émetteur, destinataire,
// lien secret (en-tête x-pm-token), tiers, non connecté. STAGING.
// Usage : node scripts/staging/rls_documents_factures_test.js
// Réf. : supabase/migration_rls_documents_factures.sql
const { as } = require('./sb');

const COGERANT = '2n7PqKsfsjMNNVwGCGgkqd9SGJW2';   // cogérant de l'élevage 47c2… de xoRH (admin)
const DEST = 'WQvZxEM9KDdhtSi34tkUgVvZh5d2';       // client / acquéreur / pro pension (non admin)
const TIERS = 'G59EC6CC61OUFQdVPMmw8e9Gp8v2';      // non admin, sans lien

const CAS = [
  // [table, colonne token, id, token, qui lit en « émetteur », qui lit en « destinataire »]
  ['factures', 'token', 'bjzehzgR7XQ3LXqTbtSk', '70990758-9164-4dd0-8a25-d085df306be7', COGERANT, null],
  ['pension_factures', 'token', 'ee166670-4ff2-4255-8b2f-cb82db7a9eb1', '221faec2-05e8-473a-9174-78c446c2a48b', DEST, null],
  ['devis', 'token_acceptation', 'e65599e5-c0f5-44ba-ba1c-0ebda02bbc6f', 'hlw4qyrfiyf160b', null, DEST],
  ['cessions', 'token', '253edc24-357e-4104-aa0a-306261c02652', 'bf3dbfc1-034d-490c-9023-dfa03561c98b', null, DEST],
  ['certificats_engagement', 'token_signature', 'b0fb519d-5490-4836-8063-f7eb708c7c6a', '4cbc5a94-d5ec-43f2-9b2c-6b2b8144eceb', null, null],
  ['documents_animaux', 'token', 'ac382c49-347a-42ef-af27-df535bce92df', 'f14885b8-95ea-4845-8a25-b56eaf186b7a', null, null],
];

let ok = 0, ko = 0;
function check(label, cond, detail) {
  if (cond) ok++; else ko++;
  console.log(`${cond ? 'OK ' : 'KO '} ${label}${cond ? '' : '  → ' + detail}`);
}
const nb = (r) => (r.status === 200 ? JSON.parse(r.body).length : `HTTP ${r.status} ${r.body.slice(0, 120)}`);

(async () => {
  const anon = await as(null), tiers = await as(TIERS);
  const clients = { [COGERANT]: await as(COGERANT), [DEST]: await as(DEST) };

  for (const [table, col, id, token, emetteur, dest] of CAS) {
    console.log(`── ${table}`);
    const one = `${table}?select=id&id=eq.${id}`;
    let r = await anon.rest(one);
    check('Non connecté sans lien : rien', nb(r) === 0, nb(r));
    r = await anon.rest(`${table}?select=id&${col}=eq.${token}`, { 'x-pm-token': token });
    check('Non connecté AVEC le lien : sa ligne', nb(r) === 1, nb(r));
    r = await anon.rest(`${table}?select=id`, { 'x-pm-token': token });
    check('… et seulement elle (requête sans filtre)', nb(r) === 1, nb(r));
    r = await anon.rest(`${table}?select=id`, { 'x-pm-token': 'faux-token' });
    check('Mauvais lien : rien', nb(r) === 0, nb(r));
    r = await tiers.rest(one);
    check('Tiers connecté : pas cette ligne', nb(r) === 0, nb(r));
    if (emetteur) {
      r = await clients[emetteur].rest(one);
      check('Émetteur (compte / cogérant) : sa ligne', nb(r) === 1, nb(r));
    }
    if (dest) {
      r = await clients[dest].rest(one);
      check('Destinataire : sa ligne', nb(r) === 1, nb(r));
    }
  }

  console.log('── Animal lié, sur les pages de signature (non connecté)');
  const tDoc = 'f14885b8-95ea-4845-8a25-b56eaf186b7a', animalDoc = '1786093435841';
  let r = await anon.rest(`documents_animaux?select=id,animaux(id)&token=eq.${tDoc}`, { 'x-pm-token': tDoc });
  const emb = r.status === 200 ? JSON.parse(r.body)[0]?.animaux : null;
  check('Contrat ouvert par lien : l\'animal s\'affiche', !!emb && emb.id === animalDoc, r.body.slice(0, 120));
  r = await anon.rest('animaux?select=id&reproducteur_public=not.is.true', { 'x-pm-token': tDoc });
  check('… et seul cet animal est visible avec ce lien', nb(r) === 1, nb(r));
  r = await anon.rest(`animaux?select=id&id=eq.${animalDoc}&reproducteur_public=not.is.true`);
  check('Sans lien : l\'animal n\'est pas visible', nb(r) === 0, nb(r));

  console.log(`\n${ok} OK / ${ko} KO`);
  process.exit(ko ? 1 : 0);
})().catch((e) => { console.error(e.message); process.exit(1); });
