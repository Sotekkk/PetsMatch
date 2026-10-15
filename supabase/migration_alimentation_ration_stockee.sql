-- Plan d'alimentation : la ration calculée chez le propriétaire (nombre de
-- repas, quantité par jour, 2e composant d'une ration mixte, kcal) est
-- désormais enregistrée, pour que la pension / le pet-sitter la lisent sans
-- refaire le calcul. Jusqu'ici seuls le type, la marque et la gamme étaient
-- stockés (la quantité n'existait qu'à l'écran du propriétaire). Idempotent.
ALTER TABLE public.alimentations ADD COLUMN IF NOT EXISTS nb_repas INTEGER;
ALTER TABLE public.alimentations ADD COLUMN IF NOT EXISTS ration_grammes NUMERIC;
ALTER TABLE public.alimentations ADD COLUMN IF NOT EXISTS ration2_grammes NUMERIC;
ALTER TABLE public.alimentations ADD COLUMN IF NOT EXISTS ration_kcal NUMERIC;

NOTIFY pgrst, 'reload schema';
