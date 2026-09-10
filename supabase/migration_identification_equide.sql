-- ============================================================
-- PetsMatch — Identification équidé sur la fiche animal :
-- N° SIRE, carte d'immatriculation, livret / document d'identification.
-- Le n° de transpondeur (puce) reste dans animaux.identification.
-- Idempotent. SQL Editor Supabase → Run. Relançable.
-- ============================================================

ALTER TABLE animaux ADD COLUMN IF NOT EXISTS num_sire              text;
ALTER TABLE animaux ADD COLUMN IF NOT EXISTS carte_immatriculation text;
ALTER TABLE animaux ADD COLUMN IF NOT EXISTS livret_signaletique   text;
