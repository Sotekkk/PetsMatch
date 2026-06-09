-- Fix : autoriser la lecture publique de user_profiles
-- (nécessaire pour l'admin panel et la carte des services)
-- Si la table n'a pas de RLS activée, ces commandes sont sans effet négatif.

-- Activer RLS si ce n'est pas déjà le cas
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

-- Supprimer une ancienne policy restrictive si elle existe
DROP POLICY IF EXISTS "Users can view own profiles" ON user_profiles;
DROP POLICY IF EXISTS "Users can read own profiles" ON user_profiles;

-- Lecture publique (comme la table users)
CREATE POLICY IF NOT EXISTS "Public read user_profiles"
  ON user_profiles FOR SELECT
  USING (true);

-- Écriture : uniquement le propriétaire du profil
CREATE POLICY IF NOT EXISTS "Owner can insert user_profiles"
  ON user_profiles FOR INSERT
  WITH CHECK (auth.uid()::text = uid);

CREATE POLICY IF NOT EXISTS "Owner can update user_profiles"
  ON user_profiles FOR UPDATE
  USING (auth.uid()::text = uid);

CREATE POLICY IF NOT EXISTS "Owner can delete user_profiles"
  ON user_profiles FOR DELETE
  USING (auth.uid()::text = uid);
