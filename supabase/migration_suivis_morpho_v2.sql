-- ============================================================
-- PetsMatch — Suivi morphologique & bien-être — v2 (fusion avec Anatomie)
-- Remplace la table de zones nommées fixes par un système de points libres
-- (x%/y% + catégorie), repris tel quel du mécanisme d'anatomie_points_page.dart
-- (seances_osteo/points_osteo) à la demande explicite : garder le geste de
-- pointage libre existant, mais l'intégrer dans le compte-rendu structuré
-- (suivis_morpho + photos/vidéos/observations). seances_osteo/points_osteo
-- restent intacts (utilisés par maréchal-ferrant, non concerné par cette
-- fusion) — cette migration ne les touche pas.
-- À exécuter APRÈS migration_suivis_morpho.sql, dans l'éditeur SQL Supabase.
-- ============================================================

DROP TABLE IF EXISTS suivis_morpho_zones;

CREATE TABLE IF NOT EXISTS suivis_morpho_points (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  suivi_id   UUID NOT NULL REFERENCES suivis_morpho(id) ON DELETE CASCADE,
  vue        TEXT NOT NULL DEFAULT 'profil_d', -- profil_g | profil_d
  x_pct      NUMERIC(5,2) NOT NULL,
  y_pct      NUMERIC(5,2) NOT NULL,
  categorie  TEXT NOT NULL,
    -- tension_cervicale | tension_thoracique | tension_lombaire |
    -- tension_sacro_iliaque | trigger | acupuncture | autre (mêmes valeurs
    -- que points_osteo.categorie — cf. kCategoriesOsteo)
  note       TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_suivis_morpho_points_suivi ON suivis_morpho_points(suivi_id);

ALTER TABLE suivis_morpho_points ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "suivis_morpho_points_anon" ON suivis_morpho_points;
CREATE POLICY "suivis_morpho_points_anon" ON suivis_morpho_points FOR ALL USING (true) WITH CHECK (true);

-- Une photo peut désormais être liée à un point précis plutôt qu'à une
-- "zone" nommée libre.
ALTER TABLE suivis_morpho_photos
  ADD COLUMN IF NOT EXISTS point_id UUID REFERENCES suivis_morpho_points(id) ON DELETE CASCADE;
ALTER TABLE suivis_morpho_photos DROP COLUMN IF EXISTS zone;
