-- Migration : factures — ajout profile_id (user_profiles.id)
-- Remplace uid_eleveur (Firebase UID) par profile_id UUID

ALTER TABLE factures
  ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE factures f
SET profile_id = up.id
FROM user_profiles up
WHERE up.uid = f.uid_eleveur
  AND up.is_main = true
  AND f.profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_factures_profile_id ON factures(profile_id);
