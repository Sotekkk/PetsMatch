-- Migration: création complète des tables communauté (groupes + forum)
-- À exécuter AVANT migration_communaute_groupes_v2.sql

-- ── TABLE GROUPES ──────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS groupes (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  createur_uid     TEXT        NOT NULL,
  nom              TEXT        NOT NULL,
  description      TEXT        DEFAULT '',
  type             TEXT        DEFAULT 'autre'
                               CHECK (type IN ('race', 'region', 'loisir', 'autre')),
  prive            BOOLEAN     DEFAULT FALSE,
  regles           JSONB       DEFAULT '[]'::jsonb,
  photo_cover_url  TEXT,
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_groupes_type       ON groupes (type);
CREATE INDEX IF NOT EXISTS idx_groupes_createur   ON groupes (createur_uid);

ALTER TABLE groupes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "groupes_select" ON groupes;
CREATE POLICY "groupes_select" ON groupes FOR SELECT USING (true);
DROP POLICY IF EXISTS "groupes_insert" ON groupes;
CREATE POLICY "groupes_insert" ON groupes FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "groupes_update" ON groupes;
CREATE POLICY "groupes_update" ON groupes FOR UPDATE USING (true);
DROP POLICY IF EXISTS "groupes_delete" ON groupes;
CREATE POLICY "groupes_delete" ON groupes FOR DELETE USING (true);


-- ── TABLE GROUPES_MEMBRES ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS groupes_membres (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  groupe_id   UUID        NOT NULL REFERENCES groupes(id) ON DELETE CASCADE,
  user_uid    TEXT        NOT NULL,
  role        TEXT        DEFAULT 'membre' CHECK (role IN ('admin', 'membre')),
  statut      TEXT        DEFAULT 'active' CHECK (statut IN ('active', 'pending', 'banned')),
  rejoint_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(groupe_id, user_uid)
);

CREATE INDEX IF NOT EXISTS idx_gm_groupe  ON groupes_membres (groupe_id);
CREATE INDEX IF NOT EXISTS idx_gm_user    ON groupes_membres (user_uid);
CREATE INDEX IF NOT EXISTS idx_gm_statut  ON groupes_membres (groupe_id, statut);

ALTER TABLE groupes_membres ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "gm_select" ON groupes_membres;
CREATE POLICY "gm_select" ON groupes_membres FOR SELECT USING (true);
DROP POLICY IF EXISTS "gm_insert" ON groupes_membres;
CREATE POLICY "gm_insert" ON groupes_membres FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "gm_update" ON groupes_membres;
CREATE POLICY "gm_update" ON groupes_membres FOR UPDATE USING (true);
DROP POLICY IF EXISTS "gm_delete" ON groupes_membres;
CREATE POLICY "gm_delete" ON groupes_membres FOR DELETE USING (true);


-- ── TABLE GROUPE_POSTS ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS groupe_posts (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  groupe_id     UUID        NOT NULL REFERENCES groupes(id) ON DELETE CASCADE,
  auteur_uid    TEXT        NOT NULL,
  contenu       TEXT        NOT NULL,
  image_url     TEXT,
  epingle       BOOLEAN     DEFAULT FALSE,
  like_count    INTEGER     DEFAULT 0,
  comment_count INTEGER     DEFAULT 0,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_gp_groupe  ON groupe_posts (groupe_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_gp_auteur  ON groupe_posts (auteur_uid);

ALTER TABLE groupe_posts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "gp_select" ON groupe_posts;
CREATE POLICY "gp_select" ON groupe_posts FOR SELECT USING (true);
DROP POLICY IF EXISTS "gp_insert" ON groupe_posts;
CREATE POLICY "gp_insert" ON groupe_posts FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "gp_update" ON groupe_posts;
CREATE POLICY "gp_update" ON groupe_posts FOR UPDATE USING (true);
DROP POLICY IF EXISTS "gp_delete" ON groupe_posts;
CREATE POLICY "gp_delete" ON groupe_posts FOR DELETE USING (true);


-- ── TABLE GROUPE_POST_LIKES ────────────────────────────────────────────────────

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


-- ── TABLE GROUPE_POST_COMMENTAIRES ─────────────────────────────────────────────

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


-- ── TABLE FORUM_SUJETS ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS forum_sujets (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  categorie_slug TEXT        NOT NULL,
  auteur_uid     TEXT        NOT NULL,
  titre          TEXT        NOT NULL,
  contenu        TEXT        NOT NULL,
  epingle        BOOLEAN     DEFAULT FALSE,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fs_categorie ON forum_sujets (categorie_slug, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_fs_auteur    ON forum_sujets (auteur_uid);

ALTER TABLE forum_sujets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "fs_select" ON forum_sujets;
CREATE POLICY "fs_select" ON forum_sujets FOR SELECT USING (true);
DROP POLICY IF EXISTS "fs_insert" ON forum_sujets;
CREATE POLICY "fs_insert" ON forum_sujets FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "fs_update" ON forum_sujets;
CREATE POLICY "fs_update" ON forum_sujets FOR UPDATE USING (true);
DROP POLICY IF EXISTS "fs_delete" ON forum_sujets;
CREATE POLICY "fs_delete" ON forum_sujets FOR DELETE USING (true);


-- ── TABLE FORUM_REPONSES ───────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS forum_reponses (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  sujet_id   UUID        NOT NULL REFERENCES forum_sujets(id) ON DELETE CASCADE,
  auteur_uid TEXT        NOT NULL,
  contenu    TEXT        NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fr_sujet  ON forum_reponses (sujet_id, created_at);
CREATE INDEX IF NOT EXISTS idx_fr_auteur ON forum_reponses (auteur_uid);

ALTER TABLE forum_reponses ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "fr_all" ON forum_reponses;
CREATE POLICY "fr_all" ON forum_reponses FOR ALL USING (true);
