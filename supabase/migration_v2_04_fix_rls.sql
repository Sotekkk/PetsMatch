-- ============================================================
-- PetsMatch V2 — Patch 04 : RLS permissive pour client Firebase
-- ============================================================
-- Contexte : l'app utilise Firebase Auth + client Supabase anon.
-- auth.uid() est donc toujours NULL → toute politique basée sur
-- auth.uid() bloque les opérations du client web/app.
-- Solution : politiques USING(true) / WITH CHECK(true) sur les
-- tables modifiées par l'app.
-- ============================================================

-- ── user_profiles ─────────────────────────────────────────────
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own profile"    ON user_profiles;
DROP POLICY IF EXISTS "Users can update own profile"  ON user_profiles;
DROP POLICY IF EXISTS "Users can insert own profile"  ON user_profiles;
DROP POLICY IF EXISTS "users_select_own"              ON user_profiles;
DROP POLICY IF EXISTS "users_update_own"              ON user_profiles;
DROP POLICY IF EXISTS "users_insert_own"              ON user_profiles;
DROP POLICY IF EXISTS "allow_all"                     ON user_profiles;
DROP POLICY IF EXISTS "Enable read access for all"    ON user_profiles;
DROP POLICY IF EXISTS "Enable insert for users"       ON user_profiles;
DROP POLICY IF EXISTS "Enable update for users"       ON user_profiles;

CREATE POLICY "firebase_allow_all" ON user_profiles
  FOR ALL USING (true) WITH CHECK (true);

-- ── users ─────────────────────────────────────────────────────
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own data"    ON users;
DROP POLICY IF EXISTS "Users can update own data"  ON users;
DROP POLICY IF EXISTS "Users can insert own data"  ON users;
DROP POLICY IF EXISTS "users_select_own"           ON users;
DROP POLICY IF EXISTS "users_update_own"           ON users;
DROP POLICY IF EXISTS "users_insert_own"           ON users;
DROP POLICY IF EXISTS "allow_all"                  ON users;
DROP POLICY IF EXISTS "firebase_allow_all"         ON users;
DROP POLICY IF EXISTS "Enable read access for all" ON users;

CREATE POLICY "firebase_allow_all" ON users
  FOR ALL USING (true) WITH CHECK (true);

-- ── animaux ───────────────────────────────────────────────────
ALTER TABLE animaux ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_all"         ON animaux;
DROP POLICY IF EXISTS "firebase_allow_all" ON animaux;

CREATE POLICY "firebase_allow_all" ON animaux
  FOR ALL USING (true) WITH CHECK (true);

-- ── annonces ──────────────────────────────────────────────────
ALTER TABLE annonces ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_all"         ON annonces;
DROP POLICY IF EXISTS "firebase_allow_all" ON annonces;

CREATE POLICY "firebase_allow_all" ON annonces
  FOR ALL USING (true) WITH CHECK (true);

-- Vérification
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename IN ('user_profiles','users','animaux','annonces')
ORDER BY tablename, cmd;
