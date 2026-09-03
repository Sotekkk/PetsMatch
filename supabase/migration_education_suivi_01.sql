-- ============================================================
-- PetsMatch — Éducateur : outil de suivi partagé (Phase 1)
-- Plan de travail = objectifs comportementaux partagés éducateur ↔ famille.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS education_objectifs (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_uid           TEXT NOT NULL,
  pro_profile_id    UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  animal_id         TEXT NOT NULL,
  owner_uid         TEXT,
  owner_profile_id  UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  libelle           TEXT NOT NULL,
  -- rappel / laisse / proprete / aboiements / destruction / socialisation_chien
  -- / socialisation_humain / manipulation / solitude / agressivite / peurs / autre
  categorie         TEXT,
  statut            TEXT NOT NULL DEFAULT 'a_travailler'
                      CHECK (statut IN ('a_travailler', 'en_cours', 'acquis')),
  ordre             INTEGER NOT NULL DEFAULT 0,
  note              TEXT,
  acquis_le         TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_education_objectifs_animal
  ON education_objectifs (animal_id);
CREATE INDEX IF NOT EXISTS idx_education_objectifs_pro
  ON education_objectifs (pro_uid, pro_profile_id);

ALTER TABLE education_objectifs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "education_objectifs_all" ON education_objectifs;
CREATE POLICY "education_objectifs_all" ON education_objectifs
  FOR ALL USING (true) WITH CHECK (true);
