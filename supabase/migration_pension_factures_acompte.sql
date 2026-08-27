-- ============================================================
-- PetsMatch — Pension : factures d'acompte / solde
-- Ajoute un type à pension_factures pour distinguer :
--   'complete' : facture du séjour complet (défaut, comportement actuel)
--   'acompte'  : acompte demandé à la réservation / l'entrée
--   'solde'    : facture du solde après un acompte
-- acompte_pct : pourcentage retenu quand type = 'acompte' (ex. 30)
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE pension_factures
  ADD COLUMN IF NOT EXISTS type        TEXT NOT NULL DEFAULT 'complete',
  ADD COLUMN IF NOT EXISTS acompte_pct NUMERIC;

CREATE INDEX IF NOT EXISTS idx_pension_factures_type ON pension_factures(type);
