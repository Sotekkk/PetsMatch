-- Migration : partage_animal — ajout profile_id (user_profiles.id)
-- Remplace uid_partageur (Firebase UID) par UUID user_profiles

ALTER TABLE partage_animal
  ADD COLUMN IF NOT EXISTS partageur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE partage_animal p
SET partageur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = p.uid_partageur
  AND up.is_main = true
  AND p.partageur_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_partage_animal_partageur_profile ON partage_animal(partageur_profile_id);
