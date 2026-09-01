-- ============================================================================
-- Alertes cyanobactéries — point précis sur la zone d'eau + statut
-- suspecté / confirmé + photo (une alerte par lieu, sur natural_places).
-- À exécuter dans Supabase → SQL Editor (idempotent).
-- ============================================================================

ALTER TABLE natural_places
  ADD COLUMN IF NOT EXISTS alerte_cyano_lat       DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS alerte_cyano_lng       DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS alerte_cyano_statut    TEXT,   -- 'suspecte' | 'confirme'
  ADD COLUMN IF NOT EXISTS alerte_cyano_photo_url TEXT;

-- Backfill : les alertes existantes (booléen seul) deviennent "suspecte",
-- point = coordonnées du lieu.
UPDATE natural_places
SET alerte_cyano_statut = 'suspecte',
    alerte_cyano_lat    = COALESCE(alerte_cyano_lat, lat),
    alerte_cyano_lng    = COALESCE(alerte_cyano_lng, lng)
WHERE alerte_cyano = true AND alerte_cyano_statut IS NULL;
