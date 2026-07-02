-- ============================================================
-- PetsMatch — Logements / Chenil pour les pensions
-- Réutilise enclos_chenil (déjà générique via uid_eleveur) pour
-- les logements de pension, et ajoute la liaison depuis pension_entrees.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE pension_entrees
  ADD COLUMN IF NOT EXISTS logement_id UUID REFERENCES enclos_chenil(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_pension_entrees_logement ON pension_entrees(logement_id);

-- Tarifs / arrhes configurables sur le profil pro pension
-- tarifs_logements : { "box": 25, "enclos": 35, ... } — prix/nuit par type de logement
-- Ajouté sur user_profiles (profils secondaires) ET users (profil principal),
-- comme durees_motifs qui suit le même besoin de double stockage.
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS arrhes_pourcentage INTEGER,
  ADD COLUMN IF NOT EXISTS tarifs_logements JSONB DEFAULT '{}';

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS arrhes_pourcentage INTEGER,
  ADD COLUMN IF NOT EXISTS tarifs_logements JSONB DEFAULT '{}';
