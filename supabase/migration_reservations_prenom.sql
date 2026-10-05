-- Migration : prénom du futur propriétaire séparé du nom dans les réservations
-- Jusqu'ici `nom` contenait le nom complet saisi en un seul champ (ex.
-- « Delafresnaye Catherine »), recopié tel quel dans le champ Nom de la
-- cession avec Prénom vide. Les formulaires de réservation (appli + site)
-- ont désormais deux champs Prénom / Nom.
--
-- Pas de reprise des anciennes lignes : impossible de savoir de façon fiable
-- quel mot est le prénom. Pour ces réservations, la cession va chercher le
-- prénom dans le profil PetsMatch de l'acquéreur ou dans son certificat
-- d'engagement.
--
-- Les RLS existantes de reservations_animaux s'appliquent telles quelles
-- (politiques au niveau de la ligne, pas des colonnes).

ALTER TABLE reservations_animaux ADD COLUMN IF NOT EXISTS prenom TEXT;

NOTIFY pgrst, 'reload schema';
