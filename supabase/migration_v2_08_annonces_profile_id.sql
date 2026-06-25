-- ============================================================
-- PetsMatch V2 — Patch 08 : profile_id sur annonces
-- ============================================================
-- Relie chaque annonce au profil (user_profiles.id) qui l'a créée.
-- Permet de filtrer "mes annonces" par profil actif au lieu de uid_eleveur seul.
-- ============================================================

-- ── 1. Colonne profile_id ─────────────────────────────────
ALTER TABLE annonces
  ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_annonces_profile_id ON annonces(profile_id);

-- ── 2. Backfill : assigner le profil correct à chaque annonce existante ──────
-- Règle : profil_source='association' → profile_type='association'
--         tout le reste                → profile_type='eleveur'
--         si l'éleveur n'a pas encore de profil éleveur → profil principal (is_main=true)
UPDATE annonces a
SET profile_id = (
  SELECT up.id
  FROM user_profiles up
  WHERE up.uid = a.uid_eleveur
    AND up.profile_type = CASE
      WHEN a.profil_source = 'association' THEN 'association'
      ELSE 'eleveur'
    END
  ORDER BY up.created_at ASC
  LIMIT 1
)
WHERE a.profile_id IS NULL;

-- Fallback : annonces encore sans profile_id → profil principal de l'uid
UPDATE annonces a
SET profile_id = (
  SELECT up.id
  FROM user_profiles up
  WHERE up.uid = a.uid_eleveur
  ORDER BY up.is_main DESC, up.created_at ASC
  LIMIT 1
)
WHERE a.profile_id IS NULL;
