-- ============================================================
-- PetsMatch — Adresse du propriétaire sur pension_entrees
-- Récupérée automatiquement via animaux_proprietes (propriétaire
-- actuel) quand l'animal est retrouvé par puce lors de l'admission.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE pension_entrees
  ADD COLUMN IF NOT EXISTS proprietaire_adresse TEXT;
