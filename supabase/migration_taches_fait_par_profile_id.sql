-- Migration : traçabilité précise de qui a réalisé/validé une tâche
-- fait_par / valide_par ne stockent que l'uid Firebase, ambigu si un uid a
-- plusieurs profils dans user_profiles (ex: profil principal + profil employé).
-- On ajoute le profile_id exact (user_profiles.id) à côté, sans retirer l'uid.

-- ── 1. taches_elevage ────────────────────────────────────────────────────────
ALTER TABLE taches_elevage
  ADD COLUMN IF NOT EXISTS fait_par_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

-- Backfill : ancien comportement (uid + is_main) pour les tâches déjà marquées faites
UPDATE taches_elevage t
SET fait_par_profile_id = up.id
FROM user_profiles up
WHERE up.uid = t.fait_par
  AND up.is_main = true
  AND t.fait_par IS NOT NULL
  AND t.fait_par_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_taches_fait_par_profile ON taches_elevage(fait_par_profile_id);

-- ── 2. plan_taches ───────────────────────────────────────────────────────────
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
