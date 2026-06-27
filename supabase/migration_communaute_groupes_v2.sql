-- Migration: communauté groupes v2
-- Ajout règles, statut membres, posts et likes

-- 1. Colonnes supplémentaires pour groupes
ALTER TABLE groupes
  ADD COLUMN IF NOT EXISTS regles       JSONB    DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS photo_cover_url TEXT;

-- 2. Statut dans groupes_membres (active / pending / banned)
ALTER TABLE groupes_membres
  ADD COLUMN IF NOT EXISTS statut TEXT DEFAULT 'active'
    CHECK (statut IN ('active', 'pending', 'banned'));

-- Index pour filtrer les membres actifs
CREATE INDEX IF NOT EXISTS idx_gm_statut ON groupes_membres (groupe_id, statut);

-- 3. Table posts dans les groupes
CREATE TABLE IF NOT EXISTS groupe_posts (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  groupe_id    UUID        NOT NULL REFERENCES groupes(id) ON DELETE CASCADE,
  auteur_uid   TEXT        NOT NULL,
  contenu      TEXT        NOT NULL,
  image_url    TEXT,
  epingle      BOOLEAN     DEFAULT FALSE,
  like_count   INTEGER     DEFAULT 0,
  comment_count INTEGER    DEFAULT 0,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_gp_groupe    ON groupe_posts (groupe_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_gp_auteur    ON groupe_posts (auteur_uid);

ALTER TABLE groupe_posts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "gp_select" ON groupe_posts;
CREATE POLICY "gp_select" ON groupe_posts FOR SELECT USING (true);
DROP POLICY IF EXISTS "gp_insert" ON groupe_posts;
CREATE POLICY "gp_insert" ON groupe_posts FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "gp_update" ON groupe_posts;
CREATE POLICY "gp_update" ON groupe_posts FOR UPDATE USING (true);
DROP POLICY IF EXISTS "gp_delete" ON groupe_posts;
CREATE POLICY "gp_delete" ON groupe_posts FOR DELETE USING (true);

-- 4. Likes sur les posts
CREATE TABLE IF NOT EXISTS groupe_post_likes (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id    UUID        NOT NULL REFERENCES groupe_posts(id) ON DELETE CASCADE,
  user_uid   TEXT        NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(post_id, user_uid)
);

CREATE INDEX IF NOT EXISTS idx_gpl_post ON groupe_post_likes (post_id);
CREATE INDEX IF NOT EXISTS idx_gpl_user ON groupe_post_likes (user_uid);

ALTER TABLE groupe_post_likes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "gpl_all" ON groupe_post_likes;
CREATE POLICY "gpl_all" ON groupe_post_likes FOR ALL USING (true);

-- 5. Commentaires sur les posts
CREATE TABLE IF NOT EXISTS groupe_post_commentaires (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id    UUID        NOT NULL REFERENCES groupe_posts(id) ON DELETE CASCADE,
  auteur_uid TEXT        NOT NULL,
  contenu    TEXT        NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_gpc_post ON groupe_post_commentaires (post_id, created_at);

ALTER TABLE groupe_post_commentaires ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "gpc_all" ON groupe_post_commentaires;
CREATE POLICY "gpc_all" ON groupe_post_commentaires FOR ALL USING (true);
