-- ============================================================
-- PetsMatch — Corrige la contrainte CHECK sur user_profiles.profile_type
-- Le check constraint défini dans migration_v2_01_user_profiles.sql ne
-- listait pas tous les types de profil pro ajoutés depuis (sante, garde,
-- toilettage, restauration, taxi_animalier...). 'taxi_animalier' bloquait
-- encore les insertions (constraint violation) — ce script réaligne la
-- contrainte sur l'ensemble des types réellement utilisés par l'app/web.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE user_profiles DROP CONSTRAINT IF EXISTS user_profiles_profile_type_check;
ALTER TABLE user_profiles ADD CONSTRAINT user_profiles_profile_type_check
  CHECK (profile_type IS NULL OR profile_type IN (
    'particulier','eleveur','association','veterinaire',
    'pension','education','petsitter','promeneur','garde',
    'sante','toilettage','photographe','marechal_ferrant',
    'restauration','taxi_animalier',
    'para_medical','petfriendly','partenaire'
  ))
  NOT VALID;  -- s'applique aux nouvelles lignes seulement, pas aux données historiques
