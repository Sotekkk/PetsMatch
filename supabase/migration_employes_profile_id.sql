-- Migration : employes + taches_elevage + plan_taches
-- Ajouter profile_id (user_profiles.id) en remplacement des Firebase UIDs
-- Contrainte métier : seuls les profils "particulier" peuvent être employés

-- ── 1. employes ────────────────────────────────────────────────────────────────
ALTER TABLE employes
  ADD COLUMN IF NOT EXISTS employe_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS eleveur_profile_id  UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

-- Backfill employé : profil particulier principal
UPDATE employes e
SET employe_profile_id = up.id
FROM user_profiles up
WHERE up.uid = e.uid_employe
  AND up.profile_type = 'particulier'
  AND up.is_main = true
  AND e.employe_profile_id IS NULL;

-- Backfill employeur : profil principal (éleveur ou association)
UPDATE employes e
SET eleveur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = e.uid_eleveur
  AND up.is_main = true
  AND e.eleveur_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_employes_employe_profile ON employes(employe_profile_id);
CREATE INDEX IF NOT EXISTS idx_employes_eleveur_profile ON employes(eleveur_profile_id);

-- ── 2. taches_elevage ──────────────────────────────────────────────────────────
ALTER TABLE taches_elevage
  ADD COLUMN IF NOT EXISTS eleveur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS assigne_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE taches_elevage t
SET eleveur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = t.uid_eleveur
  AND up.is_main = true
  AND t.eleveur_profile_id IS NULL;

UPDATE taches_elevage t
SET assigne_profile_id = up.id
FROM user_profiles up
WHERE up.uid = t.assigne_a
  AND up.profile_type = 'particulier'
  AND up.is_main = true
  AND t.assigne_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_taches_eleveur_profile  ON taches_elevage(eleveur_profile_id);
CREATE INDEX IF NOT EXISTS idx_taches_assigne_profile  ON taches_elevage(assigne_profile_id);

-- ── 3. plan_taches ────────────────────────────────────────────────────────────
ALTER TABLE plan_taches
  ADD COLUMN IF NOT EXISTS eleveur_profile_id  UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS assigned_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE plan_taches p
SET eleveur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = p.uid_eleveur
  AND up.is_main = true
  AND p.eleveur_profile_id IS NULL;

UPDATE plan_taches p
SET assigned_profile_id = up.id
FROM user_profiles up
WHERE up.uid = p.assigned_to
  AND up.profile_type = 'particulier'
  AND up.is_main = true
  AND p.assigned_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_plan_taches_eleveur_profile   ON plan_taches(eleveur_profile_id);
CREATE INDEX IF NOT EXISTS idx_plan_taches_assigned_profile  ON plan_taches(assigned_profile_id);
