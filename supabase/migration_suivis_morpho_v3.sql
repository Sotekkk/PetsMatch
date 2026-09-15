-- ============================================================
-- PetsMatch — Suivi morphologique & bien-être — v3
-- Permet de créer un suivi pour un client/animal saisi à la main (pas
-- besoin d'un RDV confirmé existant) — utile pour un client occasionnel
-- non enregistré. animal_id devient optionnel ; à défaut, on renseigne
-- les champs libres ci-dessous.
-- À exécuter APRÈS migration_suivis_morpho_v2.sql.
-- ============================================================

ALTER TABLE suivis_morpho ALTER COLUMN animal_id DROP NOT NULL;

ALTER TABLE suivis_morpho ADD COLUMN IF NOT EXISTS animal_nom_libre TEXT;
ALTER TABLE suivis_morpho ADD COLUMN IF NOT EXISTS espece_libre TEXT;      -- chien | chat | cheval
ALTER TABLE suivis_morpho ADD COLUMN IF NOT EXISTS client_nom_libre TEXT;
ALTER TABLE suivis_morpho ADD COLUMN IF NOT EXISTS client_contact_libre TEXT;
