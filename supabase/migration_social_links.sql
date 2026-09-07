-- Réseau social particulier : rattacher likes et relations de suivi au PROFIL
-- (user_profiles.id), pas seulement au uid — même logique que
-- posts_socialmedia.author_profile_id (migration_social_author_profile.sql).

ALTER TABLE post_likes
  ADD COLUMN IF NOT EXISTS author_profile_id UUID
    REFERENCES user_profiles(id) ON DELETE SET NULL;

ALTER TABLE follows
  ADD COLUMN IF NOT EXISTS follower_profile_id  UUID
    REFERENCES user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS following_profile_id UUID
    REFERENCES user_profiles(id) ON DELETE SET NULL;

-- Backfill : profil particulier de l'uid (is_main d'abord si plusieurs).
CREATE OR REPLACE FUNCTION _particulier_pid(p_uid TEXT) RETURNS UUID AS $$
  SELECT id FROM user_profiles
  WHERE uid = p_uid AND profile_type = 'particulier'
  ORDER BY is_main DESC NULLS LAST, created_at ASC
  LIMIT 1;
$$ LANGUAGE sql STABLE;

UPDATE post_likes
SET author_profile_id = _particulier_pid(uid)
WHERE author_profile_id IS NULL;

UPDATE follows
SET follower_profile_id  = _particulier_pid(follower_uid),
    following_profile_id = _particulier_pid(following_uid)
WHERE follower_profile_id IS NULL OR following_profile_id IS NULL;

DROP FUNCTION _particulier_pid(TEXT);
