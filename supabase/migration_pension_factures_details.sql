-- ============================================================
-- PetsMatch — Pension : détail de facture réouvrable
-- `details` (jsonb) stocke tout ce qu'il faut pour ré-afficher une facture
-- déjà émise depuis « Mes factures » sur le site (nuits, tarif/nuit,
-- suppléments, TVA, acompte, animal, propriétaire, séjour).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE pension_factures
  ADD COLUMN IF NOT EXISTS details JSONB;
