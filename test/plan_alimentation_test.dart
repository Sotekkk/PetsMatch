// Scénarios du cahier des charges Alimentation (§14) — mêmes valeurs
// attendues que website/src/lib/plan-alimentation.test.ts.
import 'package:flutter_test/flutter_test.dart';
import 'package:PetsMatch/utils/plan_alimentation.dart';

AlimentPlan croq() => AlimentPlan(marque: 'Josera', gamme: 'Adult Medium', type: 'croquettes', kcal: 370);
AlimentPlan barf() => AlimentPlan(marque: 'Easy BARF', gamme: 'Bœuf', type: 'barf', kcal: 140);
AlimentPlan patee(double k) => AlimentPlan(marque: "Hill's", gamme: 'Adult', type: 'patee', kcal: k);

final nala = ProfilAnimal(espece: 'chien', nom: 'Nala', sterilise: true, poidsKg: 18.4,
    dateNaissance: DateTime.now().subtract(const Duration(days: 365 * 3)));

PlanAlimentation plan(List<AlimentPlan> aliments, List<List<int>> repas) => PlanAlimentation(
      mode: aliments.length > 1 ? 'mixte' : 'unique',
      categories: {for (final a in aliments) a.type}.toList(),
      aliments: aliments,
      repas: [for (final r in repas) RepasPlan(items: [for (final a in r) ItemRepas(a)])],
    );

void main() {
  test('1. chien, croquettes seules', () {
    final c = calculerRation(plan([croq()], [[0], [0]]), nala);
    expect(c.besoin.kcal, closeTo(995.1, 0.5));
    expect(c.lignes[0][0].reco, closeTo(134.5, 0.3));
    expect(c.totalG, closeTo(268.9, 0.5));
    expect(c.kcalServies, closeTo(995.1, 0.5));
    expect(c.recoDisponible, isTrue);
  });

  test('2. chat, pâtée seule', () {
    final chat = ProfilAnimal(espece: 'chat', sterilise: true, poidsKg: 4,
        dateNaissance: DateTime.now().subtract(const Duration(days: 365 * 4)));
    final c = calculerRation(plan([patee(85)], [[0], [0]]), chat);
    expect(c.besoin.kcal, closeTo(237.6, 0.3));
    expect(c.totalG, closeTo(279.5, 0.5));
  });

  test('3. BARF le matin, croquettes le soir', () {
    final c = calculerRation(plan([barf(), croq()], [[0], [1]]), nala);
    expect(c.lignes[0][0].reco, closeTo(355.4, 0.5));
    expect(c.lignes[1][0].reco, closeTo(134.5, 0.3));
    expect(c.kcalServies, closeTo(995.1, 0.5));
  });

  test('4. BARF + croquettes aux deux repas', () {
    final c = calculerRation(plan([barf(), croq()], [[0, 1], [0, 1]]), nala);
    expect(c.lignes[0][0].reco, closeTo(177.7, 0.3));
    expect(c.lignes[0][1].reco, closeTo(67.2, 0.3));
    expect(c.totalParAliment[0], closeTo(355.4, 0.5));
  });

  test('5. trois repas de compositions différentes', () {
    final dogfy = AlimentPlan(marque: 'Dogfy Diet', gamme: 'Poulet', type: 'menagere', kcal: 125);
    final c = calculerRation(plan([patee(88), croq(), dogfy], [[0, 1], [1], [2]]), nala);
    expect(c.lignes[0][0].reco, closeTo(188.5, 0.5));
    expect(c.lignes[0][1].reco, closeTo(44.8, 0.3));
    expect(c.lignes[1][0].reco, closeTo(89.6, 0.3));
    expect(c.lignes[2][0].reco, closeTo(265.4, 0.5));
    expect(c.kcalServies, closeTo(995.1, 0.5));
  });

  test('6-7. aliment ajouté en kcal/100 g et en kcal/kg', () {
    final a = evaluerEnergie(methode: 'A', type: 'croquettes', kcalTexte: '370');
    expect(a.kcal, 370);
    expect(a.warn, isNull);
    final b = evaluerEnergie(methode: 'A', type: 'croquettes', kcalTexte: '3700', unite: 'kg');
    expect(b.kcal, 370);
    expect(b.info, contains('3700 kcal/kg = 370,0 kcal/100 g'));
    final c = evaluerEnergie(methode: 'A', type: 'croquettes', kcalTexte: '3700');
    expect(c.ok, isFalse);
    expect(c.err, contains('1 kg'));
  });

  test('8. aliment ajouté depuis la composition analytique', () {
    final e = evaluerEnergie(methode: 'B', type: 'croquettes', compo: {
      'proteines': '26', 'matieres_grasses': '16', 'fibres': '2,5', 'cendres': '7', 'humidite': '8',
    });
    expect(e.kcal, 369);
    expect(e.estime, isTrue);
    expect(e.info, contains('glucides estimés par différence : 40,5 %'));
    final partiel = evaluerEnergie(methode: 'B', type: 'croquettes', compo: {'proteines': '26', 'matieres_grasses': '16'});
    expect(partiel.ok, isFalse);
    expect(partiel.info, contains('fibres brutes'));
  });

  test('8 bis. composition sur matière sèche (Dogfy Diet)', () {
    const dogfy = {'proteines': '29', 'matieres_grasses': '44', 'fibres': '3', 'cendres': '9', 'glucides': '14', 'humidite': '66'};
    final brut = evaluerEnergie(methode: 'B', type: 'menagere', compo: dogfy);
    expect(brut.ok, isFalse);
    expect(brut.err, contains('matière sèche'));
    final sec = evaluerEnergie(methode: 'B', type: 'menagere', compo: dogfy, surMatiereSeche: true);
    expect(sec.ok, isTrue);
    expect(sec.kcal, 193);
    expect(sec.composition['proteines'], 9.86);
    expect(sec.info, contains('humidité 66 %'));
    expect(evaluerEnergie(methode: 'B', type: 'menagere', compo: {'proteines': '29', 'matieres_grasses': '44'}, surMatiereSeche: true).info,
        contains('Indiquez l’humidité'));
  });

  test('9. aliment sans valeur énergétique', () {
    final maison = AlimentPlan(marque: 'Préparation maison', gamme: 'Riz poulet', type: 'autre');
    final p = plan([croq(), maison], [[0], [1]]);
    var c = calculerRation(p, nala);
    expect(c.lignes[1][0].reco, isNull);
    expect(c.kcalServies, isNull);
    expect(c.recoDisponible, isFalse);
    expect(c.sansKcal, ['Préparation maison — Riz poulet']);
    expect(erreurEtape(5, p, c), contains('indiquez la quantité'));
    p.repas[1].items[0].g = 300;
    c = calculerRation(p, nala);
    expect(erreurEtape(5, p, c), isNull);
    expect(c.kcalServies, isNull, reason: 'total calorique partiel jamais présenté');
  });

  test('10. chiot : poids adulte requis, formule de croissance, tableau fabricant', () {
    final chiot = ProfilAnimal(espece: 'chien', nom: 'Rox', poidsKg: 10,
        dateNaissance: DateTime.now().subtract(const Duration(days: 122)));
    final p = plan([croq()], [[0], [0], [0]]);
    var c = calculerRation(p, chiot);
    expect(c.besoin.manque, contains('poids adulte estimé'));
    expect(c.recoDisponible, isFalse);
    p.poidsAdulte = 25;
    c = calculerRation(p, chiot);
    expect(c.besoin.croissance, isTrue);
    expect(c.besoin.kcal, closeTo(1417.9, 1));
    p.aliments[0].tableauCroissance = [
      {'age_mois': 3, 'poids_adulte_kg': 25, 'g_jour': 300},
      {'age_mois': 6, 'poids_adulte_kg': 25, 'g_jour': 380},
      {'age_mois': 3, 'poids_adulte_kg': 10, 'g_jour': 150},
    ];
    c = calculerRation(p, chiot);
    expect(c.fabricant[0], 300);
  });

  test('11. valeurs nutritionnelles incohérentes', () {
    final somme = evaluerEnergie(methode: 'B', type: 'croquettes', compo: {
      'proteines': '60', 'matieres_grasses': '30', 'fibres': '5', 'cendres': '7', 'humidite': '8',
    });
    expect(somme.err, contains('dépasse 100 %'));
    expect(evaluerEnergie(methode: 'B', type: 'croquettes', compo: {'proteines': '120'}).erreursChamps['proteines'],
        contains('entre 0 et 100'));
    expect(evaluerEnergie(methode: 'A', type: 'croquettes', kcalTexte: '0').err, contains('supérieure à 0'));
    expect(evaluerEnergie(methode: 'A', type: 'croquettes', kcalTexte: '-5').err, contains('positif'));
    expect(evaluerEnergie(methode: 'A', type: 'croquettes', kcalTexte: '37 kcal').err, contains('sans unité'));
    expect(evaluerEnergie(methode: 'A', type: 'patee', kcalTexte: '370').warn, contains('inhabituelle pour une pâtée'));
    expect(lireNombre('12,5').v, 12.5);
  });

  test('12-14. quantité aberrante, ration modifiée, retour à la recommandation', () {
    final p = plan([croq()], [[0], [0]]);
    p.repas[0].items[0].g = 1000;
    var c = calculerRation(p, nala);
    expect(c.ecartImportant, isTrue);
    expect(erreurEtape(5, p, c), contains('très différente'));
    expect(erreurEtape(5, p, c, ecartConfirme: true), isNull);
    expect(p.estPersonnalise, isTrue);
    p.revenirRecommandation();
    c = calculerRation(p, nala);
    expect(p.estPersonnalise, isFalse);
    expect(c.ecartImportant, isFalse);
    expect(p.repas.length, 2, reason: 'repas conservés');
  });

  test('horaires : cohérents avec le repas et croissants (facultatifs)', () {
    final p = plan([croq()], [[0], [0], [0]]);
    expect(erreursHoraires(p), isEmpty);
    p.repas[0].heure = '07:30';
    p.repas[2].heure = '19:00';
    expect(erreursHoraires(p), isEmpty, reason: 'midi sans heure accepté');
    p.repas[0].heure = '15:00';
    expect(erreursHoraires(p)[0], 'Matin : choisissez une heure entre 4 h 00 et 11 h 00.');
    p.repas[0].heure = '10:30';
    p.repas[1].heure = '11:00';
    expect(erreursHoraires(p), isEmpty);
    final quatre = plan([croq()], [[0], [0], [0], [0]]);
    quatre.repas[1].heure = '14:00';
    quatre.repas[2].heure = '13:30';
    expect(erreursHoraires(quatre)[2], 'Après-midi : l’heure doit être après celle du repas précédent (Midi, 14 h 00).');
    expect(erreurEtape(2, quatre, calculerRation(quatre, nala)), contains('Après-midi'));
  });

  test('ménagère maison estimée par la composition, parts de l\'énergie', () {
    final maison = AlimentPlan(marque: 'Préparation maison', gamme: 'Riz poulet', type: 'menagere',
        repartition: Map.of(kRepartitionMenagere));
    expect(kcalDe(maison), 120, reason: 'repère par défaut : valeur de l\'ancien onglet');
    expect(kcalDe(AlimentPlan(marque: 'Ration ménagère', type: 'menagere')), 120);
    expect(kcalDe(AlimentPlan(marque: 'BARF', type: 'barf')), 125);
    expect(kcalDe(AlimentPlan(marque: 'Maison', type: 'menagere',
        repartition: {'proteines': 50, 'legumes': 20, 'feculents': 20, 'matieres_grasses': 5, 'complements': 5})), 165);
    expect(kcalDe(AlimentPlan(marque: 'Pâtée', type: 'patee')), isNull);
    final p = plan([croq(), maison], [[0, 1], [0, 1]]);
    var c = calculerRation(p, nala);
    expect(c.sansKcal, isEmpty);
    expect(c.kcalEstimees, ['Préparation maison — Riz poulet']);
    expect(c.kcalServies, closeTo(995.1, 0.5));
    expect(c.partEnergie[0], closeTo(50, 0.1));
    // 70 % croquettes / 30 % ménagère.
    p.parts = [70, 30];
    c = calculerRation(p, nala);
    expect(c.totalParAliment[0], closeTo(995.1 * 0.7 * 100 / 370, 0.5));
    expect(c.totalParAliment[1], closeTo(995.1 * 0.3 * 100 / 120, 0.5));
    expect(c.lignes[0][0].reco, closeTo(995.1 * 0.7 * 100 / 370 / 2, 0.3));
    expect(c.partEnergie[0], closeTo(70, 0.1));
    p.parts = [70, 20];
    expect(erreurEtape(5, p, calculerRation(p, nala)), 'Parts de l\u2019énergie : le total fait 90 % au lieu de 100 %.');
    p.parts = [100, 0];
    expect(erreurEtape(5, p, calculerRation(p, nala)), contains('supérieure à 0 %'));
    p.retirerAliment(1);
    expect(p.parts, isNull);
  });

  test('4 bis. repas sans aliment', () {
    final p = plan([croq()], [[0], []]);
    expect(erreurEtape(4, p, calculerRation(p, nala)),
        'Vous avez renseigné 2 repas, mais aucun aliment pour le repas « Soir ».');
  });

  test('autres espèces : cheval, lapin, oiseau', () {
    final cheval = ProfilAnimal(espece: 'cheval', poidsKg: 500,
        dateNaissance: DateTime.now().subtract(const Duration(days: 365 * 8)));
    final foin = AlimentPlan(marque: 'Foin', type: 'foin');
    final gran = AlimentPlan(marque: 'Cavalor', gamme: 'Sport', type: 'concentre');
    var c = calculerRation(plan([foin, gran], [[0, 1], [0, 1]]), cheval);
    expect(c.besoin.totalG, closeTo(10000, 1));
    expect(c.totalParAliment[0], closeTo(7052.6, 1));
    expect(c.lignes[0][1].reco, closeTo(1473.7, 1));
    expect(c.avertissements, isEmpty);
    c = calculerRation(plan([foin, gran], [[0, 1], [0]]), cheval);
    expect(c.avertissements.single, contains('concentrés en un repas'));

    final lapin = ProfilAnimal(espece: 'lapin', poidsKg: 2,
        dateNaissance: DateTime.now().subtract(const Duration(days: 365 * 2)));
    final pl = PlanAlimentation(mode: 'mixte', categories: ['foin', 'granules', 'legumes'],
        aliments: [AlimentPlan(marque: 'Foin', type: 'foin'), AlimentPlan(marque: 'Versele', type: 'granules'),
          AlimentPlan(marque: 'Légumes', type: 'legumes')],
        repas: [RepasPlan(items: [ItemRepas(0, libre: true), ItemRepas(1), ItemRepas(2)])]);
    c = calculerRation(pl, lapin);
    expect(c.lignes[0][0].libre, isTrue);
    expect(c.lignes[0][1].reco, closeTo(45, 0.01));
    expect(c.lignes[0][2].reco, closeTo(100, 0.01));

    final oiseau = ProfilAnimal(espece: 'oiseau', poidsKg: 0.4);
    final po = plan([AlimentPlan(marque: 'Graines', type: 'graines')], [[0]]);
    c = calculerRation(po, oiseau);
    expect(c.recoDisponible, isFalse);
    expect(erreurEtape(5, po, c), contains('indiquez la quantité'));
  });

  test('gestation et lactation (NRC 2006) selon le nombre de petits', () {
    ProfilAnimal f(String espece, double kg, String etat, {int? sem}) => ProfilAnimal(espece: espece, nom: 'Lia', sexe: 'femelle',
        poidsKg: kg, etatRepro: etat, semaineLactation: sem,
        dateNaissance: DateTime.now().subtract(const Duration(days: 365 * 4)));
    final p = plan([croq()], [[0], [0]]);
    var c = calculerRation(p, f('chien', 20, 'lactation', sem: 3));
    expect(c.besoin.manque, contains('nombre de petits'));
    p.nbPetits = 6;
    c = calculerRation(p, f('chien', 20, 'lactation', sem: 3));
    expect(c.besoin.kcal, closeTo(4011.3, 1));
    p.nbPetits = 2;
    c = calculerRation(p, f('chien', 20, 'lactation', sem: 1));
    expect(c.besoin.kcal, closeTo(2091.3, 1));
    c = calculerRation(p, f('chien', 20, 'gestation_fin'));
    expect(c.besoin.kcal, closeTo(1768.3, 1));
    p.nbPetits = 4;
    c = calculerRation(p, f('chat', 4, 'lactation', sem: 4));
    expect(c.besoin.kcal, closeTo(541.2, 1));
    c = calculerRation(p, f('chat', 4, 'gestation_debut'));
    expect(c.besoin.kcal, closeTo(354.4, 1));
  });

  test('lactation déduite de la portée (petits présents, mise bas récente)', () {
    final now = DateTime(2026, 10, 25);
    final portees = [
      for (var i = 0; i < 6; i++) {'portee_id': 'p2', 'date_naissance': '2026-10-05', 'statut': i == 0 ? 'decede' : 'present'},
      for (var i = 0; i < 4; i++) {'portee_id': 'p1', 'date_naissance': '2025-12-01', 'statut': 'sorti'},
    ];
    // Gestation non mise à jour (pas de date de mise bas) : la portée fait foi.
    var e = detecterReproduction(espece: 'chien', gestation: {'date': '2026-08-03'}, portees: portees, maintenant: now);
    expect(e.etat, 'lactation');
    expect(e.semaine, 3);
    expect(e.nbPetits, 5);
    expect(e.miseBas, '2026-10-05');
    expect(e.source, 'Repris de la portée née le 05/10/2026 (5 petits sur 6 nés)');
    // Petits grands (plus de 8 semaines) : plus de lactation.
    e = detecterReproduction(espece: 'chien', portees: portees, maintenant: DateTime(2026, 12, 15));
    expect(e.etat, 'normal');
    // Gestation en cours après la dernière portée.
    e = detecterReproduction(espece: 'chien', gestation: {'date': '2026-09-01'}, portees: portees.sublist(6), maintenant: now);
    expect(e.etat, 'gestation_fin');
    // Sans portée : nombre de nés de la gestation.
    e = detecterReproduction(espece: 'chat', gestation: {'date': '2026-08-01', 'date_naissance': '2026-10-20', 'nb_nes': 4}, maintenant: now);
    expect(e.etat, 'lactation');
    expect(e.nbPetits, 4);
    expect(e.semaine, 1);
  });

  test('anciennes données : mixte croquettes + ménagère séparées', () {
    final p = planDepuisLigne({
      'type_ration': 'mixte', 'marque': 'Purina', 'gamme': 'Pro Plan Medium', 'densite_calorique': 380,
      'mixte_ratio_croq': 70, 'notes': '67|28|5|2|1|||menagere||', 'niveau_activite': 'modere',
    }, 'chien')!;
    expect(p.repris, isTrue);
    expect(p.aliments.map((a) => a.type), ['croquettes', 'menagere']);
    expect(p.repas[0].items.single.a, 0);
    expect(p.repas[1].items.single.a, 1);
    expect(p.activite, 'normal');
    final vieux = planDepuisLigne({'type_ration': 'mixte', 'notes': '67|28|5|2|0|||patee||', 'ration_grammes': 400}, 'cheval')!;
    expect(vieux.aliments.map((a) => a.type), ['foin', 'concentre', 'complement']);
    expect(vieux.repas[0].items[0].g, closeTo(400 * 0.67 / 2, 0.01));
    expect(planDepuisLigne(null, 'chien'), isNull);
  });

  test('plan enregistré relu tel quel (vue professionnel)', () {
    final p = plan([barf(), croq()], [[0], [1]]);
    p.repas[0].heure = '07:30';
    final json = p.toJson(calculerRation(p, nala));
    final relu = planDepuisLigne({'plan': json, 'updated_at': DateTime.now().toUtc().toIso8601String()}, 'chien')!;
    expect(relu.repris, isFalse);
    final c = calculEnregistre(relu);
    expect(c.lignes[0][0].eff, 355);
    expect(relu.repas[0].heure, '07:30');
    expect(relu.aliments[0].nom, 'Easy BARF — Bœuf');
  });
}
