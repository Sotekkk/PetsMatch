-- ============================================================
-- PetsMatch — Éducateur : outil de suivi partagé (Phase 3)
-- Boucle de retour : la famille commente / filme un exercice attribué,
-- l'éducateur le voit avant la séance suivante.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS exercices_retours (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  attribution_id    UUID NOT NULL REFERENCES exercices_attribues(id) ON DELETE CASCADE,
  author_uid        TEXT NOT NULL,
  author_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  note              TEXT,
  -- [{ "type": "image" | "video", "url": "..." }]
  media             JSONB NOT NULL DEFAULT '[]'::jsonb,
  ressenti          TEXT CHECK (ressenti IN ('facile', 'moyen', 'difficile', 'bloque')),
  -- true = écrit par l'éducateur (réponse), false / NULL = par la famille
  from_pro          BOOLEAN NOT NULL DEFAULT false,
  vu_par_pro        BOOLEAN NOT NULL DEFAULT false,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_exercices_retours_attribution
  ON exercices_retours (attribution_id);

ALTER TABLE exercices_retours ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "exercices_retours_all" ON exercices_retours;
CREATE POLICY "exercices_retours_all" ON exercices_retours
  FOR ALL USING (true) WITH CHECK (true);
