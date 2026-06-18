-- ─────────────────────────────────────────────────────────────────────────────
-- Fix RLS table users : autoriser insert/update depuis l'app (Firebase Auth)
-- PetsMatch utilise Firebase Auth, pas Supabase Auth → auth.uid() = null
-- Il faut donc autoriser le rôle anon à insérer/mettre à jour les profils
-- ─────────────────────────────────────────────────────────────────────────────

-- Vérifier les policies existantes avant :
-- SELECT * FROM pg_policies WHERE tablename = 'users';

-- Supprimer les anciennes policies si elles existent
DROP POLICY IF EXISTS "users_anon_insert"  ON users;
DROP POLICY IF EXISTS "users_anon_update"  ON users;
DROP POLICY IF EXISTS "users_anon_select"  ON users;
DROP POLICY IF EXISTS "users_insert"       ON users;
DROP POLICY IF EXISTS "users_update"       ON users;

-- Permettre à toute requête (anon, authenticated) d'insérer un nouveau profil
-- (appelé depuis l'appli mobile / web lors de l'inscription)
CREATE POLICY "users_anon_insert" ON users
  FOR INSERT
  WITH CHECK (true);

-- Permettre à toute requête de mettre à jour un profil existant
-- (upsert lors de l'inscription et de l'édition de profil)
CREATE POLICY "users_anon_update" ON users
  FOR UPDATE
  USING (true)
  WITH CHECK (true);

-- Permettre à tout le monde de lire les profils publics
CREATE POLICY "users_anon_select" ON users
  FOR SELECT
  USING (true);
