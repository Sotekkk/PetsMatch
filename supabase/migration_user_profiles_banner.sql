-- Ajoute banner_url à user_profiles (profils secondaires association/éleveur)
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS banner_url TEXT;
