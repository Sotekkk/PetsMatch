-- Migration : groupes communautaires — ajout profile_id sur toutes les tables
-- Remplace createur_uid / auteur_uid / user_uid (Firebase UIDs) par UUID user_profiles

-- ── groupes ──────────────────────────────────────────────────────────────────
ALTER TABLE groupes
  ADD COLUMN IF NOT EXISTS createur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE groupes g
SET createur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = g.createur_uid
  AND up.is_main = true
  AND g.createur_profile_id IS NULL;

-- ── groupes_membres ───────────────────────────────────────────────────────────
ALTER TABLE groupes_membres
  ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES user_profiles(id) ON DELETE CASCADE;

UPDATE groupes_membres gm
SET profile_id = up.id
FROM user_profiles up
WHERE up.uid = gm.user_uid
  AND up.is_main = true
  AND gm.profile_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_groupes_membres_profile
  ON groupes_membres(groupe_id, profile_id) WHERE profile_id IS NOT NULL;

-- ── groupe_posts ──────────────────────────────────────────────────────────────
ALTER TABLE groupe_posts
  ADD COLUMN IF NOT EXISTS auteur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE groupe_posts gp
SET auteur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = gp.auteur_uid
  AND up.is_main = true
  AND gp.auteur_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_groupe_posts_auteur_profile ON groupe_posts(auteur_profile_id);

-- ── groupe_post_likes ─────────────────────────────────────────────────────────
ALTER TABLE groupe_post_likes
  ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES user_profiles(id) ON DELETE CASCADE;

UPDATE groupe_post_likes l
SET profile_id = up.id
FROM user_profiles up
WHERE up.uid = l.user_uid
  AND up.is_main = true
  AND l.profile_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_groupe_post_likes_profile
  ON groupe_post_likes(post_id, profile_id) WHERE profile_id IS NOT NULL;

-- ── groupe_post_commentaires ──────────────────────────────────────────────────
ALTER TABLE groupe_post_commentaires
  ADD COLUMN IF NOT EXISTS auteur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE groupe_post_commentaires c
SET auteur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = c.auteur_uid
  AND up.is_main = true
  AND c.auteur_profile_id IS NULL;

-- ── groupe_commentaire_likes ──────────────────────────────────────────────────
ALTER TABLE groupe_commentaire_likes
  ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES user_profiles(id) ON DELETE CASCADE;

UPDATE groupe_commentaire_likes l
SET profile_id = up.id
FROM user_profiles up
WHERE up.uid = l.user_uid
  AND up.is_main = true
  AND l.profile_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_groupe_commentaire_likes_profile
  ON groupe_commentaire_likes(comment_id, profile_id) WHERE profile_id IS NOT NULL;
