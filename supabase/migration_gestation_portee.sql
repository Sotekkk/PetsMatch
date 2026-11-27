-- ══════════════════════════════════════════════════════════════════════════
-- Portée créée depuis la gestation (27/11/2026)
-- ══════════════════════════════════════════════════════════════════════════
-- La mise bas réelle saisie dans l'onglet Gestations propose de créer la
-- portée (fiches des petits préremplies). La gestation garde l'identifiant
-- de la portée créée : bouton « Créer la portée » remplacé par « Portée
-- créée », pas de seconde création.
-- (animaux.portee_id contient le même identifiant sur chaque petit.)
-- ══════════════════════════════════════════════════════════════════════════

ALTER TABLE gestations ADD COLUMN IF NOT EXISTS portee_id TEXT;

NOTIFY pgrst, 'reload schema';

-- Vérification
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'gestations' AND column_name = 'portee_id';

-- Retour arrière :
-- ALTER TABLE gestations DROP COLUMN IF EXISTS portee_id;
