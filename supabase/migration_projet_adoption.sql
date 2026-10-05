-- Inscription particulier — « Vos animaux & votre projet » (appli + site).
-- Le projet d'adoption n'existait que dans Firestore (users.adoptProject,
-- appli seule) : colonne partagée sur le profil, écrite à l'inscription par
-- l'appli et par le site (la présentation va dans user_profiles.description).
-- Lecture accordée colonne par colonne depuis la phase 2 (données perso) :
-- même niveau que description.
BEGIN;

ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS projet_adoption text;
GRANT SELECT (projet_adoption) ON user_profiles TO anon, authenticated;

SELECT has_column_privilege('anon', 'user_profiles', 'projet_adoption', 'SELECT') AS lecture,
       has_column_privilege('anon', 'user_profiles', 'projet_adoption', 'UPDATE') AS ecriture;

COMMIT;
