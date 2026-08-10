-- ============================================================
-- PetsMatch — Migrations en attente à exécuter sur Supabase
-- ============================================================
-- Où l'exécuter : dashboard Supabase → SQL Editor → New query
-- → coller tout le contenu de ce fichier → Run.
-- Ce script est idempotent (IF NOT EXISTS partout), on peut le relancer
-- sans risque s'il a déjà tourné partiellement.
--
-- Contenu vérifié le 2026-08-04 : les colonnes ci-dessous sont absentes
-- de la base de prod (zyvpngcvzrkdytypjlyq.supabase.co).
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- 1. Traçabilité précise de qui a réalisé/validé une tâche
--    (agenda éleveur/association — fait_par / valide_par ne stockaient
--    que l'uid Firebase, ambigu si un uid a plusieurs profils dans
--    user_profiles). Sans cette migration, l'agenda ne charge plus
--    les tâches du jour (erreur Postgres 42703 côté web/mobile).
-- ────────────────────────────────────────────────────────────

ALTER TABLE taches_elevage
  ADD COLUMN IF NOT EXISTS fait_par_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE taches_elevage t
SET fait_par_profile_id = up.id
FROM user_profiles up
WHERE up.uid = t.fait_par`
  AND up.is_main = true
  AND t.fait_par IS NOT NULL
  AND t.fait_par_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_taches_fait_par_profile ON taches_elevage(fait_par_profile_id);

ALTER TABLE plan_taches
  ADD COLUMN IF NOT EXISTS valide_par_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE plan_taches p
SET valide_par_profile_id = up.id
FROM user_profiles up
WHERE up.uid = p.valide_par
  AND up.is_main = true
  AND p.valide_par IS NOT NULL
  AND p.valide_par_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_plan_taches_valide_par_profile ON plan_taches(valide_par_profile_id);
