-- ============================================================
-- PetsMatch V2 — Patch 10 : profile_id sur likes et favoris
-- ============================================================

ALTER TABLE likes    ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;
ALTER TABLE favoris  ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_likes_profile_id   ON likes(profile_id);
CREATE INDEX IF NOT EXISTS idx_favoris_profile_id ON favoris(profile_id);

-- Backfill : rattacher les likes existants au profil principal de l'utilisateur
UPDATE likes l
SET profile_id = (
  SELECT up.id FROM user_profiles up
  WHERE up.uid = l.user_uid
    AND (l.profile_type IS NULL OR up.profile_type = l.profile_type OR up.is_main = true)
  ORDER BY up.is_main DESC, up.created_at ASC
  LIMIT 1
)
WHERE l.profile_id IS NULL;

UPDATE favoris f
SET profile_id = (
  SELECT up.id FROM user_profiles up
  WHERE up.uid = f.user_uid
    AND (f.profile_type IS NULL OR up.profile_type = f.profile_type OR up.is_main = true)
  ORDER BY up.is_main DESC, up.created_at ASC
  LIMIT 1
)
WHERE f.profile_id IS NULL;
