// Tests RLS groupe 5c (partie 1) sur le STAGING : journal d'activité,
// signalements, stats d'annonces, inscriptions aux événements, discussion
// de promenade, groupes privés.
// Prérequis : fixtures_donnees_privees.sql (action=creer).
// Usage : node scripts/staging/rls_donnees_privees_test.js
// Réf. : supabase/migration_rls_donnees_privees.sql
const { as } = require('./sb');

const XORH = 'xoRHVSob5uTWm3sbl6lKWFuIgKF2';   // a une activité, organise la promenade, propriétaire de l'annonce
const NAT = 'YF9kR7jSTObnnw9lVj8gCl031rS2';    // créatrice de l'événement
const RIOW = 'RIOWjkshiibFwwJpkSzf2P4kDKH2';   // participant accepté de la promenade, membre du groupe privé
const G59E = 'G59EC6CC61OUFQdVPMmw8e9Gp8v2';   // créateur du groupe privé ; tiers ailleurs
const COG = '2n7PqKsfsjMNNVwGCGgkqd9SGJW2';    // cogérant de xoRH ; tiers pour le groupe
const ANNONCE = '984d05b9-e8ca-4f58-9e5e-5c44dade40e4';
const EVENEMENT = 'ba2c339d-51e8-4ca5-b3af-4b0b31ceebfc';
const PROMENADE = '10568176-6ade-4c32-bc95-dd3fa37aff18';
const GRP_PRIVE = '00000000-0000-4000-8000-0000000c5a01';
const POST_PRIVE = '00000000-0000-4000-8000-0000000c5a02';
const GRP_PUBLIC = '6959faa8-3e6e-4e5f-8c27-f00ca9f90ebe';

let ok = 0, ko = 0;
function check(label, cond, detail) {
  if (cond) ok++; else ko++;
  console.log(`${cond ? 'OK ' : 'KO '} ${label}${cond ? '' : '  → ' + detail}`);
}
const nb = (r) => (r.status >= 200 && r.status < 300 ? (r.body ? JSON.parse(r.body).length : 0) : `HTTP ${r.status} ${r.body.slice(0, 120)}`);

(async () => {
  const [xorh, nat, riow, g59e, cog, anon] = await Promise.all([XORH, NAT, RIOW, G59E, COG, null].map(as));

  console.log('── Journal d\'activité');
  check('Le titulaire voit son activité', nb(await xorh.rest(`activity_log?select=id&uid=eq.${XORH}`)) > 0, '');
  check('Un tiers ne la voit pas', nb(await riow.rest(`activity_log?select=id&uid=eq.${XORH}`)) === 0, '');
  check('Non connecté : rien', nb(await anon.rest('activity_log?select=id&limit=5')) === 0, '');
  let r = await riow.insertMin('activity_log', { uid: XORH, activity_type: 'balade', xp_earned: 999 });
  check('Ajouter de l\'activité au nom d\'un autre : refusé', r.status >= 400, r.status);

  console.log('── Signalements de conversations');
  check('L\'auteur voit son signalement', nb(await riow.rest("conversation_reports?select=id&reason=eq.test_rls")) === 1, '');
  check('Un tiers ne le voit pas', nb(await g59e.rest("conversation_reports?select=id&reason=eq.test_rls")) === 0, '');
  check('Non connecté : rien', nb(await anon.rest('conversation_reports?select=id')) === 0, '');
  r = await anon.insertMin('conversation_reports', { conversation_id: 'x', reported_by_uid: 'x', reason: 'test_rls' });
  check('Signaler sans compte : refusé', r.status >= 400, r.status);

  console.log('── Statistiques d\'annonces');
  check('Le cogérant du propriétaire voit les stats', nb(await cog.rest(`annonces_stats_daily?select=id&annonce_id=eq.${ANNONCE}`)) > 0, '');
  check('Un tiers ne les voit pas', nb(await riow.rest(`annonces_stats_daily?select=id&annonce_id=eq.${ANNONCE}`)) === 0, '');
  check('Non connecté : rien', nb(await anon.rest('annonces_stats_daily?select=id&limit=5')) === 0, '');

  console.log('── Inscriptions aux événements');
  check('L\'inscrit voit son inscription', nb(await xorh.rest(`evenements_inscrits?select=user_uid&evenement_id=eq.${EVENEMENT}&user_uid=eq.${XORH}`)) === 1, '');
  check('La créatrice de l\'événement voit tous les inscrits', nb(await nat.rest(`evenements_inscrits?select=user_uid&evenement_id=eq.${EVENEMENT}`)) >= 2, '');
  check('Un tiers ne voit pas les inscrits', nb(await riow.rest(`evenements_inscrits?select=user_uid&evenement_id=eq.${EVENEMENT}`)) === 0, '');

  console.log('── Discussion de promenade');
  const qMsg = `promenades_messages?select=id&promenade_id=eq.${PROMENADE}`;
  check('Un participant accepté lit la discussion', nb(await riow.rest(qMsg)) > 0, '');
  check('L\'organisateur lit la discussion', nb(await xorh.rest(qMsg)) > 0, '');
  check('Un tiers ne la lit pas', nb(await g59e.rest(qMsg)) === 0, '');
  r = await g59e.insertMin('promenades_messages', { promenade_id: PROMENADE, user_uid: G59E, message: 'test_rls' });
  check('Un tiers ne peut pas y écrire', r.status >= 400, r.status);
  r = await riow.insertMin('promenades_messages', { promenade_id: PROMENADE, user_uid: RIOW, message: 'test_rls' });
  check('Un participant y écrit', r.status >= 200 && r.status < 300, `${r.status} ${r.body.slice(0, 100)}`);

  console.log('── Groupes');
  check('Groupe public : publications visibles sans compte', nb(await anon.rest(`groupe_posts?select=id&groupe_id=eq.${GRP_PUBLIC}`)) > 0, '');
  check('Groupe privé : le groupe reste trouvable', nb(await cog.rest(`groupes?select=id&id=eq.${GRP_PRIVE}`)) === 1, '');
  check('Groupe privé : un membre voit les publications', nb(await riow.rest(`groupe_posts?select=id&groupe_id=eq.${GRP_PRIVE}`)) === 1, '');
  check('Groupe privé : le créateur les voit', nb(await g59e.rest(`groupe_posts?select=id&groupe_id=eq.${GRP_PRIVE}`)) === 1, '');
  check('Groupe privé : un non-membre ne les voit pas', nb(await cog.rest(`groupe_posts?select=id&groupe_id=eq.${GRP_PRIVE}`)) === 0, '');
  check('Groupe privé : non connecté ne les voit pas', nb(await anon.rest(`groupe_posts?select=id&groupe_id=eq.${GRP_PRIVE}`)) === 0, '');
  check('Groupe privé : commentaires cachés aux non-membres', nb(await cog.rest(`groupe_post_commentaires?select=id&post_id=eq.${POST_PRIVE}`)) === 0, '');
  check('Groupe privé : un membre voit les commentaires', nb(await riow.rest(`groupe_post_commentaires?select=id&post_id=eq.${POST_PRIVE}`)) === 1, '');

  console.log(`\n${ok} OK / ${ko} KO`);
  process.exit(ko ? 1 : 0);
})().catch((e) => { console.error(e.message); process.exit(1); });
