-- Protocoles crees par un employe (autorise par l'employeur) : trace qui a
-- cree le protocole pour l'afficher a l'employeur et auto-attribuer les
-- taches generees au createur. Aucune contrainte sur profil_source /
-- employe_permissions.permission (colonnes texte libres) : "pension" et la
-- nouvelle permission write_protocoles n'ont donc pas besoin d'etre ajoutees
-- ici, seulement cote application.
alter table plan_templates
  add column if not exists created_by_uid text,
  add column if not exists created_by_profile_id uuid;
