-- ============================================================
-- PetsMatch V2 — Patch 12 : abonnements par profil
-- ============================================================

-- 1. plan_code sur user_profiles (accès premium par profil)
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS plan_code  TEXT    NOT NULL DEFAULT 'free',
  ADD COLUMN IF NOT EXISTS plan_until TIMESTAMPTZ;

-- Backfill depuis users
UPDATE user_profiles up
SET
  plan_code  = COALESCE(u.plan_code, 'free'),
  is_premium = COALESCE(u.is_premium, false)
FROM users u
WHERE up.uid = u.uid
  AND up.is_main = true;

-- 2. profile_id sur abonnements (lier chaque abonnement à un profil)
ALTER TABLE abonnements
  ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_abonnements_profile_id ON abonnements(profile_id);

-- Backfill profile_id depuis uid (profil principal de chaque user)
UPDATE abonnements a
SET profile_id = up.id
FROM user_profiles up
WHERE up.uid = a.uid
  AND up.is_main = true
  AND a.profile_id IS NULL;
