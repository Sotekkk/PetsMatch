-- ============================================================
-- PetsMatch V2 — Patch 05 : profile_id sur animaux + tables liées
-- ============================================================
-- Objectif : lier chaque animal à un profil précis (user_profiles.id)
-- plutôt qu'au seul uid Firebase.
-- Un éleveur + son profil particulier ont ainsi des animaux séparés.
--
-- Tables modifiées :
--   animaux            → profile_id     (profil créateur/éleveur)
--   animaux_proprietes → profile_id_proprio (profil du propriétaire)
--   likes, favoris     → profile_id
--   notifications      → profile_id
--   employes           → profil_id_pro, profil_id_employe
-- ============================================================

-- ── 1. animaux.profile_id ─────────────────────────────────────
ALTER TABLE animaux
  ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_animaux_profile_id ON animaux(profile_id);

-- Backfill : profil du bon type selon is_association
UPDATE animaux a
SET profile_id = (
  SELECT up.id
  FROM user_profiles up
  WHERE up.uid = a.uid_eleveur
    AND up.profile_type = CASE
      WHEN a.is_association IS TRUE THEN 'association'
      ELSE 'eleveur'
    END
  ORDER BY up.created_at ASC
  LIMIT 1
)
WHERE a.profile_id IS NULL AND a.uid_eleveur IS NOT NULL AND a.uid_eleveur != '';

-- Fallback : profil principal (particuliers sans profil éleveur)
UPDATE animaux a
SET profile_id = (
  SELECT up.id FROM user_profiles up
  WHERE up.uid = COALESCE(NULLIF(a.uid_eleveur,''), a.uid_proprietaire)
  ORDER BY up.is_main DESC, up.created_at ASC
  LIMIT 1
)
WHERE a.profile_id IS NULL;

-- ── 2. animaux_proprietes.profile_id_proprio ──────────────────
ALTER TABLE animaux_proprietes
  ADD COLUMN IF NOT EXISTS profile_id_proprio UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_ap_profile_id_proprio ON animaux_proprietes(profile_id_proprio);

-- Backfill : si uid_proprio == uid_eleveur de l'animal → profil éleveur/asso
-- sinon → profil particulier (acquéreur)
UPDATE animaux_proprietes ap
SET profile_id_proprio = (
  SELECT up.id
  FROM user_profiles up
  WHERE up.uid = ap.uid_proprio
    AND up.profile_type = (
      SELECT CASE
        WHEN a.is_association IS TRUE THEN 'association'
        WHEN a.uid_eleveur = ap.uid_proprio THEN 'eleveur'
        ELSE 'particulier'
      END
      FROM animaux a WHERE a.id = ap.animal_id
    )
  ORDER BY up.created_at ASC
  LIMIT 1
)
WHERE ap.profile_id_proprio IS NULL;

-- Fallback animaux_proprietes
UPDATE animaux_proprietes ap
SET profile_id_proprio = (
  SELECT up.id FROM user_profiles up
  WHERE up.uid = ap.uid_proprio
  ORDER BY up.is_main DESC, up.created_at ASC
  LIMIT 1
)
WHERE ap.profile_id_proprio IS NULL;

-- ── 3. likes.profile_id ───────────────────────────────────────
ALTER TABLE likes
  ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_likes_profile_id ON likes(profile_id);

UPDATE likes l
SET profile_id = (
  SELECT up.id FROM user_profiles up
  WHERE up.uid = l.user_uid
    AND up.profile_type = COALESCE(l.profile_type, 'particulier')
  ORDER BY up.created_at ASC
  LIMIT 1
)
WHERE l.profile_id IS NULL;

UPDATE likes l
SET profile_id = (
  SELECT up.id FROM user_profiles up
  WHERE up.uid = l.user_uid
  ORDER BY up.is_main DESC, up.created_at ASC
  LIMIT 1
)
WHERE l.profile_id IS NULL;

-- ── 4. favoris.profile_id ─────────────────────────────────────
ALTER TABLE favoris
  ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_favoris_profile_id ON favoris(profile_id);

UPDATE favoris f
SET profile_id = (
  SELECT up.id FROM user_profiles up
  WHERE up.uid = f.user_uid
    AND up.profile_type = COALESCE(f.profile_type, 'particulier')
  ORDER BY up.created_at ASC
  LIMIT 1
)
WHERE f.profile_id IS NULL;

UPDATE favoris f
SET profile_id = (
  SELECT up.id FROM user_profiles up
  WHERE up.uid = f.user_uid
  ORDER BY up.is_main DESC, up.created_at ASC
  LIMIT 1
)
WHERE f.profile_id IS NULL;

-- ── 5. notifications.profile_id ───────────────────────────────
ALTER TABLE notifications
  ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_notifications_profile_id ON notifications(profile_id);

UPDATE notifications n
SET profile_id = (
  SELECT up.id FROM user_profiles up
  WHERE up.uid = n.uid
    AND up.profile_type = COALESCE(n.profile_type, 'particulier')
  ORDER BY up.created_at ASC
  LIMIT 1
)
WHERE n.profile_id IS NULL;

UPDATE notifications n
SET profile_id = (
  SELECT up.id FROM user_profiles up
  WHERE up.uid = n.uid
  ORDER BY up.is_main DESC, up.created_at ASC
  LIMIT 1
)
WHERE n.profile_id IS NULL;

-- ── 6. employes : profil_id_pro + profil_id_employe ──────────
ALTER TABLE employes
  ADD COLUMN IF NOT EXISTS profil_id_pro      UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS profil_id_employe  UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_employes_profil_id_pro     ON employes(profil_id_pro);
CREATE INDEX IF NOT EXISTS idx_employes_profil_id_employe ON employes(profil_id_employe);

-- Backfill employes.profil_id_pro (profil employeur)
UPDATE employes e
SET profil_id_pro = (
  SELECT up.id FROM user_profiles up
  WHERE up.uid = e.uid_eleveur
    AND up.profile_type = COALESCE(e.profil_source, 'eleveur')
  ORDER BY up.created_at ASC
  LIMIT 1
)
WHERE e.profil_id_pro IS NULL AND e.uid_eleveur IS NOT NULL;

-- Backfill employes.profil_id_employe : seulement le profil particulier
UPDATE employes e
SET profil_id_employe = (
  SELECT up.id FROM user_profiles up
  WHERE up.uid = e.uid_employe
    AND up.profile_type = 'particulier'
  ORDER BY up.created_at ASC
  LIMIT 1
)
WHERE e.profil_id_employe IS NULL AND e.uid_employe IS NOT NULL;

-- ── Vérification ──────────────────────────────────────────────
SELECT
  'animaux'                AS table_name,
  COUNT(*) FILTER (WHERE profile_id IS NOT NULL)          AS avec_profile_id,
  COUNT(*) FILTER (WHERE profile_id IS NULL)              AS sans_profile_id
FROM animaux
UNION ALL
SELECT 'animaux_proprietes',
  COUNT(*) FILTER (WHERE profile_id_proprio IS NOT NULL),
  COUNT(*) FILTER (WHERE profile_id_proprio IS NULL)
FROM animaux_proprietes
UNION ALL
SELECT 'likes',
  COUNT(*) FILTER (WHERE profile_id IS NOT NULL),
  COUNT(*) FILTER (WHERE profile_id IS NULL)
FROM likes
UNION ALL
SELECT 'favoris',
  COUNT(*) FILTER (WHERE profile_id IS NOT NULL),
  COUNT(*) FILTER (WHERE profile_id IS NULL)
FROM favoris
UNION ALL
SELECT 'notifications',
  COUNT(*) FILTER (WHERE profile_id IS NOT NULL),
  COUNT(*) FILTER (WHERE profile_id IS NULL)
FROM notifications
UNION ALL
SELECT 'employes_pro',
  COUNT(*) FILTER (WHERE profil_id_pro IS NOT NULL),
  COUNT(*) FILTER (WHERE profil_id_pro IS NULL)
FROM employes
UNION ALL
SELECT 'employes_employe',
  COUNT(*) FILTER (WHERE profil_id_employe IS NOT NULL),
  COUNT(*) FILTER (WHERE profil_id_employe IS NULL)
FROM employes;
