// Tests RLS agenda_events / rdv / notifications / registre_mouvements sur
// le STAGING, par rôle, via la vraie API REST.
// Usage : node scripts/staging/rls_agenda_rdv_test.js
// Les lignes créées portent le marqueur « test_rls » ; ménage ensuite :
//   delete from agenda_events where titre like 'test_rls%';
//   delete from notifications where title like 'test_rls%';
//   delete from registre_mouvements where notes like 'test_rls%';
// Réf. : supabase/migration_rls_agenda_rdv_notifs_registre.sql
const { as } = require('./sb');

const NAT = 'YF9kR7jSTObnnw9lVj8gCl031rS2';
const NAT_ELEVAGE = '732eb61b-915a-4f81-81c4-27905a63e40c';
const NAT_ASSO = '33ce0cdf-8e06-4a0c-ac4a-43bdf07dc65c';
const EMP_DROITS = 'IfhRVwY55KUXW12lBG4D0bs0V383';   // employé élevage, write_sante/repro/animaux…
const EMP_SANS = 'RIOWjkshiibFwwJpkSzf2P4kDKH2';     // employé élevage sans droit
const GERANT = 'xoRHVSob5uTWm3sbl6lKWFuIgKF2';
const GERANT_ELEVAGE = '47c2a0c7-6214-45cf-bd75-702cb0ebc8c3';
const GERANT_PARTICULIER = 'a8b353bd-a742-4620-951d-a4c4d8be37b0';
const COGERANT = '2n7PqKsfsjMNNVwGCGgkqd9SGJW2';
const PRO = '6kmGQ4s7vNYokWGK3eT8VikbhWz2';          // pro d'un RDV dont GERANT est client
const RDV = '387a0912-c993-40b4-9a7d-79da9b2912d5';
const TIERS = 'G59EC6CC61OUFQdVPMmw8e9Gp8v2';
const CESSION_ANIMAL = '1786093435841';               // cédant GERANT → acquéreur ACQ
const ACQ = 'WQvZxEM9KDdhtSi34tkUgVvZh5d2';
const TS = Date.now();

let ok = 0, ko = 0;
function check(label, cond, r) {
  if (cond) ok++; else ko++;
  console.log(`${cond ? 'OK ' : 'KO '} ${label}${cond || !r ? '' : '  → ' + r.status + ' ' + r.body.slice(0, 160)}`);
}
const rows = (r) => (r.status >= 200 && r.status < 300 && r.body ? JSON.parse(r.body) : []);
const n = async (c, q) => rows(await c.rest(q)).length;

(async () => {
  const [nat, empD, empS, cog, gerant, pro, tiers, acq, anon] = await Promise.all(
    [NAT, EMP_DROITS, EMP_SANS, COGERANT, GERANT, PRO, TIERS, ACQ, null].map(as));

  console.log('── Agenda (lecture, scoping par profil)');
  const qEl = `agenda_events?select=id&uid=eq.${NAT}&pro_profile_id=eq.${NAT_ELEVAGE}`;
  const qAs = `agenda_events?select=id&uid=eq.${NAT}&pro_profile_id=eq.${NAT_ASSO}`;
  const nbEl = await n(nat, qEl);
  check(`Natacha voit son agenda élevage (${nbEl})`, nbEl > 0);
  check('Employé élevage (sans droit) voit l\'agenda élevage', (await n(empS, qEl)) === nbEl);
  check('Employé élevage ne voit PAS l\'agenda association', (await n(empS, qAs)) === 0);
  check('Tiers ne voit pas l\'agenda de Natacha', (await n(tiers, qEl)) === 0);
  check('Non connecté ne voit aucun agenda', (await n(anon, 'agenda_events?select=id&limit=5')) === 0);

  console.log('── Agenda (écriture)');
  let r = await empD.insert('agenda_events', { uid: NAT, titre: `test_rls ${TS}`, type: 'autre', date_debut: new Date().toISOString(), pro_profile_id: NAT_ELEVAGE });
  check('Employé ajoute un événement à l\'agenda élevage', rows(r).length === 1, r);
  r = await empD.insert('agenda_events', { uid: NAT, titre: `test_rls ${TS}`, type: 'autre', date_debut: new Date().toISOString(), pro_profile_id: NAT_ASSO });
  check('Employé élevage n\'écrit pas dans l\'agenda association', r.status >= 400, r);
  r = await tiers.insert('agenda_events', { uid: NAT, titre: `test_rls ${TS}`, type: 'autre', date_debut: new Date().toISOString() });
  check('Tiers n\'écrit pas dans l\'agenda de Natacha', r.status >= 400, r);
  r = await cog.insert('agenda_events', { uid: GERANT, titre: `test_rls ${TS}`, type: 'autre', date_debut: new Date().toISOString(), pro_profile_id: GERANT_ELEVAGE });
  check('Cogérant écrit dans l\'agenda élevage du gérant', rows(r).length === 1, r);
  r = await cog.insert('agenda_events', { uid: GERANT, titre: `test_rls ${TS}`, type: 'autre', date_debut: new Date().toISOString(), pro_profile_id: GERANT_PARTICULIER });
  check('Cogérant n\'écrit pas dans l\'agenda particulier du gérant', r.status >= 400, r);
  r = await nat.insert('agenda_events', { uid: NAT, titre: `test_rls ${TS} perso`, type: 'autre', date_debut: new Date().toISOString(), pro_profile_id: NAT_ELEVAGE });
  const evNat = rows(r)[0];
  r = await tiers.del(`agenda_events?id=eq.${evNat?.id}`);
  check('Tiers ne supprime pas un événement de Natacha', rows(r).length === 0, r);

  console.log('── RDV');
  check('Client voit son RDV', (await n(gerant, `rdv?select=id&id=eq.${RDV}`)) === 1);
  check('Pro voit le RDV', (await n(pro, `rdv?select=id&id=eq.${RDV}`)) === 1);
  check('Tiers ne voit pas le RDV', (await n(tiers, `rdv?select=id&id=eq.${RDV}`)) === 0);
  check('Non connecté ne voit aucun RDV', (await n(anon, 'rdv?select=id&limit=5')) === 0);
  r = await tiers.update(`rdv?id=eq.${RDV}`, { notes_client: 'piraté' });
  check('Tiers ne modifie pas le RDV', rows(r).length === 0, r);
  r = await pro.insert('agenda_events', { uid: PRO, titre: `test_rls ${TS} rdv`, type: 'rdv', date_debut: new Date().toISOString(), couleur: `rdv:${RDV}` });
  const evRdv = rows(r)[0];
  check('Pro crée l\'événement lié au RDV', !!evRdv, r);
  r = await tiers.del(`agenda_events?id=eq.${evRdv?.id}`);
  check('Tiers ne supprime pas l\'événement du pro', rows(r).length === 0, r);
  r = await gerant.del(`agenda_events?id=eq.${evRdv?.id}`);
  check('Le client supprime l\'événement du pro lié à SON RDV (annulation)', rows(r).length === 1, r);

  console.log('── Notifications');
  check('Natacha lit ses notifications', (await n(nat, `notifications?select=id&uid=eq.${NAT}&limit=5`)) > 0);
  check('Tiers ne lit pas celles de Natacha', (await n(tiers, `notifications?select=id&uid=eq.${NAT}&limit=5`)) === 0);
  check('Non connecté ne lit aucune notification', (await n(anon, 'notifications?select=id&limit=5')) === 0);
  r = await tiers.insertMin('notifications', { uid: NAT, title: `test_rls ${TS}`, body: 'test', type: 'test', read: false });
  check('Connecté : notifie un autre utilisateur', r.status >= 200 && r.status < 300, r);
  r = await anon.insertMin('notifications', { uid: NAT, title: `test_rls ${TS}`, body: 'test', type: 'test', read: false });
  check('Non connecté : ne peut pas notifier', r.status >= 400, r);

  console.log('── Registre des mouvements');
  const qReg = `registre_mouvements?select=id&uid_eleveur=eq.${NAT}`;
  const nbReg = await n(nat, qReg);
  check(`Natacha lit son registre (${nbReg})`, nbReg > 0);
  check('Employé sans droit lit le registre', (await n(empS, qReg)) === nbReg);
  check('Tiers ne lit pas le registre', (await n(tiers, qReg)) === 0);
  check('Non connecté ne lit aucun registre', (await n(anon, 'registre_mouvements?select=id&limit=5')) === 0);
  const ligne = (uid, extra) => ({ animal_id: `test_${TS}`, uid_eleveur: uid, type: 'entree', date_mouvement: new Date().toISOString().slice(0, 10), notes: `test_rls ${TS}`, ...extra });
  r = await empD.insert('registre_mouvements', ligne(NAT, { eleveur_profile_id: NAT_ELEVAGE, motif: 'naissance' }));
  check('Employé AVEC droit écrit au registre', rows(r).length === 1, r);
  r = await empS.insert('registre_mouvements', ligne(NAT, { eleveur_profile_id: NAT_ELEVAGE, motif: 'naissance' }));
  check('Employé SANS droit n\'écrit pas au registre', r.status >= 400, r);
  r = await tiers.insert('registre_mouvements', ligne(NAT, { motif: 'naissance' }));
  check('Tiers n\'écrit pas au registre de Natacha', r.status >= 400, r);

  console.log('── Registre : cession (la partie qui finalise écrit les 2 lignes)');
  const cess = (uid, type, motif = 'cession') => ({ animal_id: CESSION_ANIMAL, uid_eleveur: uid, type, motif, date_mouvement: new Date().toISOString().slice(0, 10), notes: `test_rls ${TS}` });
  r = await acq.insert('registre_mouvements', cess(GERANT, 'sortie'));
  check('Acquéreur écrit la sortie du cédant', rows(r).length === 1, r);
  r = await acq.insert('registre_mouvements', cess(ACQ, 'entree'));
  check('Acquéreur écrit sa propre entrée', rows(r).length === 1, r);
  r = await gerant.insert('registre_mouvements', cess(ACQ, 'entree'));
  check('Cédant écrit l\'entrée de l\'acquéreur', rows(r).length === 1, r);
  r = await acq.insert('registre_mouvements', cess(GERANT, 'sortie', 'autre'));
  check('Acquéreur n\'écrit pas un autre motif chez le cédant', r.status >= 400, r);
  r = await tiers.insert('registre_mouvements', cess(GERANT, 'sortie'));
  check('Tiers ne peut pas inventer une cession', r.status >= 400, r);
  r = await acq.insert('registre_mouvements', cess(NAT, 'entree'));
  check('Partie de la cession n\'écrit pas chez un tiers', r.status >= 400, r);

  console.log(`\n${ok} OK / ${ko} KO`);
  process.exit(ko ? 1 : 0);
})().catch((e) => { console.error(e.message); process.exit(1); });
