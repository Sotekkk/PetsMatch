-- Migration : pension_acces — ajout pro_profile_id + owner_profile_id (même structure que animal_acces_pro)

ALTER TABLE pension_acces
  ADD COLUMN IF NOT EXISTS pro_profile_id   UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS owner_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

-- Remplir depuis user_profiles (profil principal du pro)
UPDATE pension_acces pa
SET pro_profile_id = up.id
FROM user_profiles up
WHERE up.uid = pa.pro_uid
  AND up.is_main = true
  AND pa.pro_profile_id IS NULL;

-- Remplir owner depuis animaux_proprietes
UPDATE pension_acces pa
SET owner_profile_id = ap.profile_id_proprio
FROM animaux_proprietes ap
WHERE ap.animal_id = pa.animal_id
  AND ap.profile_id_proprio IS NOT NULL
  AND pa.owner_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_pension_acces_profile ON pension_acces(pro_profile_id);
