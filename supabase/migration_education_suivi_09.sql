-- ============================================================
-- PetsMatch — Éducateur : outil de suivi partagé (Phase 9)
-- Attestation de fin de programme (PDF) remise à la famille.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS education_attestations (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  animal_id         TEXT NOT NULL,
  pro_uid           TEXT NOT NULL,
  pro_profile_id    UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  owner_uid         TEXT,
  owner_profile_id  UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  pdf_url           TEXT NOT NULL,
  contenu           JSONB,
  emise_le          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_education_attestations_animal
  ON education_attestations (animal_id);

ALTER TABLE education_attestations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "education_attestations_all" ON education_attestations;
CREATE POLICY "education_attestations_all" ON education_attestations
  FOR ALL USING (true) WITH CHECK (true);
