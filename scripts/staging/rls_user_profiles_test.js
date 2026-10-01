// Tests RLS user_profiles + colonnes réservées + essai gratuit, sur le
// STAGING, par rôle, via la vraie API REST.
// Usage : node scripts/staging/rls_user_profiles_test.js
// Écritures sans relecture puis lecture via user_profiles_complet (comme
// l'appli depuis la phase 2 « données personnelles »).
// Réf. : supabase/migration_rls_user_profiles.sql
// ⚠ Modifie des profils du staging (valeurs remises en fin de test) et crée
//   puis supprime un profil « education » pour le propriétaire.
// ⚠ L'essai gratuit n'est accordé qu'UNE fois par compte et par type : la
//   ligne d'abonnement d'essai reste après le test. Avant de le relancer :
//   delete from abonnements where essai_gratuit and profil_type='education'
//     and uid='G59EC6CC61OUFQdVPMmw8e9Gp8v2';   (staging uniquement)
const { as } = require('./sb');

// ⚠ Natacha (YF9k…), le gérant (xoRH…) et PZlt… sont ADMINS : ne pas les
// utiliser comme « propriétaire » ou « tiers » ordinaires.
const PROPRIO = 'G59EC6CC61OUFQdVPMmw8e9Gp8v2';          // association, non admin
const PROPRIO_ASSO = '3d503027-fc07-4f07-b2e2-0acd62e693da';
const GERANT = 'xoRHVSob5uTWm3sbl6lKWFuIgKF2';
const GERANT_ELEVAGE = '47c2a0c7-6214-45cf-bd75-702cb0ebc8c3';   // profil de la cogérance
const GERANT_PARTICULIER = 'a8b353bd-a742-4620-951d-a4c4d8be37b0';
const GERANT_GARDE = '29481bc5-6d5f-469f-acf4-fb600c6c7f6e';
const COGERANT = '2n7PqKsfsjMNNVwGCGgkqd9SGJW2';
const TIERS = 'RIOWjkshiibFwwJpkSzf2P4kDKH2';   // non admin
const ADMIN = 'PZltNeW1M4cmEmOdRlbvOVmUNyB2';
const TS = Date.now();

let ok = 0, ko = 0;
function check(label, cond, r) {
  if (cond) ok++; else ko++;
  console.log(`${cond ? 'OK ' : 'KO '} ${label}${cond || !r ? '' : '  → ' + r.status + ' ' + r.body.slice(0, 160)}`);
}
const rows = (r) => (r.status >= 200 && r.status < 300 && r.body ? JSON.parse(r.body) : []);

(async () => {
  const own = await as(PROPRIO), cog = await as(COGERANT), tiers = await as(TIERS),
    admin = await as(ADMIN), anon = await as(null);

  const avant = rows(await own.rest(`user_profiles?select=description,plan_code,is_premium,statut_pro,is_influencer,is_validate&id=eq.${PROPRIO_ASSO}`))[0];
  check('Lecture publique d\'un profil (non connecté)', rows(await anon.rest(`user_profiles?select=id&id=eq.${PROPRIO_ASSO}`)).length === 1);

  console.log('── Modification');
  let r = await anon.updateVue('user_profiles', 'user_profiles_complet', `id=eq.${PROPRIO_ASSO}`, { description: 'anon' });
  check('Non connecté ne modifie pas un profil', rows(r).length === 0, r);
  r = await tiers.updateVue('user_profiles', 'user_profiles_complet', `id=eq.${PROPRIO_ASSO}`, { description: 'tiers' });
  check('Tiers ne modifie pas le profil du propriétaire', rows(r).length === 0, r);
  r = await own.updateVue('user_profiles', 'user_profiles_complet', `id=eq.${PROPRIO_ASSO}`, { description: `test ${TS}` });
  check('Le propriétaire modifie son profil', rows(r).length === 1 && rows(r)[0].description === `test ${TS}`, r);

  console.log('── Colonnes réservées (propriétaire non admin)');
  r = await own.updateVue('user_profiles', 'user_profiles_complet', `id=eq.${PROPRIO_ASSO}`,
    { plan_code: 'premium', is_premium: true, is_influencer: true, statut_pro: 'validated', rejection_reason: 'x' });
  const apres = rows(r)[0] || {};
  check('plan_code / is_premium inchangés', apres.plan_code === avant.plan_code && apres.is_premium === avant.is_premium, r);
  check('is_influencer inchangé', apres.is_influencer === avant.is_influencer, r);
  check('statut_pro inchangé (pas d\'auto-validation)', apres.statut_pro === avant.statut_pro, r);
  r = await own.updateVue('user_profiles', 'user_profiles_complet', `id=eq.${PROPRIO_ASSO}`, { statut_pro: 'en_attente' });
  check('Redemande de vérification (en_attente) permise', rows(r)[0]?.statut_pro === 'en_attente', r);

  console.log('── Admin');
  r = await admin.updateVue('user_profiles', 'user_profiles_complet', `id=eq.${PROPRIO_ASSO}`, { statut_pro: avant.statut_pro, description: avant.description });
  check('Admin remet le statut (validation)', rows(r)[0]?.statut_pro === avant.statut_pro, r);

  console.log('── Cogérant (profil élevage uniquement)');
  const descElevage = rows(await cog.rest(`user_profiles?select=description&id=eq.${GERANT_ELEVAGE}`))[0]?.description;
  r = await cog.updateVue('user_profiles', 'user_profiles_complet', `id=eq.${GERANT_ELEVAGE}`, { description: descElevage });
  check('Cogérant modifie l\'élevage de sa cogérance', rows(r).length === 1, r);
  r = await cog.updateVue('user_profiles', 'user_profiles_complet', `id=eq.${GERANT_PARTICULIER}`, { description: 'cogérant' });
  check('Cogérant ne modifie pas le profil particulier du gérant', rows(r).length === 0, r);
  r = await cog.updateVue('user_profiles', 'user_profiles_complet', `id=eq.${GERANT_GARDE}`, { description: 'cogérant' });
  check('Cogérant ne modifie pas le profil garde du gérant', rows(r).length === 0, r);

  console.log('── Création / essai gratuit / suppression');
  r = await anon.insertVue('user_profiles', 'user_profiles_complet', { uid: PROPRIO, profile_type: 'education' });
  check('Non connecté ne crée pas de profil', r.status >= 400, r);
  r = await tiers.insertVue('user_profiles', 'user_profiles_complet', { uid: PROPRIO, profile_type: 'education' });
  check('Tiers ne crée pas de profil pour un autre', r.status >= 400, r);
  r = await own.insertVue('user_profiles', 'user_profiles_complet', { uid: PROPRIO, profile_type: 'education', nom: `test ${TS}`, statut_pro: 'actif', plan_code: 'premium', is_validate: true });
  const cree = rows(r)[0];
  check('Le propriétaire crée son profil pro', !!cree, r);
  if (cree) {
    check('… statut forcé à en_attente / non validé', cree.statut_pro === 'en_attente' && cree.is_validate === false, r);
    const p = rows(await own.rest(`user_profiles?select=plan_code,is_premium,plan_until&id=eq.${cree.id}`))[0] || {};
    check(`… essai gratuit accordé (plan ${p.plan_code}, premium ${p.is_premium})`, p.plan_code === 'premium' && p.is_premium === true && !!p.plan_until);
    const ab = rows(await own.rest(`abonnements?select=id,essai_gratuit&profile_id=eq.${cree.id}`));
    check('… ligne d\'abonnement d\'essai créée', ab.length === 1 && ab[0].essai_gratuit === true);
    r = await tiers.delMin(`user_profiles?id=eq.${cree.id}`);
    check('Tiers ne supprime pas le profil du propriétaire', rows(r).length === 0, r);
    r = await own.delMin(`user_profiles?id=eq.${cree.id}`);
    check('Le propriétaire supprime son profil', rows(r).length === 1, r);
  }

  console.log(`\n${ok} OK / ${ko} KO`);
  process.exit(ko ? 1 : 0);
})().catch((e) => { console.error(e.message); process.exit(1); });
