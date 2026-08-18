-- Permet de choisir directement le(s) chien(s) d'un protocole "Animal
-- individuel" dès sa création/modification, au lieu d'attendre le clic sur
-- "Appliquer". La sélection reste pré-remplie (mais modifiable) à
-- l'application. Idempotent — safe à relancer.
ALTER TABLE plan_templates ADD COLUMN IF NOT EXISTS default_animal_ids TEXT[];
