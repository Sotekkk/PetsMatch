// Nom affiché d'un client depuis sa ligne user_profiles(_complet) : profil
// particulier → prénom + nom de la personne (le champ « nom » peut porter le
// nom d'élevage du compte) ; structure (élevage, pro, asso) → son nom.
// La sélection doit inclure profile_type, firstname, lastname, nom.
// Miroir site : website/src/lib/nom-client.ts.
String nomClientProfil(Map p, {String defaut = ''}) {
  final nom = (p['nom'] ?? '').toString().trim();
  final complet = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
  final n = p['profile_type'] == 'particulier'
      ? (complet.isNotEmpty ? complet : nom)
      : (nom.isNotEmpty ? nom : complet);
  return n.isNotEmpty ? n : defaut;
}
