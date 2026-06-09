-- Migration : profils secondaires complets (même données que le profil principal)

-- 1. Ajouter profile_id UUID à la table users (identifiant unique du profil principal)
ALTER TABLE users ADD COLUMN IF NOT EXISTS profile_id UUID DEFAULT gen_random_uuid();
-- Générer les UUIDs pour les lignes existantes qui n'en ont pas encore
UPDATE users SET profile_id = gen_random_uuid() WHERE profile_id IS NULL;

-- 2. Compléter user_profiles avec toutes les colonnes manquantes
-- (pour que chaque profil secondaire soit aussi complet qu'un profil principal)

ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS horaires JSONB DEFAULT '{}';
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS accept_new_clients BOOLEAN DEFAULT TRUE;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS banner_url TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS tarifs TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS instagram TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS facebook TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS certifications JSONB DEFAULT '[]';
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS durees_motifs JSONB DEFAULT '{}';
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS lng DOUBLE PRECISION;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS is_pro BOOLEAN DEFAULT FALSE;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS desc_entreprise TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS departement TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS region TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS ville_elevage TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS code_postal_elevage TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS rue_elevage TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS adress_elevage TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS pays_elevage TEXT;

-- 3. Synchroniser lat/lng depuis latitude/longitude pour les lignes existantes
UPDATE user_profiles SET lat = latitude, lng = longitude
WHERE (lat IS NULL OR lng IS NULL) AND latitude IS NOT NULL AND longitude IS NOT NULL;

-- 4. Index sur profile_id dans users
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_profile_id ON users (profile_id);

-- 5. Statut de validation pour les profils secondaires (même logique que users.statut_pro)
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS statut_pro TEXT DEFAULT 'en_attente';

-- 6. Colonne pour les animaux suivis par profil spécifique
-- vet_access_grants : ajouter pro_profile_id (UUID du profil vet)
ALTER TABLE vet_access_grants ADD COLUMN IF NOT EXISTS pro_profile_id TEXT;
-- pension_acces : ajouter pro_profile_id (UUID du profil pension)
ALTER TABLE pension_acces ADD COLUMN IF NOT EXISTS pro_profile_id TEXT;
-- Table générique pour education/garde/sante etc.
CREATE TABLE IF NOT EXISTS pro_animal_access (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  pro_uid TEXT NOT NULL,
  pro_profile_id TEXT, -- UUID du profil secondaire (user_profiles.id), NULL = profil principal
  animal_id TEXT NOT NULL,
  profile_type TEXT NOT NULL, -- 'education', 'garde', 'sante', etc.
  statut TEXT DEFAULT 'active',
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(pro_profile_id, animal_id, profile_type)
);

-- Note : Les animaux restent liés au uid (compte Firebase) car un animal
-- appartient à un utilisateur, pas à un profil spécifique.
-- Le SUIVI d'un animal par un pro est lié au profil (pro_profile_id),
-- pas au compte. Un même pro peut suivre un animal en vet ET en educ
-- via deux entrées distinctes dans les tables d'accès.
