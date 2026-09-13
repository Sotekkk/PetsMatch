-- La contrainte CHECK d'origine (migration_v2_02_access_members.sql) ne
-- couvrait que 'pending'/'active'/'revoked'. Le site utilise déjà
-- 'write_requested' (demande d'accès écriture élargie, ex. pet-sitter voulant
-- ajouter un vaccin) et 'active_write' (validation par le propriétaire) sans
-- que la contrainte les autorise — chaque tentative échoue silencieusement
-- (23514 check constraint violation). Élargit la contrainte pour couvrir ces
-- deux statuts déjà référencés dans le code (site + appli).
ALTER TABLE animal_access DROP CONSTRAINT IF EXISTS animal_access_statut_check;
ALTER TABLE animal_access ADD CONSTRAINT animal_access_statut_check
  CHECK (statut IN ('pending', 'active', 'active_write', 'write_requested', 'revoked'));
