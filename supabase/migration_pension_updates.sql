-- ============================================================
-- PetsMatch — Journal de séjour pension (nouvelles au propriétaire)
-- Photo/vidéo/note postées par la pension pendant le séjour, visibles
-- par le propriétaire une fois la fiche liée (animal_id).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS pension_updates (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pension_entree_id UUID REFERENCES pension_entrees(id) ON DELETE CASCADE,
  animal_id         TEXT REFERENCES animaux(id) ON DELETE CASCADE,
  pro_uid           TEXT NOT NULL,
  photo_url         TEXT,
  video_url         TEXT,
  note              TEXT,
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pension_updates_entree ON pension_updates(pension_entree_id);
CREATE INDEX IF NOT EXISTS idx_pension_updates_animal ON pension_updates(animal_id);

ALTER TABLE pension_updates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Select pension_updates" ON pension_updates;
CREATE POLICY "Select pension_updates" ON pension_updates
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Insert pension_updates" ON pension_updates;
CREATE POLICY "Insert pension_updates" ON pension_updates
  FOR INSERT WITH CHECK (pro_uid IS NOT NULL AND length(pro_uid) > 0);

DROP POLICY IF EXISTS "Delete pension_updates" ON pension_updates;
CREATE POLICY "Delete pension_updates" ON pension_updates
  FOR DELETE USING (true);
