-- ============================================================
-- PetsMatch — Saillies multiples par chaleur + fenêtre de mise-bas
-- ============================================================
-- Où l'exécuter : dashboard Supabase → SQL Editor → New query → Run.
-- Idempotent (IF NOT EXISTS) : relançable sans risque.
--
--  saillies.dates (jsonb)
--    Liste des dates de saillie d'un même épisode de reproduction
--    (une chaleur) : ["2026-03-03", "2026-03-05", "2026-03-07"].
--    La colonne `date` reste renseignée = 1re saillie (tri + compat).
--
--  gestations.date_prevue_fin (date)
--    Fin de la fenêtre de mise-bas estimée.
--    `date_prevue` = début de fenêtre (1re saillie + durée gestation)
--    `date_prevue_fin` = fin de fenêtre (dernière saillie + durée gestation)
--    Date « la plus probable » = milieu des deux (calculée à l'affichage).
--    Si une seule saillie : date_prevue_fin = date_prevue (fenêtre d'un jour).
-- ============================================================

ALTER TABLE saillies
  ADD COLUMN IF NOT EXISTS dates JSONB;

ALTER TABLE gestations
  ADD COLUMN IF NOT EXISTS date_prevue_fin DATE;
