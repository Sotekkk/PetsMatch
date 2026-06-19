-- ─────────────────────────────────────────────────────────────────────────────
-- Cession d'animal : colonnes supplémentaires sur la table animaux
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE animaux
  ADD COLUMN IF NOT EXISTS uid_acquereur          TEXT,
  ADD COLUMN IF NOT EXISTS cession_contrat_url    TEXT,
  ADD COLUMN IF NOT EXISTS cession_certificat_url TEXT,
  ADD COLUMN IF NOT EXISTS cession_prix           NUMERIC,
  ADD COLUMN IF NOT EXISTS cession_notes          TEXT;

-- Index pour permettre la requête "animaux reçus" (vue acquéreur)
CREATE INDEX IF NOT EXISTS idx_animaux_uid_acquereur ON animaux(uid_acquereur);
