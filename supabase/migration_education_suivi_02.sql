-- ============================================================
-- PetsMatch — Éducateur : outil de suivi partagé (Phase 2)
-- Bibliothèque d'exercices de l'éducateur + attribution à une famille.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

-- ─── Catalogue de l'éducateur ───────────────────────────────
CREATE TABLE IF NOT EXISTS exercices_bibliotheque (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_uid           TEXT NOT NULL,
  pro_profile_id    UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  titre             TEXT NOT NULL,
  description       TEXT,
  -- [{ "type": "image" | "video", "url": "..." }]
  media             JSONB NOT NULL DEFAULT '[]'::jsonb,
  categorie         TEXT,
  actif             BOOLEAN NOT NULL DEFAULT true,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_exercices_biblio_pro
  ON exercices_bibliotheque (pro_uid, actif);

ALTER TABLE exercices_bibliotheque ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "exercices_bibliotheque_all" ON exercices_bibliotheque;
CREATE POLICY "exercices_bibliotheque_all" ON exercices_bibliotheque
  FOR ALL USING (true) WITH CHECK (true);

-- ─── Attribution à une famille (snapshots figés) ────────────
CREATE TABLE IF NOT EXISTS exercices_attribues (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  exercice_id           UUID REFERENCES exercices_bibliotheque(id) ON DELETE SET NULL,
  pro_uid               TEXT NOT NULL,
  pro_profile_id        UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  animal_id             TEXT NOT NULL,
  owner_uid             TEXT,
  owner_profile_id      UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  objectif_id           UUID REFERENCES education_objectifs(id) ON DELETE SET NULL,
  -- si l'exercice est attaché à un compte rendu de séance
  progression_id        UUID,
  titre_snapshot        TEXT NOT NULL,
  description_snapshot  TEXT,
  media_snapshot        JSONB NOT NULL DEFAULT '[]'::jsonb,
  cadence               TEXT,
  echeance              DATE,
  statut                TEXT NOT NULL DEFAULT 'a_faire'
                          CHECK (statut IN ('a_faire', 'en_cours', 'fait', 'abandonne')),
  rappels_actifs        BOOLEAN NOT NULL DEFAULT false,
  assigned_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_exercices_attribues_animal
  ON exercices_attribues (animal_id);
CREATE INDEX IF NOT EXISTS idx_exercices_attribues_pro
  ON exercices_attribues (pro_uid, pro_profile_id);

ALTER TABLE exercices_attribues ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "exercices_attribues_all" ON exercices_attribues;
CREATE POLICY "exercices_attribues_all" ON exercices_attribues
  FOR ALL USING (true) WITH CHECK (true);
