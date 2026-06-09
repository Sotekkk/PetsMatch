-- Migration : profils multi-comptes + colonne profile_type sur notifications

-- 1. Colonnes manquantes sur user_profiles
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS profile_label TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS adresse TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS rue TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS ville TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS code_postal TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS pays TEXT DEFAULT 'France';
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS site_web TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS cat_pro TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS name_elevage TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS profession_pro TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS siret TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS rayon_intervention INTEGER DEFAULT 20;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS especes_acceptees TEXT[] DEFAULT '{}';
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS especes_elevees TEXT[] DEFAULT '{}';
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS numero_elevage TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS acaced_numero TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS is_elevage BOOLEAN DEFAULT FALSE;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS firstname TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS lastname TEXT;

-- Contrainte unicité uid+profile_type si elle n'existe pas
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'user_profiles_uid_profile_type_key'
  ) THEN
    ALTER TABLE user_profiles ADD CONSTRAINT user_profiles_uid_profile_type_key UNIQUE (uid, profile_type);
  END IF;
END $$;

-- 2. Colonne profile_type sur notifications (pour notifs liées à un profil secondaire)
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS profile_type TEXT;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS profile_id TEXT;

-- Index pour les requêtes par profil
CREATE INDEX IF NOT EXISTS idx_notifications_uid_profile ON notifications (uid, profile_type);
CREATE INDEX IF NOT EXISTS idx_user_profiles_uid ON user_profiles (uid);
