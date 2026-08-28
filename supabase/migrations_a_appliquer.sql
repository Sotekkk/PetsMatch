-- ============================================================
-- PetsMatch — Migrations en attente à exécuter sur Supabase
-- ============================================================
-- Où l'exécuter : dashboard Supabase → SQL Editor → New query
-- → coller tout le contenu de ce fichier → Run.
-- Ce script est idempotent (IF NOT EXISTS partout), on peut le relancer
-- sans risque s'il a déjà tourné partiellement.
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- 1. Suivi gestation — saillies multiples par chaleur
--    `saillies.dates` (jsonb) : toutes les dates de saillie d'un même
--       épisode (une chaleur), ex. ["2026-03-03","2026-03-05"].
--       `saillies.date` reste = 1re saillie (tri + compatibilité).
--    `gestations.date_prevue_fin` (date) : fin de la fenêtre de mise-bas.
--       date_prevue = 1re saillie + durée gestation (début de fenêtre)
--       date_prevue_fin = dernière saillie + durée gestation (fin)
--       Date la plus probable = milieu (calculée à l'affichage).
--    Sans cette migration : les saillies s'enregistrent quand même avec
--    une seule date et la gestation garde une date de mise-bas unique.
-- ────────────────────────────────────────────────────────────

ALTER TABLE saillies
  ADD COLUMN IF NOT EXISTS dates JSONB;

ALTER TABLE gestations
  ADD COLUMN IF NOT EXISTS date_prevue_fin DATE;
