// Scénarios du cahier des charges Alimentation (§14) — mêmes valeurs
// attendues que test/plan_alimentation_test.dart (appli).
// Lancer : node --experimental-strip-types scripts/plan-alimentation.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  calculerRation, evaluerEnergie, erreurEtape, lireNombre, revenirRecommandation, estPersonnalise,
  ecartImportant, planDepuisLigne, planVersJson, calculEnregistre, nomAliment, detecterReproduction, erreursHoraires,
  kcalDe, REPARTITION_MENAGERE, retirerAliment,
} from '../src/lib/plan-alimentation.ts';

const proche = (v, attendu, tol, msg) => assert.ok(v != null && Math.abs(v - attendu) <= tol, `${msg ?? ''} ${v} ≠ ${attendu}`);
const croq = () => ({ marque: 'Josera', gamme: 'Adult Medium', type: 'croquettes', kcal: 370 });
const barf = () => ({ marque: 'Easy BARF', gamme: 'Bœuf', type: 'barf', kcal: 140 });
const patee = k => ({ marque: "Hill's", gamme: 'Adult', type: 'patee', kcal: k });
const ilYa = jours => new Date(Date.now() - jours * 86400000).toISOString();
const nala = { espece: 'chien', nom: 'Nala', sterilise: true, poidsKg: 18.4, dateNaissance: ilYa(365 * 3) };
const plan = (aliments, repas) => ({
  mode: aliments.length > 1 ? 'mixte' : 'unique', categories: [...new Set(aliments.map(a => a.type))], activite: 'normal',
  aliments, repas: repas.map(r => ({ items: r.map(a => ({ a })) })),
});

test('1. chien, croquettes seules', () => {
  const c = calculerRation(plan([croq()], [[0], [0]]), nala);
  proche(c.besoin.kcal, 995.1, 0.5);
  proche(c.lignes[0][0].reco, 134.5, 0.3);
  proche(c.totalG, 268.9, 0.5);
  proche(c.kcalServies, 995.1, 0.5);
  assert.ok(c.recoDisponible);
});

test('2. chat, pâtée seule', () => {
  const chat = { espece: 'chat', sterilise: true, poidsKg: 4, dateNaissance: ilYa(365 * 4) };
  const c = calculerRation(plan([patee(85)], [[0], [0]]), chat);
  proche(c.besoin.kcal, 237.6, 0.3);
  proche(c.totalG, 279.5, 0.5);
});

test('3. BARF le matin, croquettes le soir', () => {
  const c = calculerRation(plan([barf(), croq()], [[0], [1]]), nala);
  proche(c.lignes[0][0].reco, 355.4, 0.5);
  proche(c.lignes[1][0].reco, 134.5, 0.3);
  proche(c.kcalServies, 995.1, 0.5);
});

test('4. BARF + croquettes aux deux repas', () => {
  const c = calculerRation(plan([barf(), croq()], [[0, 1], [0, 1]]), nala);
  proche(c.lignes[0][0].reco, 177.7, 0.3);
  proche(c.lignes[0][1].reco, 67.2, 0.3);
  proche(c.totalParAliment[0], 355.4, 0.5);
});

test('5. trois repas de compositions différentes', () => {
  const dogfy = { marque: 'Dogfy Diet', gamme: 'Poulet', type: 'menagere', kcal: 125 };
  const c = calculerRation(plan([patee(88), croq(), dogfy], [[0, 1], [1], [2]]), nala);
  proche(c.lignes[0][0].reco, 188.5, 0.5);
  proche(c.lignes[0][1].reco, 44.8, 0.3);
  proche(c.lignes[1][0].reco, 89.6, 0.3);
  proche(c.lignes[2][0].reco, 265.4, 0.5);
  proche(c.kcalServies, 995.1, 0.5);
});

test('6-7. aliment ajouté en kcal/100 g et en kcal/kg', () => {
  const a = evaluerEnergie({ methode: 'A', type: 'croquettes', kcalTexte: '370' });
  assert.equal(a.kcal, 370);
  assert.equal(a.warn, undefined);
  const b = evaluerEnergie({ methode: 'A', type: 'croquettes', kcalTexte: '3700', unite: 'kg' });
  assert.equal(b.kcal, 370);
  assert.match(b.info, /3700 kcal\/kg = 370,0 kcal\/100 g/);
  const c = evaluerEnergie({ methode: 'A', type: 'croquettes', kcalTexte: '3700' });
  assert.equal(c.ok, false);
  assert.match(c.err, /1 kg/);
});

test('8. aliment ajouté depuis la composition analytique', () => {
  const e = evaluerEnergie({ methode: 'B', type: 'croquettes', compo: {
    proteines: '26', matieres_grasses: '16', fibres: '2,5', cendres: '7', humidite: '8',
  } });
  assert.equal(e.kcal, 369);
  assert.ok(e.estime);
  assert.match(e.info, /glucides estimés par différence : 40,5 %/);
  const partiel = evaluerEnergie({ methode: 'B', type: 'croquettes', compo: { proteines: '26', matieres_grasses: '16' } });
  assert.equal(partiel.ok, false);
  assert.match(partiel.info, /fibres brutes/);
});

test('8 bis. composition sur matière sèche (Dogfy Diet)', () => {
  const dogfy = { proteines: '29', matieres_grasses: '44', fibres: '3', cendres: '9', glucides: '14', humidite: '66' };
  const brut = evaluerEnergie({ methode: 'B', type: 'menagere', compo: dogfy });
  assert.equal(brut.ok, false);
  assert.match(brut.err, /matière sèche/);
  const sec = evaluerEnergie({ methode: 'B', type: 'menagere', compo: dogfy, surMatiereSeche: true });
  assert.ok(sec.ok);
  assert.equal(sec.kcal, 193);
  assert.equal(sec.composition.proteines, 9.86);
  assert.match(sec.info, /humidité 66 %/);
  assert.match(evaluerEnergie({ methode: 'B', type: 'menagere', compo: { proteines: '29', matieres_grasses: '44' }, surMatiereSeche: true }).info,
    /Indiquez l’humidité/);
});

test('9. aliment sans valeur énergétique', () => {
  const maison = { marque: 'Préparation maison', gamme: 'Riz poulet', type: 'autre' };
  const p = plan([croq(), maison], [[0], [1]]);
  let c = calculerRation(p, nala);
  assert.equal(c.lignes[1][0].reco, null);
  assert.equal(c.kcalServies, null);
  assert.equal(c.recoDisponible, false);
  assert.deepEqual(c.sansKcal, ['Préparation maison — Riz poulet']);
  assert.match(erreurEtape(5, p, c), /indiquez la quantité/);
  p.repas[1].items[0].g = 300;
  c = calculerRation(p, nala);
  assert.equal(erreurEtape(5, p, c), null);
  assert.equal(c.kcalServies, null, 'total calorique partiel jamais présenté');
});

test('10. chiot : poids adulte requis, formule de croissance, tableau fabricant', () => {
  const chiot = { espece: 'chien', nom: 'Rox', poidsKg: 10, dateNaissance: ilYa(122) };
  const p = plan([croq()], [[0], [0], [0]]);
  let c = calculerRation(p, chiot);
  assert.match(c.besoin.manque, /poids adulte estimé/);
  assert.equal(c.recoDisponible, false);
  p.poidsAdulte = 25;
  c = calculerRation(p, chiot);
  assert.ok(c.besoin.croissance);
  proche(c.besoin.kcal, 1417.9, 1);
  p.aliments[0].tableauCroissance = [
    { age_mois: 3, poids_adulte_kg: 25, g_jour: 300 },
    { age_mois: 6, poids_adulte_kg: 25, g_jour: 380 },
    { age_mois: 3, poids_adulte_kg: 10, g_jour: 150 },
  ];
  c = calculerRation(p, chiot);
  assert.equal(c.fabricant[0], 300);
});

test('11. valeurs nutritionnelles incohérentes', () => {
  const somme = evaluerEnergie({ methode: 'B', type: 'croquettes', compo: {
    proteines: '60', matieres_grasses: '30', fibres: '5', cendres: '7', humidite: '8',
  } });
  assert.match(somme.err, /dépasse 100 %/);
  assert.match(evaluerEnergie({ methode: 'B', type: 'croquettes', compo: { proteines: '120' } }).erreursChamps.proteines, /entre 0 et 100/);
  assert.match(evaluerEnergie({ methode: 'A', type: 'croquettes', kcalTexte: '0' }).err, /supérieure à 0/);
  assert.match(evaluerEnergie({ methode: 'A', type: 'croquettes', kcalTexte: '-5' }).err, /positif/);
  assert.match(evaluerEnergie({ methode: 'A', type: 'croquettes', kcalTexte: '37 kcal' }).err, /sans unité/);
  assert.match(evaluerEnergie({ methode: 'A', type: 'patee', kcalTexte: '370' }).warn, /inhabituelle pour une pâtée/);
  assert.equal(lireNombre('12,5').v, 12.5);
});

test('12-14. quantité aberrante, ration modifiée, retour à la recommandation', () => {
  let p = plan([croq()], [[0], [0]]);
  p.repas[0].items[0].g = 1000;
  let c = calculerRation(p, nala);
  assert.ok(ecartImportant(c));
  assert.match(erreurEtape(5, p, c), /très différente/);
  assert.equal(erreurEtape(5, p, c, { ecartConfirme: true }), null);
  assert.ok(estPersonnalise(p));
  p = revenirRecommandation(p);
  c = calculerRation(p, nala);
  assert.equal(estPersonnalise(p), false);
  assert.equal(ecartImportant(c), false);
  assert.equal(p.repas.length, 2, 'repas conservés');
});

test('horaires : cohérents avec le repas et croissants (facultatifs)', () => {
  const p = plan([croq()], [[0], [0], [0]]);
  assert.deepEqual(erreursHoraires(p), {});
  p.repas[0].heure = '07:30';
  p.repas[2].heure = '19:00';
  assert.deepEqual(erreursHoraires(p), {}, 'midi sans heure accepté');
  p.repas[0].heure = '15:00';
  assert.equal(erreursHoraires(p)[0], 'Matin : choisissez une heure entre 4 h 00 et 11 h 00.');
  p.repas[0].heure = '10:30';
  p.repas[1].heure = '11:00';
  assert.deepEqual(erreursHoraires(p), {});
  const quatre = plan([croq()], [[0], [0], [0], [0]]);
  quatre.repas[1].heure = '14:00';
  quatre.repas[2].heure = '13:30';
  assert.equal(erreursHoraires(quatre)[2], 'Après-midi : l’heure doit être après celle du repas précédent (Midi, 14 h 00).');
  assert.match(erreurEtape(2, quatre, calculerRation(quatre, nala)), /Après-midi/);
});

test("ménagère maison estimée par la composition, parts de l'énergie", () => {
  const maison = { marque: 'Préparation maison', gamme: 'Riz poulet', type: 'menagere', repartition: { ...REPARTITION_MENAGERE } };
  assert.equal(kcalDe(maison), 120, "repère par défaut : valeur de l'ancien onglet");
  assert.equal(kcalDe({ marque: 'Ration ménagère', gamme: '', type: 'menagere' }), 120);
  assert.equal(kcalDe({ marque: 'BARF', gamme: '', type: 'barf' }), 125);
  assert.equal(kcalDe({ marque: 'Maison', gamme: '', type: 'menagere',
    repartition: { proteines: 50, legumes: 20, feculents: 20, matieres_grasses: 5, complements: 5 } }), 165);
  assert.equal(kcalDe({ marque: 'Pâtée', gamme: '', type: 'patee' }), null);
  const p = plan([croq(), maison], [[0, 1], [0, 1]]);
  let c = calculerRation(p, nala);
  assert.deepEqual(c.sansKcal, []);
  assert.deepEqual(c.kcalEstimees, ['Préparation maison — Riz poulet']);
  proche(c.kcalServies, 995.1, 0.5);
  proche(c.partEnergie[0], 50, 0.1);
  p.parts = [70, 30];
  c = calculerRation(p, nala);
  proche(c.totalParAliment[0], 995.1 * 0.7 * 100 / 370, 0.5);
  proche(c.totalParAliment[1], 995.1 * 0.3 * 100 / 120, 0.5);
  proche(c.lignes[0][0].reco, 995.1 * 0.7 * 100 / 370 / 2, 0.3);
  proche(c.partEnergie[0], 70, 0.1);
  p.parts = [70, 20];
  assert.equal(erreurEtape(5, p, calculerRation(p, nala)), 'Parts de l\u2019énergie : le total fait 90 % au lieu de 100 %.');
  p.parts = [100, 0];
  assert.match(erreurEtape(5, p, calculerRation(p, nala)), /supérieure à 0 %/);
  assert.equal(retirerAliment(p, 1).parts, null);
});

test('4 bis. repas sans aliment', () => {
  const p = plan([croq()], [[0], []]);
  assert.equal(erreurEtape(4, p, calculerRation(p, nala)),
    'Vous avez renseigné 2 repas, mais aucun aliment pour le repas « Soir ».');
});

test('autres espèces : cheval, lapin, oiseau', () => {
  const cheval = { espece: 'cheval', poidsKg: 500, dateNaissance: ilYa(365 * 8) };
  const foin = { marque: 'Foin', gamme: '', type: 'foin' };
  const gran = { marque: 'Cavalor', gamme: 'Sport', type: 'concentre' };
  let c = calculerRation(plan([foin, gran], [[0, 1], [0, 1]]), cheval);
  proche(c.besoin.totalG, 10000, 1);
  proche(c.totalParAliment[0], 7052.6, 1);
  proche(c.lignes[0][1].reco, 1473.7, 1);
  assert.deepEqual(c.avertissements, []);
  c = calculerRation(plan([foin, gran], [[0, 1], [0]]), cheval);
  assert.equal(c.avertissements.length, 1);
  assert.match(c.avertissements[0], /concentrés en un repas/);

  const lapin = { espece: 'lapin', poidsKg: 2, dateNaissance: ilYa(365 * 2) };
  const pl = {
    mode: 'mixte', categories: ['foin', 'granules', 'legumes'], activite: 'normal',
    aliments: [{ marque: 'Foin', gamme: '', type: 'foin' }, { marque: 'Versele', gamme: '', type: 'granules' }, { marque: 'Légumes', gamme: '', type: 'legumes' }],
    repas: [{ items: [{ a: 0, libre: true }, { a: 1 }, { a: 2 }] }],
  };
  c = calculerRation(pl, lapin);
  assert.ok(c.lignes[0][0].libre);
  proche(c.lignes[0][1].reco, 45, 0.01);
  proche(c.lignes[0][2].reco, 100, 0.01);

  const po = plan([{ marque: 'Graines', gamme: '', type: 'graines' }], [[0]]);
  c = calculerRation(po, { espece: 'oiseau', poidsKg: 0.4 });
  assert.equal(c.recoDisponible, false);
  assert.match(erreurEtape(5, po, c), /indiquez la quantité/);
});

test('gestation et lactation (NRC 2006) selon le nombre de petits', () => {
  const f = (espece, kg, etat, sem) => ({ espece, nom: 'Lia', sexe: 'femelle', poidsKg: kg, etatRepro: etat, semaineLactation: sem, dateNaissance: ilYa(365 * 4) });
  const p = plan([croq()], [[0], [0]]);
  let c = calculerRation(p, f('chien', 20, 'lactation', 3));
  assert.match(c.besoin.manque, /nombre de petits/);
  p.nbPetits = 6;
  proche(calculerRation(p, f('chien', 20, 'lactation', 3)).besoin.kcal, 4011.3, 1);
  p.nbPetits = 2;
  proche(calculerRation(p, f('chien', 20, 'lactation', 1)).besoin.kcal, 2091.3, 1);
  proche(calculerRation(p, f('chien', 20, 'gestation_fin')).besoin.kcal, 1768.3, 1);
  p.nbPetits = 4;
  proche(calculerRation(p, f('chat', 4, 'lactation', 4)).besoin.kcal, 541.2, 1);
  proche(calculerRation(p, f('chat', 4, 'gestation_debut')).besoin.kcal, 354.4, 1);
});

test('lactation déduite de la portée (petits présents, mise bas récente)', () => {
  const now = new Date(2026, 9, 25);
  const portees = [
    ...Array.from({ length: 6 }, (_, i) => ({ portee_id: 'p2', date_naissance: '2026-10-05', statut: i === 0 ? 'decede' : 'present' })),
    ...Array.from({ length: 4 }, () => ({ portee_id: 'p1', date_naissance: '2025-12-01', statut: 'sorti' })),
  ];
  let e = detecterReproduction({ espece: 'chien', gestation: { date: '2026-08-03' }, portees, maintenant: now });
  assert.equal(e.etat, 'lactation');
  assert.equal(e.semaine, 3);
  assert.equal(e.nbPetits, 5);
  assert.equal(e.miseBas, '2026-10-05');
  assert.equal(e.source, 'Repris de la portée née le 05/10/2026 (5 petits sur 6 nés)');
  e = detecterReproduction({ espece: 'chien', portees, maintenant: new Date(2026, 11, 15) });
  assert.equal(e.etat, 'normal');
  e = detecterReproduction({ espece: 'chien', gestation: { date: '2026-09-01' }, portees: portees.slice(6), maintenant: now });
  assert.equal(e.etat, 'gestation_fin');
  e = detecterReproduction({ espece: 'chat', gestation: { date: '2026-08-01', date_naissance: '2026-10-20', nb_nes: 4 }, maintenant: now });
  assert.equal(e.etat, 'lactation');
  assert.equal(e.nbPetits, 4);
  assert.equal(e.semaine, 1);
});

test('anciennes données : mixte croquettes + ménagère séparées', () => {
  const p = planDepuisLigne({
    type_ration: 'mixte', marque: 'Purina', gamme: 'Pro Plan Medium', densite_calorique: 380,
    mixte_ratio_croq: 70, notes: '67|28|5|2|1|||menagere||', niveau_activite: 'modere',
  }, 'chien');
  assert.ok(p.repris);
  assert.deepEqual(p.aliments.map(a => a.type), ['croquettes', 'menagere']);
  assert.equal(p.repas[0].items.length, 1);
  assert.equal(p.repas[0].items[0].a, 0);
  assert.equal(p.repas[1].items[0].a, 1);
  assert.equal(p.activite, 'normal');
  const vieux = planDepuisLigne({ type_ration: 'mixte', notes: '67|28|5|2|0|||patee||', ration_grammes: 400 }, 'cheval');
  assert.deepEqual(vieux.aliments.map(a => a.type), ['foin', 'concentre', 'complement']);
  proche(vieux.repas[0].items[0].g, 400 * 0.67 / 2, 0.01);
  assert.equal(planDepuisLigne(null, 'chien'), null);
});

test('plan enregistré relu tel quel (vue professionnel)', () => {
  const p = plan([barf(), croq()], [[0], [1]]);
  p.repas[0].heure = '07:30';
  const json = planVersJson(p, calculerRation(p, nala));
  const relu = planDepuisLigne({ plan: json, updated_at: new Date().toISOString() }, 'chien');
  assert.equal(relu.repris, undefined);
  const c = calculEnregistre(relu);
  assert.equal(c.lignes[0][0].eff, 355);
  assert.equal(relu.repas[0].heure, '07:30');
  assert.equal(nomAliment(relu.aliments[0]), 'Easy BARF — Bœuf');
});
