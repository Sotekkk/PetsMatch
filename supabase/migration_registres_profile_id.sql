-- Migration: ajouter eleveur_profile_id aux registres mouvements et sanitaire

-- registre_mouvements
ALTER TABLE registre_mouvements
  ADD COLUMN IF NOT EXISTS eleveur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE registre_mouvements r
SET eleveur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = r.uid_eleveur
  AND up.is_main = true
  AND r.eleveur_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS registre_mouvements_eleveur_profile_id_idx ON registre_mouvements(eleveur_profile_id);

-- registre_sanitaire
ALTER TABLE registre_sanitaire
  ADD COLUMN IF NOT EXISTS eleveur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE registre_sanitaire r
SET eleveur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = r.uid_eleveur
  AND up.is_main = true
  AND r.eleveur_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS registre_sanitaire_eleveur_profile_id_idx ON registre_sanitaire(eleveur_profile_id);
