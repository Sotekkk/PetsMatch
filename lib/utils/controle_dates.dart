/// Cohérence des dates d'un acte du carnet de santé (vaccin, traitement,
/// vermifuge, antiparasitaire, visite…). Miroir site :
/// website/src/lib/controle-dates.ts.
///
/// Lève [SaisieInvalide] avec un message clair ; les fenêtres de saisie
/// (_BaseDialog de la fiche éleveur, _openSheet de la fiche particulier)
/// l'affichent tel quel.
class SaisieInvalide implements Exception {
  final String message;
  const SaisieInvalide(this.message);
  @override
  String toString() => message;
}

/// Libellés affichés des codes des listes déroulantes du carnet de santé
/// (statut d'une chirurgie, type de traitement…) ; la valeur enregistrée
/// reste le code.
const kLibellesSante = {
  'prevu': 'Prévue', 'realise': 'Réalisée', 'annule': 'Annulée',
  'chirurgie': 'Chirurgie', 'hospitalisation': 'Hospitalisation',
  'antiparasitaire': 'Antiparasitaire', 'medicament': 'Médicament', 'autre': 'Autre',
};

/// Plus ancienne date acceptée pour un acte (pas de 12/03/0001).
final DateTime kPremiereDateActe = DateTime(1990);

void controlerDatesSante({
  DateTime? date,
  DateTime? rappel,
  DateTime? validite,
  DateTime? fin,
  bool dateObligatoire = true,
  /// Chirurgie / hospitalisation : « prevu » = pas avant aujourd'hui,
  /// « realise » = pas après aujourd'hui.
  String? statut,
}) {
  final aujourdhui = DateTime.now();
  final jour = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);
  if (date == null) {
    if (dateObligatoire) throw const SaisieInvalide('Indiquez la date.');
    return;
  }
  final d = DateTime(date.year, date.month, date.day);
  if (d.isBefore(kPremiereDateActe)) {
    throw const SaisieInvalide('La date ne peut pas être antérieure au 01/01/1990.');
  }
  if (d.isAfter(DateTime(jour.year + 2, jour.month, jour.day))) {
    throw const SaisieInvalide('La date ne peut pas dépasser deux ans dans le futur.');
  }
  if (statut == 'prevu' && d.isBefore(jour)) {
    throw const SaisieInvalide('Une intervention prévue ne peut pas avoir lieu avant aujourd\'hui. Choisissez « Réalisée » si elle a déjà eu lieu.');
  }
  if (statut == 'realise' && d.isAfter(jour)) {
    throw const SaisieInvalide('Une intervention réalisée ne peut pas être datée dans le futur. Choisissez « Prévue ».');
  }
  final limite = DateTime(d.year + 10, d.month, d.day);
  void apres(DateTime? x, String libelle) {
    if (x == null) return;
    final v = DateTime(x.year, x.month, x.day);
    if (v.isBefore(d)) throw SaisieInvalide('$libelle ne peut pas être antérieure à la date de l\'acte.');
    if (v.isAfter(limite)) throw SaisieInvalide('$libelle ne peut pas dépasser dix ans après la date de l\'acte.');
  }
  apres(rappel, 'La date de rappel');
  apres(validite, 'La date de validité');
  apres(fin, 'La date de fin');
}

/// Date d'un test génétique : ni dans le futur, ni avant la naissance de l'animal.
void controlerDateTestGenetique(DateTime? date, DateTime? naissance) {
  if (date == null) return;
  final jour = DateTime(date.year, date.month, date.day);
  final now = DateTime.now();
  if (jour.isAfter(DateTime(now.year, now.month, now.day))) {
    throw const SaisieInvalide('La date du test ne peut pas être dans le futur.');
  }
  if (naissance != null && jour.isBefore(DateTime(naissance.year, naissance.month, naissance.day))) {
    throw const SaisieInvalide('La date du test ne peut pas être antérieure à la naissance de l\'animal.');
  }
}
