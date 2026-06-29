-- Migration : partage_tokens — ajout profile_id (user_profiles.id)
-- Remplace owner_id (Firebase UID) par UUID user_profiles

ALTER TABLE partage_tokens
  ADD COLUMN IF NOT EXISTS owner_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE partage_tokens t
SET owner_profile_id = up.id
FROM user_profiles up
WHERE up.uid = t.owner_id
  AND up.is_main = true
  AND t.owner_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_partage_tokens_owner_profile ON partage_tokens(owner_profile_id);
