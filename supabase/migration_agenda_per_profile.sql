-- Migration : agenda et animaux suivis par profil (pas par compte)
-- Chaque profil pro (primaire ou secondaire) a ses propres RDV, créneaux, pensionnaires.

-- 1. Table rdv — colonne pro_profile_id
--    NULL = profil primaire, UUID = profil secondaire (user_profiles.id)
ALTER TABLE rdv ADD COLUMN IF NOT EXISTS pro_profile_id TEXT;
CREATE INDEX IF NOT EXISTS idx_rdv_pro_profile_id ON rdv(pro_uid, pro_profile_id);

-- 2. Table creneaux_pro — colonne pro_profile_id
ALTER TABLE creneaux_pro ADD COLUMN IF NOT EXISTS pro_profile_id TEXT;
-- Mettre à jour la contrainte unique pour inclure le profil
ALTER TABLE creneaux_pro DROP CONSTRAINT IF EXISTS creneaux_pro_pro_uid_date_heure_debut_key;
ALTER TABLE creneaux_pro ADD CONSTRAINT IF NOT EXISTS creneaux_pro_uid_profile_date_heure_key
  UNIQUE (pro_uid, pro_profile_id, date, heure_debut);
CREATE INDEX IF NOT EXISTS idx_creneaux_pro_profile_id ON creneaux_pro(pro_uid, pro_profile_id);

-- 3. Table pension_entrees — colonne pro_profile_id
ALTER TABLE pension_entrees ADD COLUMN IF NOT EXISTS pro_profile_id TEXT;
CREATE INDEX IF NOT EXISTS idx_pension_entrees_profile_id ON pension_entrees(pro_uid, pro_profile_id);

-- Note : pension_acces et vet_access_grants ont déjà pro_profile_id
-- (migration_secondary_profile_complete.sql)

-- Les RDV existants (pro_profile_id = NULL) appartiennent au profil primaire.
-- Les creneaux existants (pro_profile_id = NULL) appartiennent au profil primaire.
