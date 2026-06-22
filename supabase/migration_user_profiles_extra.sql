-- Colonnes supplémentaires pour les profils secondaires (ville, description, adresse)
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS ville       TEXT,
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS adresse     TEXT,
  ADD COLUMN IF NOT EXISTS telephone   TEXT,
  ADD COLUMN IF NOT EXISTS site_web    TEXT;
