-- Éducation / comportement — durée et validation des exercices attribués.
--  • Durée : exercices_attribues.echeance (existante) fixée à l'attribution
--    (1 semaine, 2 semaines par défaut, 1 mois, date, ou NULL = « jusqu'à
--    validation »). Les rappels quotidiens s'arrêtent à l'échéance ou quand
--    l'exercice est terminé (sendExerciceReminders, inchangée).
--  • Étapes : exercices_bibliotheque.etapes [{ "titre": "…" }] (facultatif),
--    copiées dans exercices_attribues.etapes_snapshot ; la famille les valide
--    une à une, dans l'ordre.
--  • Sans étapes : nb_validations = nombre de réussites à obtenir (1 par jour
--    au plus ; 1 = « Marquer fait »).
--  • validations : dates (AAAA-MM-JJ) des étapes / réussites validées ;
--    l'exercice passe « fait » (termine_le) au total atteint.
-- Idempotent.

ALTER TABLE public.exercices_bibliotheque ADD COLUMN IF NOT EXISTS etapes JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE public.exercices_attribues ADD COLUMN IF NOT EXISTS etapes_snapshot JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.exercices_attribues ADD COLUMN IF NOT EXISTS nb_validations INTEGER NOT NULL DEFAULT 1;
ALTER TABLE public.exercices_attribues ADD COLUMN IF NOT EXISTS validations JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.exercices_attribues ADD COLUMN IF NOT EXISTS termine_le TIMESTAMPTZ;

-- Exercices en cours attribués sans échéance (ancien comportement : rappels
-- sans fin) : durée par défaut de 2 semaines à compter de l'attribution.
UPDATE public.exercices_attribues
SET echeance = (assigned_at + INTERVAL '14 days')::date
WHERE echeance IS NULL AND statut IN ('a_faire', 'en_cours');

NOTIFY pgrst, 'reload schema';
