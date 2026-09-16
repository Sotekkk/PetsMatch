-- ============================================================
-- PetsMatch — Suivi morphologique : couleur libre par point
-- Jusqu'ici la couleur d'un point de silhouette était strictement liée à
-- sa catégorie (tension_cervicale, trigger, acupuncture...), obligeant à
-- choisir une catégorie inadaptée juste pour obtenir une couleur distincte.
-- `couleur` (hex sans #) devient indépendante : si renseignée, elle prime
-- sur la couleur de la catégorie à l'affichage (app + site + PDF).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE suivis_morpho_points
  ADD COLUMN IF NOT EXISTS couleur TEXT;
