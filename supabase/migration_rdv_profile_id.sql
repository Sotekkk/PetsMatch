-- Migration: ajouter client_profile_id à la table rdv
-- pro_profile_id existe déjà ; on ajoute le côté client

ALTER TABLE rdv
  ADD COLUMN IF NOT EXISTS client_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

-- Backfill depuis client_uid
UPDATE rdv r
SET client_profile_id = up.id
FROM user_profiles up
WHERE up.uid = r.client_uid
  AND up.is_main = true
  AND r.client_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS rdv_client_profile_id_idx ON rdv(client_profile_id);
