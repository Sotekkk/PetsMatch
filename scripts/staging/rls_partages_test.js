// Tests RLS des partages par lien (en-tête x-pm-token) + bloquages /
// likes, sur le STAGING. Prérequis : fixtures_partages.sql (action=creer).
// Usage : node scripts/staging/rls_partages_test.js
// Réf. : supabase/migration_rls_partages_liens.sql
const { as } = require('./sb');

const ANIMAL = 'XNH3Bl3ZqpfWB5yShw1e';        // 14 vaccinations, propriétaire xoRH…
const ALBUM = '00000000-0000-4000-8000-00000000a1b0';
const OWNER = 'xoRHVSob5uTWm3sbl6lKWFuIgKF2';
const RIOW = 'RIOWjkshiibFwwJpkSzf2P4kDKH2';   // non admin
const G59E = 'G59EC6CC61OUFQdVPMmw8e9Gp8v2';   // non admin
const COG = '2n7PqKsfsjMNNVwGCGgkqd9SGJW2';    // non admin, sans lien ici
const T = {
  vet: 'tok_vet_test_rls', vetExpire: 'tok_vet_expire_test_rls',
  album: 'tok_album_test_rls', albumExpire: 'tok_album_expire_test_rls',
  suivi: 'tok_suivi_test_rls', claim: 'tok_claim_test_rls',
  partage: '11111111-1111-4111-8111-111111111111',
};

let ok = 0, ko = 0;
function check(label, cond, detail) {
  if (cond) ok++; else ko++;
  console.log(`${cond ? 'OK ' : 'KO '} ${label}${cond ? '' : '  → ' + detail}`);
}
const nb = (r) => (r.status >= 200 && r.status < 300 ? (r.body ? JSON.parse(r.body).length : 0) : `HTTP ${r.status} ${r.body.slice(0, 120)}`);
const H = (t) => ({ 'x-pm-token': t });

(async () => {
  const anon = await as(null), riow = await as(RIOW), g59e = await as(G59E), cog = await as(COG);

  console.log('── Accès vétérinaire (partage_tokens → carnet de santé)');
  check('Non connecté : ne liste aucun token', nb(await anon.rest('partage_tokens?select=token')) === 0, '');
  check('Tiers connecté : ne voit pas les tokens d\'un autre', nb(await g59e.rest(`partage_tokens?select=token&owner_id=eq.${OWNER}`)) === 0, '');
  let r = await anon.rest('partage_tokens?select=id,animal_id', H(T.vet));
  check('Avec le lien : son accès (et lui seul)', nb(r) === 1, nb(r));
  r = await anon.rest(`vaccinations?select=id&animal_id=eq.${ANIMAL}`);
  check('Santé sans lien : rien', nb(r) === 0, nb(r));
  r = await anon.rest(`vaccinations?select=id&animal_id=eq.${ANIMAL}`, H(T.vet));
  check(`Santé avec le lien vétérinaire : visible (${nb(r)})`, nb(r) > 0, nb(r));
  r = await anon.rest('vaccinations?select=animal_id', H(T.vet));
  check('… uniquement pour CET animal', r.status === 200 && JSON.parse(r.body).every((x) => x.animal_id === ANIMAL), nb(r));
  r = await anon.rest(`vaccinations?select=id&animal_id=eq.${ANIMAL}`, H(T.vetExpire));
  check('Lien vétérinaire EXPIRÉ : rien', nb(r) === 0, nb(r));
  r = await anon.rest(`animaux?select=id&id=eq.${ANIMAL}`, H(T.vet));
  check('Animal visible avec le lien vétérinaire', nb(r) === 1, nb(r));
  r = await riow.update('partage_tokens?token=eq.tok_vet_test_rls', { used_at: new Date().toISOString() });
  check('Sans l\'en-tête : ne peut pas marquer le token', nb(r) === 0, nb(r));

  console.log('── Album partagé');
  check('Non connecté : ne liste aucun partage d\'album', nb(await anon.rest('album_partage?select=token')) === 0, '');
  r = await anon.rest('album_partage?select=album_id', H(T.album));
  check('Avec le lien : son partage', nb(r) === 1, nb(r));
  r = await anon.rest(`album_photos?select=id&album_id=eq.${ALBUM}`, H(T.album));
  check('Photos de l\'album visibles avec le lien', nb(r) === 1, nb(r));
  r = await anon.rest(`albums_photo?select=id&id=eq.${ALBUM}`, H(T.album));
  check('Album visible avec le lien', nb(r) === 1, nb(r));
  r = await anon.rest(`album_photos?select=id&album_id=eq.${ALBUM}`, H(T.albumExpire));
  check('Lien d\'album EXPIRÉ : rien', nb(r) === 0, nb(r));
  r = await anon.rest(`album_photos?select=id&album_id=eq.${ALBUM}`);
  check('Sans lien : rien (avant : tout album partagé était public)', nb(r) === 0, nb(r));
  r = await riow.rest(`albums_photo?select=id&id=eq.${ALBUM}`);
  check('Connecté sans lien, ni pro ni client : rien', nb(r) === 0, nb(r));
  r = await g59e.rest(`album_photos?select=id&album_id=eq.${ALBUM}`);
  check('Le pro de l\'album voit ses photos', nb(r) === 1, nb(r));

  console.log('── Suivi d\'éducation partagé');
  r = await anon.rest(`education_objectifs?select=id&animal_id=eq.${ANIMAL}`, H(T.suivi));
  check('Objectifs visibles avec le lien', nb(r) === 1, nb(r));
  r = await anon.rest(`education_objectifs?select=id&animal_id=eq.${ANIMAL}`);
  check('Sans lien : rien', nb(r) === 0, nb(r));
  r = await anon.rest(`vaccinations?select=id&animal_id=eq.${ANIMAL}`, H(T.suivi));
  check('Le lien de suivi n\'ouvre PAS le carnet de santé', nb(r) === 0, nb(r));

  console.log('── Partage d\'animal / réclamation');
  r = await anon.rest(`animaux?select=id&id=eq.${ANIMAL}`, H(T.partage));
  check('Animal visible avec le lien de partage', nb(r) === 1, nb(r));
  check('Non connecté : ne liste aucune réclamation', nb(await anon.rest('animal_claims?select=token')) === 0, '');
  r = await anon.rest('animal_claims?select=id', H(T.claim));
  check('Avec le lien : sa réclamation', nb(r) === 1, nb(r));
  r = await anon.update('animal_claims?token=eq.tok_claim_test_rls', { statut: 'reclame' });
  check('Non connecté ne peut pas réclamer', nb(r) === 0 || r.status >= 400, nb(r));
  r = await g59e.update('animal_claims?token=eq.tok_claim_test_rls', { statut: 'reclame', claimed_by_uid: RIOW });
  check('Réclamer au nom d\'un autre : refusé', nb(r) === 0 || r.status >= 400, nb(r));

  console.log('── Blocages / likes');
  r = await riow.insert('bloquages', { uid: RIOW, blocked_uid: G59E });
  check('Bloquer quelqu\'un', nb(r) === 1, nb(r));
  check('Le bloqué voit qu\'il l\'est', nb(await g59e.rest(`bloquages?select=id&uid=eq.${RIOW}`)) === 1, '');
  check('Un tiers ne voit pas le blocage', nb(await cog.rest(`bloquages?select=id&uid=eq.${RIOW}`)) === 0, '');
  check('Non connecté ne voit aucun blocage', nb(await anon.rest('bloquages?select=id')) === 0, '');
  r = await g59e.insert('bloquages', { uid: RIOW, blocked_uid: COG });
  check('Bloquer au nom d\'un autre : refusé', r.status >= 400, nb(r));
  r = await riow.del(`bloquages?uid=eq.${RIOW}&blocked_uid=eq.${G59E}`);
  check('Débloquer', nb(r) === 1, nb(r));
  r = await anon.insertMin('likes', { user_uid: RIOW, annonce_id: 'x', bebe_index: 0 });
  check('Non connecté ne peut pas liker', r.status >= 400, r.status);
  r = await g59e.insertMin('likes', { user_uid: RIOW, annonce_id: 'x', bebe_index: 0 });
  check('Liker au nom d\'un autre : refusé', r.status >= 400, r.status);

  console.log(`\n${ok} OK / ${ko} KO`);
  process.exit(ko ? 1 : 0);
})().catch((e) => { console.error(e.message); process.exit(1); });
