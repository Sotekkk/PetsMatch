-- ============================================================
-- PetsMatch — Forfaits garde (petsitter/promeneur)
-- Mirror de migration_education_forfaits.sql : nb_visites au lieu
-- de nb_seances (vocabulaire garde), même schéma sinon.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS forfaits_garde (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  pro_uid         TEXT NOT NULL,
  pro_profile_id  UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
  nom             TEXT NOT NULL,
  nb_visites      INTEGER NOT NULL DEFAULT 1,
  prix            NUMERIC NOT NULL DEFAULT 0,
  description     TEXT,
  actif           BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_forfaits_garde_pro ON forfaits_garde(pro_uid, actif);

ALTER TABLE forfaits_garde ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Select forfaits_garde" ON forfaits_garde;
CREATE POLICY "Select forfaits_garde" ON forfaits_garde FOR SELECT USING (true);

DROP POLICY IF EXISTS "Insert forfaits_garde" ON forfaits_garde;
CREATE POLICY "Insert forfaits_garde" ON forfaits_garde
  FOR INSERT WITH CHECK (pro_uid IS NOT NULL AND length(pro_uid) > 0);

DROP POLICY IF EXISTS "Update forfaits_garde" ON forfaits_garde;
CREATE POLICY "Update forfaits_garde" ON forfaits_garde FOR UPDATE USING (true);

DROP POLICY IF EXISTS "Delete forfaits_garde" ON forfaits_garde;
CREATE POLICY "Delete forfaits_garde" ON forfaits_garde FOR DELETE USING (true);
