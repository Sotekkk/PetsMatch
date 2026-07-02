-- Fix profil "Pension de merveilles" (uid: WQvZxEM9KDdhtSi34tkUgVvZh5d2)
-- Problèmes : cat_pro=garde dans users (au lieu de pension), statut_pro=validated partout

-- 1. Corriger le statut dans user_profiles (validated → actif)
UPDATE user_profiles
SET statut_pro = 'actif'
WHERE uid = 'WQvZxEM9KDdhtSi34tkUgVvZh5d2'
  AND statut_pro = 'validated';

-- 2. Corriger cat_pro dans la table users si garde (devrait être pension)
UPDATE users
SET cat_pro = 'pension'
WHERE uid = 'WQvZxEM9KDdhtSi34tkUgVvZh5d2'
  AND cat_pro = 'garde';

-- 3. Corriger les noms fantaisie (firstname/lastname = "pension pension")
--    Remplacer par quelque chose de neutre si c'est ce uid spécifique
--    Adapter les valeurs ci-dessous au vrai nom du propriétaire
-- UPDATE users
-- SET firstname = 'Prénom', lastname = 'Nom'
-- WHERE uid = 'WQvZxEM9KDdhtSi34tkUgVvZh5d2';

-- UPDATE user_profiles
-- SET nom = 'Pension de merveilles'
-- WHERE uid = 'WQvZxEM9KDdhtSi34tkUgVvZh5d2'
--   AND profile_type = 'particulier';
