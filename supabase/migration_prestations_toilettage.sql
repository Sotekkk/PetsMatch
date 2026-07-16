-- ============================================================
-- PetsMatch — Prestations toiletteur
-- Contrairement à prestations_photographe (prix fixe), le prix varie ici
-- selon espèce/poids de l'animal : grille_prix stocke des tranches
-- (JSONB, cohérent avec le reste du projet — ex. tarifs_logements
-- pension), résolues côté Dart à la réservation.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS prestations_toilettage (
  id             UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  pro_uid        TEXT NOT NULL,
  pro_profile_id UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
  type           TEXT NOT NULL DEFAULT 'bain',
  -- bain / coupe / tonte / demelage / griffes / oreilles / hygiene / spa
  nom            TEXT NOT NULL,
  especes        JSONB NOT NULL DEFAULT '["chien"]'::jsonb, -- chien/chat/nac
  prix_base      NUMERIC NOT NULL DEFAULT 0,
  duree_minutes  INTEGER NOT NULL DEFAULT 60,
  -- grille_prix : tranches de poids par espèce, ex.
  -- [{"espece":"chien","poids_max_kg":10,"prix":25},
  --  {"espece":"chien","poids_max_kg":25,"prix":35}]
  -- Fallback sur prix_base si aucune tranche ne correspond.
  grille_prix    JSONB DEFAULT '[]'::jsonb,
  supplements    JSONB DEFAULT '[]'::jsonb, -- [{"nom": "Poil long", "prix": 10}]
  description    TEXT,
  actif          BOOLEAN NOT NULL DEFAULT true,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_prestations_toilettage_pro ON prestations_toilettage(pro_uid, actif);

ALTER TABLE prestations_toilettage ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Select prestations_toilettage" ON prestations_toilettage;
CREATE POLICY "Select prestations_toilettage" ON prestations_toilettage FOR SELECT USING (true);

DROP POLICY IF EXISTS "Insert prestations_toilettage" ON prestations_toilettage;
CREATE POLICY "Insert prestations_toilettage" ON prestations_toilettage
  FOR INSERT WITH CHECK (pro_uid IS NOT NULL AND length(pro_uid) > 0);

DROP POLICY IF EXISTS "Update prestations_toilettage" ON prestations_toilettage;
CREATE POLICY "Update prestations_toilettage" ON prestations_toilettage FOR UPDATE USING (true);

DROP POLICY IF EXISTS "Delete prestations_toilettage" ON prestations_toilettage;
CREATE POLICY "Delete prestations_toilettage" ON prestations_toilettage FOR DELETE USING (true);
