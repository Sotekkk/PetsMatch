-- Généalogie : mêmes informations pour le père et la mère, sur la fiche
-- animal comme à la création d'une portée — nom d'usage (nom_pere /
-- nom_mere, existants), nom de pedigree avec affixe, puce, race, date de
-- naissance (date_naissance_mere existait seule). Idempotent.
ALTER TABLE public.animaux ADD COLUMN IF NOT EXISTS nom_pedigree_pere TEXT;
ALTER TABLE public.animaux ADD COLUMN IF NOT EXISTS nom_pedigree_mere TEXT;
ALTER TABLE public.animaux ADD COLUMN IF NOT EXISTS date_naissance_pere DATE;

NOTIFY pgrst, 'reload schema';
