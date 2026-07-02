-- ============================================================
-- PetsMatch — Documents légaux association (statuts, arrêté préfectoral)
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS statuts_url             TEXT,
  ADD COLUMN IF NOT EXISTS arrete_prefectoral_url  TEXT;
