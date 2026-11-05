// Fiche créée par un pro (patient de clinique, pensionnaire, client sans compte) :
// uid_eleveur est le pro, qui n'est pas le propriétaire. Propriétaire = le client une
// fois la fiche récupérée, sinon personne : le pro ne reçoit pas les notifications de
// l'animal. Miroir appli : lib/utils/animal_proprietaire.dart ; functions/animal_destinataire.js.

type AnimalProprio = {
  uid_proprietaire?: string | null; uid_eleveur?: string | null;
  cree_par_pro_profile_id?: string | null; client_clinique_id?: string | null;
};

export function proprietaireFiche(a: AnimalProprio | null | undefined): string | null {
  if (!a) return null;
  if (a.cree_par_pro_profile_id || a.client_clinique_id) return a.uid_proprietaire ?? null;
  return a.uid_proprietaire ?? a.uid_eleveur ?? null;
}
