-- Maréchal-ferrant : délai entre deux ferrures / parages, propre à chaque
-- profil (accueil « Ferrures à renouveler »). 7 semaines par défaut,
-- modifiable par le maréchal depuis son accueil (site + appli).
ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS marechal_cycle_semaines INTEGER DEFAULT 7;

ALTER TABLE public.user_profiles
  DROP CONSTRAINT IF EXISTS user_profiles_marechal_cycle_semaines_check;
ALTER TABLE public.user_profiles
  ADD CONSTRAINT user_profiles_marechal_cycle_semaines_check
  CHECK (marechal_cycle_semaines IS NULL OR marechal_cycle_semaines BETWEEN 2 AND 26);
