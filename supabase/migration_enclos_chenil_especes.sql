-- ============================================================
-- PetsMatch — Espèces acceptées par logement (enclos_chenil)
-- Permet de filtrer les logements/le planning par espèce.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE enclos_chenil
  ADD COLUMN IF NOT EXISTS especes TEXT[] DEFAULT '{}';
