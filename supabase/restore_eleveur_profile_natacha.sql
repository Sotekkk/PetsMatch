-- Restaurer le profil éleveur de Natacha (Le domaine de Negan)
-- UID : YF9kR7jSTObnnw9lVj8gCl031rS2
-- Association existante ID : 33ce0cdf-8e06-4a0c-ac4a-43bdf07dc65c

-- 1. Vérifier qu'il n'existe pas déjà un profil éleveur pour elle
SELECT id, profile_type, nom, statut_pro
FROM user_profiles
WHERE uid = 'YF9kR7jSTObnnw9lVj8gCl031rS2';

-- 2. Créer le profil éleveur depuis les données users
INSERT INTO user_profiles (
  uid,
  profile_type,
  profile_label,
  is_primary,
  nom,
  firstname,
  lastname,
  avatar_url,
  profile_picture_url_pro,
  banner_url,
  desc_entreprise,
  siret,
  numero_tva,
  rue,
  ville,
  code_postal,
  pays,
  adresse,
  rue_elevage,
  ville_elevage,
  code_postal_elevage,
  adress_elevage,
  pays_elevage,
  departement,
  region,
  departement_pro,
  region_pro,
  rue_pro,
  ville_pro,
  code_postal_pro,
  pays_pro,
  lat,
  lng,
  lat_pro,
  lng_pro,
  numero_elevage,
  phone,
  phone_number,
  email_contact,
  especes_elevees,
  is_elevage,
  is_pro,
  is_validate,
  statut_pro,
  verification_status,
  is_main,
  accept_new_clients,
  horaires,
  tarifs,
  photos_galerie,
  instagram,
  facebook,
  certifications,
  is_premium,
  plan_code,
  stripe_customer_id,
  date_of_birth,
  fcm_token,
  apns_token,
  cgu_accepted_at
)
SELECT
  uid,
  'eleveur',
  name_elevage,                    -- 'Le domaine de Negan'
  false,                           -- pas primary (association est is_main=true)
  name_elevage,
  firstname,
  lastname,
  profile_picture_url_elevage,     -- photo de l'élevage
  profile_picture_url_elevage,
  banner_url,
  desc_entreprise,
  siret,
  numero_tva,
  rue_elevage,
  ville_elevage,
  code_postal_elevage,
  pays_elevage,
  adress_elevage,
  rue_elevage,
  ville_elevage,
  code_postal_elevage,
  adress_elevage,
  pays_elevage,
  departement_elevage,
  region_elevage,
  departement_elevage,
  region_elevage,
  rue_elevage,
  ville_elevage,
  code_postal_elevage,
  pays_elevage,
  lat,
  lng,
  lat,
  lng,
  numero_elevage,
  numero_elevage,                  -- téléphone élevage = 0769758199
  phone_number,
  email,
  especes_elevees,
  true,
  false,
  COALESCE(is_validate, true),
  'validated',
  CASE WHEN validate_account_elevage = true THEN 'approved' ELSE 'pending' END,
  false,                           -- is_main = false (l'asso est is_main)
  true,
  '{}',
  '',
  '[]',
  '',
  '',
  '[]',
  is_premium,
  plan_code,
  stripe_customer_id,
  date_of_birth,
  fcm_token,
  apns_token,
  cgu_accepted_at
FROM users
WHERE uid = 'YF9kR7jSTObnnw9lVj8gCl031rS2'
  AND NOT EXISTS (
    SELECT 1 FROM user_profiles
    WHERE uid = 'YF9kR7jSTObnnw9lVj8gCl031rS2'
      AND profile_type = 'eleveur'
  )
RETURNING id, profile_type, nom, ville, statut_pro;

-- 3. Récupérer les animaux liés à son UID éleveur
SELECT
  id,
  nom,
  espece,
  race,
  sexe,
  statut,
  date_naissance,
  profile_id,
  created_at
FROM animaux
WHERE uid_eleveur = 'YF9kR7jSTObnnw9lVj8gCl031rS2'
ORDER BY created_at DESC;

-- 4. Optionnel : lier les animaux sans profile_id au nouveau profil éleveur
-- (à exécuter APRÈS avoir noté l'id retourné par l'INSERT ci-dessus)
-- UPDATE animaux
-- SET profile_id = '<id_nouveau_profil_eleveur>'
-- WHERE uid_eleveur = 'YF9kR7jSTObnnw9lVj8gCl031rS2'
--   AND profile_id IS NULL;
