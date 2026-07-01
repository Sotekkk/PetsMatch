-- ============================================================
-- Migration : pro_profile_id dans cessions + documents_animaux uid filter
-- Date      : 2026-07-01
-- ============================================================

-- Profil du cédant (éleveur / particulier / association)
ALTER TABLE cessions
  ADD COLUMN IF NOT EXISTS pro_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

-- Profil de l'acquéreur (renseigné à la confirmation)
ALTER TABLE cessions
  ADD COLUMN IF NOT EXISTS acquereur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_cessions_pro_profile   ON cessions(pro_profile_id);
CREATE INDEX IF NOT EXISTS idx_cessions_acq_profile   ON cessions(acquereur_profile_id);

-- Backfill : lier les cessions existantes au profil principal du cédant
UPDATE cessions c
SET pro_profile_id = up.id
FROM user_profiles up
WHERE up.firebase_uid = c.uid_eleveur
  AND up.is_main = true
  AND c.pro_profile_id IS NULL;
