-- Suivis ostéo / santé : date de contrôle conseillée, SAISIE par le
-- professionnel (jamais calculée automatiquement). Alimente « Suivis à
-- prévoir » du tableau de bord ostéopathe (appli + site).

ALTER TABLE public.suivis_morpho
  ADD COLUMN IF NOT EXISTS prochain_controle DATE;

CREATE INDEX IF NOT EXISTS idx_suivis_morpho_prochain_controle
  ON public.suivis_morpho (pro_profile_id, prochain_controle)
  WHERE prochain_controle IS NOT NULL;

NOTIFY pgrst, 'reload schema';
