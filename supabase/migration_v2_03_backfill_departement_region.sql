-- ============================================================
-- PetsMatch V2 — Patch 03 : Backfill champs manquants depuis users
-- Corrige les omissions dans V2_01 :
--   - departement/region personnels non transférés
--   - departement_elevage/region_elevage → departement_pro/region_pro
--   - nom non rempli si name_elevage existait (pour profils pré-existants)
--   - adresse pro (adress_elevage) non transférée
-- Idempotent (guards IS NULL / IS EMPTY)
-- ============================================================

-- 1. nom depuis name_elevage (si nom est vide et name_elevage disponible)
UPDATE user_profiles up
SET nom = u.name_elevage
FROM users u
WHERE up.uid = u.uid
  AND up.is_main = TRUE
  AND (up.nom IS NULL OR up.nom = '')
  AND u.name_elevage IS NOT NULL AND u.name_elevage != '';

-- 2. adresse personnelle depuis users.adress
UPDATE user_profiles up
SET adresse = u.adress
FROM users u
WHERE up.uid = u.uid
  AND up.is_main = TRUE
  AND (up.adresse IS NULL OR up.adresse = '')
  AND u.adress IS NOT NULL AND u.adress != '';

-- 3. adresse pro complète (string) depuis adress_elevage
--    Stockée dans adresse pour les profils pro/éleveur car c'est leur adresse principale
UPDATE user_profiles up
SET adresse = u.adress_elevage
FROM users u
WHERE up.uid = u.uid
  AND up.is_main = TRUE
  AND up.profile_type IN ('eleveur','association','veterinaire','pension',
                          'education','petsitter','promeneur','photographe',
                          'para_medical','marechal_ferrant')
  AND (up.adresse IS NULL OR up.adresse = '')
  AND u.adress_elevage IS NOT NULL AND u.adress_elevage != '';

-- 4. departement + region personnels
UPDATE user_profiles up
SET
  departement = u.departement,
  region      = u.region
FROM users u
WHERE up.uid = u.uid
  AND up.is_main = TRUE
  AND (up.departement IS NULL OR up.departement = '')
  AND u.departement IS NOT NULL AND u.departement != '';

-- 5. departement_pro + region_pro depuis les colonnes _elevage de users
UPDATE user_profiles up
SET
  departement_pro = u.departement_elevage,
  region_pro      = u.region_elevage
FROM users u
WHERE up.uid = u.uid
  AND up.is_main = TRUE
  AND (up.departement_pro IS NULL OR up.departement_pro = '')
  AND u.departement_elevage IS NOT NULL AND u.departement_elevage != '';

-- Vérification
SELECT
  up.uid,
  up.nom,
  up.departement,       up.departement_pro,
  up.region,            up.region_pro,
  up.adresse
FROM user_profiles up
WHERE up.is_main = TRUE
ORDER BY up.uid;
