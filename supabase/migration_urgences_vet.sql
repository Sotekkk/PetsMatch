-- Ajout du flag urgences 24h/24 pour les vétérinaires
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS urgences_24h BOOLEAN DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_user_profiles_urgences_24h
  ON user_profiles(urgences_24h)
  WHERE urgences_24h = TRUE;
