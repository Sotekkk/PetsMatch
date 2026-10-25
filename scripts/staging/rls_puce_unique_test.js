// Puce unique + rattachement d'un 2e pro + confidentialité — staging, rôles réels.
// À lancer sur le STAGING seulement : crée une fiche de test « Rex-test-puce » (à supprimer ensuite par psql).
// A = Clinique Vétérinaire de la Marne (vétérinaire), B = Cabinet Ostéo Test (ostéo).
const path = './';
const { STAGING } = require(path + 'config');
const { idToken } = require(path + 'token');

const A = { uid: '6kmGQ4s7vNYokWGK3eT8VikbhWz2', pid: 'dc556c6c-d474-4b34-925d-57046b61caea' };
const B = { uid: 'xoRHVSob5uTWm3sbl6lKWFuIgKF2', pid: 'dd1babdd-84b9-4048-9d0c-c48f4968b982' };
const PUCE = '250 26 99999 000 42';
let ok = 0, ko = 0;
const verif = (titre, cond, detail = '') => { cond ? ok++ : ko++; console.log(`${cond ? 'OK  ' : 'ÉCHEC'} ${titre}${detail ? ' — ' + detail : ''}`); };

async function client(u) {
  const h = { apikey: STAGING.supabasePublishableKey, Authorization: 'Bearer ' + (await idToken(u.uid)), 'Content-Type': 'application/json' };
  const call = async (method, p, body, extra = {}) => {
    const r = await fetch(STAGING.supabaseUrl + '/rest/v1/' + p, { method, headers: { ...h, ...extra }, body: body ? JSON.stringify(body) : undefined });
    const t = await r.text();
    let j; try { j = JSON.parse(t); } catch { j = t; }
    return { status: r.status, body: j };
  };
  return {
    rpc: (f, args) => call('POST', 'rpc/' + f, args),
    get: p => call('GET', p),
    ins: (t, row) => call('POST', t, row, { Prefer: 'return=representation' }),
  };
}

(async () => {
  const a = await client(A), b = await client(B);
  // 1. A crée le patient (client sans appli).
  const cree = await a.rpc('pm_creer_patient_clinique', { p_clinique: A.pid, p_client_id: null,
    p_client: { nom: 'Martin', prenom: 'Paul' }, p_animal: { nom: 'Rex-test-puce', espece: 'chien', identification: PUCE } });
  verif('A crée le patient', cree.status === 200, JSON.stringify(cree.body).slice(0, 80));
  const id = cree.body;

  // 2. B recherche la puce (autre format d'écriture).
  const cherche = await b.rpc('pm_puce_existante', { p_identification: '250269999900042', p_profile: B.pid });
  const r0 = Array.isArray(cherche.body) ? cherche.body[0] : null;
  verif('B retrouve la fiche par la puce', r0 && r0.animal_id === id && r0.detenteur === 'pro' && !r0.a_vous && !r0.deja_lie, JSON.stringify(r0));

  // 3. B ne peut pas créer une 2e fiche.
  const doublon = await b.rpc('pm_creer_patient_clinique', { p_clinique: B.pid, p_client_id: null,
    p_client: { nom: 'Martin' }, p_animal: { nom: 'Rex bis', espece: 'chien', identification: PUCE } });
  verif('B ne peut pas créer une 2e fiche (même puce)', doublon.status >= 400 && /déjà enregistrée/.test(JSON.stringify(doublon.body)), JSON.stringify(doublon.body).slice(0, 90));

  // 4. A écrit dans le carnet et ajoute une radio.
  const vaccA = await a.ins('vaccinations', { animal_id: id, vaccin: 'CHPPiL (test)' });
  const radioA = await a.ins('radios', { id: 'test-radio-A-' + Date.now(), animal_id: id, vet_id: A.uid, titre: 'Radio A' });
  verif('A écrit dans le carnet et ajoute une radio', vaccA.status === 201 && radioA.status === 201, `${vaccA.status} ${radioA.status}`);

  // 5. B se rattache (identité seule) avec son propre client.
  const ratt = await b.rpc('pm_rattacher_fiche_pro', { p_profile: B.pid, p_animal: id, p_client_id: null, p_client: { nom: 'Martin', prenom: 'Paul' } });
  verif('B se rattache à la fiche', ratt.status === 200, JSON.stringify(ratt.body).slice(0, 80));

  // 6. Ce que voit B.
  const animalB = await b.get(`animaux?id=eq.${id}&select=id,nom,identification`);
  verif('B voit l\u2019identité de l\u2019animal', Array.isArray(animalB.body) && animalB.body.length === 1);
  const vaccB = await b.get(`vaccinations?animal_id=eq.${id}&select=id`);
  verif('B ne voit pas le carnet de A', Array.isArray(vaccB.body) && vaccB.body.length === 0, `${vaccB.body.length} ligne(s)`);
  const radioVueB = await b.get(`radios?animal_id=eq.${id}&select=id,titre`);
  verif('B ne voit pas la radio de A', Array.isArray(radioVueB.body) && radioVueB.body.length === 0, `${radioVueB.body.length} ligne(s)`);
  const vaccEcritB = await b.ins('vaccinations', { animal_id: id, vaccin: 'Vaccin écrit par B' });
  verif('B ne peut pas écrire dans le carnet (droit refusé)', vaccEcritB.status >= 400 && /row-level security|42501/.test(JSON.stringify(vaccEcritB.body)), JSON.stringify(vaccEcritB.body).slice(0, 90));
  const radioB = await b.ins('radios', { id: 'test-radio-B-' + Date.now(), animal_id: id, vet_id: B.uid, titre: 'Radio B' });
  const morphoB = await b.ins('suivis_morpho', { animal_id: id, uid_auteur: B.uid, pro_profile_id: B.pid, type_suivi: 'autre', source: 'professionnel' });
  verif('B écrit ses propres documents (radio, séance)', radioB.status === 201 && morphoB.status === 201, `${radioB.status} ${morphoB.status} ${JSON.stringify(morphoB.body).slice(0, 80)}`);
  const sesDocs = await b.get(`radios?animal_id=eq.${id}&select=titre`);
  verif('B relit ses documents', Array.isArray(sesDocs.body) && sesDocs.body.length === 1 && sesDocs.body[0].titre === 'Radio B', JSON.stringify(sesDocs.body));

  // 7. Ce que voit A.
  const radiosA = await a.get(`radios?animal_id=eq.${id}&select=titre`);
  verif('A ne voit pas la radio de B', Array.isArray(radiosA.body) && radiosA.body.length === 1 && radiosA.body[0].titre === 'Radio A', JSON.stringify(radiosA.body));
  const morphoA = await a.get(`suivis_morpho?animal_id=eq.${id}&select=id`);
  verif('A ne voit pas la séance de B', Array.isArray(morphoA.body) && morphoA.body.length === 0, `${morphoA.body.length} ligne(s)`);
  const accesA = await a.get(`animal_access?animal_id=eq.${id}&select=pro_profile_id,statut`);
  verif('A ne voit pas que B est rattaché', Array.isArray(accesA.body) && accesA.body.every(x => x.pro_profile_id !== B.pid), JSON.stringify(accesA.body));
  const vaccVueA = await a.get(`vaccinations?animal_id=eq.${id}&select=vaccin`);
  verif('A garde son carnet', Array.isArray(vaccVueA.body) && vaccVueA.body.length === 1, JSON.stringify(vaccVueA.body));

  // 8. Un particulier tiers ne voit rien.
  const tiers = await client({ uid: 'G59EC6CC61OUFQdVPMmw8e9Gp8v2' });
  const vueTiers = await tiers.get(`animaux?id=eq.${id}&select=id`);
  verif('Un autre compte ne voit pas la fiche', Array.isArray(vueTiers.body) && vueTiers.body.length === 0, JSON.stringify(vueTiers.body));

  console.log(`\n${ok} OK, ${ko} échec(s) — animal de test : ${id}`);
})();
