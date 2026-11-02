// Nom affiché d'un client depuis sa ligne user_profiles(_complet) : profil
// particulier → prénom + nom de la personne (le champ « nom » peut porter le
// nom d'élevage du compte) ; structure (élevage, pro, asso) → son nom.
// La sélection doit inclure profile_type, firstname, lastname, nom.
// Miroir appli : lib/utils/nom_client.dart.
export function nomClientProfil(p: { nom?: unknown; firstname?: unknown; lastname?: unknown; profile_type?: unknown }, defaut = ''): string {
  const nom = String(p.nom ?? '').trim();
  const complet = `${String(p.firstname ?? '')} ${String(p.lastname ?? '')}`.trim();
  const n = p.profile_type === 'particulier' ? (complet || nom) : (nom || complet);
  return n || defaut;
}
