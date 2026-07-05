-- ============================================================
-- PetsMatch — Éducateur/comportementaliste : champ "Exercices
-- conseillés" distinct du compte rendu libre, sur education_progression.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE education_progression
  ADD COLUMN IF NOT EXISTS exercices_conseilles TEXT;
