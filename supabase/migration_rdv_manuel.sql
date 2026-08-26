-- ============================================================
-- PetsMatch — RDV créé manuellement par le pro (walk-in, appel
-- téléphonique...) : le client n'a pas forcément de compte PetsMatch,
-- donc client_uid reste vide et on stocke ses infos en texte libre.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE rdv ALTER COLUMN client_uid DROP NOT NULL;

ALTER TABLE rdv ADD COLUMN IF NOT EXISTS client_nom_manuel TEXT;
ALTER TABLE rdv ADD COLUMN IF NOT EXISTS client_telephone_manuel TEXT;
ALTER TABLE rdv ADD COLUMN IF NOT EXISTS animal_nom_manuel TEXT;
ALTER TABLE rdv ADD COLUMN IF NOT EXISTS cree_par_pro BOOLEAN DEFAULT false;
