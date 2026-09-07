-- Réseau social particulier : rattacher chaque post / commentaire au PROFIL
-- (user_profiles.id) depuis lequel il a été publié, pas seulement au uid.
-- Un utilisateur multi-profils (éleveur + particulier…) publie toujours
-- depuis son profil PARTICULIER — l'affichage doit montrer cette identité,
-- jamais le profil pro / is_main.

ALTER TABLE posts_socialmedia
  ADD COLUMN IF NOT EXISTS author_profile_id UUID
    REFERENCES user_profiles(id) ON DELETE SET NULL;

ALTER TABLE post_comments
  ADD COLUMN IF NOT EXISTS author_profile_id UUID
    REFERENCES user_profiles(id) ON DELETE SET NULL;

-- Backfill : profil particulier de l'auteur (is_main d'abord si plusieurs).
UPDATE posts_socialmedia p
SET author_profile_id = up.id
FROM user_profiles up
WHERE up.uid = p.uid
  AND up.profile_type = 'particulier'
  AND p.author_profile_id IS NULL
  AND up.id = (
    SELECT id FROM user_profiles
    WHERE uid = p.uid AND profile_type = 'particulier'
    ORDER BY is_main DESC NULLS LAST, created_at ASC
    LIMIT 1
  );

UPDATE post_comments c
SET author_profile_id = up.id
FROM user_profiles up
WHERE up.uid = c.uid
  AND up.profile_type = 'particulier'
  AND c.author_profile_id IS NULL
  AND up.id = (
    SELECT id FROM user_profiles
    WHERE uid = c.uid AND profile_type = 'particulier'
    ORDER BY is_main DESC NULLS LAST, created_at ASC
    LIMIT 1
  );
