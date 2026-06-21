-- Migration: tables likes + favoris
-- Generated column bebe_key pour gérer bebe_index NULL dans la PK

CREATE TABLE IF NOT EXISTS likes (
  user_uid     TEXT NOT NULL,
  annonce_id   TEXT NOT NULL,
  bebe_index   INTEGER,
  bebe_key     TEXT NOT NULL GENERATED ALWAYS AS (COALESCE(bebe_index::TEXT, '__')) STORED,
  profile_type TEXT,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_uid, annonce_id, bebe_key)
);

CREATE INDEX IF NOT EXISTS idx_likes_user    ON likes (user_uid);
CREATE INDEX IF NOT EXISTS idx_likes_annonce ON likes (annonce_id);

CREATE TABLE IF NOT EXISTS favoris (
  user_uid     TEXT NOT NULL,
  annonce_id   TEXT NOT NULL,
  bebe_index   INTEGER,
  bebe_key     TEXT NOT NULL GENERATED ALWAYS AS (COALESCE(bebe_index::TEXT, '__')) STORED,
  profile_type TEXT,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_uid, annonce_id, bebe_key)
);

CREATE INDEX IF NOT EXISTS idx_favoris_user    ON favoris (user_uid);
CREATE INDEX IF NOT EXISTS idx_favoris_annonce ON favoris (annonce_id);
