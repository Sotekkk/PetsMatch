-- ============================================================
-- PetsMatch V2 — Patch 06 : profile_id sur taches_elevage + plan_taches
-- ============================================================
-- Les tâches manuelles et protocoles sont liés au profil actif
-- (éleveur ou association) plutôt qu'au seul uid_eleveur + profil_source.
-- ============================================================

-- ── 1. taches_elevage.profile_id ──────────────────────────────
ALTER TABLE taches_elevage
  ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_taches_elevage_profile_id ON taches_elevage(profile_id);

-- Backfill selon uid_eleveur + profil_source
UPDATE taches_elevage t
SET profile_id = (
  SELECT up.id FROM user_profiles up
  WHERE up.uid = t.uid_eleveur
    AND up.profile_type = COALESCE(NULLIF(t.profil_source, ''), 'eleveur')
  ORDER BY up.created_at ASC
  LIMIT 1
)
WHERE t.profile_id IS NULL AND t.uid_eleveur IS NOT NULL;

-- Fallback : profil principal
UPDATE taches_elevage t
SET profile_id = (
  SELECT up.id FROM user_profiles up
  WHERE up.uid = t.uid_eleveur
  ORDER BY up.is_main DESC, up.created_at ASC
  LIMIT 1
)
WHERE t.profile_id IS NULL AND t.uid_eleveur IS NOT NULL;

-- ── 2. plan_taches.profile_id ─────────────────────────────────
ALTER TABLE plan_taches
  ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_plan_taches_profile_id ON plan_taches(profile_id);

UPDATE plan_taches t
SET profile_id = (
  SELECT up.id FROM user_profiles up
  WHERE up.uid = t.uid_eleveur
    AND up.profile_type = COALESCE(NULLIF(t.profil_source, ''), 'eleveur')
  ORDER BY up.created_at ASC
  LIMIT 1
)
WHERE t.profile_id IS NULL AND t.uid_eleveur IS NOT NULL;

UPDATE plan_taches t
SET profile_id = (
  SELECT up.id FROM user_profiles up
  WHERE up.uid = t.uid_eleveur
  ORDER BY up.is_main DESC, up.created_at ASC
  LIMIT 1
)
WHERE t.profile_id IS NULL AND t.uid_eleveur IS NOT NULL;

-- ── Vérification ──────────────────────────────────────────────
SELECT
  'taches_elevage' AS table_name,
  COUNT(*) FILTER (WHERE profile_id IS NOT NULL) AS avec_profile_id,
  COUNT(*) FILTER (WHERE profile_id IS NULL)     AS sans_profile_id
FROM taches_elevage
UNION ALL
SELECT 'plan_taches',
  COUNT(*) FILTER (WHERE profile_id IS NOT NULL),
  COUNT(*) FILTER (WHERE profile_id IS NULL)
FROM plan_taches;
