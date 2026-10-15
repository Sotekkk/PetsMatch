-- Fiche pension (étape 3 de l'harmonisation des fiches pro) : arrivée et
-- départ enregistrés avec leur heure réelle, la personne qui dépose /
-- récupère l'animal, les effets personnels, les consignes propres au séjour
-- (distinctes des consignes permanentes de l'animal) et les observations.
-- date_entree / date_sortie_prevue / date_sortie_effective restent les
-- dates du séjour (inchangées). Idempotent.
ALTER TABLE public.pension_entrees ADD COLUMN IF NOT EXISTS arrivee_reelle_le TIMESTAMPTZ;
ALTER TABLE public.pension_entrees ADD COLUMN IF NOT EXISTS depart_reel_le TIMESTAMPTZ;
ALTER TABLE public.pension_entrees ADD COLUMN IF NOT EXISTS depose_par TEXT;
ALTER TABLE public.pension_entrees ADD COLUMN IF NOT EXISTS recupere_par TEXT;
ALTER TABLE public.pension_entrees ADD COLUMN IF NOT EXISTS effets_personnels TEXT;
ALTER TABLE public.pension_entrees ADD COLUMN IF NOT EXISTS consignes_sejour TEXT;
ALTER TABLE public.pension_entrees ADD COLUMN IF NOT EXISTS observations_arrivee TEXT;
ALTER TABLE public.pension_entrees ADD COLUMN IF NOT EXISTS observations_depart TEXT;

NOTIFY pgrst, 'reload schema';
