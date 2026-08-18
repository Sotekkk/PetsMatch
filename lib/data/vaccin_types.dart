// Types de vaccins par espèce, avec délai de rappel (années) et durée de
// validité de la première injection (jours) — partagé entre toutes les
// fiches animal (éleveur/association via animal_fiche.dart, particulier via
// animal_fiche_particulier.dart) pour ne jamais diverger entre profils.
const Map<String, List<(String label, int rappelAns, int validiteJours)>> typesVaccinParEspece = {
  'chien': [
    ('Rage', 3, 21),
    ('CHPPI (Carré, Hépatite, Parvovirose, Parainfluenza)', 1, 0),
    ('Leptospirose (L4)', 1, 0),
    ('Toux du chenil (Bordetella)', 1, 0),
    ('Piroplasmose', 1, 0),
    ('Autre', 1, 0),
  ],
  'chat': [
    ('Rage', 3, 21),
    ('Typhus (panleucopénie)', 1, 0),
    ('Coryza', 1, 0),
    ('Leucose (FeLV)', 1, 0),
    ('PIF (coronavirus félin)', 1, 0),
    ('Autre', 1, 0),
  ],
  'lapin': [
    ('Myxomatose', 1, 0),
    ('VHD (maladie hémorragique)', 1, 0),
    ('Autre', 1, 0),
  ],
  'cheval': [
    ('Rage', 3, 21),
    ('Grippe équine', 1, 0),
    ('Tétanos', 1, 0),
    ('Autre', 1, 0),
  ],
};
// Espèces hors liste ci-dessus (oiseau, nac, ovin, caprin, porcin, autre) :
// choix générique, toujours avec "Autre" pour saisie manuelle libre.
const List<(String label, int rappelAns, int validiteJours)> typesVaccinDefaut = [
  ('Rage', 3, 21),
  ('Autre', 1, 0),
];
List<(String label, int rappelAns, int validiteJours)> typesVaccinPour(String? espece) =>
    typesVaccinParEspece[espece] ?? typesVaccinDefaut;
