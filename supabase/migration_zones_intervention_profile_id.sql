-- Migration: pro_profile_id sur zones_intervention

ALTER TABLE zones_intervention
  ADD COLUMN IF NOT EXISTS pro_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE zones_intervention z
SET pro_profile_id = up.id
FROM user_profiles up
WHERE up.uid = z.pro_uid
  AND up.is_main = true
  AND z.pro_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS zones_intervention_pro_profile_id_idx ON zones_intervention(pro_profile_id);
