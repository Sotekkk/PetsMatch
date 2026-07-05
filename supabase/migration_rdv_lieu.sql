-- ============================================================
-- PetsMatch — Lieu du RDV (au cabinet, au domicile du client, ou
-- personnalisé). Simple champ texte pour l'instant — le calcul de
-- trajet/GPS complet reste en backlog Phase 2 (item 5/5).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE rdv ADD COLUMN IF NOT EXISTS lieu TEXT;
