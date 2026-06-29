-- Migration : ordonnances — ajout profile_id (user_profiles.id)
-- Remplace pro_uid / owner_uid (Firebase UIDs) par UUID user_profiles

ALTER TABLE ordonnances
  ADD COLUMN IF NOT EXISTS pro_profile_id   UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS owner_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE ordonnances o
SET pro_profile_id = up.id
FROM user_profiles up
WHERE up.uid = o.pro_uid
  AND up.is_main = true
  AND o.pro_profile_id IS NULL;

UPDATE ordonnances o
SET owner_profile_id = up.id
FROM user_profiles up
WHERE up.uid = o.owner_uid
  AND up.is_main = true
  AND o.owner_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_ordonnances_pro_profile   ON ordonnances(pro_profile_id);
CREATE INDEX IF NOT EXISTS idx_ordonnances_owner_profile ON ordonnances(owner_profile_id);
