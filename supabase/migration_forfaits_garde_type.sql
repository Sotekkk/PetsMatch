-- Forfaits pet-sitting : packs de visites OU de promenades.
-- type_prestation : 'visite' (défaut, comportement historique) | 'promenade'.
-- nb_visites garde son nom (nombre de prestations du pack). Idempotent.
ALTER TABLE public.forfaits_garde
  ADD COLUMN IF NOT EXISTS type_prestation TEXT NOT NULL DEFAULT 'visite';

DO $$ BEGIN
  ALTER TABLE public.forfaits_garde
    ADD CONSTRAINT forfaits_garde_type_chk CHECK (type_prestation IN ('visite', 'promenade'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

NOTIFY pgrst, 'reload schema';
