-- « test2 assos » : jamais validée par l'admin mais statut_pro = 'actif'
-- (profil créé avant le trigger qui force 'en_attente' à la création) →
-- visible à tort dans la liste publique des associations. Remise en attente.
BEGIN;
UPDATE user_profiles SET statut_pro = 'en_attente', is_validate = false
WHERE profile_type = 'association' AND nom = 'test2 assos' AND statut_pro = 'actif';
SELECT nom, statut_pro, is_validate FROM user_profiles WHERE profile_type = 'association';
COMMIT;
