import 'package:flutter_test/flutter_test.dart';
import 'package:PetsMatch/utils/reproducteurs.dart';

void main() {
  group('Reproducteurs éligibles à une nouvelle saillie', () {
    test('chiot (non coché Reproducteur) : exclu', () {
      final chiot = {'sexe': 'male', 'statut': 'present', 'reproducteur': false, 'portee_id': 'p1'};
      expect(estReproducteurEligible(chiot), isFalse);
      expect(raisonNonEligible(chiot), contains('Reproducteur'));
    });
    test('animal cédé : exclu', () {
      final cede = {'sexe': 'male', 'statut': 'sorti', 'reproducteur': true};
      expect(estReproducteurEligible(cede), isFalse);
      expect(raisonNonEligible(cede), contains('cédé'));
    });
    test('cession en cours : exclu', () {
      expect(estReproducteurEligible({'statut': 'en_attente_cession', 'reproducteur': true}), isFalse);
    });
    test('reproducteur actif : proposé', () {
      final actif = {'sexe': 'male', 'statut': 'present', 'reproducteur': true, 'is_retraite': false, 'sterilise': false};
      expect(estReproducteurEligible(actif), isTrue);
      expect(raisonNonEligible(actif), isNull);
    });
    test('reproducteur actif réservé (statut commercial) : proposé', () {
      expect(estReproducteurEligible({'statut': 'reserve', 'reproducteur': true}), isTrue);
    });
    test('reproducteur retraité : exclu', () {
      final retraite = {'statut': 'present', 'reproducteur': true, 'is_retraite': true};
      expect(estReproducteurEligible(retraite), isFalse);
      expect(raisonNonEligible(retraite), contains('retraité'));
    });
    test('stérilisé : exclu', () {
      expect(estReproducteurEligible({'statut': 'present', 'reproducteur': true, 'sterilise': true}), isFalse);
    });
    test('étalon extérieur : saisi sans fiche, jamais filtré', () {
      const ext = Reproducteur(nom: 'Étalon ext.', identification: '250…', source: 'historique');
      expect(ext.id, isNull);
      expect(ext.detail, '250…');
    });
  });
}
