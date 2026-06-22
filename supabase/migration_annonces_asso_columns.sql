-- Colonnes manquantes pour les annonces association
-- À exécuter dans Supabase Dashboard → SQL Editor

ALTER TABLE annonces ADD COLUMN IF NOT EXISTS contrat_adoption  BOOLEAN DEFAULT true;
ALTER TABLE annonces ADD COLUMN IF NOT EXISTS animal_id         TEXT;
ALTER TABLE annonces ADD COLUMN IF NOT EXISTS sterilise         BOOLEAN DEFAULT false;
ALTER TABLE annonces ADD COLUMN IF NOT EXISTS identification    BOOLEAN DEFAULT false;
ALTER TABLE annonces ADD COLUMN IF NOT EXISTS vermifuge         BOOLEAN DEFAULT false;
ALTER TABLE annonces ADD COLUMN IF NOT EXISTS vaccines          BOOLEAN DEFAULT false;
