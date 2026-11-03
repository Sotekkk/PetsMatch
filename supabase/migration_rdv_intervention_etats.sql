-- RDV « Intervention » — lot 2 : hospitalisés du jour (03/11/2026).
-- Deux étapes horodatées en plus de admis_le / sortie_le, posées quand la
-- clinique prévient la famille (« réveillé », « prêt à partir ») :
--   état = rentré (sortie_le) > prêt à partir (pret_le) > en réveil
--   (reveil_le) > au bloc (déposé et dans le créneau bloc_debut–bloc_fin)
--   > déposé (admis_le) > attendu. Idempotent.
BEGIN;
ALTER TABLE public.rdv
  ADD COLUMN IF NOT EXISTS reveil_le TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS pret_le TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS rdv_hospitalises_idx ON public.rdv (pro_profile_id)
  WHERE intervention_type IS NOT NULL AND admis_le IS NOT NULL AND sortie_le IS NULL;
COMMIT;
