import 'package:flutter_test/flutter_test.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/annonces_droits.dart';

void main() {
  test('annonces d\'animaux selon le profil actif', () {
    for (final (type, attendu) in [
      ('eleveur', 'eleveur'),
      ('association', 'association'),
      ('particulier', 'particulier'),
      ('veterinaire', 'aucun'),
      ('pension', 'aucun'),
      ('restauration', 'aucun'),
    ]) {
      User_Info.activeType = type;
      expect(typeAnimauxProfilActif(), attendu, reason: type);
    }
  });

  test('filtre de type : trois choix', () {
    expect(kFiltresTypeAnnonces.map((f) => f.$2).toList(),
        ['Toutes', 'Animaux', 'Matériel & équipements']);
  });
}
