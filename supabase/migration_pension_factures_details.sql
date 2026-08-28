-- ============================================================
-- PetsMatch — Pension : facture réouvrable + lien client
-- `details` (jsonb) : détail complet pour ré-afficher une facture émise.
-- `token`   (uuid)  : lien public /facture-pension/<token> pour le client.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE pension_factures
  ADD COLUMN IF NOT EXISTS details JSONB,
  ADD COLUMN IF NOT EXISTS token   UUID DEFAULT gen_random_uuid();

CREATE INDEX IF NOT EXISTS idx_pension_factures_token ON pension_factures(token);
