// Menu « Annonces » unifié (animaux + matériel & équipements) : quelles
// annonces d'animaux le profil actif peut gérer / publier. Le matériel &
// équipements est ouvert à tous les profils connectés. Miroir site :
// website/src/lib/annonces-droits.ts.

import 'package:PetsMatch/main.dart' show User_Info;

/// 'eleveur', 'association', 'particulier' (chevaux) ou 'aucun' (profils pro).
String typeAnimauxProfilActif() {
  final t = User_Info.activeType.isNotEmpty
      ? User_Info.activeType
      : (User_Info.isAssociation ? 'association'
          : User_Info.isPro ? User_Info.catPro
          : User_Info.isElevage ? 'eleveur' : 'particulier');
  switch (t) {
    case 'eleveur':
    case 'association':
    case 'particulier':
      return t;
    default:
      return 'aucun';
  }
}

/// Filtre de type de « Mes annonces ».
const kFiltresTypeAnnonces = <(String, String)>[
  ('toutes', 'Toutes'),
  ('animaux', 'Animaux'),
  ('materiel', 'Matériel & équipements'),
];
