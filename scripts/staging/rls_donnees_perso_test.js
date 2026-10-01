// Tests du masquage des données personnelles (users_complet /
// user_profiles_complet) et de pm_trouver_utilisateur, sur le STAGING.
// Usage : PM_EMAIL_TEST=<e-mail de G59E…> node scripts/staging/rls_donnees_perso_test.js
//   (l'e-mail n'est jamais affiché ; lu en base par le script appelant)
// Réf. : supabase/migration_donnees_perso_vues.sql
const { as } = require('./sb');

// ⚠ NAT et XORH sont ADMINS : ils ne servent ici qu'à des lectures « publiques »
// ou comme cible ; les tests de relation utilisent des lecteurs non admins.
const NAT = 'YF9kR7jSTObnnw9lVj8gCl031rS2';      // éleveuse (compte pro), admin
const NAT_ELEVAGE = '732eb61b-915a-4f81-81c4-27905a63e40c';
const RIOW = 'RIOWjkshiibFwwJpkSzf2P4kDKH2';     // employé de Natacha, non admin
const G59E = 'G59EC6CC61OUFQdVPMmw8e9Gp8v2';     // non admin, sans lien avec RIOW
const XORH = 'xoRHVSob5uTWm3sbl6lKWFuIgKF2';     // cédant (cession → WQvZ), client du pro 6kmG
const XORH_PARTICULIER = 'a8b353bd-a742-4620-951d-a4c4d8be37b0';
const WQVZ = 'WQvZxEM9KDdhtSi34tkUgVvZh5d2';     // acquéreur d'une cession de xoRH, employeur de RIOW, non admin
const PRO_6KMG = '6kmGQ4s7vNYokWGK3eT8VikbhWz2'; // pro dont xoRH est client
const CESSION_TOKEN = 'bf3dbfc1-034d-490c-9023-dfa03561c98b';
const EMAIL_G59E = process.env.PM_EMAIL_TEST || '';

let ok = 0, ko = 0;
function check(label, cond, detail = '') {
  if (cond) ok++; else ko++;
  console.log(`${cond ? 'OK ' : 'KO '} ${label}${cond ? '' : '  → ' + detail}`);
}
const one = async (c, q, h) => {
  const r = await c.rest(q, h);
  if (r.status !== 200) return { _err: `${r.status} ${r.body.slice(0, 120)}` };
  return JSON.parse(r.body)[0] || null;
};
const vu = (row, col) => row && !row._err && row[col] !== null && row[col] !== undefined;

(async () => {
  const anon = await as(null), riow = await as(RIOW), g59e = await as(G59E),
    xorh = await as(XORH), wqvz = await as(WQVZ), pro = await as(PRO_6KMG), nat = await as(NAT);
  const u = (uid) => `users_complet?select=uid,email,date_of_birth,phone_number,adress,lat,firstname&uid=eq.${uid}`;

  console.log('── Non connecté');
  let r = await one(anon, u(G59E));
  check('lit la fiche publique (prénom)', vu(r, 'firstname'), JSON.stringify(r));
  check('… sans e-mail ni date de naissance', !vu(r, 'email') && !vu(r, 'date_of_birth'), JSON.stringify(r));
  r = await one(anon, u(NAT));
  check('compte PRO : téléphone et adresse publics', vu(r, 'phone_number') || vu(r, 'adress'), JSON.stringify(r));
  check('compte PRO : e-mail de connexion masqué', !vu(r, 'email'), JSON.stringify(r));
  r = await one(anon, `user_profiles_complet?select=id,rue,lat,date_of_birth,nom&id=eq.${XORH_PARTICULIER}`);
  check('profil particulier : adresse / GPS / naissance masqués', r && !vu(r, 'rue') && !vu(r, 'lat') && !vu(r, 'date_of_birth'), JSON.stringify(r));
  r = await one(anon, `user_profiles_complet?select=id,phone,adresse,date_of_birth&id=eq.${NAT_ELEVAGE}`);
  check('profil élevage : contact public, naissance masquée', (vu(r, 'phone') || vu(r, 'adresse')) && !vu(r, 'date_of_birth'), JSON.stringify(r));

  console.log('── Titulaire / tiers');
  r = await one(g59e, u(G59E));
  check('le titulaire voit son e-mail', vu(r, 'email'), JSON.stringify(r).slice(0, 80));
  r = await one(riow, u(G59E));
  check('un tiers ne voit pas l\'e-mail', !vu(r, 'email'), JSON.stringify(r));

  console.log('── Relations légitimes');
  r = await one(wqvz, u(RIOW));
  check('employeur (non admin) → e-mail de son employé', vu(r, 'email'), JSON.stringify(r).slice(0, 80));
  r = await one(riow, u(NAT));
  check('employé → e-mail de son employeuse', vu(r, 'email'), JSON.stringify(r).slice(0, 80));
  r = await one(wqvz, u(XORH));
  check('acquéreur → coordonnées du cédant', vu(r, 'email'), JSON.stringify(r).slice(0, 80));
  r = await one(g59e, u(WQVZ));
  check('tiers (non admin) → pas l\'e-mail de l\'acquéreur', !vu(r, 'email'), JSON.stringify(r));
  r = await one(pro, u(XORH));
  check('pro → coordonnées de son client (RDV)', vu(r, 'email'), JSON.stringify(r).slice(0, 80));
  r = await one(anon, u(XORH), { 'x-pm-token': CESSION_TOKEN });
  check('lien de signature de cession → coordonnées du cédant', vu(r, 'email'), JSON.stringify(r).slice(0, 80));
  r = await one(anon, u(G59E), { 'x-pm-token': CESSION_TOKEN });
  check('… mais pas celles d\'un autre', !vu(r, 'email'), JSON.stringify(r));

  console.log('── Recherche par e-mail exact (pm_trouver_utilisateur)');
  const rpc = async (c, body) => {
    const res = await fetch('https://ozftswznayxzrbcfmher.supabase.co/rest/v1/rpc/pm_trouver_utilisateur', {
      method: 'POST',
      headers: { apikey: 'sb_publishable_I63yWhGMxKQZQAiEsYIP3Q_UR6DiIdv', 'Content-Type': 'application/json',
        ...(c ? { Authorization: 'Bearer ' + c } : {}) },
      body: JSON.stringify(body) });
    return res.status === 200 ? await res.json() : `HTTP ${res.status}`;
  };
  const { idToken } = require('./token');
  const tRiow = await idToken(RIOW);
  if (EMAIL_G59E) {
    let x = await rpc(tRiow, { p_email: EMAIL_G59E.toUpperCase() });
    check('e-mail exact (casse indifférente) → 1 résultat', Array.isArray(x) && x.length === 1 && x[0].uid === G59E, JSON.stringify(x).slice(0, 80));
    check('… sans renvoyer d\'e-mail ni de téléphone', Array.isArray(x) && x[0] && !('email' in x[0]) && !('phone_number' in x[0]), Object.keys(x[0] || {}).join(','));
    x = await rpc(tRiow, { p_email: EMAIL_G59E.slice(0, 4) });
    check('e-mail partiel → aucun résultat', Array.isArray(x) && x.length === 0, JSON.stringify(x).slice(0, 80));
    x = await rpc(null, { p_email: EMAIL_G59E });
    check('non connecté → aucun résultat', Array.isArray(x) && x.length === 0, JSON.stringify(x).slice(0, 80));
  } else {
    console.log('--  PM_EMAIL_TEST absent : recherche par e-mail non testée');
  }

  console.log(`\n${ok} OK / ${ko} KO`);
  process.exit(ko ? 1 : 0);
})().catch((e) => { console.error(e.message); process.exit(1); });
