-- ============================================================
-- PetsMatch — Santé (ostéopathe/kiné) : restructuration en séances
-- datées (compte rendu par visite) au lieu d'un canvas unique.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS seances_osteo (
  id             UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  animal_id      TEXT NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  pro_uid        TEXT NOT NULL,
  pro_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  date_seance    DATE NOT NULL DEFAULT CURRENT_DATE,
  note           TEXT,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_seances_osteo_animal ON seances_osteo(animal_id);
CREATE INDEX IF NOT EXISTS idx_seances_osteo_pro     ON seances_osteo(pro_uid, pro_profile_id);

ALTER TABLE seances_osteo ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Select seances_osteo" ON seances_osteo;
CREATE POLICY "Select seances_osteo" ON seances_osteo FOR SELECT USING (true);

DROP POLICY IF EXISTS "Insert seances_osteo" ON seances_osteo;
CREATE POLICY "Insert seances_osteo" ON seances_osteo
  FOR INSERT WITH CHECK (pro_uid IS NOT NULL AND length(pro_uid) > 0);

DROP POLICY IF EXISTS "Update seances_osteo" ON seances_osteo;
CREATE POLICY "Update seances_osteo" ON seances_osteo FOR UPDATE USING (true);

DROP POLICY IF EXISTS "Delete seances_osteo" ON seances_osteo;
CREATE POLICY "Delete seances_osteo" ON seances_osteo FOR DELETE USING (true);

-- points_osteo rattaché à une séance (compte rendu daté) plutôt qu'un
-- canvas partagé unique.
ALTER TABLE points_osteo
  ADD COLUMN IF NOT EXISTS seance_id UUID REFERENCES seances_osteo(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_points_osteo_seance ON points_osteo(seance_id);

-- Backfill : les points déjà créés avant cette migration (sans séance)
-- sont regroupés en une séance par (animal_id, pro_profile_id, jour de
-- création) pour ne rien perdre.
DO $$
DECLARE
  r RECORD;
  new_seance_id UUID;
BEGIN
  FOR r IN
    SELECT DISTINCT animal_id, pro_uid, pro_profile_id, DATE(created_at) AS jour
    FROM points_osteo
    WHERE seance_id IS NULL
  LOOP
    INSERT INTO seances_osteo (animal_id, pro_uid, pro_profile_id, date_seance, note)
    VALUES (r.animal_id, r.pro_uid, r.pro_profile_id, r.jour, 'Séance migrée automatiquement')
    RETURNING id INTO new_seance_id;

    UPDATE points_osteo
    SET seance_id = new_seance_id
    WHERE seance_id IS NULL
      AND animal_id = r.animal_id
      AND pro_uid = r.pro_uid
      AND (pro_profile_id = r.pro_profile_id OR (pro_profile_id IS NULL AND r.pro_profile_id IS NULL))
      AND DATE(created_at) = r.jour;
  END LOOP;
END $$;
