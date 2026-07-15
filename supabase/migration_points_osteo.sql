-- ============================================================
-- PetsMatch — Santé (ostéopathe/kiné) : points travaillés sur
-- schéma anatomique interactif (chien/chat/cheval)
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS points_osteo (
  id             UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  animal_id      TEXT NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  pro_uid        TEXT NOT NULL,
  pro_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  rdv_id         UUID REFERENCES rdv(id) ON DELETE SET NULL,
  espece         TEXT NOT NULL,             -- chien / chat / cheval
  vue            TEXT NOT NULL DEFAULT 'mediale', -- laterale / mediale
  x_pct          NUMERIC(5,2) NOT NULL,     -- position en % de la largeur de l'image (0-100)
  y_pct          NUMERIC(5,2) NOT NULL,     -- position en % de la hauteur de l'image (0-100)
  categorie      TEXT NOT NULL,             -- tension_cervicale / tension_thoracique / tension_lombaire /
                                             -- tension_sacro_iliaque / trigger / acupuncture / autre
  note           TEXT,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_points_osteo_animal ON points_osteo(animal_id);
CREATE INDEX IF NOT EXISTS idx_points_osteo_pro     ON points_osteo(pro_uid, pro_profile_id);

ALTER TABLE points_osteo ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Select points_osteo" ON points_osteo;
CREATE POLICY "Select points_osteo" ON points_osteo FOR SELECT USING (true);

DROP POLICY IF EXISTS "Insert points_osteo" ON points_osteo;
CREATE POLICY "Insert points_osteo" ON points_osteo
  FOR INSERT WITH CHECK (pro_uid IS NOT NULL AND length(pro_uid) > 0);

DROP POLICY IF EXISTS "Update points_osteo" ON points_osteo;
CREATE POLICY "Update points_osteo" ON points_osteo FOR UPDATE USING (true);

DROP POLICY IF EXISTS "Delete points_osteo" ON points_osteo;
CREATE POLICY "Delete points_osteo" ON points_osteo FOR DELETE USING (true);
