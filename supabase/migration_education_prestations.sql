-- ============================================================
-- PetsMatch — Éducateur/comportementaliste : catalogue de cours personnalisé
-- Remplace la liste fixe (cours individuel/évaluation/autre) par des types de
-- cours définis par le pro lui-même (nom + durée), même modèle que
-- prestations_toilettage / prestations_photographe.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS prestations_education (
  id             UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  pro_uid        TEXT NOT NULL,
  pro_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  nom            TEXT NOT NULL,
  description    TEXT,
  duree_minutes  INTEGER NOT NULL DEFAULT 60,
  prix           NUMERIC,
  bilan_requis   BOOLEAN NOT NULL DEFAULT false, -- remplace le motif "évaluation" codé en dur
  domicile_ok    BOOLEAN NOT NULL DEFAULT true,  -- ce type de cours peut être proposé à domicile
  actif          BOOLEAN NOT NULL DEFAULT true,
  ordre          INTEGER DEFAULT 0,
  created_at     TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_prestations_education_pro ON prestations_education(pro_uid, actif);

ALTER TABLE prestations_education ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "prestations_education_all" ON prestations_education;
CREATE POLICY "prestations_education_all" ON prestations_education
  FOR ALL USING (true) WITH CHECK (true);
