// Dates de naissance plausibles — animaux (âge maximum selon l'espèce) et
// personnes (18 à 110 ans). Bornes des sélecteurs de date + messages d'erreur.
// Miroir site : website/src/lib/ages-plausibles.ts.

/// Longévité maximale raisonnable (années) — au-delà, la date est une erreur de saisie.
const Map<String, int> kAgeMaxEspece = {
  'chien': 30, 'chat': 35,
  'cheval': 50, 'poney': 50, 'equide': 60, 'ane': 60, 'mule': 50, 'mulet': 50,
  'lapin': 18, 'cobaye': 12, "cochon d'inde": 12, 'hamster': 5, 'gerbille': 6, 'rat': 5, 'souris': 4,
  'chinchilla': 25, 'furet': 15, 'degu': 15, 'octodon': 15, 'nac': 30,
  'perroquet': 80, 'oiseau': 80, 'perruche': 20, 'canari': 20, 'poule': 15, 'volaille': 15, 'canard': 20, 'oie': 30,
  'tortue': 120, 'reptile': 100, 'serpent': 40, 'lezard': 30,
  'poisson': 40,
  'chevre': 25, 'caprin': 25, 'mouton': 25, 'ovin': 25, 'vache': 30, 'bovin': 30, 'cochon': 25, 'porcin': 25,
  'alpaga': 30, 'lama': 30,
};
const int kAgeMaxAnimalDefaut = 50;
const int kAgeMinPersonne = 18;
const int kAgeMaxPersonne = 110;

String _norm(String? s) => (s ?? '').toLowerCase().trim()
    .replaceAll(RegExp('[éèêë]'), 'e').replaceAll(RegExp('[àâä]'), 'a').replaceAll(RegExp('[îï]'), 'i')
    .replaceAll(RegExp('[ôö]'), 'o').replaceAll(RegExp('[ûüù]'), 'u').replaceAll('ç', 'c');

int ageMaxEspece(String? espece) {
  final e = _norm(espece);
  if (e.isEmpty) return kAgeMaxAnimalDefaut;
  if (kAgeMaxEspece.containsKey(e)) return kAgeMaxEspece[e]!;
  final singulier = e.endsWith('s') ? e.substring(0, e.length - 1) : e;
  if (kAgeMaxEspece.containsKey(singulier)) return kAgeMaxEspece[singulier]!;
  for (final k in kAgeMaxEspece.keys) {
    if (e.contains(k)) return kAgeMaxEspece[k]!;
  }
  return kAgeMaxAnimalDefaut;
}

DateTime _aujourdhui() { final n = DateTime.now(); return DateTime(n.year, n.month, n.day); }

/// Date de naissance la plus ancienne acceptée pour cette espèce.
DateTime premiereNaissanceAnimal(String? espece) {
  final a = _aujourdhui();
  return DateTime(a.year - ageMaxEspece(espece), a.month, a.day);
}

/// Message d'erreur, ou null si la date est plausible.
String? erreurNaissanceAnimal(DateTime? date, String? espece) {
  if (date == null) return null;
  if (date.isAfter(_aujourdhui())) return 'La date de naissance ne peut pas être dans le futur.';
  if (date.isBefore(premiereNaissanceAnimal(espece))) {
    return "Date peu plausible : cette espèce vit rarement plus de ${ageMaxEspece(espece)} ans.";
  }
  return null;
}

/// Bornes d'une date de naissance de personne (18 à 110 ans par défaut).
DateTime premiereNaissancePersonne() { final a = _aujourdhui(); return DateTime(a.year - kAgeMaxPersonne, a.month, a.day); }
DateTime derniereNaissancePersonne({int ageMin = kAgeMinPersonne}) { final a = _aujourdhui(); return DateTime(a.year - ageMin, a.month, a.day); }

String? erreurNaissancePersonne(DateTime? date, {int ageMin = kAgeMinPersonne}) {
  if (date == null) return null;
  if (date.isAfter(derniereNaissancePersonne(ageMin: ageMin))) return 'Vous devez avoir au moins $ageMin ans.';
  if (date.isBefore(premiereNaissancePersonne())) return 'Date de naissance invalide.';
  return null;
}

/// Date ramenée dans [min, max] (date initiale d'un sélecteur, qui doit être dans ses bornes).
DateTime borner(DateTime d, DateTime min, DateTime max) => d.isBefore(min) ? min : (d.isAfter(max) ? max : d);
