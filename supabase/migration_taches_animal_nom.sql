-- Ajout du champ animal_nom dans taches_elevage pour la sélection d'animaux dans les tâches
ALTER TABLE taches_elevage ADD COLUMN IF NOT EXISTS animal_nom TEXT;
