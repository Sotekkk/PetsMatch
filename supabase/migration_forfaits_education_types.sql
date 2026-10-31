-- Éducateur : forfaits par type de séances + décompte par RDV. 31/10/2026.
--
-- 1. forfaits_education.type_seances : séances individuelles, collectives ou
--    mixte (couvre les deux) — recopié sur forfaits_souscrits à l'attribution.
-- 2. forfaits_souscrits.facture_id : facture du forfait (payé d'avance,
--    préparée à l'attribution).
-- 3. rdv.forfait_souscrit_id : séance du RDV décomptée de ce forfait (pas de
--    facture à la séance ; évite de décompter deux fois le même RDV).
-- Idempotent.

ALTER TABLE public.forfaits_education
  ADD COLUMN IF NOT EXISTS type_seances text NOT NULL DEFAULT 'mixte';
ALTER TABLE public.forfaits_souscrits
  ADD COLUMN IF NOT EXISTS type_seances text NOT NULL DEFAULT 'mixte',
  ADD COLUMN IF NOT EXISTS facture_id uuid;
ALTER TABLE public.rdv
  ADD COLUMN IF NOT EXISTS forfait_souscrit_id uuid;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'forfaits_education_type_seances_check') THEN
    ALTER TABLE public.forfaits_education ADD CONSTRAINT forfaits_education_type_seances_check
      CHECK (type_seances IN ('individuel', 'collectif', 'mixte'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'forfaits_souscrits_type_seances_check') THEN
    ALTER TABLE public.forfaits_souscrits ADD CONSTRAINT forfaits_souscrits_type_seances_check
      CHECK (type_seances IN ('individuel', 'collectif', 'mixte'));
  END IF;
END $$;

COMMENT ON COLUMN public.forfaits_education.type_seances IS 'individuel | collectif | mixte (couvre les deux)';
COMMENT ON COLUMN public.rdv.forfait_souscrit_id IS 'Séance décomptée de ce forfait (éducateur) : pas de facture à la séance';
