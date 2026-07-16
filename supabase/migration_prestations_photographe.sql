-- ============================================================
-- PetsMatch — Prestations photographe animalier
-- Catalogue de prestations tarifées (contrairement à forfaits_garde/
-- forfaits_education, trop pauvre : ici durée, nombre de photos, délai
-- de livraison, km inclus, acompte et options sont nécessaires).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS prestations_photographe (
  id                     UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  pro_uid                TEXT NOT NULL,
  pro_profile_id         UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
  type                   TEXT NOT NULL DEFAULT 'shooting_individuel',
  -- shooting_individuel / portee / elevage / naissance / concours / exposition / commercial
  nom                    TEXT NOT NULL,
  prix                   NUMERIC NOT NULL DEFAULT 0,
  duree_minutes          INTEGER NOT NULL DEFAULT 60,
  nb_photos              INTEGER,
  delai_livraison_jours  INTEGER NOT NULL DEFAULT 7,
  deplacement_inclus_km  INTEGER NOT NULL DEFAULT 0,
  prix_km_supp           NUMERIC NOT NULL DEFAULT 0,
  acompte_pourcentage    INTEGER NOT NULL DEFAULT 30,
  options                JSONB DEFAULT '[]'::jsonb, -- [{"nom": "...", "prix": 0}]
  description            TEXT,
  actif                  BOOLEAN NOT NULL DEFAULT true,
  created_at             TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_prestations_photographe_pro ON prestations_photographe(pro_uid, actif);

ALTER TABLE prestations_photographe ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Select prestations_photographe" ON prestations_photographe;
CREATE POLICY "Select prestations_photographe" ON prestations_photographe FOR SELECT USING (true);

DROP POLICY IF EXISTS "Insert prestations_photographe" ON prestations_photographe;
CREATE POLICY "Insert prestations_photographe" ON prestations_photographe
  FOR INSERT WITH CHECK (pro_uid IS NOT NULL AND length(pro_uid) > 0);

DROP POLICY IF EXISTS "Update prestations_photographe" ON prestations_photographe;
CREATE POLICY "Update prestations_photographe" ON prestations_photographe FOR UPDATE USING (true);

DROP POLICY IF EXISTS "Delete prestations_photographe" ON prestations_photographe;
CREATE POLICY "Delete prestations_photographe" ON prestations_photographe FOR DELETE USING (true);
