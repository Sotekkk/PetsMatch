-- ============================================================
-- PetsMatch — Occupation "seul" (animal ne pouvant cohabiter) sur
-- pension_entrees. Le nettoyage réutilise enclos_chenil.dernier_nettoyage
-- (déjà existant, aucune migration nécessaire pour ce volet).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE pension_entrees
  ADD COLUMN IF NOT EXISTS seul_dans_logement BOOLEAN DEFAULT FALSE;
