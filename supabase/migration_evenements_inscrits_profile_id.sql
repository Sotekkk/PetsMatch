-- Migration : evenements_inscrits — ajout profile_id (user_profiles.id)
-- Remplace user_uid (Firebase UID) par profile_id UUID

ALTER TABLE evenements_inscrits
  ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES user_profiles(id) ON DELETE CASCADE;

UPDATE evenements_inscrits ei
SET profile_id = up.id
FROM user_profiles up
WHERE up.uid = ei.user_uid
  AND up.is_main = true
  AND ei.profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_evenements_inscrits_profile ON evenements_inscrits(profile_id);

-- Contrainte d'unicité sur (evenement_id, profile_id) pour éviter les doublons
CREATE UNIQUE INDEX IF NOT EXISTS uq_evenements_inscrits_profile
  ON evenements_inscrits(evenement_id, profile_id)
  WHERE profile_id IS NOT NULL;
