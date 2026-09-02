-- Photos sur les avis de lieux naturels.
-- (natural_places.photos existe déjà — la proposition de lieu accepte
--  simplement plusieurs photos côté client, aucune migration nécessaire.)
-- À exécuter dans l'éditeur SQL Supabase.

ALTER TABLE natural_place_reviews
  ADD COLUMN IF NOT EXISTS photos JSONB DEFAULT '[]'::jsonb;
