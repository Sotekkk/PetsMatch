-- ============================================================
-- PetsMatch — Taxi animalier : plusieurs animaux transportés sur un RDV
-- rdv.animal_id reste l'animal principal (1er sélectionné, compat avec le
-- reste du code qui lit une colonne unique) ; animaux_ids porte la liste
-- complète pour l'affichage. nombre_animaux (déjà existante) reflète
-- désormais Length(animaux_ids) au lieu d'un compteur saisi à la main.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE rdv
  ADD COLUMN IF NOT EXISTS animaux_ids JSONB DEFAULT '[]'::jsonb;
