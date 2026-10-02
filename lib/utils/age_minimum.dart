/// Âge minimum pour créer un compte PetsMatch — CGU (appli + site) :
/// personne physique MAJEURE, 18 ans révolus (cessions / ventes d'animaux,
/// contrats, paiements).
const int kAgeMinimum = 18;

/// [dateTexte] au format jj/mm/aaaa (sélecteur de l'inscription). Retourne un
/// message d'erreur, ou null si la date est valide et l'âge suffisant.
String? erreurAgeInscription(String dateTexte) {
  final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(dateTexte.trim());
  if (m == null) return 'Indiquez votre date de naissance.';
  final naissance = DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
  final now = DateTime.now();
  var age = now.year - naissance.year;
  if (now.month < naissance.month || (now.month == naissance.month && now.day < naissance.day)) age--;
  if (age < kAgeMinimum) {
    return 'Vous devez avoir au moins $kAgeMinimum ans pour créer un compte PetsMatch.';
  }
  if (age > 120) return 'Date de naissance invalide.';
  return null;
}
