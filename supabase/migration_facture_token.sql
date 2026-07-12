-- ============================================================
-- PetsMatch — Factures : ajout d'un token public pour l'envoi
-- par email (vue client sans compte, mirror devis.token_acceptation)
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE factures
  ADD COLUMN IF NOT EXISTS token TEXT;

-- Backfill des factures existantes (nouvelles factures : générées côté client via crypto.randomUUID())
UPDATE factures SET token = gen_random_uuid()::text WHERE token IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_factures_token ON factures(token);
