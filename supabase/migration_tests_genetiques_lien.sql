-- Tests génétiques : lien vers le résultat en ligne (Embark, Wisdom Panel,
-- Antagene…), en plus du fichier joint (colonne url). Particulier + éleveur.
BEGIN;
ALTER TABLE tests_genetiques ADD COLUMN IF NOT EXISTS lien_resultat text;
SELECT count(*) AS tests FROM tests_genetiques;
COMMIT;
