-- Migration : familles_accueil — ajout association_profile_id + fa_profile_id
-- Remplace association_uid et fa_uid (Firebase UIDs) par des UUID user_profiles

ALTER TABLE familles_accueil
  ADD COLUMN IF NOT EXISTS association_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS fa_profile_id           UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

-- Backfill association_profile_id depuis association_uid
UPDATE familles_accueil fa
SET association_profile_id = up.id
FROM user_profiles up
WHERE up.uid = fa.association_uid
  AND up.is_main = true
  AND fa.association_profile_id IS NULL;

-- Backfill fa_profile_id depuis fa_uid (profil principal de la personne)
UPDATE familles_accueil fa
SET fa_profile_id = up.id
FROM user_profiles up
WHERE up.uid = fa.fa_uid
  AND up.is_main = true
  AND fa.fa_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_familles_accueil_assoc_profile ON familles_accueil(association_profile_id);
CREATE INDEX IF NOT EXISTS idx_familles_accueil_fa_profile    ON familles_accueil(fa_profile_id);
