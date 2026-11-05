// Fiche créée par un pro (patient de clinique, pensionnaire, client sans compte) :
// uid_eleveur est le pro, qui n'est pas le propriétaire. Propriétaire = le client une
// fois la fiche récupérée, sinon personne : le pro ne reçoit pas les notifications de
// l'animal. Miroir site : website/src/lib/animal-proprietaire.ts.

String? proprietaireFiche(Map<String, dynamic>? a) {
  if (a == null) return null;
  final proprio = a['uid_proprietaire']?.toString();
  if (a['cree_par_pro_profile_id'] != null || a['client_clinique_id'] != null) return proprio;
  return proprio ?? a['uid_eleveur']?.toString();
}
