-- Éducation — exercices côté client : rappel quotidien par défaut, et tâche
-- du jour dans l'agenda du propriétaire (créée par sendExerciceReminders à
-- 8 h, taches_elevage.notes = 'exercice:<id>'). 31/10/2026.
--
-- PRÉREQUIS : migration_exercices_duree_etapes.sql (colonnes validations,
-- etapes_snapshot, nb_validations, termine_le) — sans elle, la validation
-- d'un exercice par le client est refusée par la base (« ne reste pas
-- validé »). Idempotent.

ALTER TABLE public.exercices_attribues ALTER COLUMN rappels_actifs SET DEFAULT true;

-- Exercices en cours : rappel quotidien activé (le client peut le couper :
-- rappels_mutes).
UPDATE public.exercices_attribues SET rappels_actifs = true
WHERE statut IN ('a_faire', 'en_cours') AND rappels_actifs IS DISTINCT FROM true;

NOTIFY pgrst, 'reload schema';
