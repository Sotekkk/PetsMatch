-- ============================================================
-- PetsMatch V2 — Patch 09 : statistiques détaillées annonces
-- ============================================================

-- ── 1. Stats journalières par annonce ─────────────────────
CREATE TABLE IF NOT EXISTS annonces_stats_daily (
  id           UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  annonce_id   TEXT        NOT NULL REFERENCES annonces(id) ON DELETE CASCADE,
  date         DATE        NOT NULL DEFAULT CURRENT_DATE,
  vues         INT         NOT NULL DEFAULT 0,
  visiteurs    INT         NOT NULL DEFAULT 0, -- compteur sessions uniques (approximatif)
  contacts     INT         NOT NULL DEFAULT 0,
  favoris      INT         NOT NULL DEFAULT 0,
  partages     INT         NOT NULL DEFAULT 0,
  UNIQUE (annonce_id, date)
);
CREATE INDEX IF NOT EXISTS idx_stats_daily_annonce ON annonces_stats_daily(annonce_id, date DESC);

-- ── 2. Stats par chiot de portée ──────────────────────────
CREATE TABLE IF NOT EXISTS animaux_portee_stats (
  id           UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  annonce_id   TEXT        NOT NULL REFERENCES annonces(id) ON DELETE CASCADE,
  bebe_index   INT         NOT NULL,
  date         DATE        NOT NULL DEFAULT CURRENT_DATE,
  vues         INT         NOT NULL DEFAULT 0,
  favoris      INT         NOT NULL DEFAULT 0,
  UNIQUE (annonce_id, bebe_index, date)
);
CREATE INDEX IF NOT EXISTS idx_portee_stats_annonce ON animaux_portee_stats(annonce_id, date DESC);

-- ── 3. Origine géographique des vues ──────────────────────
CREATE TABLE IF NOT EXISTS annonces_views_geo (
  id           UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  annonce_id   TEXT        NOT NULL REFERENCES annonces(id) ON DELETE CASCADE,
  departement  TEXT        NOT NULL DEFAULT 'inconnu',
  vues         INT         NOT NULL DEFAULT 0,
  updated_at   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (annonce_id, departement)
);
CREATE INDEX IF NOT EXISTS idx_views_geo_annonce ON annonces_views_geo(annonce_id);

-- RLS permissif (auth Firebase → uid null)
ALTER TABLE annonces_stats_daily  ENABLE ROW LEVEL SECURITY;
ALTER TABLE animaux_portee_stats  ENABLE ROW LEVEL SECURITY;
ALTER TABLE annonces_views_geo    ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS stats_daily_all  ON annonces_stats_daily;
DROP POLICY IF EXISTS portee_stats_all ON animaux_portee_stats;
DROP POLICY IF EXISTS views_geo_all    ON annonces_views_geo;
CREATE POLICY stats_daily_all  ON annonces_stats_daily  USING (true) WITH CHECK (true);
CREATE POLICY portee_stats_all ON animaux_portee_stats  USING (true) WITH CHECK (true);
CREATE POLICY views_geo_all    ON annonces_views_geo    USING (true) WITH CHECK (true);

-- ── 4. Fonctions RPC pour incréments atomiques ────────────

-- Incrémenter une vue annonce (appelée depuis le front)
CREATE OR REPLACE FUNCTION increment_annonce_view(
  p_annonce_id  TEXT,
  p_departement TEXT DEFAULT 'inconnu',
  p_unique      BOOLEAN DEFAULT false
)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  -- Stats journalières
  INSERT INTO annonces_stats_daily (annonce_id, date, vues, visiteurs)
  VALUES (p_annonce_id, CURRENT_DATE, 1, CASE WHEN p_unique THEN 1 ELSE 0 END)
  ON CONFLICT (annonce_id, date) DO UPDATE
    SET vues      = annonces_stats_daily.vues + 1,
        visiteurs = annonces_stats_daily.visiteurs + CASE WHEN p_unique THEN 1 ELSE 0 END;

  -- Géo
  IF p_departement IS NOT NULL AND p_departement != '' THEN
    INSERT INTO annonces_views_geo (annonce_id, departement, vues, updated_at)
    VALUES (p_annonce_id, p_departement, 1, NOW())
    ON CONFLICT (annonce_id, departement) DO UPDATE
      SET vues = annonces_views_geo.vues + 1, updated_at = NOW();
  END IF;

  -- Compteur total sur l'annonce
  UPDATE annonces SET vues = COALESCE(vues, 0) + 1 WHERE id = p_annonce_id;
END;
$$;

-- Incrémenter une vue chiot de portée
CREATE OR REPLACE FUNCTION increment_portee_view(
  p_annonce_id TEXT,
  p_bebe_index INT
)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO animaux_portee_stats (annonce_id, bebe_index, date, vues)
  VALUES (p_annonce_id, p_bebe_index, CURRENT_DATE, 1)
  ON CONFLICT (annonce_id, bebe_index, date) DO UPDATE
    SET vues = animaux_portee_stats.vues + 1;
END;
$$;

-- Incrémenter favoris chiot de portée
CREATE OR REPLACE FUNCTION increment_portee_favori(
  p_annonce_id TEXT,
  p_bebe_index INT,
  p_delta      INT DEFAULT 1
)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO animaux_portee_stats (annonce_id, bebe_index, date, favoris)
  VALUES (p_annonce_id, p_bebe_index, CURRENT_DATE, GREATEST(0, p_delta))
  ON CONFLICT (annonce_id, bebe_index, date) DO UPDATE
    SET favoris = GREATEST(0, animaux_portee_stats.favoris + p_delta);
END;
$$;
