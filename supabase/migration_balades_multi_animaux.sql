-- Balades (promenades GPS du particulier) avec PLUSIEURS animaux.
-- animal_id reste l'animal principal (compatibilité) ; animal_ids liste tous
-- les animaux de la balade. Rattrapage : animal_ids = {animal_id}.
BEGIN;

ALTER TABLE balades_perso ADD COLUMN IF NOT EXISTS animal_ids text[];

UPDATE balades_perso SET animal_ids = ARRAY[animal_id]
WHERE animal_ids IS NULL AND animal_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_balades_perso_animal_ids ON balades_perso USING gin (animal_ids);

SELECT count(*) AS balades, count(animal_ids) AS avec_animal_ids FROM balades_perso;

COMMIT;
