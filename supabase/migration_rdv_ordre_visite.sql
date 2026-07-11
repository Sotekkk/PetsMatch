-- ============================================================
-- PetsMatch — Tournée réordonnable (petsitter/promeneur)
-- Ordre manuel des visites du jour, distinct de l'heure du RDV
-- (permet d'optimiser le trajet sans changer les horaires réservés).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE rdv ADD COLUMN IF NOT EXISTS ordre_visite INTEGER;

CREATE INDEX IF NOT EXISTS idx_rdv_ordre_visite ON rdv(pro_uid, pro_profile_id, ordre_visite);
