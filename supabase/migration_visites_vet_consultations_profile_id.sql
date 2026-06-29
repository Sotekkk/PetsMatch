-- Migration: vet_profile_id sur visites et vet_consultations

-- visites : vet_profile_id (FK du vétérinaire auteur)
ALTER TABLE visites
  ADD COLUMN IF NOT EXISTS vet_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE visites v
SET vet_profile_id = up.id
FROM user_profiles up
WHERE up.uid = v.vet_id
  AND up.is_main = true
  AND v.vet_profile_id IS NULL
  AND v.vet_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS visites_vet_profile_id_idx ON visites(vet_profile_id);

-- vet_consultations : vet_profile_id
ALTER TABLE vet_consultations
  ADD COLUMN IF NOT EXISTS vet_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE vet_consultations vc
SET vet_profile_id = up.id
FROM user_profiles up
WHERE up.uid = vc.vet_id
  AND up.is_main = true
  AND vc.vet_profile_id IS NULL
  AND vc.vet_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS vet_consultations_vet_profile_id_idx ON vet_consultations(vet_profile_id);
