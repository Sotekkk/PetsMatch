// Autorisations d'un employé de pension (employe_permissions.permission).
// Les actions pension donnent aussi « Planning pension » (voir les
// pensionnaires). Contrôle côté base : migration_employe_pension_actions.sql.
// Miroir appli : _kPerms / _permApplies (employes_page.dart).

export const PERMS_ACTIONS_PENSION = [
  { key: 'pension_arrivees_sorties', label: 'Arrivées et sorties', desc: "Enregistrer l'arrivée et le départ des pensionnaires" },
  { key: 'pension_nouvelles',        label: 'Nouvelles + photos',  desc: 'Envoyer des nouvelles avec photos ou vidéos au propriétaire' },
  { key: 'pension_logements',        label: 'Changer de logement', desc: "Déplacer un pensionnaire d'un logement à un autre" },
  { key: 'pension_consignes',        label: 'Consignes du séjour', desc: 'Compléter les consignes du séjour' },
] as const;

/** Autorisations proposées dans « Mes employés » de la pension. */
export const PERMS_PENSION = [
  { key: 'read_planning_pension', label: 'Planning pension', desc: "Voir les pensionnaires, le planning d'occupation et leurs fiches" },
  ...PERMS_ACTIONS_PENSION,
  { key: 'write_sante',      label: 'Carnet de santé', desc: 'Vaccins, traitements, poids' },
  { key: 'write_planning',   label: 'Planning & tâches', desc: 'Créer et modifier les tâches' },
  { key: 'write_inventaire', label: 'Inventaire', desc: 'Gérer les stocks et alertes' },
  { key: 'write_notes',      label: 'Notes', desc: 'Ajouter des notes internes' },
] as const;

/** Une action pension sans voir les pensionnaires n'aurait pas de sens. */
export function completerPermsPension(perms: Set<string>): Set<string> {
  const s = new Set(perms);
  if ([...s].some(p => p.startsWith('pension_'))) s.add('read_planning_pension');
  return s;
}
