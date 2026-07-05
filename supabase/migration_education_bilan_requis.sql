-- ============================================================
-- PetsMatch — Éducateur/comportementaliste : bilan préalable obligatoire
-- Un nouveau client ne peut réserver qu'un bilan (évaluation) tant qu'il
-- n'a pas eu de séance confirmée avec ce pro — sauf si le pro désactive
-- cette exigence (certains acceptent la prise de cours directement).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS education_bilan_requis BOOLEAN DEFAULT true;
