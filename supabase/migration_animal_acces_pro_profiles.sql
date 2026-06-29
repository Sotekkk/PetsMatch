-- Migration : animal_acces_pro — ajout pro_profile_id + owner_profile_id
-- pro_uid   → garder pour compatibilité + ajouter pro_profile_id (user_profiles.id)
-- owner_uid → garder pour compatibilité + ajouter owner_profile_id (user_profiles.id)

ALTER TABLE animal_acces_pro
  ADD COLUMN IF NOT EXISTS pro_profile_id   UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS owner_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

-- Remplir pro_profile_id depuis user_profiles (profil principal du pro)
UPDATE animal_acces_pro aap
SET pro_profile_id = up.id
FROM user_profiles up
WHERE up.uid = aap.pro_uid
  AND up.is_main = true
  AND aap.pro_profile_id IS NULL;

-- Remplir owner_profile_id depuis animaux_proprietes
UPDATE animal_acces_pro aap
SET owner_profile_id = ap.profile_id_proprio
FROM animaux_proprietes ap
WHERE ap.animal_id = aap.animal_id
  AND ap.profile_id_proprio IS NOT NULL
  AND aap.owner_profile_id IS NULL;

-- Index pour les requêtes par profil pro
CREATE INDEX IF NOT EXISTS idx_animal_acces_pro_profile ON animal_acces_pro(pro_profile_id);
